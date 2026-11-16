# Branch Redirect, Flush & Hazard Stall Coordination Specification

**Module:** `branch_controller` (`rtl/stages/branch_controller.v`) / `branch_hazard_coordinator` (`rtl/stages/branch_hazard_coordinator.v`)  
**Milestone:** Milestone 5 (M5) — Hazard Detection, Forwarding & Full Pipeline Integration  
**Related Issue:** Issue #25 (Branch Redirect, Pipeline Flush & Hazard Stall Coordination)

---

## 1. Architectural Overview & Responsibilities

In the 5-stage in-order RV32I pipelined processor (**IF**, **ID**, **EX**, **MEM**, **WB**), conditional branches (`BEQ`, `BNE`) are evaluated combinationally during the **Execution (EX)** stage. 

When a branch resolves as **TAKEN** in EX:
1. **Next-PC Redirection**: The fetch program counter must immediately redirect from sequential execution (`pc + 4`) to the computed target address (`branch_target = pc + imm`).
2. **Wrong-Path Instruction Squashing**: Two younger instructions already fetched into the pipeline reside on the mispredicted path:
   - The instruction currently being fetched in **IF** (at branch PC + 8).
   - The instruction currently held in the **ID** stage (at branch PC + 4, in `if_id_reg`).
   Both must be synchronously flushed to bubbles (`valid = 0`, NOP `32'h0000_0013`) so they commit zero register or memory side effects.
3. **Deterministic Hazard Arbitration**: If a younger instruction in the ID stage triggers a load-use stall request (`stall_req == 1`) while the older branch in EX evaluates as taken, the branch redirect strictly overrides the stall request. Discarded wrong-path instructions must never stall the pipeline or delay target fetching.
4. **Exact-Once Target Execution**: The target instruction fetched from `branch_target` must enter the pipeline and execute **exactly once** without accidental squashing or duplication.

```text
                               EX Stage
                            ┌─────────────┐
                            │ branch_unit │
                            └──────┬──────┘
                                   │ branch_taken, branch_target
                                   ▼
 ┌──────────────┐          ┌───────────────────────┐          ┌──────────────┐
 │   IF Stage   │          │   branch_controller   │          │  ID/EX Reg   │
 │   [pc.v]     │◄─────────┤ (Pipeline Coordinator)├─────────►│   (Flush)    │
 │ (next_pc Mux)│ next_pc  └───────────┬───────────┘ id_ex_flush └──────────────┘
 └──────────────┘                      │
                                       │ if_id_flush, if_id_en
                                       ▼
                            ┌───────────────────────┐
                            │       if_id_reg       │
                            └───────────────────────┘
```

---

## 2. Port Interface

### Inputs
| Port Name | Width | Source Module | Functional Meaning |
|---|---:|---|---|
| `pc` | 32 | `pc.v` (`if_stage.v`) | Current fetch PC address |
| `pc_plus4` | 32 | `if_stage.v` | Sequential fetch PC+4 address |
| `branch_taken` | 1 | `ex_stage` (`branch_unit`) | Asserted when branch condition evaluates true in EX (`valid && taken`) |
| `branch_target`| 32 | `ex_stage` (`branch_unit`) | Target address computed by branch unit (`pc + imm`) |
| `stall_req` | 1 | `hazard_detection.v` | Active-high load-use interlock request from hazard unit |

### Outputs
| Port Name | Width | Destination | Functional Meaning |
|---|---:|---|---|
| `next_pc` | 32 | `pc.v` (`if_stage.next_pc`)| Multiplexed PC value loaded on next clock edge |
| `pc_src` | 2 | Top-Level / Status | PC source select code (`00`=PC+4, `01`=Branch, `10`=Hold) |
| `pc_en` | 1 | `pc.v` / Top-Level | PC update enable (`1` = update, `0` = hold) |
| `if_id_flush` | 1 | `if_id_reg.flush` | Synchronous flush clearing instruction in IF/ID to NOP bubble |
| `if_id_en` | 1 | `if_id_reg.en` | Capture enable (`0` = freeze IF/ID on load-use stall) |
| `id_ex_flush` | 1 | `id_ex_reg.flush` | Synchronous flush inserting bubble (`valid = 0`) into EX |
| `id_ex_en` | 1 | `id_ex_reg.en` | Capture enable for ID/EX register |
| `stall_out` | 1 | Status / Diagnostics | Qualified stall indicator (suppressed to `0` when branch is taken) |
| `flush_out` | 1 | Status / Diagnostics | Active-high pipeline flush event indicator |

