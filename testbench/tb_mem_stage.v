// =============================================================================
// Self-checking testbench for mem_stage.v (Issue #18)
//
// Run from the repository root:
//   iverilog -g2012 -o simulation/tb_mem_stage.vvp \
//       testbench/tb_mem_stage.v \
//       rtl/stages/mem_stage.v \
//       rtl/stages/data_mem.v
//   vvp simulation/tb_mem_stage.vvp
//
// Tests:
//   1. Reset / idle state — no memory side-effects when mem_read/write = 0
//   2. SW (store word)   — mem_write commits data at alu_result address
//   3. LW (load word)    — mem_read returns previously stored data
//   4. ALU pass-through  — alu_result_out matches alu_result input
//   5. Metadata pass-through — rd, pc, pc_plus4, reg_write, wb_from_mem, valid
//   6. Invalid address / misalignment — access_fault is asserted, no corrupt
//   7. Bubble input      — valid=0 carries no side-effects into outputs
//   8. Multiple sequential SW→LW pairs at distinct addresses
// =============================================================================
`timescale 1ns/1ps

module tb_mem_stage;

    // -------------------------------------------------------------------------
    // DUT interface
    // -------------------------------------------------------------------------
    reg         clk        = 0;
    reg  [31:0] alu_result = 0;
    reg  [31:0] store_data = 0;
    reg  [4:0]  rd         = 0;
    reg  [31:0] pc         = 0;
    reg  [31:0] pc_plus4   = 0;
    reg         mem_read   = 0;
    reg         mem_write  = 0;
    reg         reg_write  = 0;
    reg         wb_from_mem= 0;
    reg         valid      = 1;

    wire [31:0] alu_result_out;
    wire [31:0] load_data_out;
    wire [4:0]  rd_out;
    wire [31:0] pc_out;
    wire [31:0] pc_plus4_out;
    wire        reg_write_out;
    wire        wb_from_mem_out;
    wire        valid_out;
    wire        access_fault;

    // -------------------------------------------------------------------------
    // DUT instantiation (16-word data memory for fast simulation)
    // -------------------------------------------------------------------------
    mem_stage #(.MEM_DEPTH_WORDS(16)) dut (
        .clk           (clk),
        .alu_result    (alu_result),
        .store_data    (store_data),
        .rd            (rd),
        .pc            (pc),
        .pc_plus4      (pc_plus4),
        .mem_read      (mem_read),
        .mem_write     (mem_write),
        .reg_write     (reg_write),
        .wb_from_mem   (wb_from_mem),
        .valid         (valid),
        .alu_result_out(alu_result_out),
        .load_data_out (load_data_out),
        .rd_out        (rd_out),
        .pc_out        (pc_out),
        .pc_plus4_out  (pc_plus4_out),
        .reg_write_out (reg_write_out),
        .wb_from_mem_out(wb_from_mem_out),
        .valid_out     (valid_out),
        .access_fault  (access_fault)
    );

    // -------------------------------------------------------------------------
    // Clock: 10 ns period
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    integer errors = 0;
    integer test_count = 0;

    task check32;
        input [255:0] name;
        input [31:0]  got;
        input [31:0]  exp;
        begin
            test_count = test_count + 1;
            if (got !== exp) begin
                $display("FAIL [%0d]: %0s  got=%h  expected=%h", test_count, name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check1;
        input [255:0] name;
        input         got;
        input         exp;
        begin
            test_count = test_count + 1;
            if (got !== exp) begin
                $display("FAIL [%0d]: %0s  got=%b  expected=%b", test_count, name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    // Drive store on negedge, committed at following posedge inside data_mem
    task sw;
        input [31:0] addr_in;
        input [31:0] data_in;
        begin
            @(negedge clk);
            alu_result = addr_in;
            store_data = data_in;
            mem_write  = 1;
            mem_read   = 0;
            @(negedge clk);
            mem_write  = 0;
        end
    endtask

    // Combinational load: assert mem_read, settle for 1 ns, then sample
    task lw;
        input [31:0] addr_in;
        begin
            alu_result = addr_in;
            mem_read   = 1;
            mem_write  = 0;
            #1;
        end
    endtask

    task idle;
        begin
            mem_read  = 0;
            mem_write = 0;
            #1;
        end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("simulation/tb_mem_stage.vcd");
        $dumpvars(0, tb_mem_stage);

        // =====================================================================
        // 1. Idle state: no mem_read / mem_write
        // =====================================================================
        valid      = 1;
        reg_write  = 0;
        wb_from_mem= 0;
        rd         = 5'd0;
        pc         = 32'h0000_0004;
        pc_plus4   = 32'h0000_0008;
        alu_result = 32'h0;
        idle;
        check32("idle: alu_result_out",   alu_result_out,  32'h0);
        check32("idle: load_data_out",    load_data_out,   32'h0);  // mem idle → 0
        check1 ("idle: access_fault",     access_fault,    1'b0);
        check1 ("idle: valid_out",        valid_out,       1'b1);
        check1 ("idle: reg_write_out",    reg_write_out,   1'b0);

        // =====================================================================
        // 2. SW — store word then verify via LW
        // =====================================================================
        reg_write  = 0;
        wb_from_mem= 0;
        sw(32'h00, 32'hDEAD_BEEF);
        sw(32'h04, 32'hCAFE_1234);
        sw(32'h3C, 32'hABCD_EF01);  // last word (index 15 in 16-word mem)

        // =====================================================================
        // 3. LW — load previously stored words
        // =====================================================================
        reg_write  = 1;
        wb_from_mem= 1;
        rd         = 5'd5;
        pc         = 32'h0000_0010;
        pc_plus4   = 32'h0000_0014;

        lw(32'h00);
        check32("lw 0x00: load_data_out",    load_data_out,  32'hDEAD_BEEF);
        check32("lw 0x00: alu_result_out",   alu_result_out, 32'h0000_0000);
        check1 ("lw 0x00: access_fault",     access_fault,   1'b0);
        check1 ("lw 0x00: reg_write_out",    reg_write_out,  1'b1);
        check1 ("lw 0x00: wb_from_mem_out",  wb_from_mem_out,1'b1);
        check32("lw 0x00: rd_out",           {27'h0, rd_out},  {27'h0, 5'd5});
        check32("lw 0x00: pc_out",           pc_out,         32'h0000_0010);
        check32("lw 0x00: pc_plus4_out",     pc_plus4_out,   32'h0000_0014);
        check1 ("lw 0x00: valid_out",        valid_out,      1'b1);

        lw(32'h04);
        check32("lw 0x04: load_data_out",    load_data_out,  32'hCAFE_1234);

        lw(32'h3C);
        check32("lw 0x3C: load_data_out",    load_data_out,  32'hABCD_EF01);

        // =====================================================================
        // 4. ALU pass-through (R-type: mem_read=0, mem_write=0)
        // =====================================================================
        mem_read   = 0;
        mem_write  = 0;
        reg_write  = 1;
        wb_from_mem= 0;
        rd         = 5'd7;
        alu_result = 32'h1234_5678;
        pc         = 32'h0000_0020;
        pc_plus4   = 32'h0000_0024;
        #1;
        check32("alu pass: alu_result_out",  alu_result_out, 32'h1234_5678);
        check32("alu pass: load_data_out",   load_data_out,  32'h0);        // mem idle
        check1 ("alu pass: wb_from_mem_out", wb_from_mem_out,1'b0);
        check1 ("alu pass: reg_write_out",   reg_write_out,  1'b1);
        check32("alu pass: rd_out",          {27'h0, rd_out},  {27'h0, 5'd7});
        check32("alu pass: pc_out",          pc_out,         32'h0000_0020);
        check1 ("alu pass: access_fault",    access_fault,   1'b0);

        // =====================================================================
        // 5. Invalid address — misaligned read (addr[1:0] != 0)
        // =====================================================================
        reg_write  = 1;
        wb_from_mem= 1;
        lw(32'h01);
        check32("misalign lw: load_data_out", load_data_out,  32'h0);
        check1 ("misalign lw: access_fault",  access_fault,   1'b1);

        // Misaligned write: ignored and fault is flagged
        @(negedge clk);
        alu_result = 32'h03;
        store_data = 32'hBAD0_BAD0;
        mem_write  = 1;
        mem_read   = 0;
        #1;
        check1 ("misalign sw: access_fault",  access_fault,   1'b1);
        @(negedge clk); mem_write = 0;
        // Verify the neighbouring aligned word is untouched
        lw(32'h00);
        check32("misalign sw: 0x00 intact",   load_data_out,  32'hDEAD_BEEF);

        // Out-of-range address
        lw(32'h40); // depth = 16 words = 0x40 bytes → oob
        check32("oob lw: load_data_out",      load_data_out,  32'h0);
        check1 ("oob lw: access_fault",       access_fault,   1'b1);

        // =====================================================================
        // 6. Bubble input (valid = 0): outputs carry no side-effects
        // =====================================================================
        mem_read   = 0;
        mem_write  = 0;
        valid      = 0;
        reg_write  = 1;   // asserted but must be suppressed by upstream
        wb_from_mem= 1;
        rd         = 5'd31;
        alu_result = 32'hFFFF_FFFF;
        #1;
        // mem_stage is purely combinational; it passes valid through unchanged.
        // The gating of side-effects on the bubble is the responsibility of the
        // EX stage (gating mem_read/mem_write on valid_in) and the MEM/WB
        // register (bubble capture).  Here we confirm the combinational outputs
        // reflect whatever is presented, so check structural pass-throughs:
        check1 ("bubble: valid_out",          valid_out,      1'b0);
        check32("bubble: alu_result_out",     alu_result_out, 32'hFFFF_FFFF);

        // Restore valid
        valid = 1; reg_write = 0; wb_from_mem = 0;

        // =====================================================================
        // 7. Multiple sequential SW → LW pairs
        // =====================================================================
        begin : multi_sw_lw
            integer k;
            reg [31:0] addr_k;
            reg [31:0] data_k;
            for (k = 0; k < 8; k = k + 1) begin
                addr_k = k << 2;           // 0x0, 0x4, ... 0x1C
                data_k = 32'hA000_0000 | k;
                sw(addr_k, data_k);
            end
            for (k = 0; k < 8; k = k + 1) begin
                addr_k = k << 2;
                data_k = 32'hA000_0000 | k;
                lw(addr_k);
                check32("multi lw", load_data_out, data_k);
            end
        end

        // =====================================================================
        // Result summary
        // =====================================================================
        if (errors == 0)
            $display("PASS: tb_mem_stage (%0d checks)", test_count);
        else
            $display("FAILED: tb_mem_stage — %0d error(s) in %0d checks", errors, test_count);
        $finish;
    end

endmodule
