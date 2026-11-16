// =============================================================================
// Module: forwarding
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #24 - EX-Stage Forwarding & Bypass Logic
//
// Description:
//   Direct alias / wrapper for forwarding_unit.v providing identical ports
//   and parameters for seamless architectural binding.
// =============================================================================

`timescale 1ns/1ps

module forwarding #(
    parameter [1:0] FWD_ID_EX  = 2'b00,
    parameter [1:0] FWD_MEM_WB = 2'b01,
    parameter [1:0] FWD_EX_MEM = 2'b10
) (
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,
    input  wire        id_ex_valid,
    input  wire [4:0]  ex_mem_rd,
    input  wire        ex_mem_reg_write,
    input  wire        ex_mem_mem_read,
    input  wire        ex_mem_valid,
    input  wire [4:0]  mem_wb_rd,
    input  wire        mem_wb_reg_write,
    input  wire        mem_wb_valid,
    output wire [1:0]  forward_a,
    output wire [1:0]  forward_b
);

    forwarding_unit #(
        .FWD_ID_EX (FWD_ID_EX),
        .FWD_MEM_WB(FWD_MEM_WB),
        .FWD_EX_MEM(FWD_EX_MEM)
    ) u_forwarding_unit (
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

endmodule
