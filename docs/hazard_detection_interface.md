# Hazard Detection Unit Interface & Pipeline Stall Specification

**Module:** `hazard_detection` (`rtl/stages/hazard_detection.v`) / `hazard_unit` (`rtl/stages/hazard_unit.v`)  
**Milestone:** Milestone 5 (M5) — Hazard Detection, Forwarding & Full Pipeline Integration  
**Related Issue:** Issue #22 (RAW Hazard Detection & Pipeline Stall Control)

---

## 1. Overview

In a 5-stage in-order pipelined processor (**IF**, **ID**, **EX**, **MEM**, **WB**) with operand forwarding:
- **ALU-to-ALU Dependencies** are resolved combinationally by forwarding from the EX/MEM or MEM/WB pipeline registers to the EX stage forwarding multiplexers (`ex_stage.v`), incurring **zero stall cycles**.
- **Load-Use Dependencies** cannot be resolved by forwarding alone. A Load instruction (`LW`) does not obtain valid data from data memory until the end of the **MEM** stage. If an immediately following instruction in the **ID** stage consumes that loaded value, it cannot execute in the EX stage during the next clock cycle.
- The `hazard_detection` module detects this condition combinationally and generates pipeline interlock control signals to insert exactly **one stall cycle (bubble)** into the execution stream.

```text
Cycle N:
  [IF Stage]       Fetch Instruction i+2 (e.g., SUB)
  [ID Stage]       Decode Consumer   i+1 (e.g., ADD x6, x5, x1) -> reads rs1 = x5
  [EX Stage]       Execute Load      i   (e.g., LW  x5, 0(x10)) -> writes rd = x5
  [MEM Stage]      Older instruction
  [WB Stage]       Older instruction

  ===> Hazard Detected: ex_mem_read=1 && (ex_rd == id_rs1) && id_uses_rs1
       Action: Freeze PC (hold), Freeze IF/ID (hold), Flush ID/EX (insert bubble)

Cycle N+1 (Stall Cycle):
  [IF Stage]       PC holds fetch address (re-fetches SUB)
  [ID Stage]       IF/ID holds Consumer i+1 (ADD x6, x5, x1 stays in ID)
  [EX Stage]       Bubble / NOP (valid = 0) enters EX stage
  [MEM Stage]      Load i (LW x5) reads data memory
  [WB Stage]       Older instruction

Cycle N+2 (Resume):
  [IF Stage]       PC advances to fetch i+3
  [ID Stage]       SUB advances to ID
  [EX Stage]       ADD enters EX; operand x5 forwarded from MEM/WB boundary
  [MEM Stage]      Bubble advances to MEM
  [WB Stage]       LW x5 commits to Register File
```

---

## 2. Port Interface

### Inputs
| Port Name | Width | Source Module | Description |
|---|---:|---|---|
| `id_rs1` | 5 | `id_stage` (`instruction_decoder`) | Source register 1 address of instruction in ID |
| `id_rs2` | 5 | `id_stage` (`instruction_decoder`) | Source register 2 address of instruction in ID |
| `id_uses_rs1` | 1 | `id_stage` | Validates that ID instruction actively reads `rs1` (`valid_in`) |
| `id_uses_rs2` | 1 | `id_stage` | Validates that ID instruction actively reads `rs2` (R-type, SW, Branch) |
| `id_valid` | 1 | `id_stage` (`main_control`) | Validity flag of instruction in ID (`0` = bubble / flushed) |
| `ex_rd` | 5 | `id_ex_reg` (`rd_out`) | Destination register index of instruction in EX |
| `ex_mem_read` | 1 | `id_ex_reg` (`mem_read_out`) | Asserted when instruction in EX is a Load (`LW`) |
| `ex_reg_write` | 1 | `id_ex_reg` (`reg_write_out`)| Asserted when instruction in EX writes to register file |
| `ex_valid` | 1 | `id_ex_reg` (`valid_out`) | Validity flag of instruction in EX (`0` = bubble / flushed) |
| `mem_rd` | 5 | `ex_mem_reg` (`rd_out`) | Destination register index of instruction in MEM |
| `mem_mem_read` | 1 | `ex_mem_reg` (`mem_read_out`)| Asserted when instruction in MEM is a Load (`LW`) |
| `mem_reg_write`| 1 | `ex_mem_reg` (`reg_write_out`)| Asserted when instruction in MEM writes to register file |
| `mem_valid` | 1 | `ex_mem_reg` (`valid_out`) | Validity flag of instruction in MEM (`0` = bubble / flushed) |
| `branch_taken` | 1 | `ex_stage` (`branch_unit`) | Asserted when conditional branch evaluates taken in EX |

