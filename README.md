# Team Scaler MCA Project

A 5-stage pipelined RISC-V (RV32I subset) processor implemented in Verilog, targeting modular simulation with Icarus Verilog and waveform analysis in GTKWave.

---

## 1. Project Overview

This project implements a classic 5-stage RISC-V pipeline (**IF**, **ID**, **EX**, **MEM**, **WB**) supporting core integer arithmetic, memory access, and branch instructions. The design emphasizes modularity, clean pipeline interfaces, robust hazard handling capabilities (forwarding, stalls, flushes), and verifiable stage-by-stage progression.

> **Project Demo Video:** [Google Drive Folder Link](https://drive.google.com/drive/folders/1EgOdLGRiIbfGNEMWvCw3mpRqaSgrbESI?usp=sharing) (see [`video/README.md`](video/README.md))

### Supported Instruction Subset
| Format | Instructions | Description |
|---|---|---|
| **R-Type** | `add`, `sub` | Register-register arithmetic |
| **I-Type** | `addi`, `lw` | Immediate arithmetic and memory load |
| **S-Type** | `sw` | Memory store |
| **B-Type** | `beq`, `bne` | Conditional branch (equality and inequality) |

---

## 2. Project Status & Work Done So Far

The repository has progressed through the first three major architectural milestones (Scaffold, IF stage, ID stage, EX stage), fully implemented and validated with comprehensive unit and integration testbenches:

```
[ Milestone 1: IF Stage ] ──► [ Milestone 2: ID Stage ] ──► [ Milestone 3: EX Stage ] ──► [ M4: MEM/WB ] ──► [ M5: CPU Integration ]
        (Completed)                   (Completed)                   (Completed)              (Completed)             (Completed)
```

### Milestone Progress Tracker
- [x] **Repository Scaffold & Workflow (Issue #1, PR #28)**
  - Initial repository layout, `.gitkeep` directory scaffolding, contribution workflow (`CONTRIBUTING.md`), and PR template (`.github/pull_request_template.md`).
- [x] **Milestone 1: Instruction Fetch (IF) Stage (Issues #2–#6, PRs #29–#33)**
  - Program counter with synchronous reset and hold support (`pc.v`).
  - Read-only instruction memory initialized via `$readmemh` (`instr_mem.v`).
  - Unified fetch wrapper calculating sequential PC+4 (`if_stage.v`).
  - IF/ID pipeline register with synchronous reset, flush, and hold controls (`if_id_reg.v`).
  - Test suites (`tb_pc_instr_mem.v`, `tb_fetch.v`, `tb_if_stage.v`, `tb_if_id_reg.v`) and hex test image (`programs/if_test.hex`).
  - Detailed interface specification in [`docs/if_stage_interface.md`](docs/if_stage_interface.md).
- [x] **Milestone 2: Instruction Decode (ID) Stage (Issues #7–#11, PRs #34–#38)**
  - Instruction decoder extracting opcodes, register indices, and sign-extended immediates (`instruction_decoder.v`).
  - 32-register dual-read single-write register file with `x0 = 0` hardwiring and WB write-to-read bypass (`register_file.v`).
  - Main control unit decoding execution, memory, write-back signals, and operand-use tracking (`main_control.v`).
  - Structural decode stage wrapper (`id_stage.v`).
  - ID/EX pipeline register capturing operands, decoded controls, and validity (`id_ex_reg.v`).
  - Full test coverage (`tb_instruction_decoder.v`, `tb_register_file.v`, `tb_main_control.v`, `tb_id_stage.v`, `tb_id_ex_reg.v`).
  - Interface documentation in [`docs/id_stage_interface.md`](docs/id_stage_interface.md) and [`docs/id_ex_interface.md`](docs/id_ex_interface.md).
- [x] **Milestone 3: Execution (EX) Stage (Issues #12–#16, PRs #39–#43)**
  - 32-bit Arithmetic Logic Unit supporting ADD and SUB operations (`alu.v`).
  - ALU control decoder translating `alu_op`, `funct3`, and `funct7` into operation codes (`alu_control.v`).
  - Branch comparison and target calculation unit evaluating BEQ and BNE (`branch_unit.v`).
  - Complete execution datapath integrating dual-operand forwarding multiplexers (EX/MEM and MEM/WB paths), immediate selection, and side-effect suppression (`ex_stage.v`).
  - EX/MEM pipeline register capturing execution results, store data, and gated control flags (`ex_mem_reg.v`).
  - Exhaustive testbenches (`tb_alu.v`, `tb_alu_control.v`, `tb_branch_unit.v`, `tb_ex_stage.v`, `tb_ex_mem_reg.v`).
  - Interface contracts in [`docs/ex_stage_interface.md`](docs/ex_stage_interface.md) and [`docs/ex_mem_interface.md`](docs/ex_mem_interface.md).
- [x] **Milestone 4: Memory (MEM) Stage & Write-Back (WB) Integration (Issues #17–#21, PRs #54–#58)**
  - Word-addressable data memory module with synchronous write and combinational read (`data_mem.v`).
  - Structural Memory stage wrapper (`mem_stage.v`).
  - MEM/WB pipeline register with synchronous hold, flush, and bubble squash priority (`mem_wb_reg.v`).
  - Write-Back stage logic with source multiplexing and side-effect gating (`wb_stage.v`).
  - Exhaustive unit and end-to-end integration testbenches (`tb_data_mem.v`, `tb_mem_stage.v`, `tb_mem_wb_reg.v`, `tb_wb_stage.v`, `tb_load_store_wb.v`).
  - Interface contracts in [`docs/data_mem_interface.md`](docs/data_mem_interface.md), [`docs/mem_wb_interface.md`](docs/mem_wb_interface.md), [`docs/wb_stage_interface.md`](docs/wb_stage_interface.md), and [`docs/load_store_wb_verification.md`](docs/load_store_wb_verification.md).
- [x] **Milestone 5: Hazard Detection, Forwarding & Full Pipeline Integration (Completed)**
  - [x] **Load-Use Hazard Detection & Pipeline Stall Control (Issue #22)**
    - Read-After-Write (RAW) hazard detection unit comparing ID source registers with EX load destination (`hazard_detection.v`, `hazard_unit.v`).
    - Synchronous interlock control: PC hold (`next_pc <= pc`), IF/ID hold (`en = 0`), and ID/EX bubble insertion (`flush = 1`).
    - Comprehensive unit and cycle-accurate pipeline timing testbenches (`tb_hazard_detection.v`, `tb_hazard_unit.v`).
    - Complete specification contract in [`docs/hazard_detection_interface.md`](docs/hazard_detection_interface.md).
  - [x] **Branch Misprediction Flush & Hazard Coordination Unit (Issue #25)**
    - Centralized branch redirection and pipeline flush controller (`branch_controller.v`, `branch_hazard_coordinator.v`).
    - Next-PC redirection to branch target on taken branches (`BEQ`, `BNE` resolved in EX).
    - Dual-boundary synchronous flushing (`if_id_flush = 1`, `id_ex_flush = 1`) squashing wrong-path instructions in IF and ID before architectural side effects.
    - Deterministic priority table: taken branch strictly overrides younger load-use stall requests.
    - Preservation of branch target instruction execution exactly once.
    - Exhaustive self-checking testbenches (`tb_branch_controller.v`, `tb_branch_hazard_coordinator.v`) verifying taken, not-taken, RAW forwarded, and stall-interleaved branches.
    - Complete interface contract and cycle timing diagrams in [`docs/branch_hazard_coordination.md`](docs/branch_hazard_coordination.md).
  - [x] **EX-Stage Forwarding & Operand Bypass Unit (Issue #24)**
    - Dual-operand forwarding selection for EX-stage operands (`forward_a`, `forward_b`) resolving RAW hazards from `EX/MEM` and `MEM/WB` stages (`forwarding_unit.v`, `forwarding.v`).
    - Strict youngest-producer priority (`EX/MEM` over `MEM/WB`).
    - Safe hazard resolution: `x0` immunity, invalid/bubble suppression, and unforwardable load (`ex_mem_mem_read`) gating.
    - Full datapath integration with `ex_stage.v` preserving immediate selection and routing forwarded operands to ALU, store data, and branch comparison.
    - Exhaustive self-checking testbenches (`tb_forwarding_unit.v`, `tb_forwarding.v`).
    - Complete interface and multiplexer specification contract in [`docs/forwarding_interface.md`](docs/forwarding_interface.md).
  - [x] **Top-Level Pipelined CPU Integration (Issue #26)**
    - Unified 5-stage CPU datapath connecting IF, IF/ID, ID, ID/EX, EX, EX/MEM, MEM, MEM/WB, WB, and hazard/forwarding units (`cpu.v`, `top.v`).
    - Fully resolved data, control, PC redirection, forwarding, stall, and write-back feedback paths with zero undriven nets or width mismatches.
    - Comprehensive observability with exposed debug ports for stage PCs, instruction words, validity bits, register writes, memory transactions, and hazard metrics.
    - Self-checking integration test suite (`tb_cpu.v`, `tb_top.v`) executing arithmetic, memory, hazard interlocks, and branch redirection sequences in program order.
    - Complete architectural specification contract in [`docs/top_level_cpu_interface.md`](docs/top_level_cpu_interface.md).
- [ ] **Milestone 6: End-to-End Verification & Performance Analysis (Upcoming)**
  - Comprehensive assembly verification programs, CPI/IPC calculation, and performance reports.

---

## 3. Pipeline Architecture & Implementation Details

```
          ┌─────────────┐       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐
          │     IF      │       │     ID      │       │     EX      │       │     MEM     │       │     WB      │
          │             │       │             │       │             │       │             │       │             │
next_pc ─►│  [PC Reg]   │       │  [Decoder]  │       │ [ALU Ctrl]  │       │   [Data     │       │ [WB Mux]    │
          │      │      │       │      │      │       │      │      │       │   Memory]   │       │      │      │
          │  [InstrMem] │──────►│  [Reg File] │──────►│    [ALU]    │──────►│             │──────►│ (Reg Write) │
          │      │      │       │      │      │       │      │      │       │             │       │             │
          │   (PC + 4)  │       │  [Control]  │       │[Branch Unit]│       │             │       │             │
          └──────┬──────┘       └──────┬──────┘       └──────┬──────┘       └──────┬──────┘       └─────────────┘
                 │                     │                     │                     │
                 ▼                     ▼                     ▼                     ▼
          ┌─────────────┐       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐
          │  IF/ID Reg  │       │  ID/EX Reg  │       │ EX/MEM Reg  │       │ MEM/WB Reg  │
          └─────────────┘       └─────────────┘       └─────────────┘       └─────────────┘
```

### Module Breakdown

| Stage | Module | File | Responsibilities |
|---|---|---|---|
| **IF** | `pc` | `rtl/stages/pc.v` | Synchronous 32-bit program counter with active-high reset |
| **IF** | `instr_mem` | `rtl/stages/instr_mem.v` | Word-aligned 32-bit instruction memory initialized via `$readmemh` |
| **IF** | `if_stage` | `rtl/stages/if_stage.v` | Integrates PC and memory, outputs current PC, PC+4, and instruction |
| **IF/ID** | `if_id_reg` | `rtl/pipeline_registers/if_id_reg.v` | Registers `pc`, `pc_plus4`, `instr`, and `valid` bit; supports stall & flush |
| **ID** | `instruction_decoder` | `rtl/stages/instruction_decoder.v` | Extracts `opcode`, `rd`, `funct3`, `rs1`, `rs2`, `funct7`, and immediate formats |
| **ID** | `register_file` | `rtl/stages/register_file.v` | 32 x 32-bit registers, write-to-read bypass, hardwired zero at `x0` |
| **ID** | `main_control` | `rtl/stages/main_control.v` | Decodes ALU, memory, branch, and register control signals + source usage |
| **ID** | `id_stage` | `rtl/stages/id_stage.v` | Connects decoder, register file, and control unit into structural ID stage |
| **ID/EX** | `id_ex_reg` | `rtl/pipeline_registers/id_ex_reg.v` | Registers operands, immediate, control signals, and register indices |
| **EX** | `alu` | `rtl/stages/alu.v` | Evaluates 32-bit ADD and SUB arithmetic operations |
| **EX** | `alu_control` | `rtl/stages/alu_control.v` | Maps `alu_op`, `funct3`, and `funct7` into specific ALU control codes |
| **EX** | `branch_unit` | `rtl/stages/branch_unit.v` | Computes target address (`pc + imm`) and tests BEQ/BNE conditions |
| **EX** | `ex_stage` | `rtl/stages/ex_stage.v` | Integrated EX datapath with forwarding multiplexers and control gating |
| **EX/MEM**| `ex_mem_reg` | `rtl/pipeline_registers/ex_mem_reg.v`| Captures `alu_result`, `store_data`, destination register `rd`, and memory flags |
| **MEM**   | `data_mem`   | `rtl/stages/data_mem.v`              | 1 KiB word-addressable data memory with synchronous write and combinational read |
| **MEM**   | `mem_stage`  | `rtl/stages/mem_stage.v`             | Memory stage wrapper integrating data memory and address decoding |
| **MEM/WB**| `mem_wb_reg` | `rtl/pipeline_registers/mem_wb_reg.v`| Boundary register capturing load data, ALU result, and write-back controls |
| **WB**    | `wb_stage`   | `rtl/stages/wb_stage.v`              | Write-Back source multiplexer with side-effect validation |
| **M5**    | `hazard_detection` | `rtl/stages/hazard_detection.v`| Load-use RAW hazard detection and synchronous stall/bubble controller |
| **M5**    | `hazard_unit`| `rtl/stages/hazard_unit.v`           | Hazard unit wrapper / alias |
| **M5**    | `branch_controller`| `rtl/stages/branch_controller.v`   | Branch redirection, wrong-path flush, and stall coordination controller |
| **M5**    | `branch_hazard_coordinator` | `rtl/stages/branch_hazard_coordinator.v` | Branch hazard coordinator wrapper / alias |
| **M5**    | `forwarding_unit`  | `rtl/stages/forwarding_unit.v` | EX-stage RAW operand forwarding multiplexer controller |
| **M5**    | `forwarding`       | `rtl/stages/forwarding.v`      | Forwarding unit wrapper / alias |
| **Top**   | `cpu`              | `rtl/cpu.v`                    | Top-level 5-stage pipelined RV32I processor module |
| **Top**   | `top`              | `rtl/top.v`                    | Top-level wrapper / alias for testbench binding |

### Key Architectural Conventions
- **Clock & Reset:** Single rising-edge clock domain (`clk`), synchronous active-high reset (`rst`).
- **NOP Representation:** Standard RV32I NOP instruction `32'h0000_0013` (`addi x0, x0, 0`).
- **Pipeline Register Precedence:** `rst` (highest priority) > `flush` > `en` (hold when low) > normal capture.
- **Bubble Safety:** Flushed instructions or reset bubbles drive `valid = 0`, which forces combinational side-effect controls (`mem_read`, `mem_write`, `reg_write`, `branch_taken`) to `0`.
- **Operand Forwarding:** EX stage incorporates multiplexers to accept forwarded operands from `EX/MEM` (`forward = 2'b10`) and `MEM/WB` (`forward = 2'b01`) boundaries.

---

## 4. Repository Layout

```
Team-Scaler-MCA-Project/
├── .github/
│   └── pull_request_template.md     # Standard PR checklist & verification template
├── docs/
│   ├── if_stage_interface.md        # IF stage interface contract and timing
│   ├── id_stage_interface.md        # ID stage interface contract
│   ├── id_ex_interface.md           # ID/EX pipeline register specification
│   ├── ex_stage_interface.md        # EX stage datapath & forwarding specification
│   ├── ex_mem_interface.md          # EX/MEM pipeline register specification
│   ├── data_mem_interface.md        # Data memory interface specification
│   ├── mem_wb_interface.md          # MEM/WB pipeline register specification
│   ├── wb_stage_interface.md        # WB stage logic and register-file interface
│   ├── load_store_wb_verification.md# Load/Store & Write-Back integration tests
│   ├── hazard_detection_interface.md# Load-use hazard detection & stall control
│   ├── branch_hazard_coordination.md# Branch redirect, pipeline flush & hazard stall specification
│   ├── forwarding_interface.md      # EX-stage forwarding & operand bypass specification
│   └── top_level_cpu_interface.md   # Top-level pipelined CPU interface & integration contract
├── programs/
│   ├── README.md                    # Hex test image documentation
│   └── if_test.hex                  # Instruction image for fetch testing
├── reports/                         # Performance reports and simulation analysis (M6)
├── rtl/
│   ├── cpu.v                        # Top-level pipelined CPU module
│   ├── top.v                        # Top-level wrapper / alias
│   ├── common/                      # Shared parameters and constants
│   ├── pipeline_registers/
│   │   ├── if_id_reg.v              # IF/ID boundary register
│   │   ├── id_ex_reg.v              # ID/EX boundary register
│   │   ├── ex_mem_reg.v             # EX/MEM boundary register
│   │   └── mem_wb_reg.v             # MEM/WB boundary register
│   └── stages/
│       ├── pc.v                     # Program counter
│       ├── instr_mem.v              # Instruction memory
│       ├── if_stage.v               # IF stage top wrapper
│       ├── instruction_decoder.v    # Instruction decoder & immediate generator
│       ├── register_file.v          # 32x32-bit register file with WB bypass
│       ├── main_control.v           # Main control unit
│       ├── id_stage.v               # ID stage top wrapper
│       ├── alu.v                    # Arithmetic Logic Unit
│       ├── alu_control.v            # ALU control decoder
│       ├── branch_unit.v            # Branch condition and target unit
│       ├── ex_stage.v               # EX stage top wrapper
│       ├── data_mem.v               # Data memory storage
│       ├── mem_stage.v              # Memory stage wrapper
│       ├── wb_stage.v               # Write-Back multiplexer stage
│       ├── hazard_detection.v       # Load-use hazard detection unit
│       ├── hazard_unit.v            # Hazard unit wrapper / alias
│       ├── branch_controller.v      # Branch redirect & pipeline flush controller
│       ├── branch_hazard_coordinator.v # Branch coordinator wrapper / alias
│       ├── forwarding_unit.v        # EX-stage forwarding unit
│       └── forwarding.v             # Forwarding unit wrapper / alias
├── simulation/                      # Simulation binaries and VCD waveform output
├── testbench/
│   ├── fixtures/                    # Test hex programs and fixtures
│   ├── tb_cpu.v                     # Top-level pipelined CPU integration testbench
│   ├── tb_top.v                     # Top-level wrapper verification testbench
│   ├── tb_alu.v                     # ALU testbench
│   ├── tb_alu_control.v             # ALU control testbench
│   ├── tb_branch_unit.v             # Branch unit testbench
│   ├── tb_ex_stage.v                # EX stage datapath & forwarding testbench
│   ├── tb_ex_mem_reg.v              # EX/MEM pipeline register testbench
│   ├── tb_data_mem.v                # Data memory testbench
│   ├── tb_mem_stage.v               # Memory stage testbench
│   ├── tb_mem_wb_reg.v              # MEM/WB pipeline register testbench
│   ├── tb_wb_stage.v                # Write-back stage testbench
│   ├── tb_load_store_wb.v           # Load/Store & Write-Back integration testbench
│   ├── tb_hazard_detection.v        # Load-use hazard detection testbench
│   ├── tb_hazard_unit.v             # Hazard unit wrapper testbench
│   ├── tb_branch_controller.v       # Branch redirect & hazard coordination integration testbench
│   ├── tb_branch_hazard_coordinator.v # Branch coordinator wrapper testbench
│   ├── tb_forwarding_unit.v         # EX-stage forwarding unit integration testbench
│   ├── tb_forwarding.v              # Forwarding wrapper testbench
│   ├── tb_fetch.v                   # Instruction fetch integration testbench
│   ├── tb_id_stage.v                # ID stage integration testbench
│   ├── tb_id_ex_reg.v               # ID/EX pipeline register testbench
│   ├── tb_if_stage.v                # IF stage wrapper testbench
│   ├── tb_if_id_reg.v               # IF/ID pipeline register testbench
│   ├── tb_instruction_decoder.v     # Instruction decoder testbench
│   ├── tb_main_control.v            # Main control unit testbench
│   ├── tb_pc_instr_mem.v            # PC & instruction memory testbench
│   └── tb_register_file.v           # Register file testbench
├── video/
│   └── README.md                    # Project demonstration video link & guide
├── CONTRIBUTING.md                  # Team Git & GitHub collaboration guide
└── README.md                        # Project documentation & progress summary
```

---

## 5. Simulation & Verification

The project is verified using **Icarus Verilog (`iverilog`)** and **GTKWave**.

### Prerequisites
- [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog`, `vvp`)
- [GTKWave](https://gtkwave.sourceforge.net/) (for waveform viewing)

### Running Testbenches
All testbenches are self-checking and print `PASS` or `FAIL` summaries. Run commands from the root of the repository:

#### 1. Instruction Fetch (IF) Tests
```bash
# Instruction fetch integration test with hex program
iverilog -g2012 -o simulation/tb_fetch.vvp testbench/tb_fetch.v \
    rtl/stages/if_stage.v rtl/stages/pc.v rtl/stages/instr_mem.v
vvp simulation/tb_fetch.vvp

# IF/ID pipeline register test
iverilog -g2012 -o simulation/tb_if_id_reg.vvp testbench/tb_if_id_reg.v \
    rtl/pipeline_registers/if_id_reg.v
vvp simulation/tb_if_id_reg.vvp
```

#### 2. Instruction Decode (ID) Tests
```bash
# Register file testbench (checks x0 behavior and WB bypass)
iverilog -g2012 -o simulation/tb_register_file.vvp testbench/tb_register_file.v \
    rtl/stages/register_file.v
vvp simulation/tb_register_file.vvp

# ID stage integration testbench
iverilog -g2012 -o simulation/tb_id_stage.vvp testbench/tb_id_stage.v \
    rtl/stages/id_stage.v rtl/stages/instruction_decoder.v \
    rtl/stages/register_file.v rtl/stages/main_control.v
vvp simulation/tb_id_stage.vvp

# ID/EX pipeline register testbench
iverilog -g2012 -o simulation/tb_id_ex_reg.vvp testbench/tb_id_ex_reg.v \
    rtl/pipeline_registers/id_ex_reg.v
vvp simulation/tb_id_ex_reg.vvp
```

#### 3. Execution (EX) Tests
```bash
# ALU and ALU control testbenches
iverilog -g2012 -o simulation/tb_alu.vvp testbench/tb_alu.v rtl/stages/alu.v
vvp simulation/tb_alu.vvp

iverilog -g2012 -o simulation/tb_alu_control.vvp testbench/tb_alu_control.v \
    rtl/stages/alu_control.v
vvp simulation/tb_alu_control.vvp

# Branch unit testbench
iverilog -g2012 -o simulation/tb_branch_unit.vvp testbench/tb_branch_unit.v \
    rtl/stages/branch_unit.v
vvp simulation/tb_branch_unit.vvp

# EX stage integration testbench (forwarding, immediate muxing, control gating)
iverilog -g2012 -o simulation/tb_ex_stage.vvp testbench/tb_ex_stage.v \
    rtl/stages/ex_stage.v rtl/stages/alu.v rtl/stages/alu_control.v \
    rtl/stages/branch_unit.v
vvp simulation/tb_ex_stage.vvp

# EX/MEM pipeline register testbench
iverilog -g2012 -o simulation/tb_ex_mem_reg.vvp testbench/tb_ex_mem_reg.v \
    rtl/pipeline_registers/ex_mem_reg.v
vvp simulation/tb_ex_mem_reg.vvp
```

#### 4. Memory (MEM) & Write-Back (WB) Tests
```bash
# Data memory unit test
iverilog -g2012 -o simulation/tb_data_mem.vvp testbench/tb_data_mem.v \
    rtl/stages/data_mem.v
vvp simulation/tb_data_mem.vvp

# MEM stage integration test
iverilog -g2012 -o simulation/tb_mem_stage.vvp testbench/tb_mem_stage.v \
    rtl/stages/mem_stage.v rtl/stages/data_mem.v
vvp simulation/tb_mem_stage.vvp

# MEM/WB pipeline register test
iverilog -g2012 -o simulation/tb_mem_wb_reg.vvp testbench/tb_mem_wb_reg.v \
    rtl/pipeline_registers/mem_wb_reg.v
vvp simulation/tb_mem_wb_reg.vvp

# WB stage & register file integration test
iverilog -g2012 -o simulation/tb_wb_stage.vvp testbench/tb_wb_stage.v \
    rtl/stages/wb_stage.v rtl/stages/register_file.v
vvp simulation/tb_wb_stage.vvp

# Comprehensive end-to-end Load/Store & Write-Back pipeline test
iverilog -g2012 -o simulation/tb_load_store_wb.vvp testbench/tb_load_store_wb.v \
    rtl/stages/mem_stage.v rtl/stages/data_mem.v \
    rtl/pipeline_registers/mem_wb_reg.v rtl/stages/wb_stage.v \
    rtl/stages/register_file.v
vvp simulation/tb_load_store_wb.vvp
```

#### 5. Hazard Detection & Stall Control Tests
```bash
# Load-use hazard detection unit and pipeline timing test
iverilog -g2012 -o simulation/tb_hazard_detection.vvp \
    testbench/tb_hazard_detection.v \
    rtl/stages/hazard_detection.v \
    rtl/pipeline_registers/if_id_reg.v \
    rtl/pipeline_registers/id_ex_reg.v
vvp simulation/tb_hazard_detection.vvp

# Hazard unit alias verification test
iverilog -g2012 -o simulation/tb_hazard_unit.vvp \
    testbench/tb_hazard_unit.v \
    rtl/stages/hazard_unit.v \
    rtl/stages/hazard_detection.v
vvp simulation/tb_hazard_unit.vvp
```

#### 6. Forwarding & Operand Bypass Tests
```bash
# EX-stage forwarding unit and datapath integration test
iverilog -g2012 -o simulation/tb_forwarding_unit.vvp \
    testbench/tb_forwarding_unit.v \
    rtl/stages/forwarding_unit.v \
    rtl/stages/ex_stage.v \
    rtl/stages/alu.v \
    rtl/stages/alu_control.v \
    rtl/stages/branch_unit.v
vvp simulation/tb_forwarding_unit.vvp

# Forwarding unit alias verification test
iverilog -g2012 -o simulation/tb_forwarding.vvp \
    testbench/tb_forwarding.v \
    rtl/stages/forwarding.v \
    rtl/stages/forwarding_unit.v
vvp simulation/tb_forwarding.vvp
```

#### 7. Branch Redirection & Hazard Coordination Tests
```bash
# Branch redirect, pipeline flush, and hazard coordination integration test
iverilog -g2012 -o simulation/tb_branch_controller.vvp \
    testbench/tb_branch_controller.v \
    rtl/stages/branch_controller.v \
    rtl/stages/branch_hazard_coordinator.v \
    rtl/pipeline_registers/if_id_reg.v \
    rtl/stages/id_stage.v \
    rtl/stages/instruction_decoder.v \
    rtl/stages/register_file.v \
    rtl/stages/main_control.v \
    rtl/pipeline_registers/id_ex_reg.v \
    rtl/stages/forwarding_unit.v \
    rtl/stages/ex_stage.v \
    rtl/stages/alu.v \
    rtl/stages/alu_control.v \
    rtl/stages/branch_unit.v \
    rtl/pipeline_registers/ex_mem_reg.v \
    rtl/pipeline_registers/mem_wb_reg.v \
    rtl/stages/hazard_detection.v
vvp simulation/tb_branch_controller.vvp

# Branch hazard coordinator alias verification test
iverilog -g2012 -o simulation/tb_branch_hazard_coordinator.vvp \
    testbench/tb_branch_hazard_coordinator.v \
    rtl/stages/branch_hazard_coordinator.v \
    rtl/stages/branch_controller.v
vvp simulation/tb_branch_hazard_coordinator.vvp
```

#### 8. Top-Level Pipelined CPU Integration Tests
```bash
# Top-level pipelined CPU integration testbench
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
    rtl/stages/branch_controller.v
vvp simulation/tb_cpu.vvp

# Top-level wrapper alias verification test
iverilog -g2012 -o simulation/tb_top.vvp \
    testbench/tb_top.v \
    rtl/top.v \
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
vvp simulation/tb_top.vvp
```

### Viewing Waveforms
If a testbench generates a `.vcd` dump, view it with GTKWave:
```bash
gtkwave simulation/<dump_name>.vcd
```

---

## 6. Project Demonstration Video

A comprehensive video presentation and walkthrough demonstrating the 5-stage pipelined processor architecture, hazard handling, branch resolution, testbench suites, and waveform evidence in GTKWave is available:

- **Google Drive Video Folder:** [Team Scaler MCA Project Demo Video](https://drive.google.com/drive/folders/1EgOdLGRiIbfGNEMWvCw3mpRqaSgrbESI?usp=sharing)
- **Direct URL:** `https://drive.google.com/drive/folders/1EgOdLGRiIbfGNEMWvCw3mpRqaSgrbESI?usp=sharing`
- **Documentation & Details:** [`video/README.md`](video/README.md)

---

## 7. Collaboration Workflow

All contributors follow the process outlined in [`CONTRIBUTING.md`](CONTRIBUTING.md):
1. **Branch per Issue:** Create a branch for every issue from the latest `main` (`feature/issue-<num>-<desc>`, `fix/issue-...`, `docs/issue-...`).
2. **Never Commit Directly to `main`:** All additions must arrive via a Pull Request.
3. **Issue Linking:** Use `Closes #<issue-number>` when a PR completes an issue.
4. **Review & Approval:** Request review from repository owner (`WizardCarp85`). Only the owner merges approved PRs.
