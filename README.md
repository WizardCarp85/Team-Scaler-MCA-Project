# Team Scaler MCA Project

A 5-stage pipelined RISC-V (RV32I subset) processor implemented in Verilog, targeting modular simulation with Icarus Verilog and waveform analysis in GTKWave.

---

## 1. Project Overview

This project implements a classic 5-stage RISC-V pipeline (**IF**, **ID**, **EX**, **MEM**, **WB**) supporting core integer arithmetic, memory access, and branch instructions. The design emphasizes modularity, clean pipeline interfaces, robust hazard handling capabilities (forwarding, stalls, flushes), and verifiable stage-by-stage progression.

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
[ Milestone 1: IF Stage ] ──► [ Milestone 2: ID Stage ] ──► [ Milestone 3: EX Stage ] ──► [ M4: MEM ] ──► [ M5: Integration ]
        (Completed)                   (Completed)                   (Completed)              (Upcoming)         (Upcoming)
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
- [ ] **Milestone 4: Memory (MEM) Stage & MEM/WB Register (Upcoming)**
  - Data memory module with synchronous write and combinational/synchronous read.
  - MEM stage datapath and MEM/WB pipeline register.
- [ ] **Milestone 5: Write-Back (WB), Hazard Detection & Full Pipeline Integration (Upcoming)**
  - Forwarding unit (EX-to-EX, MEM-to-EX) and load-use hazard stall unit.
  - Branch misprediction flush unit and full top-level CPU integration.
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
│   └── ex_mem_interface.md          # EX/MEM pipeline register specification
├── programs/
│   ├── README.md                    # Hex test image documentation
│   └── if_test.hex                  # Instruction image for fetch testing
├── reports/                         # Performance reports and simulation analysis (M6)
├── rtl/
│   ├── common/                      # Shared parameters and constants
│   ├── pipeline_registers/
│   │   ├── if_id_reg.v              # IF/ID boundary register
│   │   ├── id_ex_reg.v              # ID/EX boundary register
│   │   └── ex_mem_reg.v             # EX/MEM boundary register
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
│       └── ex_stage.v               # EX stage top wrapper
├── simulation/                      # Simulation binaries and VCD waveform output
├── testbench/
│   ├── fixtures/                    # Test hex programs and fixtures
│   ├── tb_alu.v                     # ALU testbench
│   ├── tb_alu_control.v             # ALU control testbench
│   ├── tb_branch_unit.v             # Branch unit testbench
│   ├── tb_ex_stage.v                # EX stage datapath & forwarding testbench
│   ├── tb_ex_mem_reg.v              # EX/MEM pipeline register testbench
│   ├── tb_fetch.v                   # Instruction fetch integration testbench
│   ├── tb_id_stage.v                # ID stage integration testbench
│   ├── tb_id_ex_reg.v               # ID/EX pipeline register testbench
│   ├── tb_if_stage.v                # IF stage wrapper testbench
│   ├── tb_if_id_reg.v               # IF/ID pipeline register testbench
│   ├── tb_instruction_decoder.v     # Instruction decoder testbench
│   ├── tb_main_control.v            # Main control unit testbench
│   ├── tb_pc_instr_mem.v            # PC & instruction memory testbench
│   └── tb_register_file.v           # Register file testbench
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

### Viewing Waveforms
If a testbench generates a `.vcd` dump, view it with GTKWave:
```bash
gtkwave simulation/<dump_name>.vcd
```

---

## 6. Collaboration Workflow

All contributors follow the process outlined in [`CONTRIBUTING.md`](CONTRIBUTING.md):
1. **Branch per Issue:** Create a branch for every issue from the latest `main` (`feature/issue-<num>-<desc>`, `fix/issue-...`, `docs/issue-...`).
2. **Never Commit Directly to `main`:** All additions must arrive via a Pull Request.
3. **Issue Linking:** Use `Closes #<issue-number>` when a PR completes an issue.
4. **Review & Approval:** Request review from repository owner (`WizardCarp85`). Only the owner merges approved PRs.
