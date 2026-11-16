// =============================================================================
// Self-checking testbench for mem_wb_reg.v (Issue #19)
//
// Acceptance criteria tested:
//   - MEM data and controls remain aligned across a capture cycle
//   - Reset / bubble disables register write (reg_write_out = 0, valid_out = 0)
//   - Bubble cannot write a destination register
//   - ALU-result entry and load-data entry are captured correctly
//   - Consecutive distinct entries replace each other
//   - Flush / reset clear to safe no-write state; flush beats hold (en=0)
//   - Hold (en=0) freezes the bundle across multiple cycles
//   - Walking-bit test verifies every payload bit independently
//
// Run from repository root:
//   iverilog -g2012 -o simulation/tb_mem_wb_reg.vvp \
//       testbench/tb_mem_wb_reg.v \
//       rtl/pipeline_registers/mem_wb_reg.v
//   vvp simulation/tb_mem_wb_reg.vvp
// =============================================================================
`timescale 1ns/1ps

module tb_mem_wb_reg;

    // -------------------------------------------------------------------------
    // DUT interface
    // -------------------------------------------------------------------------
    reg        clk            = 0;
    reg        rst            = 0;
    reg        en             = 1;
    reg        flush          = 0;

    reg [31:0] alu_result_in  = 0;
    reg [31:0] load_data_in   = 0;
    reg [4:0]  rd_in          = 0;
    reg [31:0] pc_in          = 0;
    reg [31:0] pc_plus4_in    = 0;
    reg        reg_write_in   = 0;
    reg        wb_from_mem_in = 0;
    reg        valid_in       = 0;

    wire [31:0] alu_result_out;
    wire [31:0] load_data_out;
    wire [4:0]  rd_out;
    wire [31:0] pc_out;
    wire [31:0] pc_plus4_out;
    wire        reg_write_out;
    wire        wb_from_mem_out;
    wire        valid_out;

    mem_wb_reg dut (
        .clk            (clk),
        .rst            (rst),
        .en             (en),
        .flush          (flush),
        .alu_result_in  (alu_result_in),
        .load_data_in   (load_data_in),
        .rd_in          (rd_in),
        .pc_in          (pc_in),
        .pc_plus4_in    (pc_plus4_in),
        .reg_write_in   (reg_write_in),
        .wb_from_mem_in (wb_from_mem_in),
        .valid_in       (valid_in),
        .alu_result_out (alu_result_out),
        .load_data_out  (load_data_out),
        .rd_out         (rd_out),
        .pc_out         (pc_out),
        .pc_plus4_out   (pc_plus4_out),
        .reg_write_out  (reg_write_out),
        .wb_from_mem_out(wb_from_mem_out),
        .valid_out      (valid_out)
    );

    // -------------------------------------------------------------------------
    // Bundle packing — flat vector for easy comparison
    // Layout (MSB→LSB): alu_result[31:0] | load_data[31:0] | rd[4:0] |
    //                   pc[31:0] | pc_plus4[31:0] | reg_write | wb_from_mem | valid
    // Total = 32+32+5+32+32+1+1+1 = 136 bits  (bit 0 = valid)
    // -------------------------------------------------------------------------
    localparam WIDTH = 136;

    function automatic [WIDTH-1:0] pack;
        input [31:0] alu_r;
        input [31:0] ld;
        input [4:0]  rd_;
        input [31:0] pc_;
        input [31:0] pc4_;
        input        rw;
        input        wfm;
        input        v;
        begin
            pack = {alu_r, ld, rd_, pc_, pc4_, rw, wfm, v};
        end
    endfunction

    // Apply a packed bundle to DUT inputs
    task apply;
        input [WIDTH-1:0] bundle;
        begin
            {alu_result_in, load_data_in, rd_in,
             pc_in, pc_plus4_in,
             reg_write_in, wb_from_mem_in, valid_in} = bundle;
        end
    endtask

    // Flatten DUT outputs
    wire [WIDTH-1:0] result;
    assign result = {alu_result_out, load_data_out, rd_out,
                     pc_out, pc_plus4_out,
                     reg_write_out, wb_from_mem_out, valid_out};

    // -------------------------------------------------------------------------
    // Clock: 10 ns period
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Check helpers
    // -------------------------------------------------------------------------
    integer errors     = 0;
    integer test_count = 0;

    task tick_check;
        input [WIDTH-1:0] expected;
        input [255:0]     label;
        begin
            @(posedge clk); #1;
            test_count = test_count + 1;
            if (result !== expected) begin
                $display("FAIL [%0d] %0s", test_count, label);
                $display("  got      %0h", result);
                $display("  expected %0h", expected);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Named test bundles
    // -------------------------------------------------------------------------
    // ALU-result entry (R-type / addi): wb_from_mem=0, reg_write=1, valid=1
    wire [WIDTH-1:0] alu_entry;
    assign alu_entry = pack(32'hCAFE_1234, 32'h0, 5'd7,
                            32'h0000_0020, 32'h0000_0024,
                            1'b1, 1'b0, 1'b1);

    // Load-data entry (lw): wb_from_mem=1, reg_write=1, valid=1
    wire [WIDTH-1:0] lw_entry;
    assign lw_entry = pack(32'h0000_0100, 32'hDEAD_BEEF, 5'd3,
                           32'h0000_0010, 32'h0000_0014,
                           1'b1, 1'b1, 1'b1);

    // Walking-bit registers
    reg [WIDTH-1:0] walk;
    integer i;

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("simulation/tb_mem_wb_reg.vcd");
        $dumpvars(0, tb_mem_wb_reg);

        // =====================================================================
        // 1. Reset — all outputs clear to 0; reg_write disabled
        // =====================================================================
        rst = 1; en = 1; flush = 0;
        apply(alu_entry);
        tick_check({WIDTH{1'b0}}, "1. Reset clears all outputs");
        // Verify side-effect controls explicitly
        if (reg_write_out !== 1'b0 || valid_out !== 1'b0)
            $fatal(1, "FAIL: Reset did not disable reg_write/valid");
        rst = 0;

        // =====================================================================
        // 2. Active capture — ALU-result entry (R-type)
        //    Verifies alu_result, rd, pc, pc_plus4, reg_write, wb_from_mem=0
        // =====================================================================
        apply(alu_entry);
        tick_check(alu_entry, "2. Capture ALU-result entry");
        if (reg_write_out !== 1'b1 || wb_from_mem_out !== 1'b0 || valid_out !== 1'b1)
            $fatal(1, "FAIL: ALU entry control signals wrong");
        if (alu_result_out !== 32'hCAFE_1234 || rd_out !== 5'd7)
            $fatal(1, "FAIL: ALU entry data fields wrong");

        // =====================================================================
        // 3. Active capture — load-data entry (LW)
        //    Verifies load_data, rd, pc, wb_from_mem=1 on a consecutive capture
        // =====================================================================
        apply(lw_entry);
        tick_check(lw_entry, "3. Capture LW load-data entry (consecutive)");
        if (reg_write_out !== 1'b1 || wb_from_mem_out !== 1'b1 || valid_out !== 1'b1)
            $fatal(1, "FAIL: LW entry control signals wrong");
        if (load_data_out !== 32'hDEAD_BEEF || rd_out !== 5'd3)
            $fatal(1, "FAIL: LW entry data fields wrong");

        // =====================================================================
        // 4. Consecutive distinct entries — overwrite in successive cycles
        // =====================================================================
        apply(alu_entry);
        tick_check(alu_entry, "4a. Consecutive: overwrite with ALU entry");
        apply(lw_entry);
        tick_check(lw_entry, "4b. Consecutive: overwrite with LW entry again");
        apply(alu_entry);
        tick_check(alu_entry, "4c. Consecutive: overwrite with ALU entry again");

        // =====================================================================
        // 5. Hold (en = 0) — bundle frozen across multiple cycles
        // =====================================================================
        en = 0;
        apply(lw_entry);                       // change inputs — must NOT propagate
        tick_check(alu_entry, "5a. Hold: inputs ignored when en=0 (cycle 1)");
        tick_check(alu_entry, "5b. Hold: persists across multiple cycles");
        en = 1;

        // =====================================================================
        // 6. Flush (flush=1, en=1) — clears bundle
        // =====================================================================
        apply(lw_entry);
        tick_check(lw_entry, "6a. Capture LW entry before flush test");
        flush = 1;
        apply(lw_entry);
        tick_check({WIDTH{1'b0}}, "6b. Flush clears bundle (en=1)");
        if (reg_write_out !== 1'b0 || valid_out !== 1'b0)
            $fatal(1, "FAIL: Flush did not disable reg_write/valid");
        flush = 0;

        // =====================================================================
        // 7. Flush beats hold (flush=1, en=0)
        // =====================================================================
        apply(alu_entry);
        tick_check(alu_entry, "7a. Capture ALU entry before flush-beats-hold test");
        en = 0; flush = 1;
        apply(lw_entry);
        tick_check({WIDTH{1'b0}}, "7b. Flush beats hold (clears when en=0)");
        flush = 0; en = 1;

        // =====================================================================
        // 8. Reset beats hold (rst=1, en=0)
        // =====================================================================
        apply(lw_entry);
        tick_check(lw_entry, "8a. Capture LW entry before reset-beats-hold test");
        en = 0; rst = 1;
        apply(alu_entry);
        tick_check({WIDTH{1'b0}}, "8b. Reset beats hold (clears when en=0)");
        rst = 0; en = 1;

        // =====================================================================
        // 9. Bubble capture (valid_in=0, en=1)
        //    A bubble must NOT write a destination register.
        // =====================================================================
        // Present a bundle with reg_write=1 and wb_from_mem=1 but valid=0
        apply(pack(32'hBADBAD00, 32'hDEADDEAD, 5'd31,
                   32'hFFFF0000, 32'hFFFF0004,
                   1'b1, 1'b1, 1'b0));  // valid = 0
        tick_check({WIDTH{1'b0}}, "9a. Bubble input clears all outputs");
        if (reg_write_out !== 1'b0 || valid_out !== 1'b0)
            $fatal(1, "FAIL: Bubble asserted reg_write or valid");

        // =====================================================================
        // 10. Hold beats bubble (valid_in=0, en=0)
        //     A held valid bundle must survive even if valid_in goes low.
        // =====================================================================
        // First capture a valid entry
        apply(alu_entry);
        tick_check(alu_entry, "10a. Capture ALU entry before bubble-hold test");
        // Now hold with an invalid input arriving
        en = 0;
        apply(pack(32'hDEADC0DE, 32'hCAFEBABE, 5'd15,
                   32'h0000_2000, 32'h0000_2004,
                   1'b1, 1'b1, 1'b0));  // valid = 0
        tick_check(alu_entry, "10b. Hold beats bubble (en=0 keeps valid entry)");
        tick_check(alu_entry, "10c. Bubble-hold persists multiple cycles");
        // Now release — bubble should propagate and clear
        en = 1;
        tick_check({WIDTH{1'b0}}, "10d. en=1 with valid_in=0 captures bubble");

        // =====================================================================
        // 11. Data alignment — all fields captured together in one cycle
        //     Verifies alu_result and load_data are independent fields
        // =====================================================================
        apply(pack(32'hABCD_EF01, 32'h1234_5678, 5'd12,
                   32'h0000_0040, 32'h0000_0044,
                   1'b1, 1'b1, 1'b1));
        tick_check(pack(32'hABCD_EF01, 32'h1234_5678, 5'd12,
                        32'h0000_0040, 32'h0000_0044,
                        1'b1, 1'b1, 1'b1),
                   "11. Data alignment: alu_result and load_data independent");

        // =====================================================================
        // 12. Walking-bit test — every payload bit captured, held, and flushed
        // =====================================================================
        for (i = 0; i < WIDTH; i = i + 1) begin
            // bit 0 is valid; always set it so capture actually fires
            walk    = {WIDTH{1'b0}};
            walk[0] = 1'b1;   // valid_in = 1
            walk[i] = 1'b1;   // payload bit i

            apply(walk);
            en = 1; flush = 0;
            tick_check(walk, "12a. Walking-bit capture");

            // Hold: invert inputs — captured value must survive
            en = 0;
            apply(~walk);
            tick_check(walk, "12b. Walking-bit hold with inverted input");

            // Flush clears
            flush = 1;
            tick_check({WIDTH{1'b0}}, "12c. Walking-bit flush");
            flush = 0; en = 1;
        end

        // =====================================================================
        // Result summary
        // =====================================================================
        if (errors == 0)
            $display("PASS: tb_mem_wb_reg — all %0d checks passed", test_count);
        else
            $display("FAILED: tb_mem_wb_reg — %0d error(s) in %0d checks",
                     errors, test_count);
        $finish;
    end

endmodule
