# Top-Level Pipelined CPU Interface & Integration Specification

**Module:** `cpu` (`rtl/cpu.v`) / `top` (`rtl/top.v`)  
**Milestone:** Milestone 5 (M5) — Top-Level Pipelined CPU Integration  
**Related Issue:** Issue #26 (Top-Level Pipelined CPU Integration)

---

## 1. Architectural Overview

The `cpu` module unifies all stage wrappers, boundary registers, and hazard handling modules developed across Milestones 1 through 5 into a fully functional 5-stage in-order pipelined RISC-V processor implementing the RV32I integer subset:

- **Instruction Fetch (IF)**: `if_stage.v` (incorporating `pc.v`, `instr_mem.v`, and sequential PC+4 generation).
- **IF/ID Pipeline Register**: `if_id_reg.v` with synchronous hold (`en = 0`) and synchronous flush (`flush = 1`).
- **Instruction Decode (ID)**: `id_stage.v` (integrating `instruction_decoder.v`, 32-entry `register_file.v` with internal write-through bypass, and `main_control.v`).
- **ID/EX Pipeline Register**: `id_ex_reg.v` capturing decoded execution, memory, write-back flags, source/destination indices, and immediate payload.
- **Execution (EX)**: `ex_stage.v` (integrating `alu.v`, `alu_control.v`, `branch_unit.v`, and dual 2-bit operand forwarding multiplexers).
- **EX/MEM Pipeline Register**: `ex_mem_reg.v` capturing execution results, store data, and memory flags.
- **Memory Access (MEM)**: `mem_stage.v` (integrating 1 KiB word-addressable `data_mem.v` and address checking).
- **MEM/WB Pipeline Register**: `mem_wb_reg.v` capturing load data, ALU result, destination register index, and write-back controls.
- **Write-Back (WB)**: `wb_stage.v` driving register write-back data and write enable back to ID stage register file.
- **Hazard Interlock Unit**: `hazard_detection.v` detecting load-use dependencies and asserting 1-cycle pipeline interlock.
- **Operand Forwarding Unit**: `forwarding_unit.v` providing EX-to-EX and MEM-to-EX bypass without stalls.
- **Branch Coordination Controller**: `branch_controller.v` handling next-PC redirection and dual-boundary flushing on taken branches.

```text
 ┌─────────────┐       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐
 │  IF Stage   │       │  ID Stage   │       │  EX Stage   │       │  MEM Stage  │       │  WB Stage   │
 │             │       │             │       │             │       │             │       │             │
 │  [pc.v]     │       │ [decoder]   │       │[alu_control]│       │ [data_mem]  │       │  [wb_mux]   │
 │  [instr_mem]│──────►│ [reg_file]  │──────►│    [alu]    │──────►│ (1 KiB RAM) │──────►│             │
 │  (pc + 4)   │       │  [control]  │       │[branch_unit]│       │             │       │ (wb_data)   │
 └──────┬──────┘       └──────┬──────┘       └──────┬──────┘       └──────┬──────┘       └──────┬──────┘
        │                     │                     │                     │                     │
        ▼                     ▼                     ▼                     ▼                     │
 ┌─────────────┐       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐              │
 │  IF/ID Reg  │       │  ID/EX Reg  │       │ EX/MEM Reg  │       │ MEM/WB Reg  │              │
 └─────────────┘       └─────────────┘       └─────────────┘       └─────────────┘              │
        ▲                     ▲                     │                     │                     │
        │                     │                     └──────────┬──────────┴─────────────────────┘
        │                     │                                │
        │                     │                     Forwarding │ Paths (EX/MEM, MEM/WB, WB)
        │                     │                                ▼
        │                     │                  ┌───────────────────────────┐
        │                     │                  │   forwarding_unit.v       │
        │                     │                  └─────────────┬─────────────┘
        │                     │                                │ forward_a, forward_b
        │                     │                                ▼
 ┌──────┴─────────────────────┴────────────────────────────────────────────────┐
 │                 Hazard & Pipeline Interlock Coordinator                      │
 │     [hazard_detection.v] (stall)  +  [branch_controller.v] (flush/redirect) │
 └─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Module Parameters

| Parameter | Type | Default | Description |
|---|:---:|:---:|---|
| `RESET_VECTOR` | `[31:0]` | `32'h0000_0000` | Initial PC loaded on synchronous reset |
| `IMEM_DEPTH` | integer | `256` | Depth of instruction memory in 32-bit words (1 KiB) |
| `IMEM_INIT_FILE`| string | `""` | Optional hex memory file for `$readmemh` instruction memory init |
| `DMEM_DEPTH` | integer | `256` | Depth of data memory in 32-bit words (1 KiB) |
| `DMEM_INIT_FILE`| string | `""` | Optional hex memory file for `$readmemh` data memory init |

---

## 3. Top-Level Port Interface

