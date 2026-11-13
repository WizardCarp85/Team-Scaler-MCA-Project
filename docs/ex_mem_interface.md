# EX/MEM Interface & Pipeline Register Specification

**Module:** `ex_mem_reg` (`rtl/pipeline_registers/ex_mem_reg.v`)  
**Status:** Implemented for Issue #16 (Integration agreement with M4/M5 pending team confirmation)

---

## 1. Overview

The `ex_mem_reg` module captures execution results, store data, destination register index, PC metadata, and memory/write-back control signals at the EX/MEM pipeline boundary on the rising clock edge.

---

## 2. Port Interface

Every payload field has a matching `_in` and `_out` port of identical width:

| Signals | Width | Consumer and Meaning |
|---|---:|---|
| `alu_result` | 32 | Memory address for LW/SW, or computation result for register WB / forwarding |
| `store_data` | 32 | Forwarded store write data for SW in MEM stage |
| `rd` | 5 | Destination register index for WB and EX/MEM forwarding comparisons |
| `pc`, `pc_plus4` | 32 | Instruction PC and sequential PC metadata |
| `mem_read`, `mem_write` | 1 | Data memory read and write enables for MEM stage (Issue #18) |
| `reg_write`, `wb_from_mem`| 1 | WB stage register write enable and write-back source select (1 selects load data) |
| `valid` | 1 | Instruction validity flag (1 indicates live instruction; 0 indicates bubble) |

---

## 3. Edge Behavior and Priority Order

Evaluated on each rising clock edge:

1. **Synchronous Reset or Flush (`rst || flush`)**:
   - Clears every output to `0`. A flush beats a hold (`en=0`).
2. **Hold (`en == 0`)**:
   - All outputs hold their previous values across clock cycles.
   - **Hold Priority over Bubble Capture**: When `en == 0`, the register holds its current contents regardless of `valid_in` (even if `valid_in == 0`).
3. **Bubble Capture (`en == 1 && valid_in == 0`)**:
   - When capture is enabled (`en == 1`), capturing an invalid input clears every output to `0` like a flush, ensuring bubbles cannot assert side-effects.
4. **Active Capture (`en == 1 && valid_in == 1`)**:
   - Captures the complete valid bundle from `*_in` to `*_out`.

---

## 4. Differences from PR #42 EX-Stage Outputs

The `ex_stage` module (`rtl/stages/ex_stage.v`) produces outputs that are handled as follows at the EX/MEM boundary:

1. **Signals Registered into `ex_mem_reg`**:
   - `alu_result`, `store_data`, `rd`, `pc`, `pc_plus4`, `mem_read`, `mem_write`, `reg_write`, `wb_from_mem`, and `valid` are captured directly into `ex_mem_reg`.
2. **Signals NOT Registered into `ex_mem_reg`**:
   - `branch_taken` and `branch_target`: Combinational branch outcome and target address routed back to the IF stage (PC multiplexer) and hazard unit (M5) for immediate redirection and flushing; they do not advance down the sequential pipeline to MEM.
   - `rs1` and `rs2`: Source register indices exposed solely for EX-stage forwarding comparisons by M5 (`forward_a`, `forward_b`); downstream stages (MEM and WB) only need the destination register `rd`.

---

## 5. Downstream Integration & Hazard Control Coordination (M4 & M5)

- **M4 (Memory Stage Integration, Issue #18)**: Connects `alu_result_out` (address), `store_data_out` (write data), `mem_read_out`, and `mem_write_out` to data memory. Propagates `rd_out`, `reg_write_out`, `wb_from_mem_out`, `pc_out`, `pc_plus4_out`, and `valid_out` to MEM/WB. *(Agreement pending team confirmation)*.
- **M5 (Hazard, Forwarding & Stall/Flush Coordination, Issues #22, #24, #25)**:
  - **Careful Hold/Flush Coordination Required**: M5 must coordinate EX/MEM `en` (hold) and `flush` carefully:
    1. **Memory Re-execution Prevention**: A held valid memory operation (`mem_read` or `mem_write`) must not be executed repeatedly by downstream memory stages during a multi-cycle stall or wait state.
    2. **Protection of Older In-Flight Instructions**: An EX-resolved branch redirect or a load-use stall must flush only the younger pipeline boundaries (e.g., IF/ID and ID/EX) and must not accidentally discard or corrupt older instructions advancing through or held in EX/MEM.
  - **Pending Agreement**: The precise top-level stall, flush, and re-execution suppression control policy is pending integration agreement with M4 and M5.
