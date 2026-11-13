// ============================================================================
// Module: alu
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #12 - RV32I Arithmetic Logic Unit (ALU)
//
// Description:
//   A synthesizable, purely combinational 32-bit Arithmetic Logic Unit (ALU)
//   supporting the project's RV32I instruction subset.
//
// Operation Encoding (shared with Issue #13 ALU Control Decoder):
//   4'b0000 (ALU_ADD) : result = a + b
//                       Used for:
//                         - R-type ADD (rs1 + rs2)
//                         - I-type ADDI (rs1 + imm)
//                         - I-type LW effective address (rs1 + imm)
//                         - S-type SW effective address (rs1 + imm)
//   4'b0001 (ALU_SUB) : result = a - b
//                       Used for:
//                         - R-type SUB (rs1 - rs2)
//   4'b0010 - 4'b1111 : Unused / reserved operation codes.
//                       Safely and deterministically default to result = 32'h00000000.
//                       Never accidentally selects SUB or any unsafe operation.
//
// Flags:
//   equal : High (1'b1) when (a == b), indicating bitwise equality between
//           operands a and b. Branch decision policy (e.g. BEQ / BNE) remains
//           strictly outside the ALU (handled in branch control / Issue #14).
//   zero  : High (1'b1) when (result == 32'h00000000). Standard ALU result zero
//           status flag.
//
// Arithmetic & Overflow:
//   Per RV32I specification, 32-bit arithmetic operations ignore overflow and
//   wrap modulo 2^32 into the 32-bit result. No overflow traps are required.
// ============================================================================

`timescale 1ns/1ps

module alu #(
    parameter [3:0] ALU_ADD = 4'b0000,
    parameter [3:0] ALU_SUB = 4'b0001
) (
    input  wire [31:0] a,        // Operand A (e.g., rs1 data)
    input  wire [31:0] b,        // Operand B (e.g., rs2 data or sign-extended immediate)
    input  wire [3:0]  alu_ctrl, // ALU operation control code from ALU decoder
    output reg  [31:0] result,   // 32-bit ALU operation result
    output wire        equal,    // Equality flag: 1 if (a == b), 0 otherwise
    output wire        zero      // Zero flag: 1 if (result == 0), 0 otherwise
);

    // Equality flag directly compares the two 32-bit operands
    assign equal = (a == b);

    // Zero flag indicates whether the computation result is zero
    assign zero  = (result == 32'd0);

    // Combinational computation
    always @* begin
        case (alu_ctrl)
            ALU_ADD: result = a + b;
            ALU_SUB: result = a - b;
            default: result = 32'd0; // Safe, deterministic default for unused codes
        endcase
    end

endmodule
