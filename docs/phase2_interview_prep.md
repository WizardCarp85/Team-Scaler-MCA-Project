# Phase II Comprehensive Viva & Technical Interview Preparation Guide

**Project:** 5-Stage Pipelined RISC-V (RV32I) Processor in Verilog HDL  
**Course:** Modern Computer Architecture (MCA)  
**Team:** Team Scaler (`WizardCarp85`, `ABHIGYA0205`, `somraj112`, `Rudra-choudhary`, `sakshaaamm`)  
**Repository:** [WizardCarp85/Team-Scaler-MCA-Project](https://github.com/WizardCarp85/Team-Scaler-MCA-Project)  

---

## 1. Overall Five-Stage Processor Architecture & Pipeline Registers

### 1.1 The Five Pipeline Stages
The processor partitions instruction execution into five balanced stages:
1. **IF (Instruction Fetch):** Maintains the 32-bit Program Counter (`pc.v`) and fetches instruction words from instruction memory (`instr_mem.v`). In sequential execution, it calculates $\text{PC} + 4$. Under taken branches, it accepts `branch_target` from the EX stage.
2. **ID (Instruction Decode):** Decodes opcodes, register indices (`rd`, `rs1`, `rs2`), and generates sign-extended immediates (`instruction_decoder.v`). Reads source operands from the 32 general-purpose 32-bit register file (`register_file.v`). Generates control signals for ALU, memory, and write-back (`main_control.v`).
3. **EX (Execute):** Evaluates arithmetic/logical operations (`alu.v`, `alu_control.v`), evaluates branch conditions and computes branch target addresses (`branch_unit.v`). Integrates 3-to-1 operand forwarding multiplexers (`ex_stage.v`).
4. **MEM (Memory Access):** Interfaces with 1 KiB word-aligned data memory (`data_mem.v`, `mem_stage.v`). Performs synchronous memory writes for `SW` and asynchronous reads for `LW`.
5. **WB (Write-Back):** Selects between the ALU result and memory read data via a 2-to-1 multiplexer (`wb_stage.v`) and commits data into the destination register (`rd`) on the rising clock edge.

### 1.2 Pipeline Registers & Precedence Rule
Four synchronous pipeline registers separate the stages:
- `if_id_reg.v` (IF $\to$ ID): Captures `pc`, `pc_plus4`, `instr`, `valid`.
- `id_ex_reg.v` (ID $\to$ EX): Captures decoded operands, immediate, control signals, `rd`, `rs1`, `rs2`, `valid`.
- `ex_mem_reg.v` (EX $\to$ MEM): Captures `alu_result`, `store_data`, `rd`, memory controls, `valid`.
- `mem_wb_reg.v` (MEM $\to$ WB): Captures memory read data, `alu_result`, `rd`, write-back controls, `valid`.

**Control Priority in All Pipeline Registers:**
$$\text{Reset} \; (rst) > \text{Flush} \; (flush) > \text{Hold / Enable} \; (!en) > \text{Normal Capture}$$
- `rst` (highest): Synchronously clears all registers and invalidates entries (`valid = 0`).
- `flush`: Clears instruction and control signals, forcing `valid = 0` (injects a bubble).
- `!en` (stall hold): Freezes current register contents; prevents new data from entering.
- Normal capture: Clock edge captures inputs and advances instructions.

---

## 2. Hazard Mitigation Mechanisms: Forwarding, Stalls, and Flushes

### 2.1 Read-After-Write (RAW) Data Hazards & Operand Forwarding
- **The Problem:** An instruction in EX needs a register value computed by an earlier instruction currently in MEM or WB that has not yet committed to the register file.
- **The Solution:** The Forwarding Unit (`forwarding_unit.v`) monitors source registers in EX (`rs1_ex`, `rs2_ex`) against destination registers in \texttt{EX/MEM} (`rd_mem`) and \texttt{MEM/WB} (`rd_wb`).
- **Multiplexer Controls:**
  - `2'b00`: No forwarding (use operand decoded from ID stage).
  - `2'b10`: Forward from `EX/MEM` boundary register (youngest producer priority).
  - `2'b01`: Forward from `MEM/WB` boundary register.
- **Safety Invariants:**
  - Forwarding to destination `x0` is strictly suppressed (`rd != 5'd0`).
  - Bubbles / invalid instructions (`valid == 0`) never forward.
  - Instructions that do not write registers (`reg_write == 0`) never forward.

### 2.2 Load-Use Hazards & Single-Cycle Interlock Stalls
- **The Problem:** When an instruction consumes a register loaded by an immediately preceding `LW`, the loaded data is only available at the end of the MEM stage. Forwarding to the EX stage in the very next cycle is physically impossible (data is not yet read from memory).
- **Detection Condition:**
  $$\text{mem\_read\_ex} \quad \land \quad (\text{rd\_ex} \neq 0) \quad \land \quad (\text{rd\_ex} == \text{rs1\_id} \lor \text{rd\_ex} == \text{rs2\_id})$$
- **Action Taken (Single-Cycle Interlock):**
  1. Program Counter (`pc.v`) is held: `pc <= pc` (repeats fetch of younger instruction).
  2. `if_id_reg` is held: `en = 0` (preserves consumer instruction in ID).
  3. `id_ex_reg` is cleared: `flush = 1` (injects a NOP bubble into EX stage).
- In the subsequent cycle, the loaded data reaches `MEM/WB`, from which it is forwarded directly into the EX stage (`forward = 2'b01`), incurring exactly **1 stall cycle**.

### 2.3 Control Hazards: Branch Evaluation & Dual-Stage Flush
- **The Policy:** Fixed static predict-not-taken.
- **Branch Resolution:** Evaluated in the EX stage (`branch_unit.v`) by comparing operands and adding immediate offset to PC.
- **When Taken:**
  1. `next_pc` is redirected to the computed target address.
  2. `if_id_reg` is flushed (`if_id_flush = 1`), squashing the speculatively fetched fall-through instruction.
  3. `id_ex_reg` is flushed (`id_ex_flush = 1`), squashing the second speculatively fetched instruction.
- **Side-Effect Suppression:** The flushed instructions have `valid = 0`, forcing all memory write and register write signals to zero. They traverse MEM and WB as harmless bubbles and produce zero architectural side effects.
- **Priority Resolution:** Branch redirection strictly overrides load-use stall requests.

---

## 3. Benchmark Suite & Verification Methodology

### 3.1 The Three Benchmark Programs
1. **Benchmark 1: Accumulator Loop ([`programs/benchmark_accumulate.hex`](../programs/benchmark_accumulate.hex))**
   - 13 instruction words, computes $\sum_{i=1}^5 i = 15$ and $100 - \sum i = 85$.
   - Tight RAW loop dependencies, 4 taken backward branches, 1 fall-through branch, 1 forward branch over squashed trap.
2. **Benchmark 2: Array Allocation & Memory Access ([`programs/benchmark_load_store.hex`](../programs/benchmark_load_store.hex))**
   - 22 instruction words, allocates 3-element array in data memory.
   - 5 stores (`SW`), 4 loads (`LW`), 3 distinct load-use hazards (each causing exactly 1 stall cycle), store-to-load ordering, forward branch over squashed trap.
3. **Benchmark 3: Control Hazards & Dual Forwarding ([`programs/benchmark_control_hazards.hex`](../programs/benchmark_control_hazards.hex))**
   - 24 instruction words, tests both taken and not-taken BEQ and BNE instructions.
   - Dual RAW forwarding (Operand A from MEM/WB and Operand B from EX/MEM simultaneously), back-to-back immediate SW-to-LW at same address, 7 squashed wrong-path trap instructions.

### 3.2 Completion Detection & Timeout Safety
- **Completion Marker:** Workloads terminate with an explicit halt self-loop: `beq x0, x0, 0` at their final address.
- **Completion Detection:** Monitored via the Write-Back interface:
  $$\text{debug\_wb\_retired} == 1 \quad \land \quad \text{debug\_wb\_pc} == \text{HALT\_PC}$$
- **Timeout Protection:** Every testbench enforces a 500-cycle bounded timeout using `$fatal` to immediately flag infinite loops or pipeline hangs.

---

## 4. CPI / IPC Definitions & Measurement Methodology

### 4.1 Measurement Window Definitions
To prevent counting arbitrary loop cycles after completion, metrics are measured under two standard conventions:
- **Convention A (Pure Workload Window — Recommended):**
  - **Start:** Clock cycle immediately following reset deassertion (`!rst`).
  - **End:** Clock cycle where the final algorithmic instruction retires at Write-Back (`debug_wb_retired && debug_wb_pc == LAST_WORKLOAD_PC`).
  - **Instructions:** Only true workload instructions. The halt marker is **excluded**.
- **Convention B (Completion-Inclusive Window):**
  - **Start:** Clock cycle immediately following reset deassertion (`!rst`).
  - **End:** Clock cycle where the halt self-loop (`beq x0, x0, 0`) first retires at Write-Back.
  - **Instructions:** Workload instructions $+ 1$ (the single halt instruction retirement).
  - Excludes subsequent infinite looping cycles.

### 4.2 Measured Results Summary
$$\text{CPI} = \frac{\text{Measured Clock Cycles}}{\text{Measured Retired Instructions}}, \quad \text{IPC} = \frac{\text{Measured Retired Instructions}}{\text{Measured Clock Cycles}}$$

- **Benchmark 1 (Loop):**
  - Convention A: 27 instructions, 39 cycles $\implies \mathbf{\text{CPI} = 1.4444}, \mathbf{\text{IPC} = 0.6923}$
  - Convention B: 28 instructions, 42 cycles $\implies \mathbf{\text{CPI} = 1.5000}, \mathbf{\text{IPC} = 0.6667}$
- **Benchmark 2 (Memory):**
  - Convention A: 20 instructions, 27 cycles $\implies \mathbf{\text{CPI} = 1.3500}, \mathbf{\text{IPC} = 0.7407}$
  - Convention B: 21 instructions, 30 cycles $\implies \mathbf{\text{CPI} = 1.4286}, \mathbf{\text{IPC} = 0.7000}$
- **Benchmark 3 (Control):**
  - Convention A: 16 instructions, 25 cycles $\implies \mathbf{\text{CPI} = 1.5625}, \mathbf{\text{IPC} = 0.6400}$
  - Convention B: 17 instructions, 28 cycles $\implies \mathbf{\text{CPI} = 1.6471}, \mathbf{\text{IPC} = 0.6071}$

---

## 5. Single-Cycle Baseline Comparison

### 5.1 The Verilog Single-Cycle Reference Model
- Implemented in [`rtl/reference/single_cycle_cpu.v`](../rtl/reference/single_cycle_cpu.v).
- Executes the identical 7-instruction subset.
- In every clock cycle, exactly one instruction is fetched, decoded, executed, accessed in memory, and written back:
  $$\text{CPI}_{\text{single}} = 1.000, \quad \text{IPC}_{\text{single}} = 1.000$$

### 5.2 Architectural State Comparison & Cycle Metrics
Verified via [`testbench/tb_single_cycle_comparison.v`](../testbench/tb_single_cycle_comparison.v):
- **State Check:** Compared architectural state (registers x1–x7 for B1; registers x1–x12 and data memory words 16–20 for B2; registers x1–x17 and data memory word 0 for B3) matched bit-for-bit for these benchmark runs.
- **Cycle Counts (Workload Window):**
  - Benchmark 1: Single-cycle = 27 cycles (CPI 1.0) vs. Pipelined = 39 cycles (CPI 1.4444).
  - Benchmark 2: Single-cycle = 20 cycles (CPI 1.0) vs. Pipelined = 27 cycles (CPI 1.3500).
  - Benchmark 3: Single-cycle = 16 cycles (CPI 1.0) vs. Pipelined = 25 cycles (CPI 1.5625).

### 5.3 Cycle Count vs. Real-Time Execution Dynamics
- **Why does the single-cycle processor take fewer cycles?** Because it has no pipeline fill/drain latency (4 cycles), no branch flush penalties (2 cycles per taken branch), and no load-use stalls (1 cycle per hazard).
- **How does pipelining achieve higher throughput in physical hardware?**
  - Single-cycle clock period: $T_{\text{single}} = T_{\text{IF}} + T_{\text{ID}} + T_{\text{EX}} + T_{\text{MEM}} + T_{\text{WB}}$ (must accommodate the cumulative delay of all 5 stages in one clock edge).
  - Pipelined clock period: $T_{\text{pipe}} = \max(T_{\text{stage}}) + T_{\text{reg}} + T_{\text{setup}}$ (accommodates only the slowest individual stage).
  - Architectural potential: Shorter stage critical paths provide the architectural objective for a higher operating frequency ($f_{\text{pipe}} > f_{\text{single}}$). Because $T_{\text{exec}} = \frac{\text{Instructions} \times \text{CPI}}{f}$, physical execution speedup is achieved only if the clock frequency ratio exceeds the CPI penalty. Because static timing analysis on hardware was not executed for both implementations, real-time speedup is not claimed; the comparison demonstrates architectural cycle and instruction dynamics under identical workload conditions.

---

## 6. Synthesis & FPGA Status

- **Status:** FPGA synthesis and static timing analysis are pending local EDA tool installation (Xilinx Vivado / Yosys).
- **Scripts Provided:**
  - Non-project batch script: [`synthesis/synth_vivado.tcl`](../synthesis/synth_vivado.tcl) targeting Xilinx Artix-7 (`xc7a35tcpg236-1`, Basys 3).
  - Open-source generic script: [`synthesis/synth_yosys.ys`](../synthesis/synth_yosys.ys).
  - Timing constraints: [`synthesis/constraints.xdc`](../synthesis/constraints.xdc) ($100\,\text{MHz}$ clock).
- **Academic Rigor:** We do not fabricate LUT, FF, BRAM, or $F_{\max}$ values. The $100\,\text{MHz}$ testbench clock is a simulation parameter, not verified post-fit FPGA timing closure.

---

## 7. Individual Viva Questions by Member Milestone

*(Note: Milestone assignments reflect repository records and are flagged for team confirmation.)*

### Member 1: Yashkumar Nimje (`WizardCarp85`) — M5: Hazard Detection & Top-Level Integration
1. **Q:** *How does your load-use hazard detection unit distinguish a load-use dependency from a normal ALU dependency?*  
   **A:** A normal ALU dependency has `mem_read_ex == 0`, which can be resolved in the EX stage using operand forwarding without stalling. A load-use hazard has `mem_read_ex == 1` and `rd_ex != 0` matching `rs1_id` or `rs2_id`. Because data is only read in the MEM stage, forwarding into EX in the next cycle is impossible, requiring a 1-cycle stall.
2. **Q:** *What happens if a taken branch in EX coincides with a load-use stall request from ID?*  
   **A:** In `branch_controller.v`, branch redirection strictly overrides the stall. The branch flushes both IF and ID, which squashes the instruction requesting the stall. Stalling an instruction that is about to be discarded would be an error.
3. **Q:** *Why does the forwarding unit prioritize `EX/MEM` over `MEM/WB`?*  
   **A:** If both instructions write to the same destination register, the instruction in `EX/MEM` is chronologically younger than the instruction in `MEM/WB`. In sequential programming, the consumer must receive the most recently computed value.

### Member 2: Abhigya Sachdeva (`ABHIGYA0205`) — M3: Execution Stage & Verification
1. **Q:** *Explain how your `ex_stage.v` integrates forwarding multiplexers with immediate operand selection.*  
   **A:** Operand A is selected by the 3-to-1 `forward_a` mux between `rs1_data`, `ex_mem_alu_result`, and `mem_wb_write_data`. For Operand B, the 3-to-1 `forward_b` mux first selects between `rs2_data`, `ex_mem_alu_result`, and `mem_wb_write_data` to produce `forwarded_rs2`. Then, a 2-to-1 immediate mux selects between `forwarded_rs2` and `imm` based on `alu_src_imm`. This ensures `forwarded_rs2` is independently available for store data (`SW`) and branch comparison!
2. **Q:** *How did you measure CPI/IPC and prove that completion self-loops did not skew the results?*  
   **A:** We created two distinct measurement windows in `tb_performance_cpi_ipc.v`. Convention A captures metrics exactly when the last algorithmic workload instruction retires, completely excluding the completion self-loop. Convention B measures through the first retirement of the halt marker.
3. **Q:** *How did you prove that register `x0` is never corrupted during pipeline execution?*  
   **A:** In the testbenches, we assert two invariants: 1) whenever an instruction retires at WB, `debug_wb_reg_write` is never asserted if `debug_wb_rd == 5'd0`; 2) during the ID stage, read ports return zero whenever `rs1 == 0` or `rs2 == 0`. Full write-rejection is verified in `tb_register_file.v`.

