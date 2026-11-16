// =============================================================================
// Testbench: tb_hazard_detection
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #22 - Load-Use Hazard Detection & Pipeline Stall Control
//
// Description:
//   Comprehensive, self-checking verification testbench for the Hazard
//   Detection Unit (hazard_detection.v).
//
// Test Coverage:
//   1. Independent instructions (no RAW dependency)
//   2. Load-Use hazard on rs1 (R-type, I-type, SW, Branch consumers)
//   3. Load-Use hazard on rs2 (R-type, SW, Branch consumers)
//   4. Load-Use hazard on both rs1 and rs2 simultaneously
//   5. False hazard immunity: rd = x0 (never stalls)
//   6. False hazard immunity: I-type consumer immediate overlap (uses_rs2 = 0)
//   7. False hazard immunity: non-load instruction in EX (ALU forwarding resolves)
//   8. False hazard immunity: invalid/bubble instruction in EX (ex_valid = 0)
//   9. False hazard immunity: invalid/bubble instruction in ID (id_valid = 0)
//  10. Branch taken override: branch_taken in EX suppresses stall
//  11. Non-forwarding mode (FORWARDING_SUPPORTED = 0) RAW dependency detection
//  12. Cycle-accurate pipeline timing verification with if_id_reg and id_ex_reg:
//      Validates that exactly 1 stall cycle is inserted, PC/IF-ID hold, and ID/EX bubble.
//
// Compilation & Simulation:
//   iverilog -g2012 -o simulation/tb_hazard_detection.vvp \
//       testbench/tb_hazard_detection.v \
//       rtl/stages/hazard_detection.v \
//       rtl/pipeline_registers/if_id_reg.v \
//       rtl/pipeline_registers/id_ex_reg.v
//   vvp simulation/tb_hazard_detection.vvp
// =============================================================================

