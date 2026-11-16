# Data Memory Interface (`rtl/stages/data_mem.v`)

Word-addressable memory for LW and SW in the MEM stage.

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | rising edge; used for writes only |
| `mem_read` | in | 1 | LW: enables `read_data` |
| `mem_write` | in | 1 | SW: write `write_data` at the next rising edge |
| `addr` | in | 32 | byte address (the ALU result) |
| `write_data` | in | 32 | store data |
| `read_data` | out | 32 | combinational read; 0 if not reading or access invalid |
| `access_fault` | out | 1 | high while an access is requested with an invalid address |

Parameters: `DEPTH_WORDS` (default 256, power of two), `INIT_FILE` (default `""`).

- **Mapping:** word index = `addr[31:2]`; byte `0x0` is word 0, `0x4` word 1, `0x8` word 2.
- **Reset:** none. Contents are zero at time 0, or loaded from `INIT_FILE` with `$readmemh` (one 8-hex-digit word per line, word 0 first).
- **Misaligned (`addr[1:0] != 0`) or out of range (`addr >= 4*DEPTH_WORDS`):** reads return 0, writes are ignored, `access_fault` goes high. No other word is touched. Misaligned access is unsupported in this subset.
- **Write priority:** a write needs `mem_write` high and a valid address. Wrong-path stores must be killed upstream (flushed `mem_write = 0` in EX/MEM); this module does not know about pipeline state.

Test: `iverilog -g2012 -o simulation/tb_data_mem.vvp testbench/tb_data_mem.v rtl/stages/data_mem.v && vvp simulation/tb_data_mem.vvp` prints `PASS: tb_data_mem`.
