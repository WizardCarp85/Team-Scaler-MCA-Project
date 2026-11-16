// =============================================================================
// Module: mem_stage
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #18 - Memory Stage Integration
//
// Description:
//   MEM stage datapath wrapper for the 5-stage RV32I pipeline. It connects the
//   EX/MEM pipeline register outputs to the data memory module and propagates
//   control / metadata signals to the MEM/WB pipeline register boundary.
//
//   For LW:
//     - mem_read  = 1 → data memory is combinationally read; read_data is
//       forwarded to MEM/WB as load_data.
//   For SW:
//     - mem_write = 1 → store is committed on the next rising edge inside
//       data_mem. The MEM/WB register carries no meaningful load_data.
//   For R-type / I-immediate:
//     - mem_read = mem_write = 0 → memory is idle; alu_result passes through.
//
// Ports (connected to EX/MEM register outputs and MEM/WB register inputs):
//   Inputs  — identical naming to ex_mem_reg _out signals
//   Outputs — suffix _out for MEM/WB register _in signals
//
// Parameters:
//   MEM_DEPTH_WORDS — data memory depth in 32-bit words (default 256 = 1 KiB)
//   MEM_INIT_FILE   — optional $readmemh initialisation file (default = "")
// =============================================================================

`timescale 1ns/1ps

module mem_stage #(
    parameter MEM_DEPTH_WORDS = 256,
    parameter MEM_INIT_FILE   = ""
) (
    input  wire        clk,

    // -------------------------------------------------------------------------
    // Inputs from EX/MEM pipeline register (ex_mem_reg outputs)
    // -------------------------------------------------------------------------
    input  wire [31:0] alu_result,     // Memory byte address (LW/SW) or ALU result
    input  wire [31:0] store_data,     // Write data for SW
    input  wire [4:0]  rd,             // Destination register index
    input  wire [31:0] pc,             // Instruction PC (pass-through for WB/debug)
    input  wire [31:0] pc_plus4,       // Sequential PC+4 (pass-through for WB)
    input  wire        mem_read,       // LW enable
    input  wire        mem_write,      // SW enable
    input  wire        reg_write,      // Register write-back enable
    input  wire        wb_from_mem,    // WB mux: 1 → load_data, 0 → alu_result
    input  wire        valid,          // Instruction validity flag

    // -------------------------------------------------------------------------
    // Outputs to MEM/WB pipeline register (mem_wb_reg inputs)
    // -------------------------------------------------------------------------
    output wire [31:0] alu_result_out, // Pass-through ALU result for non-load WB
    output wire [31:0] load_data_out,  // Data memory read result for LW
    output wire [4:0]  rd_out,         // Destination register index
    output wire [31:0] pc_out,         // Instruction PC
    output wire [31:0] pc_plus4_out,   // Sequential PC+4
    output wire        reg_write_out,  // Register write-back enable
    output wire        wb_from_mem_out,// WB mux select
    output wire        valid_out,      // Instruction validity flag

    // -------------------------------------------------------------------------
    // Diagnostic / hazard output
    // -------------------------------------------------------------------------
    output wire        access_fault    // High when an invalid address is accessed
);

    // -------------------------------------------------------------------------
    // Data memory instantiation
    // -------------------------------------------------------------------------
    wire [31:0] read_data;

    data_mem #(
        .DEPTH_WORDS(MEM_DEPTH_WORDS),
        .INIT_FILE  (MEM_INIT_FILE)
    ) u_data_mem (
        .clk        (clk),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .addr       (alu_result),
        .write_data (store_data),
        .read_data  (read_data),
        .access_fault(access_fault)
    );

    // -------------------------------------------------------------------------
    // Pass-throughs to MEM/WB boundary
    // -------------------------------------------------------------------------
    assign alu_result_out  = alu_result;
    assign load_data_out   = read_data;
    assign rd_out          = rd;
    assign pc_out          = pc;
    assign pc_plus4_out    = pc_plus4;
    assign reg_write_out   = reg_write;
    assign wb_from_mem_out = wb_from_mem;
    assign valid_out       = valid;

endmodule
