// =============================================================================
// Testbench: tb_forwarding_unit
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #24 - EX-Stage Forwarding & Bypass Logic
//
// Description:
//   Comprehensive, self-checking verification suite for the Forwarding Unit
//   (forwarding_unit.v) integrated directly with the Execution Stage (ex_stage.v).
//
// Verification Scenarios Covered:
//   1. No hazard / No match: Defaults to FWD_ID_EX (2'b00)
//   2. EX/MEM forwarding on rs1 and rs2 independently
//   3. MEM/WB forwarding on rs1 and rs2 independently
//   4. Simultaneous independent forwarding (EX/MEM on rs1, MEM/WB on rs2, and vice versa)
//   5. Simultaneous match priority: EX/MEM strictly wins over MEM/WB
//   6. Hardwired zero x0 immunity: Writes to x0 are never forwarded
//   7. Fall-through priority: When EX/MEM targets x0, valid MEM/WB still forwards
//   8. Bubble / Invalidation immunity: ex_mem_valid=0 or mem_wb_valid=0 never forwards
//   9. Non-writing producer immunity: reg_write=0 (SW, BEQ) never forwards
//  10. Unforwardable load in EX/MEM: ex_mem_mem_read=1 suppresses EX/MEM forwarding
//  11. Invalid consumer in EX: id_ex_valid=0 defaults safely to FWD_ID_EX
//  12. Datapath Integration with ex_stage.v:
//      - Verified forwarded Operand A and B arithmetic in 32-bit ALU
//      - Verified immediate selection preservation for ALU operand B
//      - Verified store_data correctly retains forwarded rs2 data during SW
//      - Verified branch_unit condition evaluation using forwarded operands
//
// Compilation & Simulation:
//   iverilog -g2012 -o simulation/tb_forwarding_unit.vvp \
//       testbench/tb_forwarding_unit.v \
//       rtl/stages/forwarding_unit.v \
//       rtl/stages/ex_stage.v \
//       rtl/stages/alu.v \
//       rtl/stages/alu_control.v \
//       rtl/stages/branch_unit.v
//   vvp simulation/tb_forwarding_unit.vvp
// =============================================================================

