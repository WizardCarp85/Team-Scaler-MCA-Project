// -----------------------------------------------------------------------------
// pc.v - Program Counter (IF stage state)
//
// Clock      : rising edge
// Reset      : synchronous, ACTIVE-HIGH (rst). Project-wide convention; the
//              IF/ID register uses the same one.
// Reset value: RESET_VECTOR (default 32'h0000_0000)
// Update     : every clock edge pc <= next_pc. The top level / branch logic
//              selects next_pc (pc+4, branch target, ...). This module makes
//              no branch decisions.
// Stall      : none here. Stalling is done by the top level feeding pc back
//              as next_pc (this module has no enable by design for issue #2).
// Alignment  : PC is expected to be word aligned (pc[1:0] == 0).
// -----------------------------------------------------------------------------
module pc #(
    parameter [31:0] RESET_VECTOR = 32'h0000_0000
) (
    input  wire        clk,
    input  wire        rst,      // synchronous, active-high
    input  wire [31:0] next_pc,  // selected by top level / branch logic
    output reg  [31:0] pc
);

    always @(posedge clk) begin
        if (rst)
            pc <= RESET_VECTOR;
        else
            pc <= next_pc;
    end

endmodule
