# Load/Store & Write-Back Integration Verification Specification

**Verification Suite:** `tb_load_store_wb` (`testbench/tb_load_store_wb.v`)  
**Milestone:** Milestone 4 (M4) — Memory (MEM) Stage & Write-Back (WB) Integration  
**Related Issue:** Issue #21 (Load/Store & Write-Back Verification)

---

## 1. Overview & Verification Objective

This verification suite performs end-to-end integration verification across the memory access and register write-back pipeline stages of the 5-stage RV32I processor. It binds:
1. **Memory Stage (`mem_stage.v`)** with internal word-addressable data memory (`data_mem.v`).
2. **MEM/WB Pipeline Register (`mem_wb_reg.v`)** with synchronous hold, flush, and bubble squash priority.
3. **Write-Back Stage (`wb_stage.v`)** with ALU vs. Load multiplexing and strict side-effect gating.
4. **Register File (`register_file.v`)** with rising-edge storage update and combinational write-through bypass.

```text
  [EX/MEM Inputs]
         │
         ▼
    mem_stage ───────► data_mem (1 KiB storage)
         │
         ▼
    mem_wb_reg (Holds / Flushes / Squashes)
         │
         ▼
     wb_stage (Source Mux & Side-Effect Gating)
         │
         ▼
   register_file (32 x 32-bit Registers, x0=0)
```

---

## 2. Integrated Scenarios Verified

| Scenario | Objective | Verification Method & Expected Outcome |
|---|---|---|
| **1. SW followed by LW** | Store a word to memory and read it back | `SW` commits `0xDEAD_BEEF` to byte address `0x0010`. Subsequent `LW` from `0x0010` loads `0xDEAD_BEEF` and commits to `x5`. |
| **2. Multi-Address Access** | Independent multi-word addressing | Stores distinct values to addresses `0x0020` and `0x0024`. Reads back into registers `x6` and `x7`, ensuring correct word alignment without aliasing. |
| **3. Store Safety** | Verify `SW` never writes a register | An `SW` instruction carrying dummy destination `rd = x8` enters WB; `rf_write_en` remains `0` and `x8` remains `0x0000_0000`. |
| **4. Targeted Register Write** | Ensure LW writes only the targeted `rd` | `LW` writes loaded data into `x5`. Checked that neighboring registers are uncorrupted and write-through bypass provides live value during WB. |
| **5. ALU vs Stale Memory** | Prevent memory data from leaking into ALU results | An ALU operation follows immediately after memory operations with an address pointing to valid memory. Verified that `wb_data` strictly reflects `alu_result` and not stale read data. |
| **6. Bubble & Reset Safety** | Ensure bubbles/reset never cause spurious register writes | Injected invalid bubble (`valid = 0`) with asserted control signals (`reg_write = 1`); verified `rf_write_en` is `0`. Asserted `rst = 1` during active instructions; verified register writes are suppressed. |
| **7. Hardwired Zero (`x0`)** | Destination `x0` remains zero | Targeted `x0` with valid `LW` and `ALU` instructions; verified `wb_write_en` is gated low and `x0` strictly evaluates to `32'd0`. |
| **8. Pipeline Stall & Flush** | Verify `mem_wb_reg` hold and squash | Deasserted `en = 0`; verified in-flight instruction holds across clock cycles. Asserted `flush = 1`; verified bundle is immediately squashed to a bubble. |
| **9. Continuous Streaming** | Maximum throughput pipelined execution | Streamed back-to-back instructions (`SW` $\rightarrow$ `LW` $\rightarrow$ `ALU` $\rightarrow$ `ALU` $\rightarrow$ `LW`) across 5 consecutive clock cycles; verified each instruction commits correctly to its target register. |

---

## 3. Timing and Latency Characteristics

- **Store Latency**: An `SW` instruction writes to `data_mem` on the rising clock edge of the MEM stage. The subsequent cycle passes through MEM/WB with `reg_write = 0`.
- **Load Latency**:
  - In the MEM stage, `data_mem` provides combinational read data (`load_data`).
  - At the rising clock edge, `load_data` is latched into `mem_wb_reg`.
  - In the WB stage, `wb_stage` asserts `wb_write_en` and presents `wb_data`.
  - Same-cycle bypass: `register_file` provides combinational write-through bypass if the decode stage reads `rs == wb_rd`.
  - Storage commit: On the next rising clock edge, `register_file` updates internal storage for register `rd`.

---

## 4. Running the Verification Suite

Run from repository root:

```bash
iverilog -g2012 -o simulation/tb_load_store_wb.vvp \
    testbench/tb_load_store_wb.v \
    rtl/stages/mem_stage.v \
    rtl/stages/data_mem.v \
    rtl/pipeline_registers/mem_wb_reg.v \
    rtl/stages/wb_stage.v \
    rtl/stages/register_file.v

vvp simulation/tb_load_store_wb.vvp
```

### Waveform Inspection
Waveform output is dumped to `simulation/tb_load_store_wb.vcd`:
```bash
gtkwave simulation/tb_load_store_wb.vcd
```
