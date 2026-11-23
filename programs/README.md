# Instruction Images & Benchmark Suite

This directory contains RV32I-subset machine-code hex images loaded by the instruction memory module (`rtl/stages/instr_mem.v`) using `$readmemh`.

---

## 1. File Format (`$readmemh`)

- **Format**: Plain ASCII text, exactly one 32-bit instruction word per line represented as 8 hexadecimal digits (no `0x` prefix).
- **Addressing**: Line $N$ (counting 0-indexed instruction lines) represents the word at byte address $4 \times N$:
  - Line 0 = Byte address `0x00000000`
  - Line 1 = Byte address `0x00000004`
  - Line 2 = Byte address `0x00000008`
  - Line $N$ = Byte address $4 \times N$
- **Comments**: Standard Verilog line comments (`//`) are supported by `$readmemh` and used throughout to annotate addresses, instructions, and hazard descriptions.
- **Unspecified Words**: Words in memory up to `DEPTH_WORDS` (default 256 words = 1 KiB) that are not covered by the hex file automatically initialize to RISC-V NOP (`32'h0000_0013` = `addi x0, x0, 0`), ensuring no unknown (`X`) values enter the pipeline.
- **Loading**: Pass the image path via the `IMEM_INIT_FILE` parameter of `cpu.v` (or `INIT_FILE` of `instr_mem.v`). In Icarus Verilog (`iverilog`/`vvp`), file paths are resolved relative to the directory where `vvp` is executed (the repository root).

---

## 2. Benchmark Programs Summary

| Program | File | Instructions | Primary Purpose & Hazards Exercised | Completion Convention |
|---|---|---|---|---|
| **Fetch Test Data** | [`if_test.hex`](if_test.hex) | 8 | IF-only fetch & decoding verification across supported RV32I instruction formats (not a CPU benchmark). | Sequential end-of-file |
| **Benchmark 1** | [`benchmark_accumulate.hex`](benchmark_accumulate.hex) | 13 | Arithmetic accumulator loop computing $\sum_{i=1}^5 i = 15$ and $100 - \sum i = 85$. Exercises tight RAW forwarding (EX $\to$ EX, MEM $\to$ EX), 4 taken backward loop branches, 1 not-taken exit branch, forward branch over squashed trap, and self-loop halt. | Halt self-loop (`beq x0, x0, 0`) at PC `0x30` retiring at WB |
| **Benchmark 2** | [`benchmark_load_store.hex`](benchmark_load_store.hex) | 22 | Array allocation and memory sequence. Exercises base-pointer arithmetic, multiple stores (`sw`), loads (`lw`), 3 separate load-use interlock stalls, MEM/WB forwarding, store-to-load data integrity, forward branch over squashed trap, and self-loop halt. | Halt self-loop (`beq x0, x0, 0`) at PC `0x54` retiring at WB |
| **Benchmark 3** | [`benchmark_control_hazards.hex`](benchmark_control_hazards.hex) | 24 | Control hazards & dual forwarding sequence. Exercises conditional BEQ/BNE not-taken fall-throughs, taken branch flushes over 5 squashed trap instructions and 2 unfetched traps (7 traps total with zero side effects), immediate back-to-back SW-to-LW, 1-cycle load-use stall, simultaneous dual RAW forwarding to both operands, and self-loop halt. | Halt self-loop (`beq x0, x0, 0`) at PC `0x5C` retiring at WB |

---

## 3. Benchmark 1: Arithmetic & Accumulator Loop (`benchmark_accumulate.hex`)

### 3.1 Overview
Benchmark 1 implements an iterative summation loop and running difference accumulator using exclusively supported RV32I instructions (`ADDI`, `ADD`, `SUB`, `BNE`, `BEQ`).

### 3.2 Assembly Listing & Hex Encodings