---

## 3. Multiplexer Encodings & Deterministic Priority Table

### PC Source Select Mux Encodings (`pc_src`):
| Encoding | Parameter | Selected `next_pc` Source | Description |
|:---:|---|---|---|
| `2'b00` | `PC_PLUS4` | `pc_plus4` | Normal sequential fetch |
| `2'b01` | `PC_BRANCH`| `branch_target` | Branch redirect to target address |
| `2'b10` | `PC_HOLD` | `pc` | Load-use interlock hold (re-fetch current PC) |

### Deterministic Priority Arbitration Table:

| Priority | Condition | `next_pc` | `pc_src` | `pc_en` | `if_id_flush` | `if_id_en` | `id_ex_flush` | `id_ex_en` | `stall_out` | `flush_out` |
|:---:|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **1** | **Branch Taken in EX** (`branch_taken == 1`) | `branch_target` | `2'b01` | `1` | `1` | `1` | `1` | `1` | `0` | `1` |
| **2** | **Load-Use Stall** (`stall_req == 1 && !branch_taken`) | `pc` | `2'b10` | `0` | `0` | `0` | `1` | `1` | `1` | `0` |
| **3** | **Normal Sequential** (`!branch_taken && !stall_req`) | `pc_plus4` | `2'b00` | `1` | `0` | `1` | `0` | `1` | `0` | `0` |

### Architectural Rules:
1. **Branch Priority Over Stall**:
   - If a branch in EX evaluates as taken, younger instructions in ID and IF are on the mispredicted path. Any hazard stall request from a wrong-path instruction in ID is invalid and MUST be suppressed (`stall_out = 0`). Stalling a wrong-path instruction would cause a fatal pipeline deadlock or delay target fetch.
2. **Dual-Boundary Flush**:
   - Both `if_id_flush` and `id_ex_flush` are asserted combinationally in the EX cycle when `branch_taken == 1`.
   - On the next clock edge, `if_id_reg` captures NOP (`valid = 0`), and `id_ex_reg` captures bubble (`valid = 0`), squashing both wrong-path instructions.
3. **Target Fetch Preservation**:
   - Because `pc_en = 1` and `next_pc = branch_target`, the PC register captures `branch_target` on the exact same clock edge that flushes IF/ID and ID/EX.
   - In the subsequent cycle, the target instruction is fetched from memory and flows sequentially into ID, executing exactly once.

---

## 4. Cycle-by-Cycle Execution Timing

### Scenario A: Taken Branch (`BEQ x1, x2, +16` taken to `0x18`)
- `0x00`: `ADDI x1, x0, 10`
- `0x04`: `ADDI x2, x0, 10`
- `0x08`: `BEQ  x1, x2, +16` (Target = `0x18`)
- `0x0C`: `ADDI x3, x0, 99`  *(Wrong-path 1)*
- `0x10`: `ADDI x4, x0, 88`  *(Wrong-path 2)*
- `0x18`: `ADDI x5, x0, 42`  *(Target instruction)*

| Cycle | IF (Fetch PC) | ID Stage | EX Stage | MEM Stage | WB Stage | Pipeline Event & Coordinator Action |
|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **1** | `0x00` (ADDI x1) | - | - | - | - | Sequential fetch |
| **2** | `0x04` (ADDI x2) | `0x00` (ADDI x1) | - | - | - | Sequential fetch |
| **3** | `0x08` (BEQ) | `0x04` (ADDI x2) | `0x00` (ADDI x1) | - | - | Sequential fetch |
| **4** | `0x0C` (Wrong 1) | `0x08` (BEQ) | `0x04` (ADDI x2) | `0x00` (ADDI x1) | - | Sequential fetch |
| **5** | `0x10` (Wrong 2) | `0x0C` (Wrong 1) | `0x08` (BEQ) | `0x04` (ADDI x2) | `0x00` (ADDI x1) | **BEQ Taken**: `next_pc = 0x18`, `if_id_flush=1`, `id_ex_flush=1` |
| **6** | `0x18` (Target) | `bubble` *(flushed)*| `bubble` *(flushed)*| `0x08` (BEQ) | `0x04` (ADDI x2) | Wrong-path instructions squashed. Target fetched. |
| **7** | `0x1C` (Target+4)| `0x18` (Target) | `bubble` | `bubble` | `0x08` (BEQ) | Target enters ID stage |
| **8** | `0x20` | `0x1C` | `0x18` (Target) | `bubble` | `bubble` | **Target executes in EX** (`x5 = 42`) **exactly once**! |

