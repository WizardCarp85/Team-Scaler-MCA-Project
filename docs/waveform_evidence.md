# Full-CPU Waveform Verification & Timing Evidence

**Project:** Team Scaler MCA Project — 5-Stage Pipelined RISC-V (RV32I) Processor  
**Issue:** #27 — End-to-End Verification & CPI/IPC Analysis  
**Simulator:** Icarus Verilog (`iverilog` / `vvp`)  
**Waveform Viewer:** GTKWave  

---

## 1. Overview

This document presents reproducible waveform timing evidence from full-CPU simulations of the integrated 5-stage pipelined processor. All signal transitions, timing offsets, and cycle boundaries documented below were verified directly from the generated Value Change Dump (`.vcd`) simulation traces (`simulation/tb_benchmark_load_store.vcd` and `simulation/tb_benchmark_accumulate.vcd`).

> [!IMPORTANT]
> **Waveform Evidence & Toolchain Status Distinction:**
> - **Cycle-Accurate VCD Trace Evidence (Verified & Complete):** All signal transitions, timing offsets, and cycle boundaries documented below were extracted and verified directly from the simulation Value Change Dump (`.vcd`) traces (`simulation/tb_benchmark_load_store.vcd` and `simulation/tb_benchmark_accumulate.vcd`) generated via Icarus Verilog (`iverilog` / `vvp`).
> - **GTKWave GUI Rendered Screenshots (Pending Toolchain Execution):** GTKWave is not installed in this headless execution environment. Therefore, GUI-rendered screenshot image captures are explicitly marked as **pending** manual execution on a workstation with a graphical display and GTKWave installed. The full reproduction and viewing procedure is documented in [Section 4](#4-how-to-inspect-and-capture-screenshots-in-gtkwave-on-macos).

---

## 2. Waveform Case 1: Load-Use Hazard Stall & Data Forwarding

### 2.1 Context and Program Location
- **Workload:** Benchmark 2 ([`programs/benchmark_load_store.hex`](../programs/benchmark_load_store.hex))
- **Testbench:** [`testbench/tb_benchmark_load_store.v`](../testbench/tb_benchmark_load_store.v)
- **VCD Output:** `simulation/tb_benchmark_load_store.vcd`
- **Simulation Command:**
  ```bash
  mkdir -p simulation && \
  iverilog -g2012 -I rtl -I rtl/stages -I rtl/pipeline_registers \
      -o simulation/tb_benchmark_load_store.vvp \
      rtl/cpu.v rtl/stages/*.v rtl/pipeline_registers/*.v \
      testbench/tb_benchmark_load_store.v && \
  vvp simulation/tb_benchmark_load_store.vvp
  ```

### 2.2 Instructions Involved
- **Instruction 1 (Producer):** PC `0x00000028` — `lw x5, 0(x2)` (Loads word from memory address in `x2` into destination `x5`).
- **Instruction 2 (Consumer):** PC `0x0000002C` — `add x6, x5, x4` (Consumes loaded operand `x5` immediately).

### 2.3 Verified VCD Signals
All signals below are verified present in `simulation/tb_benchmark_load_store.vcd`:
- `tb_benchmark_load_store.clk`
- `tb_benchmark_load_store.rst`
- `tb_benchmark_load_store.debug_if_pc[31:0]`
- `tb_benchmark_load_store.debug_id_pc[31:0]`
- `tb_benchmark_load_store.debug_id_valid`
- `tb_benchmark_load_store.debug_ex_pc[31:0]`
- `tb_benchmark_load_store.debug_ex_valid`
- `tb_benchmark_load_store.debug_mem_pc[31:0]`
- `tb_benchmark_load_store.debug_wb_pc[31:0]`
- `tb_benchmark_load_store.debug_wb_retired`
- `tb_benchmark_load_store.debug_stall`
- `tb_benchmark_load_store.debug_forward_a[1:0]`
- `tb_benchmark_load_store.debug_wb_data[31:0]`

### 2.4 Detailed Timing and Cycle-by-Cycle Progression
```
Reset Sequence:
  - Reset asserted from 0 ns to 25 ns.
  - Deasserted at 26 ns (1 ns after the 25 ns clock edge).
  - Cycle 1 begins at the 35 ns clock edge.

Cycle 11 (135 ns - 145 ns):
  - IF: Fetches instruction at 0x0000002C (ADD).
  - ID: Decodes 0x00000028 (LW x5, 0(x2)).
  - EX: Previous store instruction at 0x00000024.

Cycle 12 (145 ns - 155 ns) — STALL CYCLE ASSERTED:
  - EX: debug_ex_pc = 32'h0000_0028 (LW in EX, mem_read=1, rd=5).
  - ID: debug_id_pc = 32'h0000_002C (ADD in ID, uses_rs1=1, rs1=5).
  - Hazard Detection: Detects mem_read_ex && (rd_ex == rs1_id) (5 == 5).
  - debug_stall asserts HIGH (1'b1) throughout 145 ns - 155 ns.
  - Action taken on rising clock edge at 155 ns:
    1. PC register holds current value (0x00000030).
    2. IF/ID pipeline register holds current instruction (0x0000002C, ADD).
    3. ID/EX pipeline register is synchronously cleared (valid_out <= 0, bubble injected into EX).

Cycle 13 (155 ns - 165 ns) — BUBBLE IN EX, MEMORY READ:
  - EX: debug_ex_valid = 0 (Bubble occupying EX stage; control signals zeroed).
  - ID: debug_id_pc = 32'h0000_002C (ADD held in ID stage).
  - MEM: debug_mem_pc = 32'h0000_0028 (LW performs data memory read; returns data = 25).
  - debug_stall deasserts (1'b0).

Cycle 14 (165 ns - 175 ns) — FORWARDING FROM MEM/WB TO EX:
  - EX: debug_ex_pc = 32'h0000_002C (ADD enters EX stage).
  - WB: debug_wb_pc = 32'h0000_0028 (LW in WB, debug_wb_rd = 5, debug_wb_data = 25, debug_wb_reg_write = 1).
  - Forwarding Unit: Detects reg_write_wb && (rd_wb == rs1_ex) (5 == 5).
  - debug_forward_a asserts 2'b01 (FWD_MEM_WB).
  - ALU Operand A receives forwarded load data (25) directly from MEM/WB.
  - Result: alu_result = 25 + 10 = 35 computed correctly with exactly 1 stall cycle.
```

---

## 3. Waveform Case 2: Taken Branch & Dual-Stage Pipeline Flush

### 3.1 Context and Program Location
- **Workload:** Benchmark 1 ([`programs/benchmark_accumulate.hex`](../programs/benchmark_accumulate.hex))
- **Testbench:** [`testbench/tb_benchmark_accumulate.v`](../testbench/tb_benchmark_accumulate.v)
- **VCD Output:** `simulation/tb_benchmark_accumulate.vcd`
- **Simulation Command:**
  ```bash
  mkdir -p simulation && \
  iverilog -g2012 -I rtl -I rtl/stages -I rtl/pipeline_registers \
      -o simulation/tb_benchmark_accumulate.vvp \
      rtl/cpu.v rtl/stages/*.v rtl/pipeline_registers/*.v \
      testbench/tb_benchmark_accumulate.v && \
  vvp simulation/tb_benchmark_accumulate.vvp
  ```

### 3.2 Instructions Involved
- **Branch Instruction:** PC `0x0000001C` — `bne x1, x2, -12` (Loop branch back to `0x00000010` while $i \neq 5$).
- **Wrong-Path Speculative Fetches:**
  - PC `0x00000020` — `addi x5, x3, 0` (In ID stage when branch resolves in EX).
  - PC `0x00000024` — `addi x6, x4, 0` (In IF stage when branch resolves in EX).
- **Branch Target:** PC `0x00000010` — `addi x1, x1, 1`.

### 3.3 Verified VCD Signals
All signals below are verified present in `simulation/tb_benchmark_accumulate.vcd`:
- `tb_benchmark_accumulate.clk`
- `tb_benchmark_accumulate.rst`
- `tb_benchmark_accumulate.debug_if_pc[31:0]`
- `tb_benchmark_accumulate.debug_id_pc[31:0]`
- `tb_benchmark_accumulate.debug_id_valid`
- `tb_benchmark_accumulate.debug_ex_pc[31:0]`
- `tb_benchmark_accumulate.debug_ex_valid`
- `tb_benchmark_accumulate.debug_branch_taken`
- `tb_benchmark_accumulate.debug_branch_target[31:0]`
- `tb_benchmark_accumulate.debug_flush`
- `tb_benchmark_accumulate.debug_wb_retired`
- `tb_benchmark_accumulate.debug_wb_pc[31:0]`

### 3.4 Detailed Timing and Cycle-by-Cycle Progression
```
Reset Sequence:
  - Reset asserted from 0 ns to 25 ns.
  - Deasserted at 26 ns (1 ns after the 25 ns clock edge).
  - Cycle 1 begins at the 35 ns clock edge.

Cycle 08 (105 ns - 115 ns):
  - IF: Fetches speculative fall-through instruction at 0x00000020.
  - ID: Decodes BNE instruction at 0x0000001C.

Cycle 09 (115 ns - 125 ns) — BRANCH RESOLUTION & FLUSH ASSERTION:
  - EX: debug_ex_pc = 32'h0000_001C (BNE evaluates in EX stage).
    - Source registers: x1 = 1, x2 = 5.
    - Comparator: x1 != x2 evaluates TRUE (branch_taken = 1).
    - Target: 0x0000001C + (-12) = 32'h0000_0010.
    - debug_branch_taken asserts HIGH (1'b1).
    - debug_branch_target evaluates to 32'h0000_0010.
    - debug_flush asserts HIGH (1'b1) throughout 115 ns - 125 ns.
  - ID: Contains wrong-path instruction 0x00000020 (addi x5, x3, 0).
  - IF: Fetches wrong-path instruction 0x00000024 (addi x6, x4, 0).
  - Action taken on rising clock edge at 125 ns:
    1. PC register is redirected to target 32'h0000_0010.
    2. ID/EX pipeline register is flushed (valid_out <= 0), squashing 0x00000020 (which was in ID stage).
    3. IF/ID pipeline register is flushed (valid_out <= 0), squashing 0x00000024 (which was being fetched in IF stage).

Cycle 10 (125 ns - 135 ns) — TARGET FETCH & SQUASHED BUBBLE RECOVERY:
  - IF: Fetches target instruction at debug_if_pc = 32'h0000_0010.
  - ID: Flushed bubble (debug_id_valid = 0).
  - EX: Flushed bubble (debug_ex_valid = 0).
  - debug_flush deasserts (1'b0).
  - MEM: BNE instruction moves to MEM (debug_mem_pc = 32'h0000_001C).

Cycle 11 (135 ns - 145 ns):
  - IF: Sequential fetch at 0x00000014.
  - ID: Decodes target instruction 0x00000010.
  - WB: BNE instruction retires at WB (debug_wb_retired = 1, debug_wb_pc = 32'h0000_001C, reg_write = 0).
  - Result: The wrong-path instructions (0x20 and 0x24) were squashed in ID/EX and IF/ID, never reached WB, and produced zero architectural side effects.
```

---

## 4. How to Inspect and Capture Screenshots in GTKWave on macOS

To view these waveforms and capture screenshots for the final submission report:

1. **Install GTKWave (if not already installed):**
   ```bash
   brew install --cask gtkwave
   ```
   *(Or download the official macOS app bundle from [gtkwave.sourceforge.net](http://gtkwave.sourceforge.net/)).*

2. **Launch GTKWave with the generated VCD file:**
   ```bash
   gtkwave simulation/tb_benchmark_load_store.vcd
   ```
   *(Or for the branch test: `gtkwave simulation/tb_benchmark_accumulate.vcd`).*

3. **Add Signals to the Display Window:**
   - In the left **SST (Search/Signal Tree)** pane, expand the top testbench module (`tb_benchmark_load_store`).
   - Select and drag the following key signals into the **Waves** pane:
     - `clk`
     - `debug_stall`
     - `debug_flush`
     - `debug_if_pc[31:0]`
     - `debug_id_pc[31:0]`
     - `debug_ex_pc[31:0]`
     - `debug_mem_pc[31:0]`
     - `debug_wb_pc[31:0]`
     - `debug_forward_a[1:0]`
     - `debug_forward_b[1:0]`
     - `debug_wb_retired`
     - `debug_wb_data[31:0]`

4. **Adjust Display Format & Zoom:**
   - Right-click multi-bit PC signals (`debug_if_pc`, `debug_id_pc`, etc.) and choose **Data Format $\to$ Hexadecimal**.
   - Right-click `debug_forward_a` and choose **Data Format $\to$ Binary**.
   - Click **Zoom Fit** (`Ctrl + Alt + F` or menu **Time $\to$ Zoom Fit**) to view the full execution.
   - Click and drag around time `115ns` to `145ns` to zoom in on the load-use stall.

5. **Capture Screenshot on macOS:**
   - Press `Cmd + Shift + 4` and select the GTKWave window region showing the stall or flush event.
   - Save the image to `reports/figures/waveform_load_use_stall.png` or `reports/figures/waveform_branch_flush.png`.
