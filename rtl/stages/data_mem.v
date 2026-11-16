// -----------------------------------------------------------------------------
// data_mem.v - Word-addressable data memory for LW / SW (MEM stage)
//
// Clock      : rising edge (writes only)
// Reset      : none. The memory array is not reset. Contents are zero at time 0
//              (or loaded from INIT_FILE), so simulation is deterministic and
//              no reset logic is needed.
// Read       : combinational. read_data = mem[word] when mem_read is high and
//              the access is valid, otherwise 32'h0.
// Write      : on the rising edge, only when mem_write is high and the access
//              is valid. Exactly one word is updated.
// Addressing : byte address. word index = addr[2+:ADDR_BITS], i.e. byte address
//              0x0 -> word 0, 0x4 -> word 1, 0x8 -> word 2, ...
// Depth      : DEPTH_WORDS 32-bit words (default 256 = 1 KiB), power of two.
//              Valid byte addresses: 0 .. 4*DEPTH_WORDS-1.
// Invalid accesses (deterministic, never touch another word):
//   misaligned   : addr[1:0] != 0
//   out of range : addr >= 4*DEPTH_WORDS
//   On a read, read_data = 0. On a write, nothing is written.
//   access_fault is asserted (combinationally) while a mem_read or mem_write
//   is requested with an invalid address. Misaligned LW/SW is unsupported in
//   this subset; the core may ignore access_fault.
// Init       : INIT_FILE ("" = none) loaded with $readmemh at time 0, one
//              8-hex-digit word per line, word 0 = byte address 0.
// -----------------------------------------------------------------------------
module data_mem #(
    parameter DEPTH_WORDS = 256,
    parameter INIT_FILE   = ""
) (
    input  wire        clk,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] addr,         // byte address
    input  wire [31:0] write_data,
    output wire [31:0] read_data,
    output wire        access_fault  // requested access was misaligned/out of range
);

    localparam ADDR_BITS = $clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            mem[i] = 32'h0000_0000;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    wire aligned  = (addr[1:0] == 2'b00);
    wire in_range = (addr[31:2] < DEPTH_WORDS);
    wire valid    = aligned && in_range;

    assign access_fault = (mem_read || mem_write) && !valid;

    assign read_data = (mem_read && valid) ? mem[addr[2 +: ADDR_BITS]] : 32'h0000_0000;

    always @(posedge clk) begin
        if (mem_write && valid)
            mem[addr[2 +: ADDR_BITS]] <= write_data;
    end

endmodule