### Clock & Reset
| Port Name | Width | Direction | Description |
|---|:---:|:---:|---|
| `clk` | 1 | Input | Single rising-edge system clock |
| `rst` | 1 | Input | Active-high synchronous system reset |

### Debug & Observability Outputs
| Port Name | Width | Direction | Functional Description |
|---|:---:|:---:|---|
| `debug_if_pc` | 32 | Output | Current fetch PC in IF stage |
| `debug_if_instr` | 32 | Output | Instruction word currently read from instruction memory |
| `debug_id_pc` | 32 | Output | Instruction PC currently in ID stage |
| `debug_id_instr` | 32 | Output | Instruction word currently in ID stage |
| `debug_id_valid` | 1 | Output | Validity indicator of instruction in ID (`0` = bubble / flushed) |
| `debug_ex_pc` | 32 | Output | Instruction PC currently in EX stage |
| `debug_ex_alu_result`| 32 | Output | ALU computation result in EX stage |
| `debug_ex_valid` | 1 | Output | Validity indicator of instruction in EX (`0` = bubble / flushed) |
| `debug_mem_pc` | 32 | Output | Instruction PC currently in MEM stage |
| `debug_mem_addr` | 32 | Output | Data memory access byte address in MEM stage |
| `debug_mem_write_data`| 32 | Output | Write data presented to data memory for `SW` |
| `debug_mem_read` | 1 | Output | Active-high memory read strobe (`LW`) |
| `debug_mem_write`| 1 | Output | Active-high memory write strobe (`SW`) |
| `debug_mem_valid`| 1 | Output | Validity indicator of instruction in MEM |
| `debug_wb_pc` | 32 | Output | PC of retiring instruction in WB stage |
| `debug_wb_reg_write`| 1 | Output | Active-high register file write strobe |
| `debug_wb_rd` | 5 | Output | Destination register index written to register file |
| `debug_wb_data` | 32 | Output | Data value written to register file port |
| `debug_wb_retired`| 1 | Output | Strobe asserted when a valid instruction retires |
| `debug_stall` | 1 | Output | Active-high load-use stall request |
| `debug_flush` | 1 | Output | Active-high branch misprediction flush event |
| `debug_branch_taken`| 1 | Output | Active-high taken branch condition evaluated in EX |
| `debug_branch_target`| 32 | Output | Computed branch target address (`pc + imm`) |
| `debug_forward_a`| 2 | Output | Forwarding multiplexer select for Operand A |
| `debug_forward_b`| 2 | Output | Forwarding multiplexer select for Operand B |

---

## 4. Supported Instruction Set & Architectural Guarantees

### Supported Instructions
- **R-Type Arithmetic**: `ADD`, `SUB`
- **I-Type Arithmetic**: `ADDI`
- **Memory Operations**: `LW` (word load), `SW` (word store)
- **Conditional Branches**: `BEQ` (equal), `BNE` (not equal)

### Architectural Guarantees:
1. **In-Order Program Flow**: All instructions advance sequentially through IF -> ID -> EX -> MEM -> WB in program order.
2. **Hardwired Zero (`x0 = 0`)**: Writes to `x0` produce no architectural side-effects; reads from `x0` always return `32'd0`.
3. **No Undriven Inputs**: Every input port across all submodules is explicitly driven; no floating nets or width truncations exist.
4. **Zero Spurious Side Effects**: Flushed instructions or reset bubbles (`valid == 0`) deassert `reg_write`, `mem_write`, `mem_read`, and `branch_taken`.
5. **Exact-Once Execution**: On a taken branch, younger instructions in IF and ID are squashed simultaneously via `if_id_flush` and `id_ex_flush`; the target instruction is fetched and executed exactly once.

---

## 5. Verification Commands

Run the full top-level test suite using Icarus Verilog:

```bash
mkdir -p simulation && \
iverilog -g2012 -o simulation/tb_cpu.vvp \
    testbench/tb_cpu.v \
    rtl/cpu.v \
    rtl/stages/if_stage.v \
    rtl/stages/pc.v \
    rtl/stages/instr_mem.v \
    rtl/pipeline_registers/if_id_reg.v \
    rtl/stages/id_stage.v \
    rtl/stages/instruction_decoder.v \
    rtl/stages/register_file.v \
    rtl/stages/main_control.v \
    rtl/pipeline_registers/id_ex_reg.v \
    rtl/stages/ex_stage.v \
    rtl/stages/alu.v \
    rtl/stages/alu_control.v \
    rtl/stages/branch_unit.v \
    rtl/pipeline_registers/ex_mem_reg.v \
    rtl/stages/mem_stage.v \
    rtl/stages/data_mem.v \
    rtl/pipeline_registers/mem_wb_reg.v \
    rtl/stages/wb_stage.v \
    rtl/stages/hazard_detection.v \
    rtl/stages/forwarding_unit.v \
    rtl/stages/branch_controller.v && \
vvp simulation/tb_cpu.vvp
```
