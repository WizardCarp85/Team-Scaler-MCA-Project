// ============================================================================
// Module: ex_stage
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #15 - Execution Stage Datapath
//
// Description:
//   The Execution (EX) stage datapath wrapper. It coordinates operand selection,
//   forwarding muxes, the Arithmetic Logic Unit (alu), the ALU control decoder
//   (alu_control), and the branch evaluation/target calculation unit (branch_unit).
//
// Forwarding Interface (Pending agreement with M5):
//   forward_a [1:0] : Selects source for ALU Operand A and Branch Operand A:
//     2'b00 = FWD_ID_EX  : ID/EX register value (rs1_data_in)
//     2'b01 = FWD_MEM_WB : MEM/WB forwarded value (forward_wb_data)
//     2'b10 = FWD_EX_MEM : EX/MEM forwarded value (forward_mem_data)
//     2'b11 = Reserved   : Defaults safely to ID/EX register value
//
//   forward_b [1:0] : Selects source for rs2 operand (Branch Operand B,
//                     Store data, and ALU Operand B candidate before alu_src_imm):
//     2'b00 = FWD_ID_EX  : ID/EX register value (rs2_data_in)
//     2'b01 = FWD_MEM_WB : MEM/WB forwarded value (forward_wb_data)
//     2'b10 = FWD_EX_MEM : EX/MEM forwarded value (forward_mem_data)
//     2'b11 = Reserved   : Defaults safely to ID/EX register value
//
// Operand Selection:
//   - ALU Operand A : Forwarded rs1 data.
//   - ALU Operand B : If alu_src_imm == 1, selects imm_in (for ADDI, LW, SW);
//                     else selects forwarded rs2 data (for R-type ADD, SUB).
//   - Store Data    : Always remains the forwarded rs2 data (even when ALU uses
//                     imm_in for SW address calculation).
//   - Branch Op A/B : Forwarded rs1 and rs2 data are directly passed to branch_unit.
//
// Bubble / Invalidation Behavior:
//   When valid_in == 0, branch_taken is forced low and all downstream side-effect
//   controls (mem_read, mem_write, reg_write, wb_from_mem) are suppressed to 0.
// ============================================================================

`timescale 1ns/1ps

module ex_stage #(
    parameter [1:0] FWD_ID_EX  = 2'b00,
    parameter [1:0] FWD_MEM_WB = 2'b01,
    parameter [1:0] FWD_EX_MEM = 2'b10
) (
    // Inputs from ID/EX pipeline register
    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] rs1_data_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] imm_in,
    input  wire [4:0]  rs1_in,
    input  wire [4:0]  rs2_in,
    input  wire [4:0]  rd_in,
    input  wire [2:0]  funct3_in,
    input  wire [6:0]  funct7_in,
    input  wire [1:0]  alu_op_in,
    input  wire [1:0]  branch_type_in,
    input  wire        alu_src_imm_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        reg_write_in,
    input  wire        wb_from_mem_in,
    input  wire        valid_in,

    // Forwarding inputs from hazard / forwarding unit (M5)
    input  wire [1:0]  forward_a,          // 00=ID/EX, 01=MEM/WB, 10=EX/MEM
    input  wire [1:0]  forward_b,          // 00=ID/EX, 01=MEM/WB, 10=EX/MEM
    input  wire [31:0] forward_mem_data,   // EX/MEM stage forwarded result
    input  wire [31:0] forward_wb_data,    // MEM/WB stage forwarded result

    // Execution & Branch Outputs
    output wire [31:0] alu_result,
    output wire        branch_taken,
    output wire [31:0] branch_target,

    // Pass-through & Pipeline Outputs (for EX/MEM boundary and M5 forwarding)
    output wire [31:0] store_data,         // Forwarded rs2 data to MEM
    output wire [4:0]  rd,                 // Destination register index
    output wire [31:0] pc,                 // Instruction PC
    output wire [31:0] pc_plus4,           // Sequential PC+4
    output wire [4:0]  rs1,                // Source register 1 index (for M5)
    output wire [4:0]  rs2,                // Source register 2 index (for M5)
    output wire        mem_read,           // Memory read enable (gated by valid)
    output wire        mem_write,          // Memory write enable (gated by valid)
    output wire        reg_write,          // Register write enable (gated by valid)
    output wire        wb_from_mem,        // Write-back source select (gated by valid)
    output wire        valid               // Stage valid bit
);

    // ------------------------------------------------------------------------
    // 1. Forwarding Multiplexers
    // ------------------------------------------------------------------------
    reg [31:0] fwd_rs1_data;
    reg [31:0] fwd_rs2_data;

    always @* begin
        case (forward_a)
            FWD_EX_MEM: fwd_rs1_data = forward_mem_data;
            FWD_MEM_WB: fwd_rs1_data = forward_wb_data;
            default:    fwd_rs1_data = rs1_data_in;
        endcase
    end

    always @* begin
        case (forward_b)
            FWD_EX_MEM: fwd_rs2_data = forward_mem_data;
            FWD_MEM_WB: fwd_rs2_data = forward_wb_data;
            default:    fwd_rs2_data = rs2_data_in;
        endcase
    end

    // Store data is always the forwarded rs2 operand
    assign store_data = fwd_rs2_data;

    // ------------------------------------------------------------------------
    // 2. ALU Operand Selection
    // ------------------------------------------------------------------------
    wire [31:0] alu_operand_a = fwd_rs1_data;
    wire [31:0] alu_operand_b = alu_src_imm_in ? imm_in : fwd_rs2_data;

    // ------------------------------------------------------------------------
    // 3. Submodule Instantiations: alu_control, alu, branch_unit
    // ------------------------------------------------------------------------
    wire [3:0] alu_ctrl;
    alu_control u_alu_control (
        .alu_op(alu_op_in),
        .funct3(funct3_in),
        .funct7(funct7_in),
        .alu_ctrl(alu_ctrl)
    );

    wire alu_equal;
    wire alu_zero;
    alu u_alu (
        .a(alu_operand_a),
        .b(alu_operand_b),
        .alu_ctrl(alu_ctrl),
        .result(alu_result),
        .equal(alu_equal),
        .zero(alu_zero)
    );

    branch_unit u_branch_unit (
        .valid(valid_in),
        .branch_type(branch_type_in),
        .pc(pc_in),
        .imm(imm_in),
        .op_a(fwd_rs1_data),
        .op_b(fwd_rs2_data),
        .branch_taken(branch_taken),
        .branch_target(branch_target)
    );

    // ------------------------------------------------------------------------
    // 4. Downstream Control Gating & Metadata Pass-through
    // ------------------------------------------------------------------------
    assign valid       = valid_in;
    assign pc          = pc_in;
    assign pc_plus4    = pc_plus4_in;
    assign rd          = rd_in;
    assign rs1         = rs1_in;
    assign rs2         = rs2_in;

    // Suppress all side-effect controls on invalid / bubble cycles
    assign mem_read    = valid_in ? mem_read_in    : 1'b0;
    assign mem_write   = valid_in ? mem_write_in   : 1'b0;
    assign reg_write   = valid_in ? reg_write_in   : 1'b0;
    assign wb_from_mem = valid_in ? wb_from_mem_in : 1'b0;

endmodule
