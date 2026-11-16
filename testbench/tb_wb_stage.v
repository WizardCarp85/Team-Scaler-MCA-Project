// =============================================================================
// Testbench: tb_wb_stage
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #20 - Write-Back Logic & Register File Interface
//
// Description:
//   Self-checking verification suite for the Write-Back (WB) stage and its
//   integration with the Instruction Decode (ID) register file.
//
// Test Scenarios Covered:
//   1. ALU-Result Selection:
//      - Selects alu_result when wb_from_mem = 0 (R-type and I-immediate ops).
//   2. Load-Data Selection:
//      - Selects load_data when wb_from_mem = 1 (LW load ops).
//   3. Side-Effect Gating:
//      - Disabled write (reg_write = 0, e.g. SW, BEQ, BNE) forces wb_write_en = 0.
//      - Bubble cycle (valid = 0) forces wb_write_en = 0 and retired = 0.
//      - Destination x0 (rd = 5'd0) forces wb_write_en = 0.
//   4. Metadata Pass-through:
//      - Retired, pc_out, and pc_plus4_out accurately track valid and PC inputs.
//   5. Register File Integration:
//      - Connects wb_stage outputs directly to M2's register_file.
//      - Verifies ALU computation commits to register file and reads back.
//      - Verifies LW load data commits to register file and reads back.
//      - Verifies write-through bypass on the active write cycle.
//      - Verifies x0 remains zero even if targeted by valid write instructions.
//      - Verifies bubbles and unasserted reg_write never modify register contents.
//
// Run from repository root:
//   iverilog -g2012 -o simulation/tb_wb_stage.vvp \
//       testbench/tb_wb_stage.v \
//       rtl/stages/wb_stage.v \
//       rtl/stages/register_file.v
//   vvp simulation/tb_wb_stage.vvp
// =============================================================================

