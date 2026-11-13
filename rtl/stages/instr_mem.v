// -----------------------------------------------------------------------------
// instr_mem.v - Instruction Memory (read-only, combinational read)
//
// Read       : combinational. instr = mem[addr[2+:ADDR_BITS]] (word addressed).
// Depth      : DEPTH_WORDS 32-bit words (default 256 = 1 KiB). Must be a power
//              of two. Byte addresses 0 .. 4*DEPTH_WORDS-1 are valid.
// Alignment  : addr[1:0] is ignored (word aligned project; low bits dropped).
// Out of range: addr >= 4*DEPTH_WORDS returns NOP (32'h0000_0013, addi x0,x0,0).
// Init       : $readmemh(INIT_FILE) at time 0 if INIT_FILE is not "".
//              File format: one 32-bit word per line, 8 hex digits, word 0
//              first (byte address 0). '//' comments are allowed.
//              Words not covered by the file are initialised to NOP so that
//              no X ever reaches decode.
// No write port: the instruction memory is not modified at run time.
// -----------------------------------------------------------------------------
module instr_mem #(
    parameter DEPTH_WORDS = 256,
    parameter INIT_FILE   = ""
) (
    input  wire [31:0] addr,   // byte address (the PC)
    output wire [31:0] instr
);

    localparam [31:0] NOP = 32'h0000_0013;
    localparam ADDR_BITS  = $clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            mem[i] = NOP;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    wire in_range = (addr[31:2] < DEPTH_WORDS);

    assign instr = in_range ? mem[addr[2 +: ADDR_BITS]] : NOP;

endmodule