`timescale 1ns/1ps

module tb_hazard_detection;

    // -------------------------------------------------------------------------
    // DUT Inputs & Outputs
    // -------------------------------------------------------------------------
    reg  [4:0]  id_rs1;
    reg  [4:0]  id_rs2;
    reg         id_uses_rs1;
    reg         id_uses_rs2;
    reg         id_valid;

    reg  [4:0]  ex_rd;
    reg         ex_mem_read;
    reg         ex_reg_write;
    reg         ex_valid;

    reg  [4:0]  mem_rd;
    reg         mem_mem_read;
    reg         mem_reg_write;
    reg         mem_valid;

    reg         branch_taken;

    wire        stall;
    wire        pc_stall;
    wire        pc_en;
    wire        if_id_stall;
    wire        if_id_en;
    wire        id_ex_flush;
    wire        id_ex_bubble;

    integer test_count = 0;

    // -------------------------------------------------------------------------
    // Instantiate DUT: Non-Forwarding Mode (FORWARDING_SUPPORTED = 0)
    // -------------------------------------------------------------------------
    wire nf_stall;
    hazard_detection #(.FORWARDING_SUPPORTED(0)) u_non_fwd (
        .id_rs1         (id_rs1),
        .id_rs2         (id_rs2),
        .id_uses_rs1    (id_uses_rs1),
        .id_uses_rs2    (id_uses_rs2),
        .id_valid       (id_valid),
        .ex_rd          (ex_rd),
        .ex_mem_read    (ex_mem_read),
        .ex_reg_write   (ex_reg_write),
        .ex_valid       (ex_valid),
        .mem_rd         (mem_rd),
        .mem_mem_read   (mem_mem_read),
        .mem_reg_write  (mem_reg_write),
        .mem_valid      (mem_valid),
        .branch_taken   (branch_taken),
        .stall          (nf_stall),
        .pc_stall       (),
        .pc_en          (),
        .if_id_stall    (),
        .if_id_en       (),
        .id_ex_flush    (),
        .id_ex_bubble   ()
    );
    hazard_detection #(.FORWARDING_SUPPORTED(1)) dut (
        .id_rs1         (id_rs1),
        .id_rs2         (id_rs2),
        .id_uses_rs1    (id_uses_rs1),
        .id_uses_rs2    (id_uses_rs2),
        .id_valid       (id_valid),
        .ex_rd          (ex_rd),
        .ex_mem_read    (ex_mem_read),
        .ex_reg_write   (ex_reg_write),
        .ex_valid       (ex_valid),
        .mem_rd         (mem_rd),
        .mem_mem_read   (mem_mem_read),
        .mem_reg_write  (mem_reg_write),
        .mem_valid      (mem_valid),
        .branch_taken   (branch_taken),
        .stall          (stall),
        .pc_stall       (pc_stall),
        .pc_en          (pc_en),
        .if_id_stall    (if_id_stall),
        .if_id_en       (if_id_en),
        .id_ex_flush    (id_ex_flush),
        .id_ex_bubble   (id_ex_bubble)
    );

    // -------------------------------------------------------------------------
    // Check Task
    // -------------------------------------------------------------------------
    task check;
        input        exp_stall;
        input [127:0] test_name;
        begin
            #1;
            if (stall !== exp_stall ||
                pc_stall !== exp_stall ||
                pc_en !== ~exp_stall ||
                if_id_stall !== exp_stall ||
                if_id_en !== ~exp_stall ||
                id_ex_flush !== exp_stall ||
                id_ex_bubble !== exp_stall) begin
                $fatal(1, "FAIL [%0s]: exp_stall=%b | got: stall=%b pc_stall=%b pc_en=%b if_id_stall=%b if_id_en=%b id_ex_flush=%b",
                       test_name, exp_stall, stall, pc_stall, pc_en, if_id_stall, if_id_en, id_ex_flush);
            end
            test_count = test_count + 1;
        end
    endtask

    // Helper task to clear inputs to idle state
    task reset_inputs;
        begin
            id_rs1        = 5'd0;
            id_rs2        = 5'd0;
            id_uses_rs1   = 1'b0;
            id_uses_rs2   = 1'b0;
            id_valid      = 1'b0;
            ex_rd         = 5'd0;
            ex_mem_read   = 1'b0;
            ex_reg_write  = 1'b0;
            ex_valid      = 1'b0;
            mem_rd        = 5'd0;
            mem_mem_read  = 1'b0;
            mem_reg_write = 1'b0;
            mem_valid     = 1'b0;
            branch_taken  = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Pipeline Clock & Integration Signals
    // -------------------------------------------------------------------------
    reg clk = 0;
    always #5 clk = ~clk;

    // IF/ID Register instances for timing test
    reg        pipe_rst = 0;
    wire [31:0] pipe_if_id_pc;
    wire [31:0] pipe_if_id_pc4;
    wire [31:0] pipe_if_id_instr;
    wire        pipe_if_id_valid;

    reg  [31:0] pipe_if_pc_in;
    reg  [31:0] pipe_if_instr_in;

    if_id_reg u_test_if_id (
        .clk         (clk),
        .rst         (pipe_rst),
        .en          (if_id_en),
        .flush       (1'b0),
        .pc_in       (pipe_if_pc_in),
        .pc_plus4_in (pipe_if_pc_in + 32'd4),
        .instr_in    (pipe_if_instr_in),
        .pc_out      (pipe_if_id_pc),
        .pc_plus4_out(pipe_if_id_pc4),
        .instr_out   (pipe_if_id_instr),
        .valid_out   (pipe_if_id_valid)
    );

    // ID/EX Register instance for timing test
    wire [31:0] pipe_id_ex_pc;
    wire [31:0] pipe_id_ex_pc4;
    wire [31:0] pipe_id_ex_rs1_data;
    wire [31:0] pipe_id_ex_rs2_data;
    wire [31:0] pipe_id_ex_imm;
    wire [4:0]  pipe_id_ex_rs1;
    wire [4:0]  pipe_id_ex_rs2;
    wire [4:0]  pipe_id_ex_rd;
    wire [2:0]  pipe_id_ex_funct3;
    wire [6:0]  pipe_id_ex_funct7;
    wire [1:0]  pipe_id_ex_alu_op;
    wire [1:0]  pipe_id_ex_branch_type;
    wire        pipe_id_ex_alu_src_imm;
    wire        pipe_id_ex_mem_read;
    wire        pipe_id_ex_mem_write;
    wire        pipe_id_ex_reg_write;
    wire        pipe_id_ex_wb_from_mem;
    wire        pipe_id_ex_valid;

    reg  [4:0]  pipe_id_rd_in;
    reg         pipe_id_mem_read_in;
    reg         pipe_id_reg_write_in;
    reg         pipe_id_valid_in;

    id_ex_reg u_test_id_ex (
        .clk             (clk),
        .rst             (pipe_rst),
        .en              (1'b1),
        .flush           (id_ex_flush),
        .pc_in           (32'h00001000),
        .pc_plus4_in     (32'h00001004),
        .rs1_data_in     (32'd0),
        .rs2_data_in     (32'd0),
        .imm_in          (32'd0),
        .rs1_in          (id_rs1),
        .rs2_in          (id_rs2),
        .rd_in           (pipe_id_rd_in),
        .funct3_in       (3'd0),
        .funct7_in       (7'd0),
        .alu_op_in       (2'd0),
        .branch_type_in  (2'd0),
        .alu_src_imm_in  (1'b0),
        .mem_read_in     (pipe_id_mem_read_in),
        .mem_write_in    (1'b0),
        .reg_write_in    (pipe_id_reg_write_in),
        .wb_from_mem_in  (pipe_id_mem_read_in),
        .valid_in        (pipe_id_valid_in),
        .pc_out          (pipe_id_ex_pc),
        .pc_plus4_out    (pipe_id_ex_pc4),
        .rs1_data_out    (pipe_id_ex_rs1_data),
        .rs2_data_out    (pipe_id_ex_rs2_data),
        .imm_out         (pipe_id_ex_imm),
        .rs1_out         (pipe_id_ex_rs1),
        .rs2_out         (pipe_id_ex_rs2),
        .rd_out          (pipe_id_ex_rd),
        .funct3_out      (pipe_id_ex_funct3),
        .funct7_out      (pipe_id_ex_funct7),
        .alu_op_out      (pipe_id_ex_alu_op),
        .branch_type_out (pipe_id_ex_branch_type),
        .alu_src_imm_out (pipe_id_ex_alu_src_imm),
        .mem_read_out    (pipe_id_ex_mem_read),
        .mem_write_out   (pipe_id_ex_mem_write),
        .reg_write_out   (pipe_id_ex_reg_write),
        .wb_from_mem_out (pipe_id_ex_wb_from_mem),
        .valid_out       (pipe_id_ex_valid)
    );

    // -------------------------------------------------------------------------
    // Main Verification Procedure
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("simulation/tb_hazard_detection.vcd");
        $dumpvars(0, tb_hazard_detection);

        reset_inputs();

        // ====================================================================
        // Scenario 1: Independent Instructions (No Hazard)
        // ====================================================================
        // EX has LW x5; ID has ADD x6, x1, x2 (consumes x1, x2; no match with x5)
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd1; id_uses_rs2 = 1; id_rs2 = 5'd2;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd5;
        check(1'b0, "Independent instructions: no stall");

        // EX has ADD x5; ID has SUB x8, x6, x7 (no match)
        ex_mem_read = 0; ex_rd = 5'd5;
        id_rs1 = 5'd6; id_rs2 = 5'd7;
        check(1'b0, "ALU in EX, independent ID: no stall");

        // ====================================================================
        // Scenario 2: Load-Use Hazard on rs1
        // ====================================================================
        // EX has LW x5; ID has ADD x6, x5, x2 (rs1 matches x5)
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd5; id_uses_rs2 = 1; id_rs2 = 5'd2;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd5;
        check(1'b1, "Load-use on rs1: stall asserted");

        // EX has LW x15; ID has ADDI x8, x15, 4 (rs1 matches x15)
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd15; id_uses_rs2 = 0; id_rs2 = 5'd4;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd15;
        check(1'b1, "Load-use on rs1 (ADDI consumer): stall asserted");

        // EX has LW x3; ID has SW x2, 0(x3) (base address rs1 matches x3)
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd3; id_uses_rs2 = 1; id_rs2 = 5'd2;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd3;
        check(1'b1, "Load-use on rs1 (SW base address): stall asserted");

        // EX has LW x4; ID has BEQ x4, x10, target (branch op_a rs1 matches x4)
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd4; id_uses_rs2 = 1; id_rs2 = 5'd10;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd4;
        check(1'b1, "Load-use on rs1 (BEQ operand A): stall asserted");

        // ====================================================================
        // Scenario 3: Load-Use Hazard on rs2
        // ====================================================================
        // EX has LW x7; ID has SUB x8, x2, x7 (rs2 matches x7)
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd2; id_uses_rs2 = 1; id_rs2 = 5'd7;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd7;
        check(1'b1, "Load-use on rs2: stall asserted");

        // EX has LW x12; ID has SW x12, 4(x1) (store data rs2 matches x12)
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd1; id_uses_rs2 = 1; id_rs2 = 5'd12;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd12;
        check(1'b1, "Load-use on rs2 (SW store data): stall asserted");

        // EX has LW x9; ID has BNE x1, x9, target (branch op_b rs2 matches x9)
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd1; id_uses_rs2 = 1; id_rs2 = 5'd9;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd9;
        check(1'b1, "Load-use on rs2 (BNE operand B): stall asserted");

        // ====================================================================
        // Scenario 4: Load-Use Hazard on both rs1 and rs2
        // ====================================================================
        // EX has LW x5; ID has ADD x6, x5, x5
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd5; id_uses_rs2 = 1; id_rs2 = 5'd5;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd5;
        check(1'b1, "Load-use on both rs1 and rs2: stall asserted");

        // ====================================================================
        // Scenario 5: False Hazard Immunity: rd = x0
        // ====================================================================
        // EX has LW x0, 0(x1); ID has ADD x6, x0, x2
        // x0 is permanently zero; writes to x0 are discarded. Must NOT stall!
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd0; id_uses_rs2 = 1; id_rs2 = 5'd2;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd0;
        check(1'b0, "Immunity: LW x0 does NOT stall rs1=x0");

        // EX has LW x0; ID has ADD x6, x2, x0
        id_rs1 = 5'd2; id_rs2 = 5'd0;
        check(1'b0, "Immunity: LW x0 does NOT stall rs2=x0");

        // ====================================================================
        // Scenario 6: False Hazard Immunity: Immediate Bits in rs2 field
        // ====================================================================
        // In I-type instructions (ADDI, LW), bits [24:20] hold immediate bits.
        // id_uses_rs2 is set to 0 by id_stage.
        // EX has LW x5; ID has ADDI x6, x1, 5 (imm[4:0] == 5 matches ex_rd, but uses_rs2 == 0)
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd1; id_uses_rs2 = 1'b0; id_rs2 = 5'd5;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd5;
        check(1'b0, "Immunity: ADDI immediate bits in rs2 field do NOT stall");

        // EX has LW x8; ID has LW x6, 8(x1) (imm bits match x8, uses_rs2 == 0)
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd1; id_uses_rs2 = 1'b0; id_rs2 = 5'd8;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd8;
        check(1'b0, "Immunity: LW offset bits in rs2 field do NOT stall");

        // ====================================================================
        // Scenario 7: False Hazard Immunity: Non-Load in EX (ALU Forwarding)
        // ====================================================================
        // EX has ADD x5, x1, x2 (ex_mem_read = 0); ID has ADD x6, x5, x3
        // Resolved by EX-to-EX forwarding in next cycle! Must NOT stall!
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd5; id_uses_rs2 = 1; id_rs2 = 5'd3;
        ex_valid = 1; ex_mem_read = 0; ex_reg_write = 1; ex_rd = 5'd5;
        check(1'b0, "Immunity: R-type ADD in EX does NOT stall (EX forwarding)");

        // EX has SUB x7, x1, x2; ID has ADD x6, x3, x7
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd3; id_uses_rs2 = 1; id_rs2 = 5'd7;
        ex_valid = 1; ex_mem_read = 0; ex_reg_write = 1; ex_rd = 5'd7;
        check(1'b0, "Immunity: R-type SUB in EX does NOT stall (EX forwarding)");

        // EX has ADDI x9, x1, 10; ID has ADD x6, x9, x3
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd9; id_uses_rs2 = 1; id_rs2 = 5'd3;
        ex_valid = 1; ex_mem_read = 0; ex_reg_write = 1; ex_rd = 5'd9;
        check(1'b0, "Immunity: I-type ADDI in EX does NOT stall (EX forwarding)");

        // ====================================================================
        // Scenario 8: False Hazard Immunity: Invalid / Bubble in EX
        // ====================================================================
        // ex_valid = 0 (bubble/flush in EX stage)
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd5; id_uses_rs2 = 1; id_rs2 = 5'd2;
        ex_valid = 1'b0; ex_mem_read = 1'b1; ex_reg_write = 1'b1; ex_rd = 5'd5;
        check(1'b0, "Immunity: Invalid bubble in EX does NOT stall");

        // ====================================================================
        // Scenario 9: False Hazard Immunity: Invalid / Bubble in ID
        // ====================================================================
        // id_valid = 0 (bubble/flush in ID stage)
        reset_inputs();
        id_valid = 1'b0; id_uses_rs1 = 1'b0; id_rs1 = 5'd5; id_uses_rs2 = 1'b0; id_rs2 = 5'd5;
        ex_valid = 1'b1; ex_mem_read = 1'b1; ex_reg_write = 1'b1; ex_rd = 5'd5;
        check(1'b0, "Immunity: Invalid bubble in ID does NOT stall");

        // ====================================================================
        // Scenario 10: Branch Taken in EX Overrides Stall
        // ====================================================================
        // Load-use condition is present, BUT branch_taken is asserted.
        // Branch redirect flushes younger stages; stall must NOT lock pipeline.
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd5; id_uses_rs2 = 1; id_rs2 = 5'd2;
        ex_valid = 1; ex_mem_read = 1; ex_reg_write = 1; ex_rd = 5'd5;
        branch_taken = 1'b1;
        check(1'b0, "Branch taken in EX overrides stall request");

        // ====================================================================
        // Scenario 11: Non-Forwarding Mode Verification
        // ====================================================================
        // Test module with FORWARDING_SUPPORTED = 0
        // In non-fwd mode: ALU in EX writing to x5 while ID reads x5 MUST stall!
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd5;
        ex_valid = 1; ex_mem_read = 0; ex_reg_write = 1; ex_rd = 5'd5;
        #1;
        if (nf_stall !== 1'b1) $fatal(1, "FAIL [Non-fwd EX RAW]: exp 1 got %b", nf_stall);
        test_count = test_count + 1;

        // In non-fwd mode: ALU in MEM writing to x6 while ID reads x6 MUST stall!
        reset_inputs();
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd6;
        mem_valid = 1; mem_reg_write = 1; mem_rd = 5'd6;
        #1;
        if (nf_stall !== 1'b1) $fatal(1, "FAIL [Non-fwd MEM RAW]: exp 1 got %b", nf_stall);
        test_count = test_count + 1;

        // ====================================================================
        // Scenario 12: Cycle-Accurate Multi-Cycle Pipeline Timing Verification
        // ====================================================================
        // Synchronous pipeline test with if_id_reg and id_ex_reg:
        // Program:
        //   Instr 0: LW  x5, 0(x10)
        //   Instr 1: ADD x6, x5, x1   <-- Load-use hazard on x5!
        //   Instr 2: SUB x7, x2, x3   <-- In IF during stall
        //
        // Timing sequence:
        //   Cycle 1: LW in ID, ADD in IF
        //   Cycle 2: LW in EX, ADD in ID -> STALL asserted!
        //   Cycle 3: STALL active:
        //            - PC & IF/ID hold (ADD held in IF/ID)
        //            - Bubble inserted into ID/EX (valid = 0)
        //            - LW advances to MEM
        //            - STALL clears!
        //   Cycle 4: ADD enters EX (valid = 1), SUB enters ID. Resume normal flow.
        // ====================================================================
        pipe_rst = 1;
        @(posedge clk);
        #1;
        pipe_rst = 0;
        reset_inputs();

        // Cycle 1: LW is in ID stage
        //   (Simulated ID outputs for LW x5, 0(x10))
        pipe_if_pc_in = 32'h00000004;      // ADD is being fetched in IF
        pipe_if_instr_in = 32'h00128333;   // ADD x6, x5, x1
        id_valid = 1; id_uses_rs1 = 1; id_rs1 = 5'd10; id_uses_rs2 = 0; id_rs2 = 5'd0;
        pipe_id_rd_in = 5'd5; pipe_id_mem_read_in = 1'b1; pipe_id_reg_write_in = 1'b1; pipe_id_valid_in = 1'b1;

        // No instruction in EX yet
        ex_valid = 0; ex_mem_read = 0; ex_rd = 5'd0;
        #1;
        if (stall !== 1'b0) $fatal(1, "FAIL Cycle 1: Unexpected stall");
        test_count = test_count + 1;

        @(posedge clk); #1;
        // Cycle 2:
        //   LW x5 has entered EX stage (id_ex_reg outputs)
        ex_valid    = pipe_id_ex_valid;
        ex_mem_read = pipe_id_ex_mem_read;
        ex_rd       = pipe_id_ex_rd;

        //   ADD x6, x5, x1 has entered ID stage (if_id_reg outputs)
        id_valid    = pipe_if_id_valid;
        id_uses_rs1 = 1'b1;
        id_rs1      = 5'd5; // ADD reads x5!
        id_uses_rs2 = 1'b1;
        id_rs2      = 5'd1;

        //   In IF: SUB x7, x2, x3 is being fetched
        pipe_if_pc_in = 32'h00000008;
        pipe_if_instr_in = 32'h003103B3;

        #1;
        // Verify hazard detection combinationally asserts STALL in Cycle 2
        if (stall !== 1'b1) $fatal(1, "FAIL Cycle 2: Expected stall == 1 for Load-Use, got %b", stall);
        if (if_id_en !== 1'b0) $fatal(1, "FAIL Cycle 2: Expected if_id_en == 0 (hold), got %b", if_id_en);
        if (id_ex_flush !== 1'b1) $fatal(1, "FAIL Cycle 2: Expected id_ex_flush == 1 (bubble), got %b", id_ex_flush);
        test_count = test_count + 1;

        // Clock edge: Cycle 2 -> Cycle 3
        @(posedge clk); #1;
        // Cycle 3 (Stall Cycle in progress):
        //   LW has advanced to MEM stage
        mem_valid    = 1'b1;
        mem_mem_read = 1'b1;
        mem_rd       = 5'd5;

        //   ID/EX captured a bubble due to id_ex_flush = 1!
        ex_valid    = pipe_id_ex_valid;
        ex_mem_read = pipe_id_ex_mem_read;
        ex_rd       = pipe_id_ex_rd;

        if (pipe_id_ex_valid !== 1'b0) $fatal(1, "FAIL Cycle 3: Expected ID/EX bubble (valid=0), got %b", pipe_id_ex_valid);

        //   IF/ID held the ADD instruction due to if_id_en = 0!
        if (pipe_if_id_pc !== 32'h00000004) $fatal(1, "FAIL Cycle 3: Expected IF/ID PC to hold 0x04, got %h", pipe_if_id_pc);
        if (pipe_if_id_instr !== 32'h00128333) $fatal(1, "FAIL Cycle 3: Expected IF/ID instr to hold ADD, got %h", pipe_if_id_instr);

        //   Now that EX holds a bubble, hazard detection should CLEAR combinationally!
        #1;
        if (stall !== 1'b0) $fatal(1, "FAIL Cycle 3: Expected stall == 0 after 1 bubble cycle, got %b", stall);
        if (if_id_en !== 1'b1) $fatal(1, "FAIL Cycle 3: Expected if_id_en == 1 to release hold, got %b", if_id_en);
        if (id_ex_flush !== 1'b0) $fatal(1, "FAIL Cycle 3: Expected id_ex_flush == 0, got %b", id_ex_flush);
        test_count = test_count + 1;

        // Clock edge: Cycle 3 -> Cycle 4
        // Setup inputs for ADD entering ID/EX
        pipe_id_rd_in = 5'd6; pipe_id_mem_read_in = 1'b0; pipe_id_reg_write_in = 1'b1; pipe_id_valid_in = 1'b1;
        @(posedge clk); #1;
        // Cycle 4:
        //   ADD has entered EX stage (valid = 1)
        if (pipe_id_ex_valid !== 1'b1) $fatal(1, "FAIL Cycle 4: Expected ADD in EX (valid=1), got %b", pipe_id_ex_valid);
        if (pipe_id_ex_rd !== 5'd6) $fatal(1, "FAIL Cycle 4: Expected ADD rd=x6 in EX, got %d", pipe_id_ex_rd);

        //   SUB has entered ID stage
        if (pipe_if_id_pc !== 32'h00000008) $fatal(1, "FAIL Cycle 4: Expected SUB PC=0x08 in IF/ID, got %h", pipe_if_id_pc);
        test_count = test_count + 1;

        // ====================================================================
        // Final Summary
        // ====================================================================
        $display("PASS: all %0d hazard detection unit tests completed successfully", test_count);
        $finish;
    end

endmodule