`timescale 1ns/1ps

module tb_wb_stage;

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    reg         clk         = 0;
    reg         rst         = 0;

    // wb_stage inputs
    reg  [31:0] alu_result  = 32'd0;
    reg  [31:0] load_data   = 32'd0;
    reg  [4:0]  rd          = 5'd0;
    reg  [31:0] pc          = 32'd0;
    reg  [31:0] pc_plus4    = 32'd0;
    reg         reg_write   = 1'b0;
    reg         wb_from_mem = 1'b0;
    reg         valid       = 1'b0;

    // wb_stage outputs
    wire        wb_write_en;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;
    wire [31:0] pc_out;
    wire [31:0] pc_plus4_out;
    wire        retired;

    // register_file read ports
    reg  [4:0]  rf_rs1 = 5'd0;
    reg  [4:0]  rf_rs2 = 5'd0;
    wire [31:0] rf_rs1_data;
    wire [31:0] rf_rs2_data;

    // -------------------------------------------------------------------------
    // Submodule Instantiations
    // -------------------------------------------------------------------------
    // 1. Write-Back Stage DUT
    wb_stage dut (
        .alu_result   (alu_result),
        .load_data    (load_data),
        .rd           (rd),
        .pc           (pc),
        .pc_plus4     (pc_plus4),
        .reg_write    (reg_write),
        .wb_from_mem  (wb_from_mem),
        .valid        (valid),
        .wb_write_en  (wb_write_en),
        .wb_rd        (wb_rd),
        .wb_data      (wb_data),
        .pc_out       (pc_out),
        .pc_plus4_out (pc_plus4_out),
        .retired      (retired)
    );

    // 2. M2 Register File Instance (Agreed ID-Stage Interface)
    register_file u_rf (
        .clk        (clk),
        .rst        (rst),
        .write_en   (wb_write_en),
        .rd         (wb_rd),
        .write_data (wb_data),
        .rs1        (rf_rs1),
        .rs2        (rf_rs2),
        .rs1_data   (rf_rs1_data),
        .rs2_data   (rf_rs2_data)
    );

    // -------------------------------------------------------------------------
    // Clock Generation (10ns period)
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Test Accounting & Helper Tasks
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

    // -------------------------------------------------------------------------
    // Main Verification Sequence
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("simulation/tb_wb_stage.vcd");
        $dumpvars(0, tb_wb_stage);

        // Reset the register file first
        rst = 1;
        valid = 0;
        reg_write = 0;
        @(posedge clk); #1;
        rst = 0;
        @(posedge clk); #1;

        // =====================================================================
        // Test 1: ALU-Result Selection (wb_from_mem = 0)
        // =====================================================================
        alu_result  = 32'hDEAD_BEEF;
        load_data   = 32'hCAFE_BABE;
        rd          = 5'd1;
        pc          = 32'h0000_1000;
        pc_plus4    = 32'h0000_1004;
        reg_write   = 1'b1;
        wb_from_mem = 1'b0;
        valid       = 1'b1;
        #1;

        check32("T1: wb_data selects alu_result", wb_data, 32'hDEAD_BEEF);
        check32("T1: wb_rd matches rd", {27'd0, wb_rd}, {27'd0, 5'd1});
        check1 ("T1: wb_write_en asserted for valid ALU write", wb_write_en, 1'b1);
        check1 ("T1: retired asserted", retired, 1'b1);
        check32("T1: pc_out matches", pc_out, 32'h0000_1000);
        check32("T1: pc_plus4_out matches", pc_plus4_out, 32'h0000_1004);

        // =====================================================================
        // Test 2: Load-Data Selection (wb_from_mem = 1)
        // =====================================================================
        alu_result  = 32'h0000_0080; // memory effective address
        load_data   = 32'h1234_5678; // loaded word from data_mem
        rd          = 5'd2;
        pc          = 32'h0000_1008;
        pc_plus4    = 32'h0000_100C;
        reg_write   = 1'b1;
        wb_from_mem = 1'b1;
        valid       = 1'b1;
        #1;

        check32("T2: wb_data selects load_data", wb_data, 32'h1234_5678);
        check32("T2: wb_rd matches rd", {27'd0, wb_rd}, {27'd0, 5'd2});
        check1 ("T2: wb_write_en asserted for valid LW write", wb_write_en, 1'b1);
        check1 ("T2: retired asserted", retired, 1'b1);

        // =====================================================================
        // Test 3: Destination x0 Gating (rd = 5'd0)
        // =====================================================================
        alu_result  = 32'hFFFF_FFFF;
        load_data   = 32'hAAAA_5555;
        rd          = 5'd0;          // Attempt write to x0
        reg_write   = 1'b1;
        wb_from_mem = 1'b0;
        valid       = 1'b1;
        #1;

        check1 ("T3: wb_write_en deasserted for rd == x0", wb_write_en, 1'b0);
        check32("T3: wb_rd is 0", {27'd0, wb_rd}, 32'd0);

        // =====================================================================
        // Test 4: Disabled Write Gating (reg_write = 0, e.g. SW / BEQ / BNE)
        // =====================================================================
        alu_result  = 32'h0000_0040;
        load_data   = 32'h0000_0000;
        rd          = 5'd5;
        reg_write   = 1'b0;          // No-write instruction
        wb_from_mem = 1'b0;
        valid       = 1'b1;
        #1;

        check1 ("T4: wb_write_en deasserted when reg_write == 0", wb_write_en, 1'b0);

        // =====================================================================
        // Test 5: Bubble Cycle Gating (valid = 0)
        // =====================================================================
        alu_result  = 32'hBAD0_BAD0;
        load_data   = 32'hBAD1_BAD1;
        rd          = 5'd6;
        reg_write   = 1'b1;          // Asserted but invalid/bubble
        wb_from_mem = 1'b0;
        valid       = 1'b0;
        #1;

        check1 ("T5: wb_write_en deasserted on bubble (valid == 0)", wb_write_en, 1'b0);
        check1 ("T5: retired deasserted on bubble", retired, 1'b0);

        // =====================================================================
        // Test 6: Register File Integration - ALU Operation Commit & Bypass
        // =====================================================================
        @(negedge clk);
        alu_result  = 32'hA1B2_C3D4;
        load_data   = 32'h0000_0000;
        rd          = 5'd10;
        reg_write   = 1'b1;
        wb_from_mem = 1'b0;
        valid       = 1'b1;
        rf_rs1      = 5'd10;         // Read same register simultaneously
        #1;

        // Verify combinational write-through bypass from M2 register file
        check32("T6: Write-through bypass to rs1", rf_rs1_data, 32'hA1B2_C3D4);

        // Clock the rising edge to commit storage
        @(posedge clk); #1;

        // Change inputs to ensure value is preserved in storage
        alu_result = 32'd0;
        valid      = 0;
        reg_write  = 0;
        #1;
        check32("T6: Committed value retained in x10", rf_rs1_data, 32'hA1B2_C3D4);

        // =====================================================================
        // Test 7: Register File Integration - LW Load Data Commit
        // =====================================================================
        @(negedge clk);
        alu_result  = 32'h0000_0020;
        load_data   = 32'h7788_99AA;
        rd          = 5'd15;
        reg_write   = 1'b1;
        wb_from_mem = 1'b1;
        valid       = 1'b1;
        rf_rs1      = 5'd15;
        #1;

        check32("T7: LW write-through bypass", rf_rs1_data, 32'h7788_99AA);
        @(posedge clk); #1;

        valid     = 0;
        reg_write = 0;
        #1;
        check32("T7: Committed LW data retained in x15", rf_rs1_data, 32'h7788_99AA);

        // =====================================================================
        // Test 8: Register File Integration - Write to x0 Never Modifies Storage
        // =====================================================================
        @(negedge clk);
        alu_result  = 32'hFFFF_FFFF;
        load_data   = 32'hFFFF_FFFF;
        rd          = 5'd0;
        reg_write   = 1'b1;
        wb_from_mem = 1'b0;
        valid       = 1'b1;
        rf_rs1      = 5'd0;
        #1;

        check1 ("T8: wb_write_en is 0 for x0", wb_write_en, 1'b0);
        check32("T8: rs1=0 reads 0 during bypass attempt", rf_rs1_data, 32'd0);
        @(posedge clk); #1;
        check32("T8: x0 remains zero after posedge", rf_rs1_data, 32'd0);

        // Repeat with load data on x0
        @(negedge clk);
        wb_from_mem = 1'b1;
        @(posedge clk); #1;
        check32("T8: x0 remains zero after LW attempt", rf_rs1_data, 32'd0);

        // =====================================================================
        // Test 9: Register File Integration - Bubble Never Writes
        // =====================================================================
        // We know x10 has 32'hA1B2_C3D4. Attempt to overwrite x10 during a bubble.
        @(negedge clk);
        alu_result  = 32'h0000_0000;
        rd          = 5'd10;
        reg_write   = 1'b1;
        wb_from_mem = 1'b0;
        valid       = 1'b0;          // Bubble!
        rf_rs1      = 5'd10;
        #1;

        check1 ("T9: wb_write_en suppressed during bubble", wb_write_en, 1'b0);
        @(posedge clk); #1;
        check32("T9: x10 uncorrupted after bubble clock", rf_rs1_data, 32'hA1B2_C3D4);

        // =====================================================================
        // Test 10: Register File Integration - SW / Branch (reg_write=0) Never Writes
        // =====================================================================
        // Attempt to overwrite x15 with reg_write = 0
        @(negedge clk);
        alu_result  = 32'h0000_0000;
        load_data   = 32'h0000_0000;
        rd          = 5'd15;
        reg_write   = 1'b0;          // Store or branch instruction
        wb_from_mem = 1'b0;
        valid       = 1'b1;
        rf_rs1      = 5'd15;
        #1;

        check1 ("T10: wb_write_en suppressed when reg_write == 0", wb_write_en, 1'b0);
        @(posedge clk); #1;
        check32("T10: x15 uncorrupted after store/branch cycle", rf_rs1_data, 32'h7788_99AA);

        // =====================================================================
        // Test 11: Consecutive Back-to-Back Register Writes (ALU then LW)
        // =====================================================================
        @(negedge clk);
        alu_result  = 32'h1111_1111;
        rd          = 5'd20;
        reg_write   = 1'b1;
        wb_from_mem = 1'b0;
        valid       = 1'b1;

        @(negedge clk);
        // Next cycle back-to-back: LW writing x21
        load_data   = 32'h2222_2222;
        rd          = 5'd21;
        reg_write   = 1'b1;
        wb_from_mem = 1'b1;
        valid       = 1'b1;

        @(posedge clk); #1;
        valid     = 0;
        reg_write = 0;

        rf_rs1 = 5'd20;
        rf_rs2 = 5'd21;
        #1;
        check32("T11: x20 has back-to-back ALU write value", rf_rs1_data, 32'h1111_1111);
        check32("T11: x21 has back-to-back LW write value",  rf_rs2_data, 32'h2222_2222);

        // =====================================================================
        // Summary
        // =====================================================================
        if (errors == 0)
            $display("PASS: tb_wb_stage — all %0d checks completed successfully", test_count);
        else
            $display("FAILED: tb_wb_stage — %0d error(s) out of %0d checks", errors, test_count);

        $finish;
    end

endmodule
