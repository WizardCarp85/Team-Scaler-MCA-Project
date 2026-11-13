# Instruction images

## Format (`$readmemh`, used by `instr_mem.v`)
- Plain text, one 32-bit instruction per line as 8 hex digits, no `0x` prefix.
- Line N (counting instruction lines from 0) is the word at byte address `4*N`
  (word 0 = address 0x00, word 1 = 0x04, ...).
- `//` comments are allowed. Words not present in the file default to NOP
  (`00000013`).
- Load it with the `INIT_FILE` parameter of `instr_mem` / `if_stage`. Paths are
  relative to the directory where `vvp` is run (use the repository root).

## `if_test.hex`
IF-only test data, not a CPU benchmark. It has one instruction of each of the
seven supported types, plus SUB and a second branch form.

| Addr | Hex | Instruction | Encoding check |
|---|---|---|---|
| 0x00 | 00002083 | `lw x1, 0(x0)` | I-type, opcode 0000011, funct3 010 |
| 0x04 | 00108133 | `add x2, x1, x1` | R-type, opcode 0110011, funct7 0000000, funct3 000 |
| 0x08 | 00e00193 | `addi x3, x0, 14` | I-type, opcode 0010011, imm 14 |
| 0x0c | 40310233 | `sub x4, x2, x3` | R-type, funct7 0100000, funct3 000 |
| 0x10 | 00310463 | `beq x2, x3, +8` | B-type, opcode 1100011, funct3 000, imm 8 |
| 0x14 | 00002023 | `sw x0, 0(x0)` | S-type, opcode 0100011, funct3 010 |
| 0x18 | 00202223 | `sw x2, 4(x0)` | S-type, imm[11:5]=0, imm[4:0]=4 |
| 0x1c | fe021ee3 | `bne x4, x0, -4` | B-type, funct3 001, imm -4 |

## Run the fetch test (from the repository root)
```
iverilog -g2012 -o simulation/tb_fetch.vvp testbench/tb_fetch.v \
    rtl/stages/if_stage.v rtl/stages/pc.v rtl/stages/instr_mem.v
vvp simulation/tb_fetch.vvp
```
Expected output: `PASS: tb_fetch` (a mismatch prints `FAIL: ...` lines and
`FAILED: N error(s)`).
