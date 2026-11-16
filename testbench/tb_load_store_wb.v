// =============================================================================
// Testbench: tb_load_store_wb
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #21 - Load/Store & Write-Back Verification
//
// Description:
//   End-to-end integration-level verification suite for the MEM, MEM/WB,
//   and WB datapath stages integrated directly with M2's Register File.
//
// Pipeline Datapath Under Test:
//   [EX/MEM Inputs]
//          │
//          ▼
//     mem_stage (data_mem)
//          │
//          ▼
//     mem_wb_reg
//          │
//          ▼
//      wb_stage
//          │
//          ▼
//    register_file (ID stage)
//
// Required Scenarios Verified:
//   1. SW followed by LW: Store known word with SW and load it back with LW.
//   2. Multiple addresses: Load from at least two distinct word addresses.
//   3. SW register protection: Verify SW never asserts register write or modifies RF.
//   4. LW target verification: Verify LW writes loaded value to intended rd and no other.
//   5. ALU vs stale memory: Verify ALU result is not replaced by stale memory data.
//   6. Bubble & Reset safety: Verify bubbles and reset never trigger register writes.
//   7. Hardwired zero x0: Verify writes to x0 are suppressed and x0 remains 0.
//   8. Pipeline control: Verify stall (hold, en=0) and flush squash operations.
//   9. Full-throughput streaming: Back-to-back pipelined execution of SW, LW, and ALU.
//
// Compilation & Simulation:
//   iverilog -g2012 -o simulation/tb_load_store_wb.vvp \
//       testbench/tb_load_store_wb.v \
//       rtl/stages/mem_stage.v \
//       rtl/stages/data_mem.v \
//       rtl/pipeline_registers/mem_wb_reg.v \
//       rtl/stages/wb_stage.v \
//       rtl/stages/register_file.v
//   vvp simulation/tb_load_store_wb.vvp
// =============================================================================

