# Forwarding Unit Interface & Bypass Specification

**Module:** `forwarding_unit` (`rtl/stages/forwarding_unit.v`) / `forwarding` (`rtl/stages/forwarding.v`)  
**Milestone:** Milestone 5 (M5) — Hazard Detection, Forwarding & Full Pipeline Integration  
**Related Issue:** Issue #24 (EX-Stage Forwarding & Bypass Logic)

---

## 1. Overview & Datapath Integration

In the 5-stage RV32I pipeline, Read-After-Write (RAW) data dependencies between an executing instruction in **EX** and older in-flight instructions in **EX/MEM** and **MEM/WB** are resolved combinationally via operand forwarding, eliminating pipeline bubbles for ALU-to-ALU, ALU-to-Store, and MEM-to-ALU data paths.

```text
                  ┌──────────────────────┐
                  │      ID/EX Reg       │
                  └──────────┬───────────┘
                             │ (rs1_data, rs2_data)
                             ▼
  forward_mem_data ──► ┌───────────┐
 (from EX/MEM Reg)     │Forward Mux│ ◄─── forward_a [1:0]
  forward_wb_data  ──► │  (Op A)   │
 (from MEM/WB / WB)    └─────┬─────┘
                             ▼
                     fwd_rs1_data ───────► [ ALU Operand A ]
                                          [ Branch Operand A ]

  forward_mem_data ──► ┌───────────┐
 (from EX/MEM Reg)     │Forward Mux│ ◄─── forward_b [1:0]
  forward_wb_data  ──► │  (Op B)   │
 (from MEM/WB / WB)    └─────┬─────┘
                             ▼
                     fwd_rs2_data ───────► [ Store Data to MEM ]
                             │            [ Branch Operand B ]
                             ▼
                       ┌───────────┐
            imm_in ──► │  Imm Mux  │ ◄─── alu_src_imm
                       └─────┬─────┘
                             ▼
                      [ ALU Operand B ]
```

---

## 2. Port Interface

### Inputs
| Port Name | Width | Source Module | Description |
|---|---:|---|---|
| `id_ex_rs1` | 5 | `id_ex_reg` (`rs1_out`) | Source register 1 address of instruction in EX |
| `id_ex_rs2` | 5 | `id_ex_reg` (`rs2_out`) | Source register 2 address of instruction in EX |
| `id_ex_valid` | 1 | `id_ex_reg` (`valid_out`)| Validity flag of instruction in EX (`0` = bubble / flushed) |
| `ex_mem_rd` | 5 | `ex_mem_reg` (`rd_out`) | Destination register address in EX/MEM (younger producer) |
| `ex_mem_reg_write`| 1 | `ex_mem_reg` (`reg_write_out`)| Register write enable in EX/MEM |
| `ex_mem_mem_read` | 1 | `ex_mem_reg` (`mem_read_out`) | Memory read enable in EX/MEM (1 = LW) |
| `ex_mem_valid`| 1 | `ex_mem_reg` (`valid_out`)| Validity flag in EX/MEM (`0` = bubble / flushed) |
| `mem_wb_rd` | 5 | `mem_wb_reg` (`rd_out`) | Destination register address in MEM/WB (older producer) |
| `mem_wb_reg_write`| 1 | `mem_wb_reg` (`reg_write_out`)| Register write enable in MEM/WB |
| `mem_wb_valid`| 1 | `mem_wb_reg` (`valid_out`)| Validity flag in MEM/WB (`0` = bubble / flushed) |

### Outputs
| Port Name | Width | Destination | Functional Meaning |
|---|---:|---|---|
| `forward_a` | 2 | `ex_stage.forward_a` | Selects source for Operand A (`rs1`) |
| `forward_b` | 2 | `ex_stage.forward_b` | Selects source for Operand B (`rs2`) |

---

## 3. Multiplexer Encodings & Priority Rules

The multiplexer control encodings coordinate directly with the parameters defined in `ex_stage.v`:

| Encoding | Parameter | Selected Data Source in `ex_stage.v` |
|:---:|---|---|
| `2'b00` | `FWD_ID_EX` | ID/EX register operand (`rs1_data_in` / `rs2_data_in`) |
| `2'b01` | `FWD_MEM_WB` | MEM/WB forwarded value (`forward_wb_data` from WB stage) |
| `2'b10` | `FWD_EX_MEM` | EX/MEM forwarded value (`forward_mem_data` from EX/MEM) |
| `2'b11` | Reserved | Defaults safely to `FWD_ID_EX` |

### Priority Order:
When both the EX/MEM and MEM/WB stages target the same destination register as an EX-stage source register:
1. **EX/MEM Forwarding (Priority 1):** The instruction in EX/MEM is younger than the instruction in MEM/WB and holds the most recent computation. Therefore, EX/MEM forwarding strictly takes precedence.
2. **MEM/WB Forwarding (Priority 2):** Evaluated only if EX/MEM does not forward.
3. **No Forwarding (Priority 3):** If neither stage matches, defaults to `FWD_ID_EX`.

---

## 4. Forwarding Conditions & Safety Guarantees

### A. Producer Forwardability Rules
```verilog
// EX/MEM is forwardable if valid, writing to a register, not targeting x0, and not a load
wire ex_mem_forwardable = ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read && (ex_mem_rd != 5'd0);

// MEM/WB is forwardable if valid, writing to a register, and not targeting x0
wire mem_wb_forwardable = mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 5'd0);
```

### B. Safety & Protection Guarantees
1. **Hardwired Zero (`x0`) Protection:**
   - RISC-V register `x0` is permanently hardwired to `32'd0`. Any instruction targeting `x0` (`rd == 5'd0`) is never forwarded (`ex_mem_rd != 0` and `mem_wb_rd != 0`).
2. **Bubble & Invalidation Immunity:**
   - When a stage contains an invalid instruction or flushed bubble (`valid == 0`) or an instruction that does not write to a register (`reg_write == 0`, such as `SW`, `BEQ`, `BNE`), forwarding is completely suppressed.
3. **Unforwardable Memory Load Protection:**
   - When an instruction in EX/MEM is a memory load (`ex_mem_mem_read == 1`), its loaded data is not yet available at the start of the EX stage. The forwarding unit suppresses EX/MEM forwarding (`!ex_mem_mem_read`).
4. **Immediate Operand Preservation:**
   - In `ex_stage.v`, `forward_b` selects `fwd_rs2_data`. For instructions with `alu_src_imm == 1` (`ADDI`, `LW`, `SW`), the immediate multiplexer downstream of the forwarding mux preserves immediate selection for the ALU, while `store_data` and branch comparisons correctly receive `fwd_rs2_data`.