### Outputs
| Port Name | Width | Destination | Functional Behavior |
|---|---:|---|---|
| `stall` | 1 | Top-level CPU / Status | Unified active-high stall indicator |
| `pc_stall` | 1 | Top-level PC Mux | `1` = hold PC (`next_pc <= pc`); `0` = advance PC |
| `pc_en` | 1 | Top-level PC / Logic | Active-high PC enable (`pc_en = ~stall`) |
| `if_id_stall`| 1 | `if_id_reg` control | `1` = hold IF/ID register; `0` = normal capture |
| `if_id_en` | 1 | `if_id_reg.en` | Active-high enable (`if_id_en = ~stall`); freezes IF/ID |
| `id_ex_flush`| 1 | `id_ex_reg.flush` | `1` = clear ID/EX to synchronous NOP bubble |
| `id_ex_bubble`| 1 | `id_ex_reg` alias | Direct alias for `id_ex_flush` |

---

## 3. Hazard Detection Logic & Rules

### A. Load-Use Hazard Condition
A load-use hazard is declared if and only if all of the following conditions are met:
1. The instruction in EX is valid (`ex_valid == 1`).
2. The instruction in EX is a memory read (`ex_mem_read == 1`).
3. The destination register in EX is not `x0` (`ex_rd != 5'd0`).
4. The instruction in ID is valid (`id_valid == 1`).
5. A RAW match occurs on an active operand:
   - `id_uses_rs1 && (id_rs1 == ex_rd)`, OR
   - `id_uses_rs2 && (id_rs2 == ex_rd)`.

```verilog
wire match_rs1_ex = id_valid && id_uses_rs1 && ex_valid && (ex_rd != 5'd0) && (id_rs1 == ex_rd);
wire match_rs2_ex = id_valid && id_uses_rs2 && ex_valid && (ex_rd != 5'd0) && (id_rs2 == ex_rd);
wire load_use_hazard = ex_mem_read && (match_rs1_ex || match_rs2_ex);
```

### B. Strict Safety & Immunity Guarantees
1. **Hardwired Zero (`x0`) Immunity**:
   - RISC-V register `x0` is permanently zero. A load targeting `x0` (`lw x0, 0(x1)`) produces no architectural side effects. Checking `ex_rd != 5'd0` ensures `x0` never triggers a pipeline stall.
2. **Immediate Field Immunity (`id_uses_rs2`)**:
   - In I-type instructions (`ADDI`, `LW`), bits `[24:20]` represent immediate payload, not a source register index.
   - The decode stage sets `uses_rs2 = 0` for these instructions. Qualifying comparisons with `id_uses_rs2` guarantees that immediate values matching `ex_rd` never trigger spurious stalls.
3. **Bubble Immunity (`id_valid`, `ex_valid`)**:
   - Reset states and flushed bubbles have `valid = 0`. Flushed instructions never stall the pipeline.
4. **Branch Override (`branch_taken`)**:
   - When a branch in EX is taken, instructions in IF and ID are on the mispredicted path and must be flushed, not stalled. Asserting `branch_taken` combinationally suppresses the stall request (`stall = raw_stall && !branch_taken`).

---

## 4. Pipeline Register Interlock Protocol

The hazard unit integrates with the stage boundary registers according to the following agreed contract:

| Stage Boundary | Control Signal | Stall Value | Operational Behavior |
|---|---|:---:|---|
| **PC (Fetch)** | `next_pc` | `pc` | Top-level selects current `pc` instead of `pc+4`, re-fetching the current address. |
| **IF/ID Register** | `if_id_reg.en` | `0` | Capture disabled; holds instruction, PC, and sequential metadata across clock edge. |
| **ID/EX Register** | `id_ex_reg.flush` | `1` | Flushes outputs; clears controls and inserts a bubble (`valid = 0`) into EX. |
| **EX/MEM Register**| `ex_mem_reg.en` | `1` | Advances normally; allows in-flight `LW` to reach MEM stage. |
| **MEM/WB Register**| `mem_wb_reg.en` | `1` | Advances normally; allows older instructions to commit to Write-Back. |

---

## 5. Timing & Cycle Sequence Summary

```text
Clock:           _/~~\__/~~\__/~~\__/~~\__/~~\__
Instruction 1:   [ IF ][ ID ][ EX ][ MEM][ WB ]   <-- LW x5, 0(sp)
Instruction 2:         [ IF ][ ID ][ STALL ][ EX ][ MEM][ WB ] <-- ADD x6, x5, x1
                                  ▲
                         1-cycle bubble in EX
```
At the end of the stall cycle:
- `LW` completes memory read and enters `mem_wb_reg`.
- `ADD` advances from ID into `id_ex_reg`.
- In the subsequent cycle, the EX stage forwarding multiplexer (`FWD_MEM_WB = 2'b01`) forwards the loaded memory word directly to the ALU input with zero loss of correctness.
