// =============================================================================
// Module: hazard_unit
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #22 - Load-Use Hazard Detection & Pipeline Stall Control
//
// Description:
//   Direct alias / wrapper for hazard_detection.v providing identical ports
//   and parameters for seamless architectural binding.
// =============================================================================

`timescale 1ns/1ps

module hazard_unit #(
    parameter FORWARDING_SUPPORTED = 1
) (
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire        id_uses_rs1,
    input  wire        id_uses_rs2,
    input  wire        id_valid,
    input  wire [4:0]  ex_rd,
    input  wire        ex_mem_read,
    input  wire        ex_reg_write,
    input  wire        ex_valid,
    input  wire [4:0]  mem_rd,
    input  wire        mem_mem_read,
    input  wire        mem_reg_write,
    input  wire        mem_valid,
    input  wire        branch_taken,
    output wire        stall,
    output wire        pc_stall,
    output wire        pc_en,
    output wire        if_id_stall,
    output wire        if_id_en,
    output wire        id_ex_flush,
    output wire        id_ex_bubble
);

    hazard_detection #(
        .FORWARDING_SUPPORTED(FORWARDING_SUPPORTED)
    ) u_hazard_detection (
        .id_rs1         (id_rs1),
        .id_rs2         (id_rs2),
        .id_uses_rs1    (id_uses_rs1),
        .id_uses_rs2    (id_uses_rs2),
        .id_valid       (id_valid),
        .ex_rd          (ex_rd),
        .ex_mem_read    (ex_mem_read),
        .ex_reg_write   (ex_reg_write),
        .ex_valid       (ex_valid),
        .mem_rd         (mem_rd),
        .mem_mem_read   (mem_mem_read),
        .mem_reg_write  (mem_reg_write),
        .mem_valid      (mem_valid),
        .branch_taken   (branch_taken),
        .stall          (stall),
        .pc_stall       (pc_stall),
        .pc_en          (pc_en),
        .if_id_stall    (if_id_stall),
        .if_id_en       (if_id_en),
        .id_ex_flush    (id_ex_flush),
        .id_ex_bubble   (id_ex_bubble)
    );

endmodule
