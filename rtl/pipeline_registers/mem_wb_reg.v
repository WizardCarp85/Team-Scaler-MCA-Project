// ============================================================================
// Module: mem_wb_reg
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #19 - MEM/WB Pipeline Register
//
// Description:
//   Synchronous pipeline register separating the Memory (MEM) stage from the
//   Write-Back (WB) stage. Captures the ALU result, load data, destination
//   register index, PC metadata, and write-back control signals together on
//   the rising clock edge.
//
//   Fields carried forward to WB:
//     alu_result  - arithmetic / address result (non-load write-back value)
//     load_data   - data memory read result    (load write-back value)
//     rd          - destination register index  (register file write port)
//     pc          - instruction PC              (debug / M5 metadata)
//     pc_plus4    - sequential PC+4             (debug / M5 metadata)
//     reg_write   - register file write enable  (side-effect control)
//     wb_from_mem - write-back mux select       (1 = load_data, 0 = alu_result)
//     valid       - instruction validity flag   (0 = bubble)
//
// Priority Order (evaluated on each rising clock edge):
//   1. rst || flush        : Clears the entire bundle to a safe no-write state.
//                            A flush beats a hold (en = 0).
//   2. en == 0             : Holds the entire bundle across clock cycles (stall).
//   3. en == 1, valid_in=0 : Captures a cleared bubble; reg_write forced to 0,
//                            ensuring a bubble cannot write a destination register.
//   4. en == 1, valid_in=1 : Captures the active bundle from *_in to *_out.
//
// This priority order and coding style match ex_mem_reg (Issue #16) exactly.
// ============================================================================

`timescale 1ns/1ps

module mem_wb_reg (
    input  wire        clk,
    input  wire        rst,    // synchronous active-high reset
    input  wire        en,     // 1 = advance/capture, 0 = hold (stall)
    input  wire        flush,  // 1 = squash to bubble (beats en = 0)

    // -------------------------------------------------------------------------
    // Inputs from MEM stage (mem_stage outputs)
    // -------------------------------------------------------------------------
    input  wire [31:0] alu_result_in,   // ALU result pass-through for non-load WB
    input  wire [31:0] load_data_in,    // Data memory read data for LW
    input  wire [4:0]  rd_in,           // Destination register index
    input  wire [31:0] pc_in,           // Instruction PC (debug metadata)
    input  wire [31:0] pc_plus4_in,     // Sequential PC+4 (debug metadata)
    input  wire        reg_write_in,    // Register file write enable
    input  wire        wb_from_mem_in,  // WB mux select: 1=load_data, 0=alu_result
    input  wire        valid_in,        // Instruction validity flag (0 = bubble)

    // -------------------------------------------------------------------------
    // Outputs to WB stage and forwarding / hazard logic (M5)
    // -------------------------------------------------------------------------
    output reg  [31:0] alu_result_out,
    output reg  [31:0] load_data_out,
    output reg  [4:0]  rd_out,
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg         reg_write_out,   // 0 on reset / flush / bubble
    output reg         wb_from_mem_out,
    output reg         valid_out        // 0 on reset / flush / bubble
);

    // -------------------------------------------------------------------------
    // Synchronous pipeline register logic
    //
    // rst, flush, and bubble (en && !valid_in) all collapse to the same
    // cleared-bundle action, matching the ex_mem_reg implementation style.
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst || flush || (en && !valid_in)) begin
            // Safe no-write state: reg_write and valid are both 0.
            // A bubble arriving with en=1 is captured as an all-zero bundle,
            // preventing any spurious register file write in WB.
            alu_result_out  <= 32'd0;
            load_data_out   <= 32'd0;
            rd_out          <= 5'd0;
            pc_out          <= 32'd0;
            pc_plus4_out    <= 32'd0;
            reg_write_out   <= 1'b0;
            wb_from_mem_out <= 1'b0;
            valid_out       <= 1'b0;
        end else if (en) begin
            // Active capture: latch the full bundle.
            alu_result_out  <= alu_result_in;
            load_data_out   <= load_data_in;
            rd_out          <= rd_in;
            pc_out          <= pc_in;
            pc_plus4_out    <= pc_plus4_in;
            reg_write_out   <= reg_write_in;
            wb_from_mem_out <= wb_from_mem_in;
            valid_out       <= valid_in;
        end
        // en == 0 (and not rst/flush): implicit hold — registers retain value.
    end

endmodule
