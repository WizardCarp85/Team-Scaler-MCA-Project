# IF Stage Interface Contract (M1)

Covers `pc.v`, `instr_mem.v`, `if_stage.v` (in `rtl/stages/`) and `if_id_reg.v`
(in `rtl/pipeline_registers/`). Port names and widths below match the RTL.

## Project conventions
- Clock: rising edge. Reset: synchronous, **active-high** `rst`.
- Reset vector: `32'h0000_0000` (parameter `RESET_VECTOR`).
- Addresses and instructions are 32 bits. PCs are word aligned (`pc[1:0] == 0`).
- NOP = `32'h0000_0013` (`addi x0, x0, 0`).

## Modules

### `pc` - program counter
| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | clock |
| `rst` | in | 1 | sync, active-high; `pc <= RESET_VECTOR` |
| `next_pc` | in | 32 | loaded into `pc` every rising edge |
| `pc` | out | 32 | registered current fetch address |

Parameter: `RESET_VECTOR` (default 0). No enable port: to stall fetch, the top
level drives `next_pc = pc`.

### `instr_mem` - instruction memory
| Port | Dir | Width | Description |
|---|---|---|---|
| `addr` | in | 32 | byte address (the PC) |
| `instr` | out | 32 | instruction, combinational read |

Parameters: `DEPTH_WORDS` (default 256, power of two), `INIT_FILE` (default
`""`). `addr[1:0]` is ignored. Addresses at or above `4*DEPTH_WORDS`, and words
not in the image, read as NOP. No write port. Image format: see
`programs/README.md`.

### `if_stage` - fetch wrapper
| Port | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst` | in | 1 | as above |
| `next_pc` | in | 32 | selected by top level, loaded into PC |
| `pc` | out | 32 | current fetch address |
| `pc_plus4` | out | 32 | `pc + 4` |
| `instr` | out | 32 | instruction at `pc` |

Parameters `RESET_VECTOR`, `DEPTH_WORDS`, `INIT_FILE` pass through. `pc`,
`pc_plus4` and `instr` always describe the same fetch. IF makes no branch,
stall or flush decisions.

### `if_id_reg` - IF/ID pipeline register
| Port | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst` | in | 1 | as above |
| `en` | in | 1 | 1 = capture, 0 = hold (stall) |
| `flush` | in | 1 | 1 = replace contents with a NOP bubble |
| `pc_in`, `pc_plus4_in`, `instr_in` | in | 32 | from `if_stage` (`pc`, `pc_plus4`, `instr`) |
| `pc_out`, `pc_plus4_out`, `instr_out` | out | 32 | to ID stage |
| `valid_out` | out | 1 | 0 = bubble (reset or flush), 1 = fetched instruction |

Priority on each rising edge (highest first):

| rst | flush | en | Result |
|---|---|---|---|
| 1 | x | x | NOP, pc = 0, pc_plus4 = 0, valid = 0 |
| 0 | 1 | x | same as reset (flush beats stall) |
| 0 | 0 | 0 | hold all fields |
| 0 | 0 | 1 | capture inputs, valid = 1 |

Reset values: `instr_out = 32'h00000013`, `pc_out = 0`, `pc_plus4_out = 0`,
`valid_out = 0`.

## Next-PC redirection
`if_stage` only loads what it is given. The top level builds `next_pc`:

| Condition | `next_pc` |
|---|---|
| normal | `pc_plus4` |
| branch taken in EX | branch target (from M3) |
| stall (load-use) | `pc` (hold) |

The select signals come from M3 (branch taken, target) and M5 (stall, flush).
The new PC is loaded on the clock edge that ends the cycle in which the branch
is resolved.

## Cycle example
Program: `0x00 A`, `0x04 B` (taken `beq` to `0x18`), `0x08 C`, `0x0C D`,
`0x18 T`. Branch resolves in EX. Bubble = NOP with `valid = 0`.

| Cycle | IF (fetch pc) | ID | EX | Notes |
|---|---|---|---|---|
| 1 | A (0x00) | - | - | |
| 2 | B (0x04) | A | - | |
| 3 | C (0x08) | B | A | |
| 4 | D (0x0C) | C | B | B is taken: `next_pc = 0x18`, `flush` asserted to IF/ID (and ID/EX, M5) |
| 5 | T (0x18) | bubble | bubble | C and D discarded; T fetched from target |
| 6 | next (0x1C) | T | bubble | |

Stall (load-use): the hazard unit sets `en = 0` on IF/ID and drives
`next_pc = pc`. IF/ID keeps its instruction for one extra cycle and the PC
refetches the same address.

## Assumptions and limits
- Word-aligned PCs; unaligned or out-of-range fetches return NOP, with no exception.
- Instruction memory is read-only at run time and loaded only at time 0.
- Default depth is 256 words (1 KiB); override with `DEPTH_WORDS`.
- No branch prediction. No exceptions or interrupts.

## Open questions for M2 / M5
- **M2:** Is `valid_out` wanted in ID/EX, or should decode ignore it and rely on the NOP? (Both work; NOP alone is enough functionally.)
- **M5:** Confirm the top-level stall method (`next_pc = pc` and `en = 0`), since `pc` has no enable port.
- **M5:** Confirm that on a taken branch both IF/ID and ID/EX are flushed in the same cycle.
- **M3 / M5:** Confirm the branch redirect and flush are both asserted combinationally in the EX cycle, as shown above.

Status: not yet reviewed by M2/M5. These questions are open until they answer.
