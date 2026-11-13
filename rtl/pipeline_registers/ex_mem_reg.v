// ============================================================================
// Module: ex_mem_reg
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #16 - EX/MEM Pipeline Register
//
// Description:
//   Synchronous pipeline register separating the Execution (EX) stage from the
//   Memory (MEM) stage. Captures execution results, store data, destination
//   register, PC metadata, and memory/write-back controls together on the
//   rising clock edge.
//
// Priority Order:
//   1. rst or flush : Clears the entire bundle to a safe no-side-effect state.
//                     A flush beats a hold.
//   2. en == 0      : Holds the entire bundle across clock cycles.
//   3. valid_in == 0: Captures a cleared bubble with valid_out=0 and all
//                     side-effect controls deasserted.
//   4. en && valid  : Captures the active bundle.
// ============================================================================

`timescale 1ns/1ps

module ex_mem_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire        flush,

    // Inputs from EX stage (ex_stage)
    input  wire [31:0] alu_result_in,
    input  wire [31:0] store_data_in,
    input  wire [4:0]  rd_in,
    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        reg_write_in,
    input  wire        wb_from_mem_in,
    input  wire        valid_in,

    // Outputs to MEM stage & Hazard / Forwarding logic
    output reg  [31:0] alu_result_out,
    output reg  [31:0] store_data_out,
    output reg  [4:0]  rd_out,
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         reg_write_out,
    output reg         wb_from_mem_out,
    output reg         valid_out
);

    // Synchronous active-high reset. Flush beats hold.
    // Invalid input captures a cleared bubble.
    always @(posedge clk) begin
        if (rst || flush || (en && !valid_in)) begin
            alu_result_out  <= 32'd0;
            store_data_out  <= 32'd0;
            rd_out          <= 5'd0;
            pc_out          <= 32'd0;
            pc_plus4_out    <= 32'd0;
            mem_read_out    <= 1'b0;
            mem_write_out   <= 1'b0;
            reg_write_out   <= 1'b0;
            wb_from_mem_out <= 1'b0;
            valid_out       <= 1'b0;
        end else if (en) begin
            alu_result_out  <= alu_result_in;
            store_data_out  <= store_data_in;
            rd_out          <= rd_in;
            pc_out          <= pc_in;
            pc_plus4_out    <= pc_plus4_in;
            mem_read_out    <= mem_read_in;
            mem_write_out   <= mem_write_in;
            reg_write_out   <= reg_write_in;
            wb_from_mem_out <= wb_from_mem_in;
            valid_out       <= valid_in;
        end
    end

endmodule
