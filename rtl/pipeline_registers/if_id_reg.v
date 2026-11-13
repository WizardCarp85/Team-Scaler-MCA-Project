// -----------------------------------------------------------------------------
// if_id_reg.v - IF/ID pipeline register
//
// Clock    : rising edge
// Reset    : synchronous, ACTIVE-HIGH (rst), same convention as pc.v
// en       : active-high capture enable. en = 0 holds ALL fields (stall).
// flush    : active-high, synchronous. Replaces the stored instruction with a
//            NOP and clears the metadata (pc, pc_plus4, valid).
//
// Priority (highest first), evaluated on each rising edge:
//   1. rst    -> NOP, pc = 0, pc_plus4 = 0, valid = 0
//   2. flush  -> NOP, pc = 0, pc_plus4 = 0, valid = 0   (wins over stall)
//   3. !en    -> hold every field
//   4. else   -> capture instr_in, pc_in, pc_plus4_in, valid = 1
//
// NOP encoding: 32'h0000_0013 (addi x0, x0, 0).
// valid       : 0 means "bubble" (reset or flushed), 1 means a fetched
//               instruction. Downstream stages can use it to ignore bubbles.
// All fields (instr, pc, pc_plus4, valid) update together, so they always
// belong to the same fetch.
// -----------------------------------------------------------------------------
module if_id_reg (
    input  wire        clk,
    input  wire        rst,          // synchronous, active-high
    input  wire        en,           // 1 = capture, 0 = hold (stall)
    input  wire        flush,        // 1 = insert NOP bubble
    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] instr_in,
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] instr_out,
    output reg         valid_out
);

    localparam [31:0] NOP = 32'h0000_0013;

    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out       <= 32'h0000_0000;
            pc_plus4_out <= 32'h0000_0000;
            instr_out    <= NOP;
            valid_out    <= 1'b0;
        end else if (en) begin
            pc_out       <= pc_in;
            pc_plus4_out <= pc_plus4_in;
            instr_out    <= instr_in;
            valid_out    <= 1'b1;
        end
        // else: hold
    end

endmodule
