// -----------------------------------------------------------------------------
// if_stage.v - Instruction Fetch stage wrapper
//
// Contains: pc (state) + instr_mem (combinational read) + PC+4 adder.
// Does NOT decide branches, stalls or flushes. The top level selects next_pc
// (typically: pc_plus4, branch target, or pc itself to stall) and feeds it back.
//
// Ports
//   clk            in  1   rising-edge clock
//   rst            in  1   synchronous, active-high; pc <= RESET_VECTOR
//   next_pc        in  32  value loaded into the PC on the next rising edge
//   pc             out 32  current fetch address (registered PC)
//   pc_plus4       out 32  pc + 4 (for the next-PC mux and IF/ID register)
//   instr          out 32  instruction at pc (combinational)
//
// Timing: during a cycle, pc, pc_plus4 and instr all describe the SAME fetch
// address. They change together after the rising edge that loads next_pc.
// Reset: pc = RESET_VECTOR while/after rst; instr is the word at that address.
// Init : INIT_FILE is passed to instr_mem ($readmemh; see instr_mem.v).
// -----------------------------------------------------------------------------
module if_stage #(
    parameter [31:0] RESET_VECTOR = 32'h0000_0000,
    parameter        DEPTH_WORDS  = 256,
    parameter        INIT_FILE    = ""
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] next_pc,
    output wire [31:0] pc,
    output wire [31:0] pc_plus4,
    output wire [31:0] instr
);

    pc #(.RESET_VECTOR(RESET_VECTOR)) u_pc (
        .clk     (clk),
        .rst     (rst),
        .next_pc (next_pc),
        .pc      (pc)
    );

    instr_mem #(.DEPTH_WORDS(DEPTH_WORDS), .INIT_FILE(INIT_FILE)) u_instr_mem (
        .addr  (pc),
        .instr (instr)
    );

    assign pc_plus4 = pc + 32'd4;

endmodule
