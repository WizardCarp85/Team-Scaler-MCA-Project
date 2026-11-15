# Execute (EX) Stage Module Documentation

**Project:** Team Scaler MCA Project — 5-Stage Pipelined RV32I Processor
**Author:** M3 (Execute Stage Developer & Documentation Lead)
**Status:** Implemented & Verified in Simulation (Milestone 3 / Issues #12–#16, PRs #39–#43)
**Related Issue:** #48 (IEEE-Format Project Report & Milestone Documentation)
**Target Location:** `docs/module-documentation/execute.md`

---

## 1. Overview & Purpose of the Execute Stage

In the classic RISC five-stage pipeline (**IF** $\rightarrow$ **ID** $\rightarrow$ **EX** $\rightarrow$ **MEM** $\rightarrow$ **WB**), the **Execution (EX)** stage serves as the computational heart of the processor. Situated between the Instruction Decode (ID) and Memory Access (MEM) stages, the EX stage transforms decoded operands into concrete operational results.

```
┌─────────────┐       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│  IF: Fetch  │ ──►   │ ID: Decode  │ ──►   │ EX: Execute │ ──►   │ MEM: Memory │ ──►   │  WB: Write  │
│             │       │             │       │  [THIS DOC] │       │             │       │    Back     │
└─────────────┘       └─────────────┘       └─────────────┘       └─────────────┘       └─────────────┘
      ▲                      ▲                     ▲                     ▲                     ▲
  (if_stage)             (id_stage)           (ex_stage)            (Upcoming)            (Upcoming)
      │                      │                     │                     │                     │
  [IF/ID Reg]            [ID/EX Reg]          [EX/MEM Reg]          [MEM/WB Reg]               │
```

### Primary Roles of the EX Stage in this RV32I Core
1. **Arithmetic & Logic Computations:** Performs 32-bit addition and subtraction for register-register instructions (`add`, `sub`) and immediate arithmetic (`addi`).
2. **Memory Effective Address Generation:** Computes the byte address for data memory access (`lw`, `sw`) by adding the base register value to the sign-extended 12-bit immediate offset ($rs1 + \text{offset}$).
3. **Branch Condition & Target Calculation:** Evaluates conditional branch tests (`beq`, `bne`) using forwarded register values and simultaneously computes the branch target address as $PC + \text{immediate}$.
4. **Data Forwarding Multiplexing:** Incorporates 3-to-1 operand forwarding multiplexers on both source paths ($rs1$ and $rs2$) to ingest forwarded data from the `EX/MEM` and `MEM/WB` pipeline boundaries, resolving Read-After-Write (RAW) data hazards without stalling when the result is already computed.
5. **Decoupled Store Data Path:** Preserves the forwarded $rs2$ data as the write payload for store instructions (`sw`), keeping it distinct from the ALU's second operand, which consumes the immediate offset to compute the memory address.
6. **Side-Effect Control Gating:** Inspects the incoming instruction validity flag (`valid_in`). When an invalid instruction or pipeline bubble is detected (`valid_in == 0`), all downstream side-effect controls (`mem_read`, `mem_write`, `reg_write`, `branch_taken`) are suppressed to `0`.
7. **Boundary Registration:** Latches execution results, store data, destination register indices, and memory/write-back control signals into the synchronous `ex_mem_reg` pipeline register on each rising clock edge.

---

## 2. Execution Stage Datapath Architecture

The EX stage datapath is encapsulated within the structural wrapper module `ex_stage.v`. It coordinates three dedicated combinational submodules (`alu_control`, `alu`, `branch_unit`) and interfaces with the `id_ex_reg` register on input and `ex_mem_reg` register on output.

```
                             EX STAGE DATAPATH ARCHITECTURE

    ========================= INPUTS FROM ID/EX REGISTER =========================
    pc_in, pc_plus4_in, rs1_data_in, rs2_data_in, imm_in, rs1_in, rs2_in, rd_in,
    funct3_in, funct7_in, alu_op_in, branch_type_in, alu_src_imm_in, controls, valid_in
    ==============================================================================
                                     │
      ┌──────────────────────────────┼──────────────────────────────┐
      │                              │                              │
      │   forward_a [1:0]            │   forward_b [1:0]            │
      │   (From M5 Hazard Unit)      │   (From M5 Hazard Unit)      │
      │         │                    │         │                    │
      │         ▼                    │         ▼                    │
      │    ┌─────────┐               │    ┌─────────┐               │
      │    │  MUX A  │◄─ forward_mem │    │  MUX B  │◄─ forward_mem │
      │    │ (3-to-1)│◄─ forward_wb  │    │ (3-to-1)│◄─ forward_wb  │
      │    └────┬────┘               │    └────┬────┘               │
      │         │                    │         │                    │
      │    fwd_rs1_data              │    fwd_rs2_data              │
      │         │                    │         ├────────────────────┼──────► store_data
      │         │                    │         │                    │       (To EX/MEM)
      │         │                    │         │   alu_src_imm_in   │
      │         │                    │         │         │          │
      │         │                    │         ▼         ▼          │
      │         │                    │    ┌──────────────────┐      │
      │         │                    │    │   ALU SRC B MUX   │◄─────┼──────  imm_in
      │         │                    │    │      (2-to-1)    │      │
      │         │                    │    └────────┬─────────┘      │
      │         │                    │             │                │
      │         ▼                    │             ▼                │
      │    alu_operand_a             │        alu_operand_b         │
      │         │                    │             │                │
      │         └──────────┐         │         ┌───┘                │
      │                    │         │         │                    │
      │  funct3 ──┐        ▼         │         ▼                    │
      │  funct7 ──┼──►┌─────────┐    │    ┌─────────┐               │
      │  alu_op ──┘   │   ALU   │    │    │         │               │
      │               │ CONTROL │───►│───►│   ALU   │───────────────┼──────► alu_result
      │               │ decoder │    │    │         │               │       (To EX/MEM)
      │               └─────────┘    │    └─────────┘               │
      │                 alu_ctrl     │                              │
      │                  (4-bit)     │                              │
      │                              │                              │
      │   fwd_rs1_data ──────────────┼──────────┐                   │
      │   fwd_rs2_data ──────────────┼──────┐   │                   │
      │   pc_in ─────────────────────┼──┐   │   │                   │
      │   imm_in ────────────────────┼┐ │   │   │                   │
      │   branch_type ───────────────┼┼─┼───┼───┼──┐                │
      │   valid_in ──────────────────┼┼─┼───┼───┼──┼──┐             │
      │                              ││ │   │   │  │  │             │
      │                              ▼▼ ▼   ▼   ▼  ▼  ▼             │
      │                         ┌───────────────────────┐           │
      │                         │      BRANCH UNIT      │───────────┼──────► branch_taken
      │                         │  (BEQ, BNE, Target)   │           │        (To IF & M5)
      │                         └───────────┬───────────┘           │
      │                                     │                       │
      │                                     └───────────────────────┼──────► branch_target
      │                                                             │        (To IF Stage)
      │                                                             │
      │  Control Signals & Metadata Gating                          │
      │  (mem_read, mem_write, reg_write, wb_from_mem, valid, rd)   │
      └─────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
                     ================================
                     TO EX/MEM PIPELINE REGISTER & M5
                     ================================
```

---

## 3. M3 Module Breakdown & Responsibilities

Milestone 3 comprises five core Verilog modules located under `rtl/`:

| Module Name | File Path | Type | Primary Responsibilities |
|---|---|---|---|
| `alu` | `rtl/stages/alu.v` | Combinational | Executes 32-bit two's-complement arithmetic (ADD, SUB); evaluates equality (`equal`) and zero (`zero`) flags; safely defaults to zero on unused codes. |
| `alu_control` | `rtl/stages/alu_control.v` | Combinational | Translates the 2-bit `alu_op` instruction class from ID and the instruction `funct3`/`funct7` fields into a 4-bit `alu_ctrl` operation code for the ALU. |
| `branch_unit` | `rtl/stages/branch_unit.v` | Combinational | Tests branch conditions for BEQ and BNE using forwarded source operands; computes branch target addresses ($PC + \text{imm}$); suppresses `branch_taken` when `valid=0`. |
| `ex_stage` | `rtl/stages/ex_stage.v` | Structural Wrapper | Connects forwarding multiplexers, ALU operand selection, submodules, side-effect gating, and pass-through metadata into a unified stage datapath. |
| `ex_mem_reg` | `rtl/pipeline_registers/ex_mem_reg.v` | Synchronous Sequential | Pipeline boundary register capturing `alu_result`, `store_data`, destination register `rd`, PC metadata, and control signals on rising clock edge with synchronous reset, flush, and hold support. |

---

## 4. Arithmetic Logic Unit (`alu`)

The ALU (`rtl/stages/alu.v`) is a purely combinational 32-bit execution unit supporting the core RV32I integer instruction set.

### 4.1 Operation Encodings
The module defines operation codes as 4-bit parameters shared with `alu_control`:

```verilog
parameter [3:0] ALU_ADD = 4'b0000;
parameter [3:0] ALU_SUB = 4'b0001;
```

| Operation Code | Name | Arithmetic Equation | Used By Instructions |
|---|---|---|---|
| `4'b0000` | `ALU_ADD` | $\text{result} = a + b$ | `add` ($rs1 + rs2$)<br>`addi` ($rs1 + \text{imm}$)<br>`lw` ($rs1 + \text{offset}$ address)<br>`sw` ($rs1 + \text{offset}$ address) |
| `4'b0001` | `ALU_SUB` | $\text{result} = a - b$ | `sub` ($rs1 - rs2$) |
| `4'b0010`–`4'b1111` | Reserved | $\text{result} = 32\text{'h0000\_0000}$ | Unused operation codes safely default to zero. |

### 4.2 Status Flags
The ALU produces two independent single-bit status flags:

1. **Equality Flag (`equal`):**
   ```verilog
   assign equal = (a == b);
   ```
   Asserted high (`1'b1`) when operand $a$ is bitwise identical to operand $b$, regardless of the operation performed by `alu_ctrl`. This allows independent equality comparisons without requiring an explicit subtraction. Branch policy evaluation (e.g., whether equality means taken or not taken) remains outside the ALU inside `branch_unit`.

2. **Zero Flag (`zero`):**
   ```verilog
   assign zero = (result == 32'd0);
   ```
   Asserted high (`1'b1`) when the computed 32-bit `result` is all zeros.

> **Important Distinction:** The `equal` and `zero` flags are independent:
> - For $a = 50$, $b = -50$ with `ALU_ADD`: $\text{result} = 0 \implies \text{zero} = 1$, but $a \neq b \implies \text{equal} = 0$.
> - For $a = 42$, $b = 42$ with `ALU_ADD`: $\text{result} = 84 \implies \text{zero} = 0$, but $a == b \implies \text{equal} = 1$.

### 4.3 Two's-Complement Arithmetic & Overflow Handling
In compliance with the RISC-V RV32I base integer specification:
- All 32-bit arithmetic operations ignore overflow and underflow.
- Results wrap modulo $2^{32}$ into the 32-bit output register.
- For example, adding $1$ to `32'h7FFFFFFF` (maximum signed positive 32-bit integer) yields `32'h80000000` without generating a processor exception or trap.

### 4.4 Deterministic Default Behavior
Any unmapped operation code (`4'b0010` through `4'b1111`) defaults strictly and deterministically to `result = 32'd0`. Under no circumstances will an unmapped or noisy control code trigger an accidental subtraction or corrupt downstream memory addresses.

---

## 5. ALU Control Decoder (`alu_control`)

The ALU control decoder (`rtl/stages/alu_control.v`) translates the coarse 2-bit `alu_op` classification generated by ID-stage `main_control` along with the instruction's `funct3` and `funct7` fields into the 4-bit `alu_ctrl` signal needed by the ALU.

### 5.1 Decoding Truth Table

| `alu_op` | `funct3` | `funct7` | Target Instruction | Output `alu_ctrl` | Operational Meaning |
|---|---|---|---|---|---|
| `2'b00` | `3'bxxx` | `7'bxxxxxxx` | `addi`, `lw`, `sw` | `4'b0000` (`ALU_ADD`) | Immediate addition / Effective address calculation |
| `2'b01` | `3'b000` | `7'h00` | `add` | `4'b0000` (`ALU_ADD`) | Register-register addition ($rs1 + rs2$) |
| `2'b01` | `3'b000` | `7'h20` | `sub` | `4'b0001` (`ALU_SUB`) | Register-register subtraction ($rs1 - rs2$) |
| `2'b01` | Other | Other | Unsupported R-type | `4'b0000` (`ALU_ADD`) | Safe default; never selects `ALU_SUB` |
| `2'b10` | `3'bxxx` | `7'bxxxxxxx` | `beq`, `bne` | `4'b0000` (`ALU_ADD`) | Branch comparison class; safe default |
| `2'b11` | `3'bxxx` | `7'bxxxxxxx` | Unused / Reserved | `4'b0000` (`ALU_ADD`) | Reserved class; safe default |

### 5.2 Crucial Disambiguation: Immediate vs. Funct Fields
In non-R-type instruction formats, the bit positions corresponding to `funct7` (`instr[31:25]`) and `funct3` (`instr[14:12]`) carry immediate bits or format specifiers rather than an arithmetic operation code:
- In `addi` and `lw`, bits `[31:20]` form the 12-bit signed immediate.
- In `sw`, bits `[31:25]` form `imm[11:5]`.

If an immediate value happens to have bit 5 set (e.g., immediate offset `0x20` or negative immediate `0xFE0`), the raw bits in the `funct7` position would equal `7'h20`. If the decoder checked `funct7` without first checking `alu_op`, it would mistakenly trigger a subtraction!

**Implementation Safety:**
When `alu_op == 2'b00`, the decoder unconditionally outputs `ALU_ADD`, ignoring `funct7` and `funct3` entirely. An immediate offset with bit patterns matching `7'h20` is guaranteed never to cause an accidental subtraction during address calculations.

### 5.3 Safe Default Policy & Architectural Caveats
Any unhandled R-type `funct` pattern or reserved `alu_op` defaults to `ALU_ADD`. Defaulting to `ALU_ADD` ensures predictable datapath behavior and prevents spurious subtractions.

> **Architectural Precaution:** A default `ALU_ADD` operation alone does **not** prevent memory or register corruption if an invalid instruction enters the pipeline. True side-effect prevention is achieved by gating control signals (`mem_write`, `reg_write`) with the pipeline validity bit (`valid_in`).

---

## 6. Branch Unit (`branch_unit`)

The branch unit (`rtl/stages/branch_unit.v`) is a purely combinational module responsible for evaluating conditional branch outcomes and computing the branch target address in parallel with ALU execution.

### 6.1 Branch Condition Evaluation
The module supports the RV32I B-type conditional branches:

```verilog
parameter [1:0] BRANCH_NONE = 2'b00;
parameter [1:0] BRANCH_BEQ  = 2'b01;
parameter [1:0] BRANCH_BNE  = 2'b10;
```

Branch condition logic operates directly on the forwarded operands (`op_a = fwd_rs1_data`, `op_b = fwd_rs2_data`):
- **BEQ (`2'b01`):** `branch_taken = (op_a == op_b)`
- **BNE (`2'b10`):** `branch_taken = (op_a != op_b)`
- **BRANCH_NONE (`2'b00`) or Reserved (`2'b11`):** `branch_taken = 1'b0`

### 6.2 Target Address Calculation ($PC + \text{immediate}$)
The branch target is calculated as:
$$\text{branch\_target} = PC + \text{imm}$$

Two critical design details in this processor's architecture:
1. **$PC$, not $PC+4$, is the base:** Branch offsets in RISC-V are relative to the address of the branch instruction itself ($PC$), not the sequential next address ($PC+4$).
2. **Immediate is already a byte offset:** In this processor's decode stage (`instruction_decoder.v`), B-type immediates are extracted and formatted with the least significant bit ($0$) already included as a 32-bit sign-extended byte offset. The branch unit does **not** shift the immediate (`imm << 1`); it performs direct 32-bit addition with wrapping modulo $2^{32}$.

### 6.3 Inactive & Bubble Behavior
- `branch_target` continuously evaluates $PC + \text{imm}$. Downstream redirect logic in IF/ID and M5 only branches when `branch_taken == 1`.
- When `valid == 0` (indicating an empty pipeline bubble or flushed instruction), `branch_taken` is forced strictly to `1'b0`. This guarantees that an invalid instruction cannot trigger a false branch redirect.
- **Architectural Scope:** The `branch_unit` does not update the PC register directly and does not clear pipeline registers; PC redirection and pipeline flushing are handled by top-level hazard control (Milestone 5).

---

## 7. Forwarding Multiplexers & Operand Selection

To prevent data hazards caused by Read-After-Write (RAW) register dependencies, the EX stage datapath incorporates dual 3-to-1 forwarding multiplexers.

### 7.1 Forwarding Selector Encodings
The EX stage provides two 2-bit selectors (`forward_a`, `forward_b`) controlled by the hazard/forwarding logic:

| Selector Value | Parameter Name | Forwarded Source | Description |
|---|---|---|---|
| `2'b00` | `FWD_ID_EX` | ID/EX Register | Default path; uses register operand read during ID stage (no hazard). |
| `2'b01` | `FWD_MEM_WB` | MEM/WB Boundary | Forwards write-back data from the instruction two cycles ahead. |
| `2'b10` | `FWD_EX_MEM` | EX/MEM Boundary | Forwards execution result from the instruction one cycle ahead. |
| `2'b11` | Reserved | ID/EX Register | Safely defaults to unforwarded ID/EX register value. |

```verilog
always @* begin
    case (forward_a)
        FWD_EX_MEM: fwd_rs1_data = forward_mem_data;
        FWD_MEM_WB: fwd_rs1_data = forward_wb_data;
        default:    fwd_rs1_data = rs1_data_in;
    endcase
end

always @* begin
    case (forward_b)
        FWD_EX_MEM: fwd_rs2_data = forward_mem_data;
        FWD_MEM_WB: fwd_rs2_data = forward_wb_data;
        default:    fwd_rs2_data = rs2_data_in;
    endcase
end
```

### 7.2 ALU Operand Selection
- **ALU Operand A:** Always consumes the forwarded $rs1$ data:
  $$\text{alu\_operand\_a} = \text{fwd\_rs1\_data}$$
- **ALU Operand B:** Multiplexed by control signal `alu_src_imm_in`:
  $$\text{alu\_operand\_b} = \text{alu\_src\_imm\_in} \mathbin{?} \text{imm\_in} : \text{fwd\_rs2\_data}$$
  - For R-type instructions (`add`, `sub`): `alu_src_imm_in == 0` $\implies$ uses `fwd_rs2_data`.
  - For I-type / memory instructions (`addi`, `lw`, `sw`): `alu_src_imm_in == 1` $\implies$ uses `imm_in`.

### 7.3 Decoupled Store Data Path (`store_data`)
A common design trap in pipelined RISC architectures involves store instructions (`sw`). For a store instruction:
1. The ALU must calculate the memory address: $\text{Address} = rs1 + \text{offset}$. Hence, `alu_src_imm_in = 1`, directing `imm_in` into the ALU's second operand.
2. The data to be stored into memory resides in $rs2$. If an immediately preceding instruction wrote to $rs2$, that value must be forwarded!

In `ex_stage.v`, the store data output is tapped directly from the output of Forwarding MUX B:
```verilog
assign store_data = fwd_rs2_data;
```
This guarantees that `store_data` always receives the freshest forwarded $rs2$ value, completely decoupled from the ALU's immediate operand selection.

### 7.4 Branch Unit Forwarding
The branch comparison inputs inside `branch_unit` connect directly to `fwd_rs1_data` and `fwd_rs2_data`. Consequently, branch decisions (`beq`, `bne`) evaluate against the freshest forwarded results without stalling, provided the producing instruction has already completed its EX stage.

---

## 8. EX/MEM Pipeline Register (`ex_mem_reg`)

The `ex_mem_reg` module (`rtl/pipeline_registers/ex_mem_reg.v`) forms the synchronous pipeline boundary between the EX and MEM stages.

### 8.1 Registered Fields (138-bit Bundle)
The register latches an aggregate payload of 138 bits on each rising clock edge:

| Field Name | Width | Consumer Stage | Functional Meaning |
|---|---:|---|---|
| `alu_result` | 32 bits | MEM & WB | Memory address for `lw`/`sw`, or computation result for register write-back and EX/MEM forwarding. |
| `store_data` | 32 bits | MEM Stage | Forwarded $rs2$ data payload to be written into data memory by `sw`. |
| `rd` | 5 bits | MEM & WB | Destination register index for write-back and forwarding comparisons. |
| `pc` | 32 bits | Pipeline / Debug | Program counter of the active instruction. |
| `pc_plus4` | 32 bits | Pipeline / Debug | Sequential return address ($PC + 4$). |
| `mem_read` | 1 bit | MEM Stage | Data memory read enable flag (`lw`). |
| `mem_write` | 1 bit | MEM Stage | Data memory write enable flag (`sw`). |
| `reg_write` | 1 bit | WB Stage | Register file write enable flag. |
| `wb_from_mem` | 1 bit | WB Stage | Write-back source multiplexer select ($1 = \text{load data from memory}$, $0 = \text{ALU result}$). |
| `valid` | 1 bit | Pipeline Control | Validity flag ($1 = \text{valid live instruction}$, $0 = \text{bubble/cleared}$). |

#### Signals Deliberately Excluded from EX/MEM
- `branch_taken` and `branch_target`: Routed combinational to the IF stage (PC multiplexer) and M5 hazard unit for immediate redirect and pipeline flush; they do not propagate down the sequential pipeline to MEM.
- `rs1` and `rs2`: Exposed by `ex_stage` exclusively for M5 EX-stage forwarding comparisons; downstream stages only require the destination register `rd`.

### 8.2 Clock Edge Priority & Control Semantics
On each rising clock edge (`posedge clk`), the register updates according to a strict priority hierarchy:

```verilog
always @(posedge clk) begin
    if (rst || flush || (en && !valid_in)) begin
        // Priority 1 & 3: Clear entire bundle to 0
        alu_result_out  <= 32'd0;
        store_data_out  <= 32'd0;
        rd_out          <= 5'd0;
        pc_out          <= 32'd0;
        pc_plus4_out    <= 32'd0;
        mem_read_out    <= 1'b0;
        mem_write_out   <= 1'b0;
        reg_write_out   <= 1'b0;
        wb_from_mem_out <= 1'b0;
        valid_out       <= 1'b0;
    end else if (en) begin
        // Priority 4: Active capture of live instruction bundle
        alu_result_out  <= alu_result_in;
        store_data_out  <= store_data_in;
        rd_out          <= rd_in;
        pc_out          <= pc_in;
        pc_plus4_out    <= pc_plus4_in;
        mem_read_out    <= mem_read_in;
        mem_write_out   <= mem_write_in;
        reg_write_out   <= reg_write_in;
        wb_from_mem_out <= wb_from_mem_in;
        valid_out       <= valid_in;
    end
    // Priority 2: When en == 0 (and !rst && !flush), retain existing state
end
```

1. **Synchronous Reset & Flush (`rst || flush`):** Highest priority. Clears the entire 138-bit bundle to all zeros. A flush beats a hold (`flush` clears even when `en == 0`).
2. **Hold (`en == 0`):** Second priority. When `en == 0` and neither `rst` nor `flush` is asserted, all register outputs retain their previous cycle values.
3. **Hold Priority over Bubble (`en == 0 && valid_in == 0`):** If the register is held (`en == 0`), it retains its current valid contents even if `valid_in == 0` appears on its inputs.
4. **Bubble Capture (`en == 1 && valid_in == 0`):** When capture is enabled but the incoming instruction is invalid (`valid_in == 0`), the register clears all outputs to zero, guaranteeing that bubbles carry no active memory or register write enables.
5. **Active Capture (`en == 1 && valid_in == 1`):** Latches the active inputs into the registered outputs.

For full interface timing and signal contracts, refer to the interface specification at [`docs/ex_mem_interface.md`](../ex_mem_interface.md).

---

## 9. Verification & Testbench Results

All Milestone 3 modules are accompanied by self-checking Verilog testbenches verified using **Icarus Verilog (`iverilog`)** and the **`vvp` runtime engine**.

### 9.1 Simulation Commands
Run all testbenches from the root of the repository:

```bash
# 1. ALU Testbench
iverilog -g2012 -o simulation/tb_alu.vvp testbench/tb_alu.v rtl/stages/alu.v
vvp simulation/tb_alu.vvp

# 2. ALU Control Decoder Testbench
iverilog -g2012 -o simulation/tb_alu_control.vvp testbench/tb_alu_control.v \
    rtl/stages/alu_control.v
vvp simulation/tb_alu_control.vvp

# 3. Branch Unit Testbench
iverilog -g2012 -o simulation/tb_branch_unit.vvp testbench/tb_branch_unit.v \
    rtl/stages/branch_unit.v
vvp simulation/tb_branch_unit.vvp

# 4. EX Stage Datapath Integration Testbench
iverilog -g2012 -o simulation/tb_ex_stage.vvp testbench/tb_ex_stage.v \
    rtl/stages/ex_stage.v rtl/stages/alu.v rtl/stages/alu_control.v \
    rtl/stages/branch_unit.v
vvp simulation/tb_ex_stage.vvp

# 5. EX/MEM Pipeline Register Testbench
iverilog -g2012 -o simulation/tb_ex_mem_reg.vvp testbench/tb_ex_mem_reg.v \
    rtl/pipeline_registers/ex_mem_reg.v
vvp simulation/tb_ex_mem_reg.vvp
```

### 9.2 Actual Execution Output
All five testbenches execute to completion with zero errors:

```text
PASS: all 80 ALU tests completed successfully
testbench/tb_alu.v:170: $finish called at 80000 (1ps)

PASS: all 45 ALU control decoder tests completed successfully
testbench/tb_alu_control.v:130: $finish called at 45000 (1ps)

PASS: all 36 branch unit tests completed successfully
testbench/tb_branch_unit.v:194: $finish called at 36000 (1ps)

PASS: all 18 EX stage datapath tests completed successfully
testbench/tb_ex_stage.v:331: $finish called at 18000 (1ps)

PASS: all 430 EX/MEM pipeline register tests completed successfully
testbench/tb_ex_mem_reg.v:234: $finish called at 1290000 (1ps)
```

### 9.3 Test Coverage Summary Table

| Testbench | Module Under Test | Tests Run | Result | Key Test Scenarios Covered |
|---|---|---:|:---:|---|
| `tb_alu.v` | `alu` | 80 | **PASS** | Positive/negative addition and subtraction; signed overflow and underflow wrap-around; carry-out discard; independent `equal` and `zero` flag verification; safe zero output across all 14 unused operation codes (`4'b0010`–`4'b1111`). |
| `tb_alu_control.v` | `alu_control` | 45 | **PASS** | R-type ADD/SUB decoding; non-R-type immediate offset safety (`alu_op=00` never selects SUB even when `funct7=7'h20`); unsupported R-type funct safety fallback; BEQ/BNE branch mapping; reserved `alu_op=11` safe default. |
| `tb_branch_unit.v` | `branch_unit` | 36 | **PASS** | BEQ taken (equal) and not taken (unequal); BNE taken (unequal) and not taken (equal); positive, negative, and zero immediate offsets; verification that base is $PC$ (not $PC+4$); verification that immediate byte offset is unshifted; 32-bit address wraparound; suppression of `branch_taken` when `valid=0`. |
| `tb_ex_stage.v` | `ex_stage` | 18 | **PASS** | Structural datapath integration; R-type ADD and SUB execution; ADDI arithmetic; LW address generation; SW address calculation with forwarded store data; single and simultaneous forwarding on operands A and B; BEQ/BNE branch condition evaluation with forwarded operands; metadata pass-through; bubble control gating when `valid_in=0`. |
| `tb_ex_mem_reg.v` | `ex_mem_reg` | 430 | **PASS** | Synchronous reset clears all fields; consecutive capture of ALU, SW, and LW instruction bundles; hold (`en=0`) persistence over multiple cycles; flush (`flush=1`) clears bundle; flush and reset priority over hold (`en=0`); invalid-input bubble capture; hold priority over invalid bubble; exhaustive 138-bit walking-bit capture, hold, and flush test. |

---

## 10. Current Limitations & Downstream Integration Dependencies

While Milestone 3 is fully implemented and verified at the module and stage level, several critical integration dependencies and architectural limitations must be understood:

### 10.1 Forwarding Multiplexers vs. Forwarding Detection Logic
- **Implemented in M3:** The 3-to-1 data multiplexers inside `ex_stage.v` that switch between ID/EX operands, EX/MEM forwarded data, and MEM/WB forwarded data are fully implemented and verified.
- **Pending in M5:** The **hazard detection and forwarding unit** (Milestone 5, Issue #24) that compares source registers ($rs1$, $rs2$) against destination registers ($rd$) and asserts the `forward_a` and `forward_b` selector codes is **not yet integrated**.

### 10.2 Load-Use Data Hazards & Address vs. Data Latency
- In a load instruction (`lw`), the value computed during the EX stage (`alu_result`) is the **memory effective address**, **not** the loaded data.
- The actual data value from memory is not available until the end of the Memory (MEM) stage (Milestone 4).
- **Hazard Implication:** An instruction immediately following `lw` that depends on the loaded register cannot receive its operand via EX-to-EX forwarding. A 1-cycle hardware pipeline stall (load-use hazard interlock, Milestone 5, Issue #22) is strictly required to hold the dependent instruction in ID/EX until the load data advances to MEM/WB.

### 10.3 Memory Re-execution Prevention during Stalls
- If a downstream stall occurs and `ex_mem_reg` is held (`en == 0`), control signals `mem_read_out` and `mem_write_out` will remain asserted.
- **Coordination with M4:** The Memory stage (Issue #18) must coordinate with top-level stall logic to ensure that a held memory operation is executed only once and not re-executed repeatedly on each stalled clock cycle.

### 10.4 Branch Redirection and Younger Stage Flushing
- When a branch is evaluated as taken (`branch_taken == 1`), `branch_unit` outputs the target address to the IF stage PC multiplexer.
- However, the instructions currently in the IF/ID and ID/EX pipeline registers represent mispredicted instructions that must be converted into bubbles (`flush = 1`).
- **Coordination with M5:** Top-level branch flush coordination (Issue #25) must flush younger pipeline registers (IF/ID and ID/EX) while protecting older in-flight instructions advancing through EX/MEM and MEM/WB.

### 10.5 Status of Verification
- **Verified to Date:** Unit and stage-level simulation tests for Milestones 1, 2, and 3 (IF, ID, and EX stages).
- **Not Yet Verified:** Complete 5-stage CPU top-level integration, end-to-end assembly program execution, CPI/IPC analysis, and FPGA synthesis. These remain pending implementation of Milestones 4 and 5.