`timescale 1ns/1ps

module tb_load_store_wb;

    // -------------------------------------------------------------------------
    // Clocks and Global Controls
    // -------------------------------------------------------------------------
    reg clk       = 0;
    reg rst       = 0;
    reg reg_en    = 1;
    reg reg_flush = 0;

    // -------------------------------------------------------------------------
    // 1. Inputs entering the MEM Stage (from EX/MEM interface)
    // -------------------------------------------------------------------------
    reg  [31:0] mem_in_alu_result  = 32'd0;
    reg  [31:0] mem_in_store_data  = 32'd0;
    reg  [4:0]  mem_in_rd          = 5'd0;
    reg  [31:0] mem_in_pc          = 32'd0;
    reg  [31:0] mem_in_pc_plus4    = 32'd0;
    reg         mem_in_mem_read    = 1'b0;
    reg         mem_in_mem_write   = 1'b0;
    reg         mem_in_reg_write   = 1'b0;
    reg         mem_in_wb_from_mem = 1'b0;
    reg         mem_in_valid       = 1'b0;

    // -------------------------------------------------------------------------
    // 2. Signals at MEM Stage -> MEM/WB Register Boundary
    // -------------------------------------------------------------------------
    wire [31:0] mem_stage_alu_result;
    wire [31:0] mem_stage_load_data;
    wire [4:0]  mem_stage_rd;
    wire [31:0] mem_stage_pc;
    wire [31:0] mem_stage_pc_plus4;
    wire        mem_stage_reg_write;
    wire        mem_stage_wb_from_mem;
    wire        mem_stage_valid;
    wire        mem_stage_access_fault;

    // -------------------------------------------------------------------------
    // 3. Signals at MEM/WB Register -> WB Stage Boundary
    // -------------------------------------------------------------------------
    wire [31:0] wb_in_alu_result;
    wire [31:0] wb_in_load_data;
    wire [4:0]  wb_in_rd;
    wire [31:0] wb_in_pc;
    wire [31:0] wb_in_pc_plus4;
    wire        wb_in_reg_write;
    wire        wb_in_wb_from_mem;
    wire        wb_in_valid;

    // -------------------------------------------------------------------------
    // 4. Signals at WB Stage -> Register File Interface
    // -------------------------------------------------------------------------
    wire        rf_write_en;
    wire [4:0]  rf_rd;
    wire [31:0] rf_write_data;
    wire [31:0] retired_pc;
    wire [31:0] retired_pc_plus4;
    wire        retired;

    // -------------------------------------------------------------------------
    // 5. Register File Inspection Ports
    // -------------------------------------------------------------------------
    reg  [4:0]  rf_rs1 = 5'd0;
    reg  [4:0]  rf_rs2 = 5'd0;
    wire [31:0] rf_rs1_data;
    wire [31:0] rf_rs2_data;

    // -------------------------------------------------------------------------
    // Device Under Test Pipeline Instantiations
    // -------------------------------------------------------------------------

    // Stage 1: Memory Stage (instantiates data_mem internally)
    mem_stage #(
        .MEM_DEPTH_WORDS (256),
        .MEM_INIT_FILE   ("")
    ) u_mem_stage (
        .clk             (clk),
        .alu_result      (mem_in_alu_result),
        .store_data      (mem_in_store_data),
        .rd              (mem_in_rd),
        .pc              (mem_in_pc),
        .pc_plus4        (mem_in_pc_plus4),
        .mem_read        (mem_in_mem_read),
        .mem_write       (mem_in_mem_write),
        .reg_write       (mem_in_reg_write),
        .wb_from_mem     (mem_in_wb_from_mem),
        .valid           (mem_in_valid),
        .alu_result_out  (mem_stage_alu_result),
        .load_data_out   (mem_stage_load_data),
        .rd_out          (mem_stage_rd),
        .pc_out          (mem_stage_pc),
        .pc_plus4_out    (mem_stage_pc_plus4),
        .reg_write_out   (mem_stage_reg_write),
        .wb_from_mem_out (mem_stage_wb_from_mem),
        .valid_out       (mem_stage_valid),
        .access_fault    (mem_stage_access_fault)
    );

    // Stage 2: MEM/WB Pipeline Register
    mem_wb_reg u_mem_wb_reg (
        .clk             (clk),
        .rst             (rst),
        .en              (reg_en),
        .flush           (reg_flush),
        .alu_result_in   (mem_stage_alu_result),
        .load_data_in    (mem_stage_load_data),
        .rd_in           (mem_stage_rd),
        .pc_in           (mem_stage_pc),
        .pc_plus4_in     (mem_stage_pc_plus4),
        .reg_write_in    (mem_stage_reg_write),
        .wb_from_mem_in  (mem_stage_wb_from_mem),
        .valid_in        (mem_stage_valid),
        .alu_result_out  (wb_in_alu_result),
        .load_data_out   (wb_in_load_data),
        .rd_out          (wb_in_rd),
        .pc_out          (wb_in_pc),
        .pc_plus4_out    (wb_in_pc_plus4),
        .reg_write_out   (wb_in_reg_write),
        .wb_from_mem_out (wb_in_wb_from_mem),
        .valid_out       (wb_in_valid)
    );

    // Stage 3: Write-Back Stage
    wb_stage u_wb_stage (
        .alu_result      (wb_in_alu_result),
        .load_data       (wb_in_load_data),
        .rd              (wb_in_rd),
        .pc              (wb_in_pc),
        .pc_plus4        (wb_in_pc_plus4),
        .reg_write       (wb_in_reg_write),
        .wb_from_mem     (wb_in_wb_from_mem),
        .valid           (wb_in_valid),
        .wb_write_en     (rf_write_en),
        .wb_rd           (rf_rd),
        .wb_data         (rf_write_data),
        .pc_out          (retired_pc),
        .pc_plus4_out    (retired_pc_plus4),
        .retired         (retired)
    );

    // Stage 4: Register File (M2 Architecture Interface)
    register_file u_register_file (
        .clk             (clk),
        .rst             (rst),
        .write_en        (rf_write_en),
        .rd              (rf_rd),
        .write_data      (rf_write_data),
        .rs1             (rf_rs1),
        .rs2             (rf_rs2),
        .rs1_data        (rf_rs1_data),
        .rs2_data        (rf_rs2_data)
    );

    // -------------------------------------------------------------------------
    // Clock: 100MHz (10ns period)
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Verification Helpers & Accounting
    // -------------------------------------------------------------------------
    integer errors     = 0;
    integer test_count = 0;

    task check32;
        input [255:0] name;
        input [31:0]  got;
        input [31:0]  exp;
        begin
            test_count = test_count + 1;
            if (got !== exp) begin
                $display("FAIL [%0d]: %0s | got=0x%08h expected=0x%08h", test_count, name, got, exp);
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
                $display("FAIL [%0d]: %0s | got=%b expected=%b", test_count, name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    // Drive an instruction into MEM stage on negedge clk
    task drive_mem;
        input [31:0] alu_r;
        input [31:0] store_d;
        input [4:0]  dest_rd;
        input [31:0] pc_val;
        input        m_read;
        input        m_write;
        input        r_write;
        input        wb_sel;
        input        v;
        begin
            @(negedge clk);
            mem_in_alu_result  = alu_r;
            mem_in_store_data  = store_d;
            mem_in_rd          = dest_rd;
            mem_in_pc          = pc_val;
            mem_in_pc_plus4    = pc_val + 32'd4;
            mem_in_mem_read    = m_read;
            mem_in_mem_write   = m_write;
            mem_in_reg_write   = r_write;
            mem_in_wb_from_mem = wb_sel;
            mem_in_valid       = v;
        end
    endtask

    // Drive bubble / nop into MEM stage
    task drive_bubble;
        begin
            drive_mem(32'd0, 32'd0, 5'd0, 32'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        end
    endtask

    // Read register file synchronously after commitment
    task read_rf_reg;
        input  [4:0]  reg_idx;
        output [31:0] data_out;
        begin
            rf_rs1 = reg_idx;
            #1;
            data_out = rf_rs1_data;
        end
    endtask

    reg [31:0] temp_data;

    // -------------------------------------------------------------------------
    // Main Verification Procedures
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("simulation/tb_load_store_wb.vcd");
        $dumpvars(0, tb_load_store_wb);

        // =====================================================================
        // Initial System Reset
        // =====================================================================
        rst       = 1;
        reg_en    = 1;
        reg_flush = 0;
        drive_bubble();
        @(posedge clk); #1;
        rst = 0;
        @(posedge clk); #1;

        // Verify all initial RF reads are 0
        read_rf_reg(5'd1, temp_data); check32("Init x1 is 0", temp_data, 32'd0);
        read_rf_reg(5'd2, temp_data); check32("Init x2 is 0", temp_data, 32'd0);
        read_rf_reg(5'd5, temp_data); check32("Init x5 is 0", temp_data, 32'd0);

        // =====================================================================
        // Scenario 1 & 4: Store a known word with SW and load it back with LW
        //   - SW 0xDEAD_BEEF to byte address 0x0000_0010 (rd = x8)
        //   - LW from address 0x0000_0010 into rd = x5
        // =====================================================================
        $display("--- Running Scenario 1 & 4: SW then LW to intended rd ---");
        // Cycle 1: Issue SW into MEM stage
        drive_mem(32'h0000_0010, 32'hDEAD_BEEF, 5'd8, 32'h0000_1000,
                  1'b0, 1'b1, 1'b0, 1'b0, 1'b1); // mem_write=1, reg_write=0

        // Cycle 2: posedge commits SW to data_mem. SW enters mem_wb_reg.
        // Issue LW from 0x0000_0010 into x5 into MEM stage.
        drive_mem(32'h0000_0010, 32'h0000_0000, 5'd5, 32'h0000_1004,
                  1'b1, 1'b0, 1'b1, 1'b1, 1'b1); // mem_read=1, reg_write=1, wb_from_mem=1

        // Verify that while SW is in WB, rf_write_en is 0 (Scenario 3)
        #1;
        check1 ("Scenario 3: SW in WB does not assert rf_write_en", rf_write_en, 1'b0);

        // Cycle 3: posedge advances LW into mem_wb_reg. Issue bubble into MEM.
        drive_bubble();
        #1;
        // LW is now in WB stage!
        check1 ("Scenario 4: LW in WB asserts rf_write_en", rf_write_en, 1'b1);
        check32("Scenario 4: LW target rd is x5", {27'd0, rf_rd}, {27'd0, 5'd5});
        check32("Scenario 4: LW wb_data is loaded 0xDEAD_BEEF", rf_write_data, 32'hDEAD_BEEF);

        // Check write-through bypass in register file
        rf_rs1 = 5'd5;
        #1;
        check32("Scenario 4: LW write-through bypass delivers loaded word", rf_rs1_data, 32'hDEAD_BEEF);

        // Cycle 4: posedge commits LW into register x5
        @(posedge clk); #1;
        read_rf_reg(5'd5, temp_data);
        check32("Scenario 1: RF x5 contains loaded word 0xDEAD_BEEF", temp_data, 32'hDEAD_BEEF);

        // Verify that x8 (the rd specified on SW) was NEVER modified (Scenario 3)
        read_rf_reg(5'd8, temp_data);
        check32("Scenario 3: x8 (SW dummy rd) was never written", temp_data, 32'd0);

        // =====================================================================
        // Scenario 2: Load from at least two different word addresses
        //   - Store 0xCAFE_BABE to addr 0x0000_0020
        //   - Store 0x1234_5678 to addr 0x0000_0024
        //   - Load from addr 0x0000_0020 into x6
        //   - Load from addr 0x0000_0024 into x7
        // =====================================================================
        $display("--- Running Scenario 2: Two distinct word address stores & loads ---");
        // Store 1
        drive_mem(32'h0000_0020, 32'hCAFE_BABE, 5'd0, 32'h0000_1010,
                  1'b0, 1'b1, 1'b0, 1'b0, 1'b1);
        // Store 2
        drive_mem(32'h0000_0024, 32'h1234_5678, 5'd0, 32'h0000_1014,
                  1'b0, 1'b1, 1'b0, 1'b0, 1'b1);
        // Load 1: Addr 0x20 -> x6
        drive_mem(32'h0000_0020, 32'h0000_0000, 5'd6, 32'h0000_1018,
                  1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        // Load 2: Addr 0x24 -> x7
        drive_mem(32'h0000_0024, 32'h0000_0000, 5'd7, 32'h0000_101C,
                  1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        drive_bubble();

        // Wait for both loads to retire and commit
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;

        read_rf_reg(5'd6, temp_data);
        check32("Scenario 2: Addr 0x20 loaded to x6 correctly", temp_data, 32'hCAFE_BABE);
        read_rf_reg(5'd7, temp_data);
        check32("Scenario 2: Addr 0x24 loaded to x7 correctly", temp_data, 32'h1234_5678);

        // =====================================================================
        // Scenario 5: ALU result not accidentally replaced by stale memory data
        //   - Immediately follow memory operations with an ALU computation
        //   - ALU result = 0x55AA_55AA, rd = x12, wb_from_mem = 0, mem_read=0
        //   - Address presented is an existing memory word (0x20 containing CAFE_BABE)
        // =====================================================================
        $display("--- Running Scenario 5: ALU result vs Stale Memory Data ---");
        drive_mem(32'h55AA_55AA, 32'h0000_0000, 5'd12, 32'h0000_1020,
                  1'b0, 1'b0, 1'b1, 1'b0, 1'b1); // wb_from_mem = 0
        drive_bubble();

        // When ALU instruction enters WB:
        #1;
        check32("Scenario 5: wb_data is ALU result (not stale memory)", rf_write_data, 32'h55AA_55AA);
        check1 ("Scenario 5: rf_write_en asserted for ALU op", rf_write_en, 1'b1);

        @(posedge clk); #1;
        read_rf_reg(5'd12, temp_data);
        check32("Scenario 5: x12 committed ALU value 0x55AA_55AA", temp_data, 32'h55AA_55AA);

        // =====================================================================
        // Scenario 6: Reset and Bubbles do not cause unintended register writes
        // =====================================================================
        $display("--- Running Scenario 6: Bubble & Reset write protection ---");
        // Canary test: x13 is currently 0.
        // Send a bubble with valid=0, but dirty reg_write=1, rd=13, data=0xBAD0_BAD0
        drive_mem(32'hBAD0_BAD0, 32'hBAD0_BAD0, 5'd13, 32'h0000_1030,
                  1'b0, 1'b0, 1'b1, 1'b0, 1'b0); // valid = 0!
        #1;
        check1 ("Scenario 6: mem_stage_valid is 0", mem_stage_valid, 1'b0);

        @(posedge clk); #1; // bubble latches into mem_wb_reg
        check1 ("Scenario 6: wb_in_valid is 0", wb_in_valid, 1'b0);
        check1 ("Scenario 6: rf_write_en suppressed for bubble in WB", rf_write_en, 1'b0);
        check1 ("Scenario 6: retired is 0 for bubble", retired, 1'b0);

        @(posedge clk); #1;
        read_rf_reg(5'd13, temp_data);
        check32("Scenario 6: x13 remains untouched (0x0)", temp_data, 32'd0);

        // Global Reset during in-flight valid write to x14
        drive_mem(32'hBAD1_BAD1, 32'd0, 5'd14, 32'h0000_1034,
                  1'b0, 1'b0, 1'b1, 1'b0, 1'b1);
        @(negedge clk);
        rst = 1; // assert synchronous reset
        @(posedge clk); #1;
        rst = 0;
        check1 ("Scenario 6: rf_write_en is 0 after reset", rf_write_en, 1'b0);

        @(posedge clk); #1;
        read_rf_reg(5'd14, temp_data);
        check32("Scenario 6: x14 was not written due to reset", temp_data, 32'd0);

        // =====================================================================
        // Scenario 7: Destination x0 protection
        //   - Valid LW with rd = 0
        //   - Valid ALU with rd = 0
        // =====================================================================
        $display("--- Running Scenario 7: Hardwired x0 protection ---");
        // LW to x0
        drive_mem(32'h0000_0020, 32'd0, 5'd0, 32'h0000_1040,
                  1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        // ALU to x0
        drive_mem(32'hFFFF_FFFF, 32'd0, 5'd0, 32'h0000_1044,
                  1'b0, 1'b0, 1'b1, 1'b0, 1'b1);
        drive_bubble();

        @(posedge clk); #1;
        check1 ("Scenario 7: rf_write_en is 0 for rd=0 (LW)", rf_write_en, 1'b0);

        @(posedge clk); #1;
        check1 ("Scenario 7: rf_write_en is 0 for rd=0 (ALU)", rf_write_en, 1'b0);

        @(posedge clk); #1;
        read_rf_reg(5'd0, temp_data);
        check32("Scenario 7: x0 remains strictly 0", temp_data, 32'd0);

        // =====================================================================
        // Scenario 8: Pipeline Stall (Hold en=0) and Flush
        // =====================================================================
        $display("--- Running Scenario 8: Stall & Flush verification ---");
        // Load into x18
        drive_mem(32'h0000_0020, 32'd0, 5'd18, 32'h0000_1050,
                  1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        @(posedge clk); #1; // LW is now captured in mem_wb_reg

        // Assert stall on mem_wb_reg (en=0)
        reg_en = 0;
        drive_mem(32'h9999_9999, 32'd0, 5'd19, 32'h0000_1054,
                  1'b0, 1'b0, 1'b1, 1'b0, 1'b1); // next op in MEM
        #1;
        check32("Scenario 8: Stalled WB holds original x18 target", {27'd0, rf_rd}, {27'd0, 5'd18});

        @(posedge clk); #1;
        // Verify held data didn't get overwritten while en=0
        check32("Scenario 8: Stalled bundle maintained after clock edge", {27'd0, rf_rd}, {27'd0, 5'd18});
        reg_en = 1; // release stall

        // Test flush: squash next operation
        reg_flush = 1;
        @(posedge clk); #1;
        reg_flush = 0;
        check1 ("Scenario 8: Flushed bundle asserts valid_out=0", wb_in_valid, 1'b0);
        check1 ("Scenario 8: Flushed bundle forces rf_write_en=0", rf_write_en, 1'b0);

        // =====================================================================
        // Scenario 9: Full-Throughput Pipelined Streaming
        //   - Cycle 1: SW 0x3333_3333 to addr 0x30
        //   - Cycle 2: LW from addr 0x30 into x22
        //   - Cycle 3: ALU 0x4444_4444 into x23
        //   - Cycle 4: ALU 0x5555_5555 into x24
        //   - Cycle 5: LW from addr 0x20 into x25
        // =====================================================================
        $display("--- Running Scenario 9: Pipelined Streaming Throughput ---");
        drive_mem(32'h0000_0030, 32'h3333_3333, 5'd0,  32'h1060, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1);
        drive_mem(32'h0000_0030, 32'h0000_0000, 5'd22, 32'h1064, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        drive_mem(32'h4444_4444, 32'h0000_0000, 5'd23, 32'h1068, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1);
        drive_mem(32'h5555_5555, 32'h0000_0000, 5'd24, 32'h106C, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1);
        drive_mem(32'h0000_0020, 32'h0000_0000, 5'd25, 32'h1070, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1);
        drive_bubble();

        // Wait for streaming pipeline to drain completely
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;

        read_rf_reg(5'd22, temp_data);
        check32("Scenario 9: Streamed LW into x22 matches", temp_data, 32'h3333_3333);
        read_rf_reg(5'd23, temp_data);
        check32("Scenario 9: Streamed ALU into x23 matches", temp_data, 32'h4444_4444);
        read_rf_reg(5'd24, temp_data);
        check32("Scenario 9: Streamed ALU into x24 matches", temp_data, 32'h5555_5555);
        read_rf_reg(5'd25, temp_data);
        check32("Scenario 9: Streamed LW into x25 matches", temp_data, 32'hCAFE_BABE);

        // =====================================================================
        // Final Accounting
        // =====================================================================
        $display("===============================================================");
        if (errors == 0)
            $display("PASS: tb_load_store_wb — all %0d checks passed successfully!", test_count);
        else
            $display("FAILED: tb_load_store_wb — %0d error(s) out of %0d checks", errors, test_count);
        $display("===============================================================");

        $finish;
    end

endmodule