### Member 3: Somraj Nandi (`somraj112`) — M2: Instruction Decode & Register File
1. **Q:** *Why is write-to-read bypass needed inside the register file (`register_file.v`)?*  
   **A:** Without bypass, if an instruction writes to register $R$ in the WB stage while another instruction reads register $R$ in the ID stage during the same cycle, the ID stage would read stale data. The bypass logic forwards `write_data` combinationally if `rd == rs1` or `rd == rs2` and `writing` is active.
2. **Q:** *How does the decoder distinguish between `ADD`, `SUB`, `ADDI`, and branches?*  
   **A:** By inspecting `opcode[6:0]`: `0110011` for R-type (`ADD`/`SUB`, differentiated by `funct7[5]`), `0010011` for I-type arithmetic (`ADDI`, `funct3=000`), `0000011` for loads (`LW`), `0100011` for stores (`SW`), and `1100011` for branches (`BEQ` with `funct3=000`, `BNE` with `funct3=001`).
3. **Q:** *How does `id_ex_reg.v` handle synchronous bubble insertion?*  
   **A:** When `flush` is asserted or `valid_in == 0`, the register synchronously clears all control signals (`reg_write`, `mem_read`, `mem_write`, `branch`) and sets `valid_out = 0`.

### Member 4: Rudra Pratap Singh Choudhary (`Rudra-choudhary`) — M4: Memory & Write-Back
1. **Q:** *Explain the timing of memory writes versus memory reads in `data_mem.v`.*  
   **A:** Memory writes (`SW`) commit synchronously on the rising clock edge when `mem_write` is asserted. Memory reads (`LW`) are combinational/asynchronous, allowing the loaded word to be available at the end of the MEM cycle so it can be registered into `mem_wb_reg`.
