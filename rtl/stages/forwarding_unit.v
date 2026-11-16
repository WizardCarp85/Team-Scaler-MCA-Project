// =============================================================================
// Module: forwarding_unit
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #24 - EX-Stage Forwarding & Bypass Logic
//
// Description:
//   Forwarding Unit for the 5-stage in-order RV32I pipelined processor.
//   Resolves Read-After-Write (RAW) data hazards combinationally by routing
//   the most recent in-flight results from the EX/MEM and MEM/WB stage registers
//   directly to the Execution (EX) stage operand inputs.
//
// Forwarding Multiplexer Encodings (coordinated with M3 ex_stage.v):
//   - 2'b00 = FWD_ID_EX  : No forwarding; use register value from ID/EX.
//   - 2'b01 = FWD_MEM_WB : Forward from MEM/WB pipeline register (wb_data).
//   - 2'b10 = FWD_EX_MEM : Forward from EX/MEM pipeline register (alu_result).
//   - 2'b11 = Reserved   : Defaults safely to FWD_ID_EX.
//
// Priority & Forwarding Rules:
//   1. Youngest Producer Priority:
//      When both EX/MEM and MEM/WB target the same destination register as an
//      EX-stage source register (rs1 or rs2), EX/MEM strictly takes priority
//      over MEM/WB because it contains the newer architectural state.
//   2. Hardwired Zero (x0) Protection:
//      Writes to x0 (rd == 5'd0) are NEVER forwarded.
//   3. Bubble & Validity Immunity:
//      Invalid instructions and flushed bubbles (valid == 0) or instructions
//      that do not write to registers (reg_write == 0) NEVER trigger forwarding.
//   4. Independent Operands:
//      Forwarding selection for Operand A (rs1) and Operand B (rs2) are computed
//      completely independently.
//   5. Immediate Selection Preservation:
//      Operand B forwarding control integrates with ex_stage.v, where alu_src_imm
//      preserves immediate selection for ALU arithmetic (ADDI, LW, SW) while
//      fwd_rs2_data correctly routes to store_data (SW) and branch comparisons (BEQ/BNE).
// =============================================================================

`timescale 1ns/1ps

module forwarding_unit #(
    parameter [1:0] FWD_ID_EX  = 2'b00,
    parameter [1:0] FWD_MEM_WB = 2'b01,
    parameter [1:0] FWD_EX_MEM = 2'b10
) (
    // -------------------------------------------------------------------------
    // Inputs from Execute Stage (ID/EX Register Outputs) - Consumer
    // -------------------------------------------------------------------------
    input  wire [4:0]  id_ex_rs1,        // Source register 1 index in EX
    input  wire [4:0]  id_ex_rs2,        // Source register 2 index in EX
    input  wire        id_ex_valid,      // Validity flag of instruction in EX

    // -------------------------------------------------------------------------
    // Inputs from Memory Stage (EX/MEM Register Outputs) - Younger Producer
    // -------------------------------------------------------------------------
    input  wire [4:0]  ex_mem_rd,        // Destination register index in EX/MEM
    input  wire        ex_mem_reg_write, // Register write enable in EX/MEM
    input  wire        ex_mem_mem_read,  // Memory read flag in EX/MEM (1 for LW)
    input  wire        ex_mem_valid,     // Validity flag of instruction in EX/MEM

    // -------------------------------------------------------------------------
    // Inputs from Write-Back Stage (MEM/WB Register Outputs) - Older Producer
    // -------------------------------------------------------------------------
    input  wire [4:0]  mem_wb_rd,        // Destination register index in MEM/WB
    input  wire        mem_wb_reg_write, // Register write enable in MEM/WB
    input  wire        mem_wb_valid,     // Validity flag of instruction in MEM/WB

    // -------------------------------------------------------------------------
    // Forwarding Control Outputs to EX Stage Multiplexers
    // -------------------------------------------------------------------------
    output reg  [1:0]  forward_a,        // Forwarding control for Operand A (rs1)
    output reg  [1:0]  forward_b         // Forwarding control for Operand B (rs2)
);

    // -------------------------------------------------------------------------
    // Producer Validity & Forwardability Flags
    // -------------------------------------------------------------------------
    // An EX/MEM result is forwardable if the instruction is valid, writes to a
    // register, is not targeting x0, and is not a Load (LW data is not ready in EX/MEM).
    wire ex_mem_forwardable = ex_mem_valid && ex_mem_reg_write &&
                             !ex_mem_mem_read && (ex_mem_rd != 5'd0);

    // A MEM/WB result is forwardable if the instruction is valid, writes to a
    // register, and is not targeting x0 (both ALU and loaded data are ready in MEM/WB).
    wire mem_wb_forwardable = mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 5'd0);

    // -------------------------------------------------------------------------
    // Forwarding Logic for Operand A (rs1)
    // -------------------------------------------------------------------------
    always @* begin
        if (id_ex_valid && ex_mem_forwardable && (ex_mem_rd == id_ex_rs1)) begin
            // 1. EX/MEM Hazard: Forward youngest ALU result from EX/MEM stage
            forward_a = FWD_EX_MEM;
        end else if (id_ex_valid && mem_wb_forwardable && (mem_wb_rd == id_ex_rs1)) begin
            // 2. MEM/WB Hazard: Forward older result from MEM/WB stage
            forward_a = FWD_MEM_WB;
        end else begin
            // 3. No Hazard: Use registered operand from ID/EX register
            forward_a = FWD_ID_EX;
        end
    end

    // -------------------------------------------------------------------------
    // Forwarding Logic for Operand B (rs2)
    // -------------------------------------------------------------------------
    always @* begin
        if (id_ex_valid && ex_mem_forwardable && (ex_mem_rd == id_ex_rs2)) begin
            // 1. EX/MEM Hazard: Forward youngest ALU result from EX/MEM stage
            forward_b = FWD_EX_MEM;
        end else if (id_ex_valid && mem_wb_forwardable && (mem_wb_rd == id_ex_rs2)) begin
            // 2. MEM/WB Hazard: Forward older result from MEM/WB stage
            forward_b = FWD_MEM_WB;
        end else begin
            // 3. No Hazard: Use registered operand from ID/EX register
            forward_b = FWD_ID_EX;
        end
    end

endmodule