### Scenario B: Load-Use Hazard on Branch Followed by Taken Redirection
- `0x00`: `LW  x1, 0(x0)` (loads `0`)
- `0x04`: `BEQ x1, x0, +12` (in ID, consumes loaded `x1`; target = `0x10`)
- `0x08`: `ADDI x4, x0, 11` (in IF during stall)
- `0x10`: `ADDI x5, x0, 888` (Target)

| Cycle | IF | ID | EX | MEM | WB | Action |
|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **N** | `0x08` | `0x04` (BEQ) | `0x00` (LW) | - | - | **Hazard Detected**: `stall_req=1` -> PC hold (`0x08`), IF/ID freeze, ID/EX bubble |
| **N+1**| `0x08` (held) | `0x04` (BEQ held) | `bubble` | `0x00` (LW) | - | Stall cycle: LW reads memory; BEQ preserved in ID |
| **N+2**| `0x0C` | `0x08` | `0x04` (BEQ) | `bubble` | `0x00` (LW) | `x1` forwarded from MEM/WB. BEQ in EX evaluates **TAKEN**! `next_pc = 0x10`, dual flush. |
| **N+3**| `0x10` (Target)| `bubble` | `bubble` | `0x04` (BEQ) | `bubble` | Target fetched from `0x10`. Wrong-path `0x08` squashed. |
| **N+4**| `0x14` | `0x10` (Target) | `bubble` | `bubble` | `0x04` (BEQ) | Target enters ID stage. |
| **N+5**| `0x18` | `0x14` | `0x10` (Target) | `bubble` | `bubble` | Target executes in EX (`x5 = 888`). |

---

## 5. Safety & Side-Effect Prevention Guarantees

1. **Zero Register File Pollution**:
   - Flushed instructions have `valid = 0` registered in `id_ex_reg`. In `ex_stage.v`, all side-effect signals (`reg_write`, `mem_write`, `mem_read`) are strictly gated by `valid_in`:
     ```verilog
     assign reg_write = valid_in ? reg_write_in : 1'b0;
     ```
   - Wrong-path instructions (`0x0C`, `0x10` in Scenario A) can never assert `reg_write` or alter register state.
2. **Zero Memory Corruption**:
   - `mem_write` is forced to `0` for all bubbles, preventing spurious writes to data memory.
3. **Bubble Immunity**:
   - Pipeline bubbles (`valid == 0`) entering EX have `branch_taken` forced to `0` inside `branch_unit.v`. An empty or flushed bubble can never trigger a branch redirect.
4. **No Double Execution**:
   - On a taken branch, `if_id_en` and `id_ex_en` remain enabled so the synchronous flush takes immediate effect. The branch instruction advances to EX/MEM and is never re-executed.

---

## 6. Integration Guide for Top-Level CPU

```verilog
// Instantiate Branch Controller
branch_controller u_branch_controller (
    .pc           (pc_current),        // from if_stage / pc
    .pc_plus4     (pc_plus4),          // from if_stage
    .branch_taken (ex_branch_taken),   // from ex_stage.branch_taken
    .branch_target(ex_branch_target),  // from ex_stage.branch_target
    .stall_req    (hazard_stall),      // from hazard_detection.stall
    .next_pc      (next_pc_wire),      // to if_stage.next_pc
    .pc_src       (),
    .pc_en        (pc_en_wire),        // to pc.en (if enabled)
    .if_id_flush  (if_id_flush_wire),  // to if_id_reg.flush
    .if_id_en     (if_id_en_wire),     // to if_id_reg.en
    .id_ex_flush  (id_ex_flush_wire),  // to id_ex_reg.flush
    .id_ex_en     (id_ex_en_wire),     // to id_ex_reg.en
    .stall_out    (),
    .flush_out    ()
);
```