2. **Q:** *What is the role of `mem_wb_reg.v` and how does it prevent spurious writes on bubbles?*  
   **A:** It registers the memory output, ALU result, and write-back controls across the clock boundary. If `valid_in == 0` or `flush == 1`, it forces `reg_write_out = 0` and `valid_out = 0`, guaranteeing that flushed instructions never commit data.
3. **Q:** *How does `wb_stage.v` select its output data?*  
   **A:** It uses a 2-to-1 multiplexer controlled by `mem_to_reg`: when `mem_to_reg == 1` (for `LW`), it routes `mem_read_data`; otherwise, it routes `alu_result`.

### Member 5: Saksham Narotra (`sakshaaamm`) — M1: Instruction Fetch
1. **Q:** *How does `pc.v` support stall hold without an explicit enable input?*  
   **A:** A stall is implemented externally by feeding the current `pc` back into `next_pc` via a multiplexer controlled by the hazard detection unit: `next_pc = (stall) ? pc : (pc + 4)`.
2. **Q:** *How does `if_stage.v` initialize instruction memory?*  
   **A:** It loads a hexadecimal machine code file at simulation startup using `$readmemh`. All uninitialized memory words are automatically initialized to RISC-V NOP (`32'h0000_0013`), preventing unknown (`X`) values from entering the pipeline.
3. **Q:** *What happens in `if_id_reg.v` when a branch flush occurs?*  
   **A:** When `flush == 1`, the register synchronously resets `valid_out <= 0`, `instr_out <= NOP`, and `pc_out <= 0`, discarding the instruction currently in the fetch register.
