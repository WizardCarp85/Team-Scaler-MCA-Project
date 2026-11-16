// =============================================================================
// Module: branch_hazard_coordinator
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #25 - Branch Redirect, Flush & Hazard Stall Coordination Logic
//
// Description:
//   Direct alias / wrapper for branch_controller.v providing identical ports
//   and parameters for seamless architectural binding.
// =============================================================================

`timescale 1ns/1ps

module branch_hazard_coordinator #(
    parameter [1:0] PC_PLUS4  = 2'b00,
    parameter [1:0] PC_BRANCH = 2'b01,
    parameter [1:0] PC_HOLD   = 2'b10
) (
    input  wire [31:0] pc,
    input  wire [31:0] pc_plus4,
    input  wire        branch_taken,
    input  wire [31:0] branch_target,
    input  wire        stall_req,
    output wire [31:0] next_pc,
    output wire [1:0]  pc_src,
    output wire        pc_en,
    output wire        if_id_flush,
    output wire        if_id_en,
    output wire        id_ex_flush,
    output wire        id_ex_en,
    output wire        stall_out,
    output wire        flush_out
);

    branch_controller #(
        .PC_PLUS4 (PC_PLUS4),
        .PC_BRANCH(PC_BRANCH),
        .PC_HOLD  (PC_HOLD)
    ) u_branch_controller (
        .pc           (pc),
        .pc_plus4     (pc_plus4),
        .branch_taken (branch_taken),
        .branch_target(branch_target),
        .stall_req    (stall_req),
        .next_pc      (next_pc),
        .pc_src       (pc_src),
        .pc_en        (pc_en),
        .if_id_flush  (if_id_flush),
        .if_id_en     (if_id_en),
        .id_ex_flush  (id_ex_flush),
        .id_ex_en     (id_ex_en),
        .stall_out    (stall_out),
        .flush_out    (flush_out)
    );

endmodule
