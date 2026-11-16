// =============================================================================
// Module: wb_stage
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #20 - Write-Back Logic & Register File Interface
//
// Description:
//   Write-Back (WB) stage for the 5-stage RV32I pipelined processor.
//   It selects the final write-back value from the MEM/WB pipeline register
//   bundle and drives the write port of the register file (in the ID stage).
//
// Functionality:
//   1. WB Source Multiplexing:
//      - wb_from_mem = 0 : Selects alu_result (R-type, I-immediate arithmetic).
//      - wb_from_mem = 1 : Selects load_data (LW memory load result).
//   2. Side-Effect Gating:
//      - wb_write_en is asserted ONLY when:
//          * valid == 1 (instruction is not a bubble or flushed)
//          * reg_write == 1 (instruction is an architecture register-writing op)
//          * rd != 5'd0 (destination is not hardwired zero register x0)
//      - SW, BEQ, BNE, bubble cycles, and invalid instructions have reg_write=0
//        or valid=0 and are thus completely suppressed from writing registers.
//   3. Interface to Register File:
//      - wb_write_en -> matches register_file.write_en (and id_stage.wb_write_en)
//      - wb_rd       -> matches register_file.rd       (and id_stage.wb_rd)
//      - wb_data     -> matches register_file.write_data (and id_stage.wb_data)
//   4. Pass-through & Pipeline Metadata:
//      - pc_out, pc_plus4_out, retired are exposed for instruction retirement,
//        cycle/performance accounting (CPI/IPC), and verification logging.
// =============================================================================

`timescale 1ns/1ps

module wb_stage (
    // -------------------------------------------------------------------------
    // Inputs from MEM/WB Pipeline Register (mem_wb_reg outputs)
    // -------------------------------------------------------------------------
    input  wire [31:0] alu_result,     // Arithmetic / address calculation result
    input  wire [31:0] load_data,      // Memory load data from data_mem
    input  wire [4:0]  rd,             // Destination register index
    input  wire [31:0] pc,             // Instruction PC metadata
    input  wire [31:0] pc_plus4,       // Sequential PC+4 metadata
    input  wire        reg_write,      // Register write enable from decode
    input  wire        wb_from_mem,    // Write-back source select (1: mem, 0: alu)
    input  wire        valid,          // Instruction validity flag (0: bubble)

    // -------------------------------------------------------------------------
    // Outputs to Register File Write Port (in ID stage)
    // -------------------------------------------------------------------------
    output wire        wb_write_en,    // Gated register file write enable
    output wire [4:0]  wb_rd,          // Destination register address
    output wire [31:0] wb_data,        // Final multiplexed write-back data

    // -------------------------------------------------------------------------
    // Instruction Retirement & Debug Metadata Outputs
    // -------------------------------------------------------------------------
    output wire [31:0] pc_out,         // Retired instruction PC
    output wire [31:0] pc_plus4_out,   // Retired sequential PC+4
    output wire        retired         // 1 if a valid instruction retired this cycle
);

    // -------------------------------------------------------------------------
    // 1. Write-Back Data Multiplexer
    // -------------------------------------------------------------------------
    // Selects between memory load data (LW) and ALU computational result (all others)
    assign wb_data = wb_from_mem ? load_data : alu_result;

    // Destination register forwarded to register file
    assign wb_rd = rd;

    // -------------------------------------------------------------------------
    // 2. Register Write Enable Gating
    // -------------------------------------------------------------------------
    // Write is permitted ONLY if:
    //  - The instruction is valid (not a bubble or flushed cycle)
    //  - Decode flagged a register write (reg_write == 1)
    //  - Destination register is not x0 (hardwired zero)
    assign wb_write_en = valid && reg_write && (rd != 5'd0);

    // -------------------------------------------------------------------------
    // 3. Instruction Retirement Metadata
    // -------------------------------------------------------------------------
    assign pc_out       = pc;
    assign pc_plus4_out = pc_plus4;
    assign retired      = valid;

endmodule