`timescale 1ns/1ps

module tb_forwarding_unit;

    // -------------------------------------------------------------------------
    // Forwarding Unit Signals
    // -------------------------------------------------------------------------
    reg  [4:0]  id_ex_rs1;
    reg  [4:0]  id_ex_rs2;
    reg         id_ex_valid;

    reg  [4:0]  ex_mem_rd;
    reg         ex_mem_reg_write;
    reg         ex_mem_mem_read;
    reg         ex_mem_valid;

    reg  [4:0]  mem_wb_rd;
    reg         mem_wb_reg_write;
    reg         mem_wb_valid;

    wire [1:0]  forward_a;
    wire [1:0]  forward_b;

    localparam [1:0] FWD_ID_EX  = 2'b00;
    localparam [1:0] FWD_MEM_WB = 2'b01;
    localparam [1:0] FWD_EX_MEM = 2'b10;

    integer test_count = 0;

    // -------------------------------------------------------------------------
    // Instantiate DUT: forwarding_unit
    // -------------------------------------------------------------------------
    forwarding_unit #(
        .FWD_ID_EX (FWD_ID_EX),
        .FWD_MEM_WB(FWD_MEM_WB),
        .FWD_EX_MEM(FWD_EX_MEM)
    ) dut (
        .id_ex_rs1        (id_ex_rs1),
        .id_ex_rs2        (id_ex_rs2),
        .id_ex_valid      (id_ex_valid),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_mem_read  (ex_mem_mem_read),
        .ex_mem_valid     (ex_mem_valid),
        .mem_wb_rd        (mem_wb_rd),
        .mem_wb_reg_write (mem_wb_reg_write),
        .mem_wb_valid     (mem_wb_valid),
        .forward_a        (forward_a),
        .forward_b        (forward_b)
    );

    // -------------------------------------------------------------------------
    // Instantiate ex_stage for Datapath Integration Verification
    // -------------------------------------------------------------------------
    reg  [31:0] ex_pc_in;
    reg  [31:0] ex_pc_plus4_in;
    reg  [31:0] ex_rs1_data_in;
    reg  [31:0] ex_rs2_data_in;
    reg  [31:0] ex_imm_in;
    reg  [2:0]  ex_funct3_in;
    reg  [6:0]  ex_funct7_in;
    reg  [1:0]  ex_alu_op_in;
    reg  [1:0]  ex_branch_type_in;
    reg         ex_alu_src_imm_in;
    reg         ex_mem_read_in;
    reg         ex_mem_write_in;
    reg         ex_reg_write_in;
    reg         ex_wb_from_mem_in;

    reg  [31:0] forward_mem_data;
    reg  [31:0] forward_wb_data;

    wire [31:0] ex_alu_result;
    wire        ex_branch_taken;
    wire [31:0] ex_branch_target;
    wire [31:0] ex_store_data;

    ex_stage #(
        .FWD_ID_EX (FWD_ID_EX),
        .FWD_MEM_WB(FWD_MEM_WB),
        .FWD_EX_MEM(FWD_EX_MEM)
    ) u_ex_stage (
        .pc_in           (ex_pc_in),
        .pc_plus4_in     (ex_pc_plus4_in),
        .rs1_data_in     (ex_rs1_data_in),
        .rs2_data_in     (ex_rs2_data_in),
        .imm_in          (ex_imm_in),
        .rs1_in          (id_ex_rs1),
        .rs2_in          (id_ex_rs2),
        .rd_in           (5'd10),
        .funct3_in       (ex_funct3_in),
        .funct7_in       (ex_funct7_in),
        .alu_op_in       (ex_alu_op_in),
        .branch_type_in  (ex_branch_type_in),
        .alu_src_imm_in  (ex_alu_src_imm_in),
        .mem_read_in     (ex_mem_read_in),
        .mem_write_in    (ex_mem_write_in),
        .reg_write_in    (ex_reg_write_in),
        .wb_from_mem_in  (ex_wb_from_mem_in),
        .valid_in        (id_ex_valid),
        .forward_a       (forward_a),
        .forward_b       (forward_b),
        .forward_mem_data(forward_mem_data),
        .forward_wb_data (forward_wb_data),
        .alu_result      (ex_alu_result),
        .branch_taken    (ex_branch_taken),
        .branch_target   (ex_branch_target),
        .store_data      (ex_store_data),
        .rd              (),
        .pc              (),
        .pc_plus4        (),
        .rs1             (),
        .rs2             (),
        .mem_read        (),
        .mem_write       (),
        .reg_write       (),
        .wb_from_mem     (),
        .valid           ()
    );

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    task check;
        input [1:0]   exp_fwd_a;
        input [1:0]   exp_fwd_b;
        input [127:0] test_name;
        begin
            #1;
            if (forward_a !== exp_fwd_a || forward_b !== exp_fwd_b) begin
                $fatal(1, "FAIL [%0s]: exp fwd_a=%b fwd_b=%b | got fwd_a=%b fwd_b=%b",
                       test_name, exp_fwd_a, exp_fwd_b, forward_a, forward_b);
            end
            test_count = test_count + 1;
        end
    endtask

    task reset_inputs;
        begin
            id_ex_rs1        = 5'd0;
            id_ex_rs2        = 5'd0;
            id_ex_valid      = 1'b0;
            ex_mem_rd        = 5'd0;
            ex_mem_reg_write = 1'b0;
            ex_mem_mem_read  = 1'b0;
            ex_mem_valid     = 1'b0;
            mem_wb_rd        = 5'd0;
            mem_wb_reg_write = 1'b0;
            mem_wb_valid     = 1'b0;

            ex_pc_in          = 32'h0000_1000;
            ex_pc_plus4_in    = 32'h0000_1004;
            ex_rs1_data_in    = 32'd0;
            ex_rs2_data_in    = 32'd0;
            ex_imm_in         = 32'd0;
            ex_funct3_in      = 3'b000;
            ex_funct7_in      = 7'b0000000;
            ex_alu_op_in      = 2'b00;
            ex_branch_type_in = 2'b00;
            ex_alu_src_imm_in = 1'b0;
            ex_mem_read_in    = 1'b0;
            ex_mem_write_in   = 1'b0;
            ex_reg_write_in   = 1'b0;
            ex_wb_from_mem_in = 1'b0;
            forward_mem_data  = 32'd0;
            forward_wb_data   = 32'd0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Verification
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("simulation/tb_forwarding_unit.vcd");
        $dumpvars(0, tb_forwarding_unit);

        reset_inputs();

        // ====================================================================
        // 1. No Hazard / No Match
        // ====================================================================
        // Consumer in EX reads x1, x2; EX/MEM writes x3; MEM/WB writes x4
        id_ex_valid = 1; id_ex_rs1 = 5'd1; id_ex_rs2 = 5'd2;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd3;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd4;
        check(FWD_ID_EX, FWD_ID_EX, "No hazard: both operands use ID/EX");

        // ====================================================================
        // 2. EX/MEM Forwarding (Youngest Producer)
        // ====================================================================
        // Forward on rs1 only (EX/MEM writes x1)
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd1; id_ex_rs2 = 5'd2;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd1;
        check(FWD_EX_MEM, FWD_ID_EX, "EX/MEM forward on rs1 only");

        // Forward on rs2 only (EX/MEM writes x2)
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd1; id_ex_rs2 = 5'd2;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd2;
        check(FWD_ID_EX, FWD_EX_MEM, "EX/MEM forward on rs2 only");

        // Forward on both rs1 and rs2 (EX/MEM writes x5; consumer has rs1=x5, rs2=x5)
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd5; id_ex_rs2 = 5'd5;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd5;
        check(FWD_EX_MEM, FWD_EX_MEM, "EX/MEM forward on both rs1 and rs2");

        // ====================================================================
        // 3. MEM/WB Forwarding (Older Producer)
        // ====================================================================
        // Forward on rs1 only (MEM/WB writes x1)
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd1; id_ex_rs2 = 5'd2;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd1;
        check(FWD_MEM_WB, FWD_ID_EX, "MEM/WB forward on rs1 only");

        // Forward on rs2 only (MEM/WB writes x2)
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd1; id_ex_rs2 = 5'd2;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd2;
        check(FWD_ID_EX, FWD_MEM_WB, "MEM/WB forward on rs2 only");

        // Forward on both rs1 and rs2 (MEM/WB writes x7; consumer has rs1=x7, rs2=x7)
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd7; id_ex_rs2 = 5'd7;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd7;
        check(FWD_MEM_WB, FWD_MEM_WB, "MEM/WB forward on both rs1 and rs2");

        // ====================================================================
        // 4. Simultaneous Mixed Forwarding
        // ====================================================================
        // EX/MEM on rs1 (x3), MEM/WB on rs2 (x4)
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd3; id_ex_rs2 = 5'd4;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd3;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd4;
        check(FWD_EX_MEM, FWD_MEM_WB, "Mixed: EX/MEM on rs1, MEM/WB on rs2");

        // MEM/WB on rs1 (x8), EX/MEM on rs2 (x9)
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd8; id_ex_rs2 = 5'd9;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd9;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd8;
        check(FWD_MEM_WB, FWD_EX_MEM, "Mixed: MEM/WB on rs1, EX/MEM on rs2");

        // ====================================================================
        // 5. Simultaneous Match Priority: EX/MEM Strictly Takes Precedence
        // ====================================================================
        // Both EX/MEM and MEM/WB write to x5; consumer reads rs1=x5.
        // Youngest instruction is in EX/MEM -> must forward FWD_EX_MEM (2'b10)!
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd5; id_ex_rs2 = 5'd2;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd5;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd5;
        check(FWD_EX_MEM, FWD_ID_EX, "Priority: EX/MEM wins on rs1 collision");

        // Both EX/MEM and MEM/WB write to x6; consumer reads rs2=x6.
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd1; id_ex_rs2 = 5'd6;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd6;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd6;
        check(FWD_ID_EX, FWD_EX_MEM, "Priority: EX/MEM wins on rs2 collision");

        // Both EX/MEM and MEM/WB write to x11; consumer reads rs1=x11, rs2=x11.
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd11; id_ex_rs2 = 5'd11;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd11;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd11;
        check(FWD_EX_MEM, FWD_EX_MEM, "Priority: EX/MEM wins on both operands");

        // ====================================================================
        // 6. Hardwired Zero (x0) Protection
        // ====================================================================
        // An instruction writes to x0 (rd = 0). Must NEVER forward!
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd0; id_ex_rs2 = 5'd0;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd0;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd0;
        check(FWD_ID_EX, FWD_ID_EX, "x0 Protection: rd=0 never forwarded");

        // ====================================================================
        // 7. Fall-Through Priority on x0
        // ====================================================================
        // EX/MEM writes to x0 (rd = 0). MEM/WB writes to valid x5.
        // Consumer reads rs1 = x5.
        // EX/MEM should be ignored, and MEM/WB should successfully forward!
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd5; id_ex_rs2 = 5'd2;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd0; // x0 write
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd5; // valid x5 write
        check(FWD_MEM_WB, FWD_ID_EX, "Fall-through: EX/MEM rd=0 allows MEM/WB to forward");

        // ====================================================================
        // 8. Bubble & Invalidation Immunity
        // ====================================================================
        // EX/MEM targets x5, but ex_mem_valid = 0 (bubble/flushed).
        // MEM/WB targets x5 and is valid. MEM/WB must forward!
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd5; id_ex_rs2 = 5'd2;
        ex_mem_valid = 1'b0; ex_mem_reg_write = 1; ex_mem_rd = 5'd5;
        mem_wb_valid = 1'b1; mem_wb_reg_write = 1; mem_wb_rd = 5'd5;
        check(FWD_MEM_WB, FWD_ID_EX, "Immunity: EX/MEM bubble allows MEM/WB to forward");

        // Both EX/MEM and MEM/WB are invalid bubbles. No forwarding!
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd5; id_ex_rs2 = 5'd5;
        ex_mem_valid = 1'b0; ex_mem_reg_write = 1; ex_mem_rd = 5'd5;
        mem_wb_valid = 1'b0; mem_wb_reg_write = 1; mem_wb_rd = 5'd5;
        check(FWD_ID_EX, FWD_ID_EX, "Immunity: All bubbles -> FWD_ID_EX");

        // ====================================================================
        // 9. Non-Writing Producer Immunity (reg_write == 0)
        // ====================================================================
        // EX/MEM is SW or BEQ with dummy rd=5, but reg_write=0!
        // MEM/WB writes x5 with reg_write=1. MEM/WB must forward!
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd5; id_ex_rs2 = 5'd2;
        ex_mem_valid = 1; ex_mem_reg_write = 1'b0; ex_mem_rd = 5'd5;
        mem_wb_valid = 1; mem_wb_reg_write = 1'b1; mem_wb_rd = 5'd5;
        check(FWD_MEM_WB, FWD_ID_EX, "Immunity: EX/MEM reg_write=0 allows MEM/WB to forward");

        // ====================================================================
        // 10. Unforwardable Load in EX/MEM (ex_mem_mem_read == 1)
        // ====================================================================
        // EX/MEM is LW with rd=5 (memory read in progress; data not ready).
        // MEM/WB is valid with rd=5. MEM/WB must forward!
        reset_inputs();
        id_ex_valid = 1; id_ex_rs1 = 5'd5; id_ex_rs2 = 5'd2;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_mem_read = 1'b1; ex_mem_rd = 5'd5;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd5;
        check(FWD_MEM_WB, FWD_ID_EX, "Load protection: EX/MEM LW unforwardable -> MEM/WB forwards");

        // ====================================================================
        // 11. Invalid Consumer in EX (id_ex_valid == 0)
        // ====================================================================
        // EX stage holds a bubble (id_ex_valid = 0). Forwarding must default to 2'b00.
        reset_inputs();
        id_ex_valid = 1'b0; id_ex_rs1 = 5'd5; id_ex_rs2 = 5'd5;
        ex_mem_valid = 1; ex_mem_reg_write = 1; ex_mem_rd = 5'd5;
        mem_wb_valid = 1; mem_wb_reg_write = 1; mem_wb_rd = 5'd5;
        check(FWD_ID_EX, FWD_ID_EX, "Invalid consumer in EX: defaults to FWD_ID_EX");

        // ====================================================================
        // 12. Datapath Integration with ex_stage.v
        // ====================================================================
        // Scenario 12A: Forward Operand A from EX/MEM into ALU
        reset_inputs();
        id_ex_valid     = 1;
        id_ex_rs1       = 5'd1;
        id_ex_rs2       = 5'd2;
        ex_rs1_data_in  = 32'd10;       // Stale registered value
        ex_rs2_data_in  = 32'd20;
        forward_mem_data = 32'd100;     // Forwarded value from EX/MEM
        ex_mem_valid    = 1;
        ex_mem_reg_write = 1;
        ex_mem_rd       = 5'd1;         // Match rs1!
        ex_alu_op_in    = 2'b01;        // Register ADD

        #1;
        check(FWD_EX_MEM, FWD_ID_EX, "Datapath: forward_a selects FWD_EX_MEM");
        // ALU result must be 100 + 20 = 120 (not 10 + 20 = 30)
        if (ex_alu_result !== 32'd120) begin
            $fatal(1, "FAIL Datapath 12A: ALU result expected 120, got %d", ex_alu_result);
        end
        test_count = test_count + 1;

        // Scenario 12B: Forward Operand B from MEM/WB into ALU
        reset_inputs();
        id_ex_valid     = 1;
        id_ex_rs1       = 5'd1;
        id_ex_rs2       = 5'd2;
        ex_rs1_data_in  = 32'd50;
        ex_rs2_data_in  = 32'd5;        // Stale registered value
        forward_wb_data = 32'd30;       // Forwarded value from MEM/WB
        mem_wb_valid    = 1;
        mem_wb_reg_write = 1;
        mem_wb_rd       = 5'd2;         // Match rs2!
        ex_alu_op_in    = 2'b01;        // Register ADD

        #1;
        check(FWD_ID_EX, FWD_MEM_WB, "Datapath: forward_b selects FWD_MEM_WB");
        // ALU result must be 50 + 30 = 80
        if (ex_alu_result !== 32'd80) begin
            $fatal(1, "FAIL Datapath 12B: ALU result expected 80, got %d", ex_alu_result);
        end
        test_count = test_count + 1;

        // Scenario 12C: Immediate Preservation on Operand B (ADDI)
        // EX has ADDI x3, x1, 15 (alu_src_imm = 1).
        // Forwarding unit asserts forward_b because rs2 field happens to match EX/MEM.
        // ALU MUST use immediate 15!
        reset_inputs();
        id_ex_valid      = 1;
        id_ex_rs1        = 5'd1;
        id_ex_rs2        = 5'd4;
        ex_rs1_data_in   = 32'd100;
        ex_imm_in        = 32'd15;
        ex_alu_src_imm_in = 1'b1;       // Immediate select
        forward_mem_data = 32'd999;
        ex_mem_valid     = 1;
        ex_mem_reg_write = 1;
        ex_mem_rd        = 5'd4;        // Match rs2
        ex_alu_op_in     = 2'b00;       // ADD immediate

        #1;
        check(FWD_ID_EX, FWD_EX_MEM, "Datapath: forward_b selected");
        // ALU result must be 100 + 15 = 115 (immediate preserved!)
        if (ex_alu_result !== 32'd115) begin
            $fatal(1, "FAIL Datapath 12C: Immediate not preserved! ALU result expected 115, got %d", ex_alu_result);
        end
        test_count = test_count + 1;

        // Scenario 12D: Store Data Preservation during SW
        // EX has SW x4, 8(x1).
        // alu_src_imm = 1 (ALU calculates x1 + 8 for address).
        // BUT store_data MUST be the forwarded rs2 value (forward_mem_data = 999)!
        ex_mem_write_in = 1'b1;
        #1;
        if (ex_store_data !== 32'd999) begin
            $fatal(1, "FAIL Datapath 12D: Store data not forwarded! Expected 999, got %d", ex_store_data);
        end
        test_count = test_count + 1;

        // Scenario 12E: Branch Comparison with Forwarded Operands
        // EX has BEQ x1, x2, offset.
        // Stale registered values: rs1=10, rs2=20 (not equal).
        // Forwarded values: rs1=100 from EX/MEM, rs2=100 from MEM/WB (equal!).
        reset_inputs();
        id_ex_valid       = 1;
        id_ex_rs1         = 5'd1;
        id_ex_rs2         = 5'd2;
        ex_rs1_data_in    = 32'd10;
        ex_rs2_data_in    = 32'd20;
        forward_mem_data  = 32'd100;    // EX/MEM forwards 100 to rs1
        forward_wb_data   = 32'd100;    // MEM/WB forwards 100 to rs2
        ex_mem_valid      = 1;
        ex_mem_reg_write  = 1;
        ex_mem_rd         = 5'd1;
        mem_wb_valid      = 1;
        mem_wb_reg_write  = 1;
        mem_wb_rd         = 5'd2;
        ex_branch_type_in = 2'b01;      // BEQ
        ex_imm_in         = 32'h0000_0008;

        #1;
        check(FWD_EX_MEM, FWD_MEM_WB, "Datapath: Branch operands forwarded from EX/MEM and MEM/WB");
        // Forwarded values 100 == 100 -> branch_taken MUST be 1!
        if (ex_branch_taken !== 1'b1) begin
            $fatal(1, "FAIL Datapath 12E: branch_taken expected 1 with forwarded equal operands, got %b", ex_branch_taken);
        end
        test_count = test_count + 1;

        // ====================================================================
        // Final Summary
        // ====================================================================
        $display("PASS: all %0d forwarding unit tests completed successfully", test_count);
        $finish;
    end

endmodule
