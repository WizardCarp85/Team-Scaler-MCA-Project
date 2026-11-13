// ============================================================================
// Module: branch_unit
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #14 - Branch Comparison & Target Calculation
//
// Description:
//   A synthesizable, purely combinational branch evaluation and target address
//   calculation module for the EX stage supporting BEQ and BNE instructions.
//
// Ports:
//   valid         : Instruction valid flag from ID/EX. When 0 (bubble/invalid),
//                   branch_taken is forced to 0 to prevent spurious redirects.
//   branch_type   : 2-bit branch operation class from ID/EX (M2 control contract):
//                     2'b00 = No branch
//                     2'b01 = BEQ (Branch if Equal)
//                     2'b10 = BNE (Branch if Not Equal)
//                     2'b11 = Reserved (No branch)
//   pc            : 32-bit Program Counter of the branch instruction (base).
//   imm           : 32-bit sign-extended B-type immediate. Note: in this CPU,
//                   the immediate is already a byte offset with its low bit
//                   included (from instruction_decoder); it is NOT shifted.
//   op_a          : 32-bit source operand A (rs1 data or forwarded EX value).
//   op_b          : 32-bit source operand B (rs2 data or forwarded EX value).
//   branch_taken  : Combinational decision: asserted (1'b1) when valid=1 and
//                   the branch condition is satisfied; deasserted (1'b0) otherwise.
//   branch_target : 32-bit target address calculated as (pc + imm) modulo 2^32.
//
// Target Calculation & Inactive Output Behavior:
//   branch_target continuously evaluates the sum (pc + imm). When no branch
//   is taken (branch_taken == 0) or valid == 0, branch_taken is 0; downstream
//   redirect and PC multiplexer logic (Issue #25 / M5) qualifies redirection
//   with branch_taken, ignoring branch_target when branch_taken is deasserted.
//
// Architectural Scope:
//   This module does NOT update the PC, flush pipeline registers, or implement
//   forwarding muxes. Branch redirection and pipeline flushes are coordinated
//   by integration and hazard control logic.
// ============================================================================

`timescale 1ns/1ps

module branch_unit #(
    parameter [1:0] BRANCH_NONE = 2'b00,
    parameter [1:0] BRANCH_BEQ  = 2'b01,
    parameter [1:0] BRANCH_BNE  = 2'b10
) (
    input  wire        valid,         // Valid instruction flag from ID/EX
    input  wire [1:0]  branch_type,   // 00=none, 01=BEQ, 10=BNE, 11=reserved
    input  wire [31:0] pc,            // Current branch instruction PC
    input  wire [31:0] imm,           // Sign-extended B-immediate byte offset
    input  wire [31:0] op_a,          // First source operand (rs1 / forwarded)
    input  wire [31:0] op_b,          // Second source operand (rs2 / forwarded)
    output reg         branch_taken,  // High if branch condition is satisfied
    output wire [31:0] branch_target  // Branch target address (pc + imm)
);

    // Target calculation: PC + sign-extended B-immediate byte offset
    assign branch_target = pc + imm;

    // Condition evaluation: BEQ taken when equal; BNE taken when unequal
    always @* begin
        branch_taken = 1'b0;
        if (valid) begin
            case (branch_type)
                BRANCH_BEQ: branch_taken = (op_a == op_b);
                BRANCH_BNE: branch_taken = (op_a != op_b);
                default:    branch_taken = 1'b0;
            endcase
        end
    end

endmodule