| Byte Addr | Hex Code | Instruction | Operands | Description / Hazards Exercised |
|:---:|:---:|---|---|---|
| `0x00` | `00000093` | `addi` | `x1, x0, 0` | Initialize loop counter index $i = 0$ |
| `0x04` | `00500113` | `addi` | `x2, x0, 5` | Initialize loop limit $N = 5$ |
| `0x08` | `00000193` | `addi` | `x3, x0, 0` | Initialize accumulator $\text{sum} = 0$ |
| `0x0C` | `06400213` | `addi` | `x4, x0, 100` | Initialize difference accumulator $\text{diff} = 100$ |
| `0x10` | `00108093` | `addi` | `x1, x1, 1` | **loop:** $i = i + 1$ (RAW dependency on previous iteration) |
| `0x14` | `001181b3` | `add` | `x3, x3, x1` | $\text{sum} = \text{sum} + i$ (EX $\to$ EX forward of `x1`, MEM $\to$ EX forward of `x3`) |
| `0x18` | `40120233` | `sub` | `x4, x4, x1` | $\text{diff} = \text{diff} - i$ (MEM $\to$ EX forward of `x1`, MEM $\to$ EX forward of `x4`) |
| `0x1C` | `fe209ae3` | `bne` | `x1, x2, -12` | If $i \neq 5$, branch back to `0x10`. **Taken 4 times** (flushes wrong-path instructions at `0x20`, `0x24`). **Not taken on 5th iteration** (falls through). |
| `0x20` | `00018293` | `addi` | `x5, x3, 0` | Copy final $\text{sum}$ to `x5` ($x5 = 15$) after loop exit fall-through |
| `0x24` | `00020313` | `addi` | `x6, x4, 0` | Copy final $\text{diff}$ to `x6` ($x6 = 85$) |
| `0x28` | `00000463` | `beq` | `x0, x0, 8` | Forward branch to `0x30` (`done`). Flushes speculative instructions (`0x2C`, `0x30`). |
| `0x2C` | `06300393` | `addi` | `x7, x0, 99` | **TRAP INSTRUCTION:** Must be squashed by branch at `0x28`. `x7` must remain 0. |
| `0x30` | `00000063` | `beq` | `x0, x0, 0` | **done:** Halt self-loop (`0x30 + 0 = 0x30`). Signals completion. |

### 3.3 Control Hazards & Side-Effect Suppression
- **Backwards Loop Branches:** For iterations 1 through 4 ($i = 1, 2, 3, 4$), the `bne` at `0x1C` evaluates as taken in the EX stage, redirecting the IF PC to `0x10` and asserting `flush` to squash speculative fetches at `0x20` and `0x24`.
- **Loop Termination:** On iteration 5 ($i = 5$), the `bne` falls through without flush, executing `0x20` and `0x24` sequentially.
- **Trap Suppression:** The forward branch at `0x28` jumps over `0x2C`. The trap instruction (`addi x7, x0, 99`) enters IF and ID but is squashed in the pipeline when `0x28` resolves in EX. Register `x7` is guaranteed to remain `0`.

