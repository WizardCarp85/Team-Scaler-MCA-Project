# MEM Stage & MEM/WB Interface Specification

**Modules:** `mem_stage` (`rtl/stages/mem_stage.v`), `mem_wb_reg` (`rtl/pipeline_registers/mem_wb_reg.v`)  
**Status:** Implemented for Issue #18 (Integration agreement with M5 pending team confirmation)

---

## 1. Overview

The Memory (MEM) stage is the fourth stage of the 5-stage RV32I pipeline. It:

1. **Routes LW / SW** to the data memory module (`data_mem.v`) using the EX-computed ALU result as the byte address.
2. **Passes non-memory** (R-type, I-immediate) instructions transparently — the ALU result flows directly to the MEM/WB register without touching memory.
3. **Captures the full bundle** into the MEM/WB pipeline register for the Write-Back stage.

```
EX/MEM Reg ──► mem_stage ──► MEM/WB Reg ──► WB
                   │
                data_mem
```

---

## 2. `mem_stage` Port Interface

### Inputs (from `ex_mem_reg` outputs)

| Signal | Width | Description |
|---|---:|---|
| `clk` | 1 | Rising edge — used by `data_mem` for synchronous writes only |
| `alu_result` | 32 | Byte address for LW/SW; arithmetic result for non-memory instructions |
| `store_data` | 32 | Write data for SW (forwarded rs2 from EX stage) |
| `rd` | 5 | Destination register index |
| `pc` | 32 | Instruction PC (pass-through for WB/debug) |
| `pc_plus4` | 32 | Sequential PC+4 (pass-through for WB) |
| `mem_read` | 1 | LW: enables combinational read from `data_mem` |
| `mem_write` | 1 | SW: triggers synchronous write in `data_mem` at next posedge |
| `reg_write` | 1 | Register write-back enable — forwarded to MEM/WB |
| `wb_from_mem` | 1 | WB mux select: 1 → load data, 0 → ALU result |
| `valid` | 1 | Instruction validity flag |

### Outputs (to `mem_wb_reg` inputs)

| Signal | Width | Description |
|---|---:|---|
| `alu_result_out` | 32 | Pass-through ALU result for non-load write-back |
| `load_data_out` | 32 | Combinational read data from `data_mem` (valid when `mem_read = 1`) |
| `rd_out` | 5 | Destination register index |
| `pc_out` | 32 | Instruction PC |
| `pc_plus4_out` | 32 | Sequential PC+4 |
| `reg_write_out` | 1 | Register write-back enable |
| `wb_from_mem_out` | 1 | WB mux select |
| `valid_out` | 1 | Instruction validity flag |
| `access_fault` | 1 | High when `data_mem` flags a misaligned or out-of-range access |

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `MEM_DEPTH_WORDS` | 256 | Data memory depth in 32-bit words (1 KiB). Must be a power of two. |
| `MEM_INIT_FILE` | `""` | Optional `$readmemh` initialisation file for data memory. |

---

## 3. `mem_wb_reg` Port Interface

Synchronous pipeline register separating MEM from WB.

### Control Ports

| Signal | Width | Description |
|---|---:|---|
| `clk` | 1 | Rising edge drives all register updates |
| `rst` | 1 | Synchronous active-high reset; clears all outputs to 0 |
| `en` | 1 | Capture enable: 1 = advance, 0 = hold (stall) |
| `flush` | 1 | Synchronous flush; clears all outputs to 0 (beats `en=0`) |

### Data Ports

| Signal | Width | Direction | Description |
|---|---:|---|---|
| `alu_result_in/out` | 32 | in/out | ALU result for non-load WB |
| `load_data_in/out` | 32 | in/out | Load data from `data_mem` |
| `rd_in/out` | 5 | in/out | Destination register index |
| `pc_in/out` | 32 | in/out | Instruction PC |
| `pc_plus4_in/out` | 32 | in/out | Sequential PC+4 |
| `reg_write_in/out` | 1 | in/out | Register write enable |
| `wb_from_mem_in/out` | 1 | in/out | WB mux select (1 = load, 0 = ALU) |
| `valid_in/out` | 1 | in/out | Instruction validity flag |

