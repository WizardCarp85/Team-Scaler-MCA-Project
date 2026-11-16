// =============================================================================
// Module: mem_wb_reg
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #18 - Memory Stage Integration
//
// Description:
//   Synchronous pipeline register separating the Memory (MEM) stage from the
//   Write-Back (WB) stage. Captures the ALU result, load data, destination
//   register, PC metadata, and write-back control signals together on the
//   rising clock edge.
//
// Priority Order (evaluated on each rising edge):
//   1. rst || flush : Clears every output to 0 (flush beats hold).
//   2. en == 0      : Holds the entire bundle across clock cycles.
//   3. valid_in == 0: Captures a cleared bubble (all outputs 0, valid_out = 0).
//   4. en && valid  : Captures the active bundle.
//
// This matches the EX/MEM register (ex_mem_reg) priority semantics for
// consistency across the pipeline.
// =============================================================================

`timescale 1ns/1ps

module mem_wb_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,      // 1 = capture / advance, 0 = hold (stall)
    input  wire        flush,   // 1 = squash to bubble (flush beats hold)

    // -------------------------------------------------------------------------
    // Inputs from MEM stage (mem_stage outputs)
    // -------------------------------------------------------------------------
    input  wire [31:0] alu_result_in,
    input  wire [31:0] load_data_in,
    input  wire [4:0]  rd_in,
    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire        reg_write_in,
    input  wire        wb_from_mem_in,
    input  wire        valid_in,

    // -------------------------------------------------------------------------
    // Outputs to WB stage & forwarding / hazard logic
    // -------------------------------------------------------------------------
    output reg  [31:0] alu_result_out,
    output reg  [31:0] load_data_out,
    output reg  [4:0]  rd_out,
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg         reg_write_out,
    output reg         wb_from_mem_out,
    output reg         valid_out
);

    // -------------------------------------------------------------------------
    // Synchronous pipeline register logic
    // Priority: rst/flush > hold (en=0) > bubble (valid_in=0) > active capture
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst || flush) begin
            // Clear to safe no-side-effect state
            alu_result_out  <= 32'h0;
            load_data_out   <= 32'h0;
            rd_out          <= 5'h0;
            pc_out          <= 32'h0;
            pc_plus4_out    <= 32'h0;
            reg_write_out   <= 1'b0;
            wb_from_mem_out <= 1'b0;
            valid_out       <= 1'b0;
        end else if (!en) begin
            // Hold: retain current outputs unchanged (stall)
            alu_result_out  <= alu_result_out;
            load_data_out   <= load_data_out;
            rd_out          <= rd_out;
            pc_out          <= pc_out;
            pc_plus4_out    <= pc_plus4_out;
            reg_write_out   <= reg_write_out;
            wb_from_mem_out <= wb_from_mem_out;
            valid_out       <= valid_out;
        end else if (!valid_in) begin
            // Bubble capture: clear all outputs; side-effects must be 0
            alu_result_out  <= 32'h0;
            load_data_out   <= 32'h0;
            rd_out          <= 5'h0;
            pc_out          <= 32'h0;
            pc_plus4_out    <= 32'h0;
            reg_write_out   <= 1'b0;
            wb_from_mem_out <= 1'b0;
            valid_out       <= 1'b0;
        end else begin
            // Active capture
            alu_result_out  <= alu_result_in;
            load_data_out   <= load_data_in;
            rd_out          <= rd_in;
            pc_out          <= pc_in;
            pc_plus4_out    <= pc_plus4_in;
            reg_write_out   <= reg_write_in;
            wb_from_mem_out <= wb_from_mem_in;
            valid_out       <= valid_in;
        end
    end

endmodule