### 3.4 Completion Convention & Timeout
- **Halt Mechanism:** Self-loop `beq x0, x0, 0` at address `0x00000030`.
- **Detection Condition:** Testbench monitors the Write-Back interface:
  $$\text{debug\_wb\_retired} == 1 \quad \land \quad \text{debug\_wb\_pc} == 32\text{'h0000\_0030}$$
- **Timeout Protection:** Bounded timeout at 500 clock cycles. If the CPU hangs or loops indefinitely, `$fatal` halts simulation with an error.

### 3.5 Expected Architectural State
- `x1 = 5` (loop counter final value)
- `x2 = 5` (loop limit)
- `x3 = 15` ($\sum_{i=1}^5 i = 1 + 2 + 3 + 4 + 5 = 15$)
- `x4 = 85` ($100 - 15 = 85$)
- `x5 = 15` (copied from `x3` on fall-through)
- `x6 = 85` (copied from `x4` on fall-through)
- `x7 = 0` (squashed trap verification)
- `x0 = 0` (verified during execution: WB write-suppression invariant and ID read-as-zero; write-to-x0 rejection is verified by the directed register-file simulation test in `tb_register_file.v`)

### 3.6 Observed Execution Metrics & Diagnostic Counters
- **Total Clock Cycles:** 43 cycles
- **Retired Instructions:** 28 instructions
- **Workload Branch Flushes:** 5 flushes (4 taken loop iterations + 1 forward jump)
- **Halt Self-Loop Flushes:** 2 flushes (from in-place execution of `beq x0, x0, 0` at `0x30`)
- **Total Pipeline Flushes Detected:** 7 flushes
- **Pipeline Stalls:** 0 stalls (pure ALU/branch pipeline)

#### Counter Measurement Window & Accounting Details
- **Start Condition:** Counters activate on the first rising clock edge following synchronous active-high reset deassertion (`!rst`).
- **Stop Condition:** Program completion is detected at cycle 41 when the halt self-loop (`0x30: beq x0, x0, 0`) retires at Write-Back (`debug_wb_retired && debug_wb_pc == 32'h0000_0030`). The testbench executes 2 additional clock cycles before asserting final state checks and calling `$finish` at cycle 43.
- **Architectural State Sampling Timing:**
  - Because instructions execute in strict in-order sequence, when the first retirement of `0x30` occurs at WB, all earlier workload instructions have completed and committed their results.
  - The CPU does not freeze clocking on completion; the halt instruction `beq x0, x0, 0` continues executing harmlessly in-place. Because it has `rd=0`, `reg_write=0`, and `mem_write=0`, it produces no register or memory side effects, ensuring the architectural state remains stable and immutable.
- **Halt Self-Loop Contribution:**
  - The halt instruction (`beq x0, x0, 0`) evaluates as taken in the Execute stage, redirecting IF and generating 2 additional pipeline flush events.
  - Its initial retirement at WB increments `retired_count` from 27 (algorithmic instructions) to 28.
  - The 2 settling cycles increment `cycle_count` from 41 to 43.
- **Important Note on Performance Metrics:** These values are diagnostic simulation counters used solely to verify program progression and deterministic test completion. They do **not** represent validated CPI/IPC benchmark figures.

### 3.7 Simulation Command & Waveform Inspection
```bash
# Ensure simulation output directory exists
mkdir -p simulation

# Compile and simulate Benchmark 1
iverilog -g2012 -o simulation/tb_benchmark_accumulate.vvp \
    testbench/tb_benchmark_accumulate.v \
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
    rtl/stages/branch_controller.v
vvp simulation/tb_benchmark_accumulate.vvp
```
Expected output: `PASS: tb_benchmark_accumulate (all 12 checks passed)`.

#### Waveform Inspection
The testbench generates a Value Change Dump (VCD) at `simulation/tb_benchmark_accumulate.vcd`. To view in GTKWave:
```bash
gtkwave simulation/tb_benchmark_accumulate.vcd
```
Key signals to observe:
- Stage PCs: `debug_if_pc`, `debug_id_pc`, `debug_ex_pc`, `debug_mem_pc`, `debug_wb_pc`
- Branch & Flush: `debug_branch_taken`, `debug_branch_target`, `debug_flush`
- Forwarding Controls: `debug_forward_a`, `debug_forward_b`
- Write-Back Commit: `debug_wb_retired`, `debug_wb_reg_write`, `debug_wb_rd`, `debug_wb_data`
- Register File Read Ports: `uut.u_id_stage.registers.rs1_data`, `uut.u_id_stage.registers.rs2_data`

*(Note on 2D Arrays: In standard Icarus Verilog VCD generation, internal 2D unpacked arrays such as `registers[1:31]` are not dumped as separate array variables. Register updates are observed via the Write-Back interface signals `debug_wb_rd` and `debug_wb_data` on each clock edge).*

---

## 4. Benchmark 2: Memory & Array Access Sequence (`benchmark_load_store.hex`)

### 4.1 Overview
Benchmark 2 tests memory operations (`SW`, `LW`), base-pointer arithmetic, load-use hazard interlocks, store-to-load ordering, and memory array consistency.

### 4.2 Assembly Listing & Hex Encodings

| Byte Addr | Hex Code | Instruction | Operands | Description / Hazards Exercised |
|:---:|:---:|---|---|---|
| `0x00` | `04000093` | `addi` | `x1, x0, 64` | Base pointer = `0x00000040` (byte 64, data memory word 16) |
| `0x04` | `00a00213` | `addi` | `x4, x0, 10` | Element 0 value = 10 |
| `0x08` | `01900293` | `addi` | `x5, x0, 25` | Element 1 value = 25 |
| `0x0C` | `02800393` | `addi` | `x7, x0, 40` | Element 2 value = 40 |
| `0x10` | `0040a023` | `sw` | `x4, 0(x1)` | Store element 0: `mem[0x40] = 10` (word 16) |
| `0x14` | `0050a223` | `sw` | `x5, 4(x1)` | Store element 1: `mem[0x44] = 25` (word 17) |
| `0x18` | `0070a423` | `sw` | `x7, 8(x1)` | Store element 2: `mem[0x48] = 40` (word 18) |
| `0x1C` | `00408113` | `addi` | `x2, x1, 4` | Pointer to element 1: `x2 = 0x44` |
| `0x20` | `00808193` | `addi` | `x3, x1, 8` | Pointer to element 2: `x3 = 0x48` |
| `0x24` | `0000a203` | `lw` | `x4, 0(x1)` | Reload element 0: `x4 = mem[0x40] = 10` |
| `0x28` | `00012283` | `lw` | `x5, 0(x2)` | Load element 1: `x5 = mem[0x44] = 25` |
| `0x2C` | `00428333` | `add` | `x6, x5, x4` | **LOAD-USE HAZARD #1:** Uses `x5` immediately after `lw`. Stalls 1 cycle, forwards `x5` from MEM/WB. $x6 = 25 + 10 = 35$. |
| `0x30` | `0001a383` | `lw` | `x7, 0(x3)` | Load element 2: `x7 = mem[0x48] = 40` |
| `0x34` | `00730433` | `add` | `x8, x6, x7` | **LOAD-USE HAZARD #2:** Uses `x7` immediately after `lw`. Stalls 1 cycle, forwards `x7` from MEM/WB. $x8 = 35 + 40 = 75$. |
| `0x38` | `0080a623` | `sw` | `x8, 12(x1)` | Store total sum: `mem[0x4C] = 75` (word 19) |
| `0x3C` | `404404b3` | `sub` | `x9, x8, x4` | Compute difference: $x9 = 75 - 10 = 65$ (RAW forward `x8`) |
| `0x40` | `0090a823` | `sw` | `x9, 16(x1)` | Store difference: `mem[0x50] = 65` (word 20) |
| `0x44` | `00c0a503` | `lw` | `x10, 12(x1)` | **STORE-TO-LOAD ORDERING:** Read back stored sum: `x10 = mem[0x4C] = 75` |
| `0x48` | `408505b3` | `sub` | `x11, x10, x8` | **LOAD-USE HAZARD #3:** Uses `x10` immediately after `lw`. Stalls 1 cycle. Computes $x11 = 75 - 75 = 0$. |
| `0x4C` | `00058463` | `beq` | `x11, x0, 8` | If $x11 == 0$, branch forward to `0x54` (`done`). Flushes wrong-path trap. |
| `0x50` | `06300613` | `addi` | `x12, x0, 99` | **TRAP INSTRUCTION:** Must be squashed by branch at `0x4C`. `x12` must remain 0. |
| `0x54` | `00000063` | `beq` | `x0, x0, 0` | **done:** Halt self-loop (`0x54 + 0 = 0x54`). Signals completion. |

### 4.3 Hazards & Verification Features
- **Load-Use Pipeline Interlocks:** Three distinct load-use hazards are exercised (`lw` immediately followed by consumer ALU operation). In each case, the hazard detection unit:
  1. Deasserts `pc_en` and `if_id_write` (freezing IF and ID stages).
  2. Asserts `stall` / synchronous clear into `id_ex_reg` (injecting a NOP bubble into EX stage).
  3. On the subsequent cycle, allows the consumer instruction to enter EX while the forwarding unit routes the loaded operand directly from the MEM/WB pipeline register.
- **Store-to-load Ordering:** The instruction at `0x44` reads from byte `0x4C` which was updated by `sw` at `0x38`. This verifies that data memory writes commit properly on the rising clock edge in MEM stage and can be read back by subsequent load instructions.
- **Trap Squash:** Branch at `0x4C` verifies $x11 == 0$ and flushes trap instruction `0x50` (`addi x12, x0, 99`). `x12` remains `0`.

### 4.4 Completion Convention & Timeout
- **Halt Mechanism:** Self-loop `beq x0, x0, 0` at address `0x00000054`.
- **Detection Condition:** Testbench monitors Write-Back interface:
  $$\text{debug\_wb\_retired} == 1 \quad \land \quad \text{debug\_wb\_pc} == 32\text{'h0000\_0054}$$
- **Timeout Protection:** Bounded timeout at 500 clock cycles.

### 4.5 Expected Architectural State
- **Registers:**
  - `x1 = 64` (`0x40`, base pointer)
  - `x2 = 68` (`0x44`, element 1 pointer)
  - `x3 = 72` (`0x48`, element 2 pointer)
  - `x4 = 10` (reloaded element 0)
  - `x5 = 25` (loaded element 1)
  - `x6 = 35` (intermediate sum $25 + 10$)
  - `x7 = 40` (loaded element 2)
  - `x8 = 75` (total accumulated sum $10 + 25 + 40$)
  - `x9 = 65` (difference $75 - 10$)
  - `x10 = 75` (store-to-load readback of sum)
  - `x11 = 0` ($75 - 75 = 0$)
  - `x12 = 0` (squashed trap verification)
  - `x0 = 0` (verified during execution: WB write-suppression invariant and ID read-as-zero; write-to-x0 rejection is verified by the directed register-file simulation test in `tb_register_file.v`)
- **Data Memory:**
  - `mem[16]` (byte `0x40`) = 10
  - `mem[17]` (byte `0x44`) = 25
  - `mem[18]` (byte `0x48`) = 40
  - `mem[19]` (byte `0x4C`) = 75
  - `mem[20]` (byte `0x50`) = 65

### 4.6 Observed Execution Metrics & Diagnostic Counters
- **Total Clock Cycles:** 31 cycles
- **Retired Instructions:** 21 instructions
- **Load-Use Stall Cycles:** 3 stall cycles (exactly 3 location-verified load-use hazards, 0 spurious stalls)
- **Workload Branch Flushes:** 1 flush (forward jump at 0x4C)
- **Halt Self-Loop Flushes:** 2 flushes (from in-place execution of `beq x0, x0, 0` at `0x54`)
- **Total Pipeline Flushes Detected:** 3 flushes

#### Counter Measurement Window & Accounting Details
- **Start Condition:** Counters activate on the first rising clock edge following synchronous active-high reset deassertion (`!rst`).
- **Stop Condition:** Program completion is detected at cycle 29 when the halt self-loop (`0x54: beq x0, x0, 0`) retires at Write-Back (`debug_wb_retired && debug_wb_pc == 32'h0000_0054`). The testbench executes 2 additional clock cycles before asserting final state checks and calling `$finish` at cycle 31.
- **Architectural State Sampling Timing:**
  - Because instructions execute in strict in-order sequence, when the first retirement of `0x54` occurs at WB, all earlier workload stores and register writes have completed and committed.
  - The CPU does not freeze clocking on completion; the halt instruction `beq x0, x0, 0` continues executing harmlessly in-place. Because it has `rd=0`, `reg_write=0`, and `mem_write=0`, it produces no register or memory side effects, ensuring the architectural state remains stable and immutable.
- **Halt Self-Loop Contribution:**
  - The halt instruction (`beq x0, x0, 0`) evaluates as taken in the Execute stage, asserting 2 additional pipeline flush cycles (bringing total flushes from 1 to 3).
  - Its initial retirement at WB increments `retired_count` from 20 (algorithmic instructions) to 21.
  - The 2 settling cycles increment `cycle_count` from 29 to 31.
- **Important Note on Performance Metrics:** These values are diagnostic simulation counters used solely to verify program progression and deterministic test completion. They do **not** represent validated CPI/IPC benchmark figures.

### 4.7 Simulation Command & Waveform Inspection
```bash
# Ensure simulation output directory exists
mkdir -p simulation

# Compile and simulate Benchmark 2
iverilog -g2012 -o simulation/tb_benchmark_load_store.vvp \
    testbench/tb_benchmark_load_store.v \
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
    rtl/stages/branch_controller.v
vvp simulation/tb_benchmark_load_store.vvp
```
Expected output: `PASS: tb_benchmark_load_store (all 24 checks passed)`.

#### Waveform Inspection
The testbench generates a Value Change Dump (VCD) at `simulation/tb_benchmark_load_store.vcd`. To view in GTKWave:
```bash
gtkwave simulation/tb_benchmark_load_store.vcd
```
Key signals to observe:
- Stage PCs: `debug_if_pc`, `debug_id_pc`, `debug_ex_pc`, `debug_mem_pc`, `debug_wb_pc`
- Hazard Interlock: `debug_stall` (asserted for 1 cycle during each of the 3 load-use hazards)
- Forwarding Controls: `debug_forward_a`, `debug_forward_b`
- Memory Controls: `debug_mem_read`, `debug_mem_write`, `debug_mem_addr`, `debug_mem_write_data`
- Write-Back Commit: `debug_wb_retired`, `debug_wb_reg_write`, `debug_wb_rd`, `debug_wb_data`

*(Note on 2D Arrays: In standard Icarus Verilog VCD generation, internal 2D unpacked memory arrays such as `mem[0:255]` and `registers[1:31]` are not dumped as separate array variables. Memory writes and reads are observed via the MEM stage bus signals `debug_mem_addr`, `debug_mem_write_data`, and the WB stage signals).*

---

## 5. Benchmark 3: Control Hazards & Dual Forwarding (`benchmark_control_hazards.hex`)

### 5.1 Overview
Benchmark 3 verifies complex control hazard interactions, branch prediction recoveries, back-to-back store-to-load memory access, and simultaneous dual RAW operand forwarding using `programs/benchmark_control_hazards.hex`.

### 5.2 Assembly Program & Encodings

| Byte Addr | Hex Code | Instruction | Operands | Description / Hazards Exercised |
|:---:|:---:|---|---|---|
| `0x00` | `00a00093` | `addi` | `x1, x0, 10` | $x1 = 10$ |
| `0x04` | `01400113` | `addi` | `x2, x0, 20` | $x2 = 20$ |
| `0x08` | `00a00193` | `addi` | `x3, x0, 10` | $x3 = 10$ |
| `0x0C` | `00208863` | `beq`  | `x1, x2, 16` | If $x1 == x2$, branch to `0x1C`. **Not taken (10 != 20). Falls through.** |
| `0x10` | `01e00213` | `addi` | `x4, x0, 30` | Fall-through executed: $x4 = 30$ |
| `0x14` | `00308863` | `beq`  | `x1, x3, 16` | If $x1 == x3$, branch to `0x24`. **Taken (10 == 10). Flushes 0x18 (ID), 0x1C (IF).** |
| `0x18` | `06300293` | `addi` | `x5, x0, 99` | **TRAP 1:** Squashed from ID stage. $x5$ remains 0. |
| `0x1C` | `06300313` | `addi` | `x6, x0, 99` | **TRAP 2:** Squashed from IF stage. $x6$ remains 0. |
| `0x20` | `06300393` | `addi` | `x7, x0, 99` | **TRAP 3:** Skipped (never fetched; branch targets 0x24). $x7$ remains 0. |
| `0x24` | `00309863` | `bne`  | `x1, x3, 16` | If $x1 \neq x3$, branch to `0x34`. **Not taken (10 == 10). Falls through.** |
| `0x28` | `02800413` | `addi` | `x8, x0, 40` | Fall-through executed: $x8 = 40$ |
| `0x2C` | `00209863` | `bne`  | `x1, x2, 16` | If $x1 \neq x2$, branch to `0x3C`. **Taken (10 != 20). Flushes 0x30 (ID), 0x34 (IF).** |
| `0x30` | `06300493` | `addi` | `x9, x0, 99` | **TRAP 4:** Squashed from ID stage. $x9$ remains 0. |
| `0x34` | `06300513` | `addi` | `x10, x0, 99` | **TRAP 5:** Squashed from IF stage. $x10$ remains 0. |
| `0x38` | `06300593` | `addi` | `x11, x0, 99` | **TRAP 6:** Skipped (never fetched; branch targets 0x3C). $x11$ remains 0. |
| `0x3C` | `06400613` | `addi` | `x12, x0, 100` | Target instruction: $x12 = 100$ |
| `0x40` | `00c02023` | `sw`   | `x12, 0(x0)` | Store: $\text{mem}[0] = 100$ |
| `0x44` | `00002683` | `lw`   | `x13, 0(x0)` | Immediate Load: $x13 = \text{mem}[0] = 100$ |
| `0x48` | `00468733` | `add`  | `x14, x13, x4` | **LOAD-USE HAZARD:** 1-cycle stall. Operand A forwarded from MEM/WB. $x14 = 100 + 30 = 130$ |
| `0x4C` | `002087b3` | `add`  | `x15, x1, x2` | $x15 = 10 + 20 = 30$ |
| `0x50` | `40f70833` | `sub`  | `x16, x14, x15` | **DUAL FORWARDING:** $x14$ from MEM/WB, $x15$ from EX/MEM! $x16 = 130 - 30 = 100$ |
| `0x54` | `00c80463` | `beq`  | `x16, x12, 8` | If $x16 == x12$, branch to `0x5C`. **Taken (100 == 100). Flushes 0x58 (ID).** |
| `0x58` | `06300893` | `addi` | `x17, x0, 99` | **TRAP 7:** Squashed from ID stage. $x17$ remains 0. |
| `0x5C` | `00000063` | `beq`  | `x0, x0, 0` | **done:** Halt self-loop at `0x5C`. |

### 5.3 Simulation & Verification
```bash
mkdir -p simulation
iverilog -g2012 -o simulation/tb_benchmark_control_hazards.vvp \
    testbench/tb_benchmark_control_hazards.v \
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
    rtl/stages/branch_controller.v
vvp simulation/tb_benchmark_control_hazards.vvp
```
Expected output: `PASS: tb_benchmark_control_hazards (all 23 checks passed)`.

### 5.4 Observed Execution Metrics & Diagnostic Counters
- **Total Clock Cycles:** 29 cycles
- **Retired Instructions:** 17 instructions
- **Load-Use Stall Cycles:** 1 stall cycle (exactly 1 location-verified load-use hazard at LW 0x44 / ADD 0x48)
- **Workload Branch Flushes:** 3 flushes (BEQ 0x14, BNE 0x2C, BEQ 0x54 taken branches)
- **Halt Self-Loop Flushes:** 2 flushes (from in-place execution of `beq x0, x0, 0` at `0x5C`)
- **Total Pipeline Flushes Detected:** 5 flushes
- **Trap Suppression:** 5 traps flushed (`0x18`, `0x1C`, `0x30`, `0x34`, `0x58`) and 2 traps skipped (`0x20`, `0x38`); all 7 trap registers (`x5, x6, x7, x9, x10, x11, x17`) remain 0.

#### Counter Measurement Window & Accounting Details
- **Start Condition:** Counters activate on the first rising clock edge following synchronous active-high reset deassertion (`!rst`).
- **Stop Condition:** Program completion is detected at cycle 27 when the halt self-loop (`0x5C: beq x0, x0, 0`) retires at Write-Back (`debug_wb_retired && debug_wb_pc == 32'h0000_005C`). The testbench executes 2 additional clock cycles before asserting final state checks and calling `$finish` at cycle 29.
- **Architectural State Sampling Timing:**
  - Because instructions execute in strict in-order sequence, when the first retirement of `0x5C` occurs at WB, all earlier workload stores and register writes have completed and committed.
  - The CPU does not freeze clocking on completion; the halt instruction `beq x0, x0, 0` continues executing harmlessly in-place. Because it has `rd=0`, `reg_write=0`, and `mem_write=0`, it produces no register or memory side effects, ensuring the architectural state remains stable and immutable.
- **Halt Self-Loop Contribution:**
  - The halt instruction (`beq x0, x0, 0`) evaluates as taken in the Execute stage, asserting 2 additional pipeline flush cycles (bringing total flushes from 3 to 5).
  - Its initial retirement at WB increments `retired_count` from 16 (algorithmic instructions) to 17.
  - The 2 settling cycles increment `cycle_count` from 27 to 29.
- **Important Note on Performance Metrics:** These values are diagnostic simulation counters used solely to verify program progression and deterministic test completion. They do **not** represent validated CPI/IPC benchmark figures.

---

## 6. CPI / IPC Measurement & Performance Analysis

### 6.1 Measurement Windows & Definitions
In pipelined processor verification, reporting cycle and instruction metrics requires clearly defining the measurement boundary to prevent counting arbitrary completion loop cycles. We define two reproducible conventions:

1. **Convention A (Pure Workload Window — Recommended):**
   - **Start:** Clock cycle immediately following reset deassertion (`!rst`).
   - **End:** Clock cycle when the final algorithmic workload instruction retires at Write-Back (`debug_wb_retired && debug_wb_pc == LAST_WORKLOAD_PC`).
   - **Instructions:** Only true workload instructions executed. The halt marker is **excluded**.
   - **Cycles:** Elapsed cycles from reset release to completion of the workload.
2. **Convention B (Completion-Inclusive Window):**
   - **Start:** Clock cycle immediately following reset deassertion (`!rst`).
   - **End:** Clock cycle when the halt self-loop instruction (`beq x0, x0, 0`) first retires at Write-Back (`debug_wb_retired && debug_wb_pc == HALT_PC`).
   - **Instructions:** Workload instructions $+ 1$ (the single halt instruction retirement).
   - **Cycles:** Elapsed cycles until the halt marker first reaches Write-Back (includes the 2 cycles for the halt instruction to traverse EX $\to$ MEM $\to$ WB; excludes subsequent infinite looping).

### 6.2 Empirical Measurements Summary

| Workload | Window Convention | Measured Cycles | Retired Instructions | Stalls | Flushes | Measured CPI | Measured IPC |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Benchmark 1** (Accumulator Loop) | Convention A (Pure Workload) | 38 | 27 | 0 | 5 | **1.4074** | **0.7105** |
| | Convention B (Completion-Inclusive) | 41 | 28 | 0 | 6 | **1.4643** | **0.6829** |
| **Benchmark 2** (Load/Store Sequence) | Convention A (Pure Workload) | 26 | 20 | 3 | 1 | **1.3000** | **0.7692** |
| | Convention B (Completion-Inclusive) | 29 | 21 | 3 | 2 | **1.3810** | **0.7241** |
| **Benchmark 3** (Control Hazards) | Convention A (Pure Workload) | 24 | 16 | 1 | 3 | **1.5000** | **0.6667** |
| | Convention B (Completion-Inclusive) | 27 | 17 | 1 | 4 | **1.5882** | **0.6296** |

### 6.3 Run CPI/IPC Measurement Suite
```bash
mkdir -p simulation
iverilog -g2012 -o simulation/tb_performance_cpi_ipc.vvp \
    testbench/tb_performance_cpi_ipc.v \
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
    rtl/stages/branch_controller.v
vvp simulation/tb_performance_cpi_ipc.vvp
```

---

## 7. Verilog Single-Cycle Baseline Comparison

To evaluate the architectural impact of 5-stage pipelining against a non-pipelined design, a synthesizable Verilog single-cycle reference processor was implemented ([`rtl/reference/single_cycle_cpu.v`](../rtl/reference/single_cycle_cpu.v)) executing the identical 7-instruction subset.

### 7.1 Quantitative Comparison (Pure Workload Window)

| Workload | Architecture | Cycles | Retired Instrs | CPI | IPC | Compared State |
|---|---|:---:|:---:|:---:|:---:|:---:|
| **Benchmark 1** (Loop) | Single-Cycle Reference | 27 | 27 | 1.0000 | 1.0000 | Matched (x1–x7) |
| | 5-Stage Pipelined CPU | 38 | 27 | 1.4074 | 0.7105 | Matched (x1–x7) |
| **Benchmark 2** (Memory) | Single-Cycle Reference | 20 | 20 | 1.0000 | 1.0000 | Matched (x1–x12, mem[16:20]) |
| | 5-Stage Pipelined CPU | 26 | 20 | 1.3000 | 0.7692 | Matched (x1–x12, mem[16:20]) |
| **Benchmark 3** (Control) | Single-Cycle Reference | 16 | 16 | 1.0000 | 1.0000 | Matched (x1–x17, mem[0]) |
| | 5-Stage Pipelined CPU | 24 | 16 | 1.5000 | 0.6667 | Matched (x1–x17, mem[0]) |

> [!NOTE]
> **Performance Qualification:** In software simulation, single-cycle execution achieves $\text{CPI}=1.0$, while the pipelined CPU exhibits $\text{CPI} > 1$ due to fill/drain latency, load-use interlock stalls, and branch redirection flushes. In physical hardware, pipelining aims to achieve higher throughput by dividing the critical path into shorter stages, enabling a higher operating clock frequency ($f_{\text{pipe}} > f_{\text{single}}$). A physical execution speedup is realized only if the hardware frequency multiplier exceeds the CPI penalty. Because static timing analysis on hardware was not executed for both implementations, real-time speedup is not claimed; the numbers demonstrate architectural cycle and instruction dynamics under identical workload conditions.

### 7.2 Run Single-Cycle Comparison Testbench
```bash
mkdir -p simulation
iverilog -g2012 -I rtl -I rtl/stages -I rtl/pipeline_registers \
    -o simulation/tb_single_cycle_comparison.vvp \
    rtl/reference/single_cycle_cpu.v \
    rtl/cpu.v rtl/stages/*.v rtl/pipeline_registers/*.v \
    testbench/tb_single_cycle_comparison.v
vvp simulation/tb_single_cycle_comparison.vvp
```
Expected output: `ALL 3 CO-SIMULATION COMPARISON TESTS PASSED SUCCESSFULLY`.

---

## 8. Fetch Test Data (`if_test.hex`)

IF-only test data, not a CPU benchmark. It has one instruction of each of the seven supported types, plus SUB and a second branch form:

| Addr | Hex | Instruction | Encoding check |
|---|---|---|---|
| 0x00 | 00002083 | `lw x1, 0(x0)` | I-type, opcode 0000011, funct3 010 |
| 0x04 | 00108133 | `add x2, x1, x1` | R-type, opcode 0110011, funct7 0000000, funct3 000 |
| 0x08 | 00e00193 | `addi x3, x0, 14` | I-type, opcode 0010011, imm 14 |
| 0x0c | 40310233 | `sub x4, x2, x3` | R-type, funct7 0100000, funct3 000 |
| 0x10 | 00310463 | `beq x2, x3, +8` | B-type, opcode 1100011, funct3 000, imm 8 |
| 0x14 | 00002023 | `sw x0, 0(x0)` | S-type, opcode 0100011, funct3 010 |
| 0x18 | 00202223 | `sw x2, 4(x0)` | S-type, imm[11:5]=0, imm[4:0]=4 |
| 0x1c | fe021ee3 | `bne x4, x0, -4` | B-type, funct3 001, imm -4 |

### Run the fetch test (from repository root)
```bash
mkdir -p simulation
iverilog -g2012 -o simulation/tb_fetch.vvp testbench/tb_fetch.v \
    rtl/stages/if_stage.v rtl/stages/pc.v rtl/stages/instr_mem.v
vvp simulation/tb_fetch.vvp
```
Expected output: `PASS: tb_fetch`.
