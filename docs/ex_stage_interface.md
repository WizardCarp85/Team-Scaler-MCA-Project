# EX Stage Interface & Integration Specification

**Module:** `ex_stage` (`rtl/stages/ex_stage.v`)  
**Status:** Implemented for Issue #15 (Integration agreement with M4/M5 pending team confirmation)

---

## 1. Overview

The `ex_stage` module provides the complete execution stage datapath for the 5-stage pipelined RV32I processor. It unifies:
1. **Operand forwarding multiplexers** for resolving data hazards from EX/MEM and MEM/WB.
2. **ALU operand selection** (forwarded register value vs. sign-extended immediate).
3. **Submodule integration**:
   - `alu_control` (`rtl/stages/alu_control.v`): Translates `alu_op`, `funct3`, and `funct7` into `alu_ctrl`.
   - `alu` (`rtl/stages/alu.v`): Evaluates 32-bit ADD and SUB.
   - `branch_unit` (`rtl/stages/branch_unit.v`): Evaluates BEQ/BNE conditions using forwarded operands and computes `pc + imm` branch targets.
4. **Side-effect suppression & pass-through metadata**: Gates all memory/register write enables on `valid_in` and propagates metadata to the EX/MEM pipeline register.

---

## 2. Port Interface

### Inputs (from `id_ex_reg`)
| Signal | Width | Description |
|---|---:|---|
| `pc_in`, `pc_plus4_in` | 32 | Instruction PC and sequential PC+4 metadata |
| `rs1_data_in`, `rs2_data_in` | 32 | Source register values read from ID stage |
| `imm_in` | 32 | Sign-extended I/S immediate or B-type byte offset |
| `rs1_in`, `rs2_in`, `rd_in` | 5 | Source and destination register indices |
| `funct3_in`, `funct7_in` | 3, 7 | Instruction funct fields for ALU control |
| `alu_op_in` | 2 | Main ALU operation class (00: add/address, 01: R-type, 10: branch) |
| `branch_type_in` | 2 | Branch instruction type (00: none, 01: BEQ, 10: BNE) |
| `alu_src_imm_in` | 1 | 1 selects `imm_in` for ALU Operand B; 0 selects forwarded `rs2` |
| `mem_read_in`, `mem_write_in`| 1 | Memory access control signals |
| `reg_write_in`, `wb_from_mem_in`| 1 | Register write-back control signals |
| `valid_in` | 1 | Stage instruction validity flag |

### Forwarding Inputs (from M5 Forwarding Unit - Agreement Pending)
| Signal | Width | Description |
|---|---:|---|
| `forward_a` | 2 | Forwarding selector for Operand A (rs1) |
| `forward_b` | 2 | Forwarding selector for Operand B / store data (rs2) |
| `forward_mem_data` | 32 | Forwarded result from EX/MEM boundary |
| `forward_wb_data` | 32 | Forwarded result from MEM/WB boundary |

#### Forwarding Control Encoding:
- `2'b00` (`FWD_ID_EX`): Use ID/EX stage register operand (no forwarding).
- `2'b01` (`FWD_MEM_WB`): Forward from MEM/WB stage.
- `2'b10` (`FWD_EX_MEM`): Forward from EX/MEM stage.
- `2'b11`: Reserved (defaults safely to ID/EX register operand).

### Outputs (to EX/MEM boundary and M5)
| Signal | Width | Destination | Meaning |
|---|---:|---|---|
| `alu_result` | 32 | EX/MEM | Computed arithmetic result or memory effective address |
| `branch_taken` | 1 | IF / Hazard (M5) | Combinational branch condition outcome |
| `branch_target` | 32 | IF stage (M1) | Computed branch target address (`pc + imm`) |
| `store_data` | 32 | EX/MEM | Forwarded `rs2` data for SW instructions |
| `rd` | 5 | EX/MEM | Destination register index |
| `pc`, `pc_plus4` | 32 | EX/MEM | Instruction PC metadata |
| `rs1`, `rs2` | 5 | Hazard Unit (M5) | Source register indices for hazard / forwarding detection |
| `mem_read`, `mem_write` | 1 | EX/MEM | Memory read/write enables (gated by `valid`) |
| `reg_write`, `wb_from_mem` | 1 | EX/MEM | Write-back control signals (gated by `valid`) |
| `valid` | 1 | EX/MEM | Propagated instruction validity flag |

---

## 3. Critical Datapath Behaviors

1. **Store Data Forwarding**:
   - `store_data` is sourced directly from the forwarded `rs2` data (`fwd_rs2_data`).
   - For `SW` instructions, `alu_src_imm = 1`, causing the ALU to add `fwd_rs1_data + imm` to generate the memory address, while `store_data` independently carries the forwarded `rs2` store value into the memory stage.
2. **Branch Forwarding**:
   - The branch comparison operands inside `branch_unit` connect to `fwd_rs1_data` and `fwd_rs2_data`, ensuring branches evaluate against forwarded results without stalling when data is already available.
3. **Side-Effect Gating**:
   - When `valid_in == 0` (bubble or flushed instruction), `branch_taken` is forced low, and `mem_read`, `mem_write`, `reg_write`, and `wb_from_mem` are suppressed to `0`.