---

## 4. Priority Order (`mem_wb_reg`)

Evaluated on each rising clock edge:

1. **Synchronous Reset or Flush (`rst || flush`)**: Clears every output to `0`. A flush beats a hold (`en=0`).
2. **Hold (`en == 0`)**: All outputs hold their previous values across clock cycles. Hold has priority over bubble capture.
3. **Bubble Capture (`en == 1 && valid_in == 0`)**: Capturing an invalid input clears every output to `0`, ensuring bubbles cannot assert side-effects (`reg_write`, `wb_from_mem`).
4. **Active Capture (`en == 1 && valid_in == 1`)**: Captures the complete valid bundle from `*_in` to `*_out`.

> [!NOTE]
> This priority semantics is identical to `ex_mem_reg` for consistency. The only structural difference is that `load_data` replaces `store_data` and the `mem_read`/`mem_write` enables are not propagated (they are consumed by `mem_stage`).

---

## 5. Write-Back Mux

The WB stage selects the register write-back source using `wb_from_mem_out`:

```
wb_from_mem_out = 1  →  write_data = load_data_out   (LW result)
wb_from_mem_out = 0  →  write_data = alu_result_out  (R-type / I-immediate)
```

---

## 6. Data Memory Addressing

`mem_stage` connects `alu_result` directly to `data_mem.addr` (byte address):

| Byte address | Word index |
|---|---|
| `0x000` | 0 |
| `0x004` | 1 |
| `0x008` | 2 |
| `0x3FC` (depth 256 words) | 255 |

- **Misaligned** (`addr[1:0] ≠ 0`): `load_data_out = 0`, `access_fault = 1`, write ignored.
- **Out of range** (`addr ≥ 4 × MEM_DEPTH_WORDS`): same behaviour.

> [!WARNING]
> Wrong-path stores (branch misprediction, flushed instructions) **must** be killed upstream by zeroing `mem_write` in `ex_mem_reg` via flush. `data_mem` has no pipeline state awareness.

---

## 7. Downstream Integration (M5 — Hazard, Forwarding, Stall/Flush)

| Signal | Consumer | Purpose |
|---|---|---|
| `rd_out` | Forwarding unit | MEM/WB forwarding comparisons |
| `reg_write_out` | Forwarding unit | Enables MEM-to-EX forwarding |
| `wb_from_mem_out` | WB stage + forwarding | Selects load data or ALU result as forwarded value |
| `alu_result_out` | WB stage + forwarding | Non-load forwarding value |
| `load_data_out` | WB stage + forwarding | Load forwarding value |
| `valid_out` | Hazard unit | Marks live vs. bubble instruction |

> [!IMPORTANT]
> **Forwarding from MEM/WB**: The M5 forwarding unit uses `mem_wb_reg.reg_write_out`, `mem_wb_reg.rd_out`, and the selected WB data (`wb_from_mem_out ? load_data_out : alu_result_out`) as `forward_wb_data` into `ex_stage`.

> [!NOTE]
> The `mem_wb_reg.en` and `flush` inputs are driven by the M5 hazard/stall unit. The hold and flush policy mirrors `ex_mem_reg`: coordinate carefully to avoid re-executing stores or discarding in-flight instructions.

---

## 8. Running the Testbenches

```bash
# MEM stage testbench (requires data_mem.v)
iverilog -g2012 -o simulation/tb_mem_stage.vvp \
    testbench/tb_mem_stage.v \
    rtl/stages/mem_stage.v \
    rtl/stages/data_mem.v
vvp simulation/tb_mem_stage.vvp

# MEM/WB pipeline register testbench
iverilog -g2012 -o simulation/tb_mem_wb_reg.vvp \
    testbench/tb_mem_wb_reg.v \
    rtl/pipeline_registers/mem_wb_reg.v
vvp simulation/tb_mem_wb_reg.vvp
```

Expected output:
```
PASS: tb_mem_stage (N checks)
PASS: all N MEM/WB pipeline register tests completed successfully
```
