// =============================================================================
// Module: top
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #26 - Top-Level Pipelined CPU Integration
//
// Description:
//   Top-level module wrapper / alias providing identical ports and parameters
//   to cpu.v for flexible top-level testbench binding.
// =============================================================================

`timescale 1ns/1ps

module top #(
    parameter [31:0] RESET_VECTOR   = 32'h0000_0000,
    parameter        IMEM_DEPTH     = 256,
    parameter        IMEM_INIT_FILE = "",
    parameter        DMEM_DEPTH     = 256,
    parameter        DMEM_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        rst,

    // Debug & Observability Outputs
    output wire [31:0] debug_if_pc,
    output wire [31:0] debug_if_instr,
    output wire [31:0] debug_id_pc,
    output wire [31:0] debug_id_instr,
    output wire        debug_id_valid,
    output wire [31:0] debug_ex_pc,
    output wire [31:0] debug_ex_alu_result,
    output wire        debug_ex_valid,
    output wire [31:0] debug_mem_pc,
    output wire [31:0] debug_mem_addr,
    output wire [31:0] debug_mem_write_data,
    output wire        debug_mem_read,
    output wire        debug_mem_write,
    output wire        debug_mem_valid,
    output wire [31:0] debug_wb_pc,
    output wire        debug_wb_reg_write,
    output wire [4:0]  debug_wb_rd,
    output wire [31:0] debug_wb_data,
    output wire        debug_wb_retired,

    // Pipeline Control & Hazard Diagnostics
    output wire        debug_stall,
    output wire        debug_flush,
    output wire        debug_branch_taken,
    output wire [31:0] debug_branch_target,
    output wire [1:0]  debug_forward_a,
    output wire [1:0]  debug_forward_b
);

    cpu #(
        .RESET_VECTOR  (RESET_VECTOR),
        .IMEM_DEPTH    (IMEM_DEPTH),
        .IMEM_INIT_FILE(IMEM_INIT_FILE),
        .DMEM_DEPTH    (DMEM_DEPTH),
        .DMEM_INIT_FILE(DMEM_INIT_FILE)
    ) u_cpu (
        .clk                 (clk),
        .rst                 (rst),
        .debug_if_pc         (debug_if_pc),
        .debug_if_instr      (debug_if_instr),
        .debug_id_pc         (debug_id_pc),
        .debug_id_instr      (debug_id_instr),
        .debug_id_valid      (debug_id_valid),
        .debug_ex_pc         (debug_ex_pc),
        .debug_ex_alu_result (debug_ex_alu_result),
        .debug_ex_valid      (debug_ex_valid),
        .debug_mem_pc        (debug_mem_pc),
        .debug_mem_addr      (debug_mem_addr),
        .debug_mem_write_data(debug_mem_write_data),
        .debug_mem_read      (debug_mem_read),
        .debug_mem_write     (debug_mem_write),
        .debug_mem_valid     (debug_mem_valid),
        .debug_wb_pc         (debug_wb_pc),
        .debug_wb_reg_write  (debug_wb_reg_write),
        .debug_wb_rd         (debug_wb_rd),
        .debug_wb_data       (debug_wb_data),
        .debug_wb_retired    (debug_wb_retired),
        .debug_stall         (debug_stall),
        .debug_flush         (debug_flush),
        .debug_branch_taken  (debug_branch_taken),
        .debug_branch_target (debug_branch_target),
        .debug_forward_a     (debug_forward_a),
        .debug_forward_b     (debug_forward_b)
    );

endmodule
