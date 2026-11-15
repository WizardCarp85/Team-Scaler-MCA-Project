# Execution (EX) Stage Module Documentation

**Project:** Team Scaler MCA Project — 5-Stage Pipelined RV32I Processor  
**Author / Milestone:** Milestone 3 (M3) — Execution Stage Datapath & Pipeline Register  
**Related Issue:** Issue #48 (Project Documentation & Report Preparation)  
**Status:** M3 modules are implemented, verified with standalone Icarus Verilog simulation, and merged onto `main`. Full-core inter-stage connections and coordination with M4 (Memory) and M5 (Forwarding/Hazard Unit) represent **proposed integration interfaces pending team confirmation and verification**.

---

## 1. Purpose and Role of the Execute (EX) Stage

In a classic 5-stage RISC-V pipelined processor (**IF** $\rightarrow$ **ID** $\rightarrow$ **EX** $\rightarrow$ **MEM** $\rightarrow$ **WB**), the **Execution (EX) stage** is the computational heart of the datapath. Sitting between the Instruction Decode (ID) stage and the Memory Access (MEM) stage, its primary responsibilities include:

1. **Arithmetic & Logical Evaluation**: Computing 32-bit results for register-register operations (`ADD`, `SUB`) and register-immediate operations (`ADDI`).
2. **Effective Memory Address Calculation**: Adding base register values to sign-extended immediate byte offsets (`rs1 + imm`) for load (`LW`) and store (`SW`) instructions.
3. **Branch Condition Evaluation & Target Generation**:
   - Evaluating branch equality/inequality conditions (`BEQ`, `BNE`) between source operands.
   - Calculating PC-relative branch target addresses (`PC + imm`).
4. **Data Hazard Resolution (Datapath Multiplexers)**: Providing 2-bit dual-operand forwarding multiplexers that select between unforwarded ID/EX register values, older results forwarded from the EX/MEM boundary, and write-back data forwarded from the MEM/WB boundary (proposed M5 forwarding scheme).
5. **Store Data Preservation**: Ensuring that for store instructions (`SW`), the ALU computes the memory address using the immediate while the store payload data (`rs2`) is independently forwarded and passed through to the memory stage.
6. **Side-Effect Gating & Pipeline Registration**: Suppressing control side-effects (`mem_read`, `mem_write`, `reg_write`, `branch_taken`) on pipeline bubbles (`valid = 0`) and registering active results into the `ex_mem_reg` boundary register.

---

## 2. EX-Stage Datapath Architecture

The following block diagram illustrates the datapath flow within `ex_stage.v`, showing its internal submodules, operand forwarding paths, and proposed integration boundaries with neighboring stages (ID/EX, EX/MEM, M4 data memory, and M5 hazard/forwarding logic):

```text
       ========================= EX STAGE DATAPATH =========================
       [Proposed Integration Interfaces with ID/EX, EX/MEM, M4, and M5]

  [Proposed Inputs from ID/EX Register]
    rs1_data_in ──┐
    rs2_data_in ──┼────────────────────────────────┐
    imm_in ───────┼──────────────┬─────────┐       │
    pc_in ────────┼──────────────┼─────────┼───────┼─────────────────────────┐
    controls ─────┼──────────────┼─────────┼───────┼──────────────────┐      │
                  │              │         │       │                  │      │
  [Proposed M5 Forwarding]       │         │       │                  │      │
    forward_a ────┼────────┐     │         │       │                  │      │
    forward_b ────┼────────┼─────┼─────────┼───────┼────────────┐     │      │
    forward data ─┼──┬─────┼─────┼─────────┼───────┼────────┐   │     │      │
                  ▼  ▼     ▼     │         │       │        ▼   ▼     ▼      │
               ┌─────────────┐   │         │       │     ┌─────────────┐     │
               │  FWD MUX A  │◄──┘         │       │     │  FWD MUX B  │◄────┘
               └──────┬──────┘             │       │     └──────┬──────┘
                      │                    │       │            │
        fwd_rs1_data  ├──────────────┐     │       │            ├────────────┐
                      │              │     │       │            │            │
                      ▼              │     │       │            │            ▼
                 ┌─────────┐         │     │       │            │      ┌────────────┐
                 │ ALU OpA │         │     │       │            │      │ store_data │
                 └────┬────┘         │     │       │            │      └─────┬──────┘
                      │              │     │       │            │            │ (bypasses
                      │              │     │       │            │            │  ALU mux)
                      │              │     │       │            ▼            │
                      │              │     │       │     ┌─────────────┐     │
                      │              │     │       └────►│ MUX (B/Imm) │◄────┘
                      │              │     │     alu_src │  (alu_src)  │ (fwd_rs2_data)
                      │              │     │             └──────┬──────┘
                      │              │     │                    │
                      │              │     │                    ▼
                      │              │     │               ┌─────────┐
                      │              │     │               │ ALU OpB │
                      │              │     │               └────┬────┘
                      │              │     │                    │
                      │              ▼     ▼                    ▼
                      │       ┌───────────────┐            ┌───────────┐
                      │       │  BRANCH_UNIT  │            │    ALU    │◄── alu_ctrl
                      │       │   (BEQ/BNE)   │            │ (ADD/SUB) │    (from alu_control)
                      │       └───────┬───────┘            └─────┬─────┘
                      │               │                          │
                      │               ├──► branch_taken          │ alu_result
                      │               └──► branch_target         │ (or memory address)
                      │                    [Proposed to IF / M5] │
                      ▼                                          ▼
  ─────────────────────────────────────────────────────────────────────────────
  [Proposed Outputs to EX/MEM Pipeline Register (Pending M4 / M5 Integration)]
    Bundle captures: alu_result, store_data, rd, pc, pc_plus4,
                     mem_read, mem_write, reg_write, wb_from_mem, valid
```

---

## 3. M3 Modules, File Paths, and Responsibilities

Milestone 3 consists of four core stage modules, one boundary register, their accompanying interface documents, and dedicated self-checking testbenches:

| Module Name | File Path | Scope / Responsibilities |
|---|---|---|
| `alu` | [`rtl/stages/alu.v`](../../rtl/stages/alu.v) | Purely combinational 32-bit ALU. Computes `ADD` and `SUB` results, provides `equal` and `zero` status flags, and defines safe zero-output default behavior for unused opcodes. |
| `alu_control` | [`rtl/stages/alu_control.v`](../../rtl/stages/alu_control.v) | Combinational control decoder translating ID/EX `alu_op`, `funct3`, and `funct7` into the 4-bit `alu_ctrl` consumed by `alu.v`. Ignores funct fields on immediate/address instructions. |
| `branch_unit` | [`rtl/stages/branch_unit.v`](../../rtl/stages/branch_unit.v) | Combinational branch evaluator. Tests `BEQ` (equal) and `BNE` (unequal) conditions using forwarded source operands and calculates target as `PC + imm` (byte offset). |
| `ex_stage` | [`rtl/stages/ex_stage.v`](../../rtl/stages/ex_stage.v) | Structural EX datapath wrapper. Integrates `alu`, `alu_control`, `branch_unit`, dual 2-bit operand forwarding multiplexers, immediate selection, and side-effect control gating. |
| `ex_mem_reg` | [`rtl/pipeline_registers/ex_mem_reg.v`](../../rtl/pipeline_registers/ex_mem_reg.v) | Synchronous boundary register capturing the 138-bit execution bundle on the rising clock edge with active-high reset, hold, flush, and bubble-clearing support. |
| *Interface Specs* | [`docs/ex_stage_interface.md`](../ex_stage_interface.md)<br>[`docs/ex_mem_interface.md`](../ex_mem_interface.md) | Architectural interface contracts specifying signal widths, forwarding encodings, edge priorities, and proposed downstream dependencies. |

---

## 4. ALU Operation Codes, Equality and Zero Flags

The 32-bit ALU (`rtl/stages/alu.v`) is purely combinational. It consumes two 32-bit operands (`a` and `b`) and a 4-bit control code (`alu_ctrl`), producing a 32-bit `result` and two status flags:

### Operation Encodings
- `4'b0000` (`ALU_ADD`): Computes two's-complement addition:
  $$\text{result} = a + b \pmod{2^{32}}$$
  Suitable for register-register `ADD`, register-immediate `ADDI`, and memory address calculations for `LW`/`SW`. Overflow is ignored per RV32I specification, wrapping naturally modulo $2^{32}$.
- `4'b0001` (`ALU_SUB`): Computes two's-complement subtraction:
  $$\text{result} = a - b \pmod{2^{32}}$$
  Used for register-register `SUB`.
- `4'b0010` to `4'b1111` (Unused/Reserved): Safely and deterministically drives:
  $$\text{result} = 32\text{'h}0000\_0000$$
  This prevents latches, avoids undefined values, and guarantees that an invalid opcode never accidentally triggers subtraction.

### Status Flags
- **`equal` Flag (`assign equal = (a == b);`)**:
  - Asserted high (`1'b1`) if and only if all 32 bits of operand `a` match operand `b`.
  - Independent of `alu_ctrl` and independent of whether `result == 0`. For example, `5 + (-5) = 0` produces `zero = 1` but `equal = 0`.
  - Exposes dedicated equality comparison support for branch evaluation while leaving branch policy to `branch_unit`.
- **`zero` Flag (`assign zero = (result == 32'd0);`)**:
  - Asserted high (`1'b1`) when the arithmetic `result` is zero.
  - Standard status indicator for general arithmetic operations.

---

## 5. ALU Control Decoder Mapping & Safe Defaults

The ALU Control Decoder (`rtl/stages/alu_control.v`) coordinates main control with the ALU. It translates the 2-bit `alu_op` generated in ID by `main_control` along with instruction `funct3` and `funct7` fields into `alu_ctrl`:

### Decoding Truth Table
| `alu_op` | `funct3` | `funct7` | Target Instructions | `alu_ctrl` | Description |
|---|---|---|---|---|---|
| `2'b00` | `3'bxxx` | `7'bxxxxxxx` | `ADDI`, `LW`, `SW` | `4'b0000` (`ALU_ADD`) | Add/address class. `funct3` and `funct7` are ignored because for I-type and S-type instructions, instruction bits [31:25] contain immediate bits, not an R-type `funct7`. |
| `2'b01` | `3'b000` | `7'h00` | `ADD` | `4'b0000` (`ALU_ADD`) | R-type addition (`rs1 + rs2`). |
| `2'b01` | `3'b000` | `7'h20` | `SUB` | `4'b0001` (`ALU_SUB`) | R-type subtraction (`rs1 - rs2`). |
| `2'b01` | Other | Other | Unsupported R-type | `4'b0000` (`ALU_ADD`) | Safe default. Never accidentally asserts `SUB`. |
| `2'b10` | `3'bxxx` | `7'bxxxxxxx` | `BEQ`, `BNE` | `4'b0000` (`ALU_ADD`) | Branch class default. Branch evaluation is handled by `branch_unit`. |
| `2'b11` | `3'bxxx` | `7'bxxxxxxx` | Reserved | `4'b0000` (`ALU_ADD`) | Safe default for unused main control codes. |

### Architectural Safety Note on Defaulting
Defaulting invalid control combinations to `ALU_ADD` ensures safe, deterministic ALU behavior. However, **a default ALU operation alone does not suppress memory or register writes**. Instruction validity and write-enable suppression are strictly handled by surrounding pipeline control (`instruction_decoder.supported`, `main_control.valid_in`, and pipeline register `valid` bits).

---

## 6. Branch Evaluation and Target Calculation

The `branch_unit` module (`rtl/stages/branch_unit.v`) evaluates branch conditions and computes target addresses combinationally:

### Condition Evaluation (`branch_taken`)
Consumes the forwarded source operands (`op_a`, `op_b`) and the 2-bit `branch_type` from ID/EX:
- `branch_type == 2'b01` (`BEQ`): Asserted (`1'b1`) if `op_a == op_b` and `valid == 1`.
- `branch_type == 2'b10` (`BNE`): Asserted (`1'b1`) if `op_a != op_b` and `valid == 1`.
- `branch_type == 2'b00` (`None`) or `2'b11` (`Reserved`): Deasserted (`1'b0`).
- `valid == 1'b0`: Forced to `1'b0` so pipeline bubbles never trigger a branch redirect.

### Target Address Calculation (`branch_target`)
Computed combinationally as:
$$\text{branch\_target} = \text{pc} + \text{imm} \pmod{2^{32}}$$
- **Base Address**: Uses the branch instruction's own `pc` (from ID/EX), **not** sequential `pc + 4`.
- **Byte Offset**: The sign-extended immediate `imm` generated by `instruction_decoder` already incorporates the low bit ($0$) and represents a signed byte offset. **It is not shifted again** (unlike MIPS-style word offsets).
- **Inactive State**: `branch_target` continuously computes `pc + imm`. In the proposed CPU integration (Issue #25 / M5), downstream PC selection logic will qualify redirection with `branch_taken`, ignoring `branch_target` when `branch_taken == 0`.

---

## 7. Forwarding Encodings and Operand Selection

### Forwarding Architecture (Pending M5 Integration)
The `ex_stage` module implements the **datapath multiplexers** for operand forwarding. The control logic that calculates the forwarding selectors (`forward_a`, `forward_b`) belongs to the M5 Hazard/Forwarding Unit (Issue #24).

The forwarding selector encodings currently implemented in `ex_stage.v` (pending M5 confirmation) are:

| Selector Code | Name | Selected Source |
|---|---|---|
| `2'b00` | `FWD_ID_EX` | Staged register value from ID/EX (`rs1_data_in` / `rs2_data_in`) |
| `2'b01` | `FWD_MEM_WB` | Forwarded result from MEM/WB boundary (`forward_wb_data`) |
| `2'b10` | `FWD_EX_MEM` | Forwarded result from EX/MEM boundary (`forward_mem_data`) |
| `2'b11` | Reserved | Safely defaults to ID/EX staged value |

### Datapath Operand Multiplexing
- **Operand A (`alu_operand_a`)**: Directly fed by the Forward A multiplexer (`fwd_rs1_data`).
- **Operand B (`alu_operand_b`)**: Multiplexed between the immediate and forwarded register data based on `alu_src_imm_in`:
  $$\text{alu\_operand\_b} = \begin{cases} \text{imm\_in}, & \text{if } \text{alu\_src\_imm_in} = 1 \\ \text{fwd\_rs2\_data}, & \text{if } \text{alu\_src\_imm_in} = 0 \end{cases}$$
- **Branch Operands**: `branch_unit` directly connects `op_a = fwd_rs1_data` and `op_b = fwd_rs2_data`, enabling branch decisions to evaluate forwarded operands.

---

## 8. Store Data Preservation During Store Word (SW)

A critical architectural feature of `ex_stage.v` is the independent routing of `store_data`:
- For `SW` (Store Word) instructions, the ALU must calculate the target memory address:
  $$\text{address} = \text{fwd\_rs1\_data} + \text{imm\_in}$$
  This requires asserting `alu_src_imm_in = 1`, which directs the ALU to select `imm_in` for Operand B.
- However, the actual payload data to be stored into memory comes from `rs2`. If the value in `rs2` was produced by an immediately preceding instruction, it arrives via the Forward B multiplexer as `fwd_rs2_data`.
- In `ex_stage.v`:
  ```verilog
  assign store_data = fwd_rs2_data;
  ```
  `store_data` is tapped directly from the output of the Forward B multiplexer **before** the ALU Operand B multiplexer. Thus, even while the ALU consumes `imm_in` for address generation, `store_data` reliably preserves the forwarded `rs2` store value and propagates it to `ex_mem_reg`. (Actual data memory write execution in MEM depends on pending M4 implementation).

---

## 9. EX/MEM Pipeline Register (`ex_mem_reg`)

The `ex_mem_reg` module (`rtl/pipeline_registers/ex_mem_reg.v`) latches execution stage outputs on the rising clock edge for proposed consumption by the Memory (MEM) stage. For complete details, see [`docs/ex_mem_interface.md`](../ex_mem_interface.md).

### Captured Bundle Fields (138 bits total)
1. `alu_result_out [31:0]`: Arithmetic result or memory effective address.
2. `store_data_out [31:0]`: Forwarded store data for `SW`.
3. `rd_out [4:0]`: Destination register index.
4. `pc_out [31:0]`, `pc_plus4_out [31:0]`: Program counter metadata.
5. `mem_read_out`, `mem_write_out`: Data memory read and write enables.
6. `reg_write_out`, `wb_from_mem_out`: Write-back control signals.
7. `valid_out`: Instruction validity flag.

### Signals NOT Latched into EX/MEM
- `branch_taken` and `branch_target`: Combinational signals routed immediately to the IF stage (PC multiplexer) and M5 hazard control; they do not advance down the sequential pipeline to MEM.
- `rs1` and `rs2`: Source indices needed only for EX forwarding; downstream stages only require the destination index `rd`.

### Edge Behavior and Priority
Evaluated on each rising clock edge:
1. **Synchronous Reset or Flush (`rst || flush`)**: Clears all 138 bits to `0`. A flush beats a hold (`en=0`).
2. **Hold (`en == 0`)**: Holds all current output values unchanged across clock cycles. **Hold has priority over invalid-input bubble capture** (`valid_in == 0` with `en == 0` continues holding).
3. **Bubble Capture (`en == 1 && valid_in == 0`)**: Capturing an invalid input clears all 138 bits to `0`, ensuring bubbles cannot assert side-effects.
4. **Active Capture (`en == 1 && valid_in == 1`)**: Latches the complete valid bundle from input to output.

---

## 10. Verification Commands & Actual Test Results

All Milestone 3 modules have been verified in standalone simulation using dedicated self-checking testbenches with **Icarus Verilog (`iverilog` v13.0)** and `vvp`.

> [!NOTE] Test Suite Scope & Functional Coverage Clarification
> - The total of **609 checks/cycles** is the arithmetic sum of reported testbench assertions and checked simulation cycles across all 5 test suites. It is **not** a metric of exhaustive functional coverage or formal verification.
> - For `tb_ex_mem_reg.v`, the **430 checks represent individual checked simulation cycles** that verify active capture, synchronous reset/flush priority, hold stability, walking-bit patterns across the 138-bit payload, and bubble-clearing priority.
> - Passing these isolated module-level and stage-level testbenches confirms standalone circuit correctness under simulated stimulus; it does **not** establish full CPU integration, multi-stage pipeline interaction, or end-to-end RISC-V program correctness.

### Verification Test Suite Summary
| Testbench | Files Compiled | Reported Checks / Cycles | Simulation Result |
|---|---|---:|---|
| [`tb_alu.v`](../../testbench/tb_alu.v) | `testbench/tb_alu.v rtl/stages/alu.v` | 80 checks | **PASS** |
| [`tb_alu_control.v`](../../testbench/tb_alu_control.v) | `testbench/tb_alu_control.v rtl/stages/alu_control.v` | 45 checks | **PASS** |
| [`tb_branch_unit.v`](../../testbench/tb_branch_unit.v) | `testbench/tb_branch_unit.v rtl/stages/branch_unit.v` | 36 checks | **PASS** |
| [`tb_ex_stage.v`](../../testbench/tb_ex_stage.v) | `testbench/tb_ex_stage.v rtl/stages/ex_stage.v rtl/stages/alu.v rtl/stages/alu_control.v rtl/stages/branch_unit.v` | 18 checks | **PASS** |
| [`tb_ex_mem_reg.v`](../../testbench/tb_ex_mem_reg.v) | `testbench/tb_ex_mem_reg.v rtl/pipeline_registers/ex_mem_reg.v` | 430 checked cycles | **PASS** |
| **Sum of M3 Checks/Cycles** | | **609 checks/cycles** | **100% PASS** |

### Exact Compile and Execution Commands & Actual Terminal Output

1. **ALU Testbench (`tb_alu.v`)**:
   ```bash
   iverilog -g2012 -s tb_alu -o /tmp/tb_alu.vvp testbench/tb_alu.v rtl/stages/alu.v
   vvp /tmp/tb_alu.vvp
   ```
   *Actual Output:*
   ```text
   PASS: all 80 ALU tests completed successfully
   testbench/tb_alu.v:170: $finish called at 80000 (1ps)
   ```

2. **ALU Control Decoder Testbench (`tb_alu_control.v`)**:
   ```bash
   iverilog -g2012 -s tb_alu_control -o /tmp/tb_alu_control.vvp testbench/tb_alu_control.v rtl/stages/alu_control.v
   vvp /tmp/tb_alu_control.vvp
   ```
   *Actual Output:*
   ```text
   PASS: all 45 ALU control decoder tests completed successfully
   testbench/tb_alu_control.v:130: $finish called at 45000 (1ps)
   ```

3. **Branch Unit Testbench (`tb_branch_unit.v`)**:
   ```bash
   iverilog -g2012 -s tb_branch_unit -o /tmp/tb_branch_unit.vvp testbench/tb_branch_unit.v rtl/stages/branch_unit.v
   vvp /tmp/tb_branch_unit.vvp
   ```
   *Actual Output:*
   ```text
   PASS: all 36 branch unit tests completed successfully
   testbench/tb_branch_unit.v:194: $finish called at 36000 (1ps)
   ```

4. **EX Stage Datapath Testbench (`tb_ex_stage.v`)**:
   ```bash
   iverilog -g2012 -s tb_ex_stage -o /tmp/tb_ex_stage.vvp testbench/tb_ex_stage.v rtl/stages/ex_stage.v rtl/stages/alu.v rtl/stages/alu_control.v rtl/stages/branch_unit.v
   vvp /tmp/tb_ex_stage.vvp
   ```
   *Actual Output:*
   ```text
   PASS: all 18 EX stage datapath tests completed successfully
   testbench/tb_ex_stage.v:331: $finish called at 18000 (1ps)
   ```

5. **EX/MEM Pipeline Register Testbench (`tb_ex_mem_reg.v`)**:
   ```bash
   iverilog -g2012 -s tb_ex_mem_reg -o /tmp/tb_ex_mem_reg.vvp testbench/tb_ex_mem_reg.v rtl/pipeline_registers/ex_mem_reg.v
   vvp /tmp/tb_ex_mem_reg.vvp
   ```
   *Actual Output:*
   ```text
   PASS: all 430 EX/MEM pipeline register tests completed successfully
   testbench/tb_ex_mem_reg.v:234: $finish called at 1290000 (1ps)
   ```

---

## 11. Current Limitations and Integration Dependencies

While Milestone 3 is internally complete and thoroughly tested at the unit and stage level, several critical integration dependencies and architectural limitations remain:

1. **No End-to-End CPU Verification Yet**:
   - The verified testbenches exercise isolated modules and stage wrappers with synthetic test vectors. The full 5-stage pipeline, multi-instruction program execution, and retire-stage commit have **not yet been verified together**.
2. **Forwarding Multiplexers vs. Forwarding Controller (M5 Dependency)**:
   - The EX stage includes the multiplexers that consume `forward_a` and `forward_b`.
   - However, the hazard detection logic and forwarding controller that actually compares `ID/EX.rs1` / `ID/EX.rs2` against `EX/MEM.rd` / `MEM/WB.rd` resides in **Milestone 5 (Issue #24)** and is not yet integrated or confirmed.
3. **Load-Use Data Hazard Handling (Intended Pipeline Timing)**:
   - For a Load instruction (`LW`), the `alu_result` computed in EX and captured in `ex_mem_reg` is the memory byte *effective address*, **not** the loaded data word.
   - The actual data is only retrieved after data memory access occurs in the Memory (MEM) stage (Milestone 4).
   - Consequently, a dependent instruction immediately following `LW` cannot resolve its data dependency through EX-to-EX forwarding from `EX/MEM`.
   - In the proposed five-stage pipeline with single-cycle synchronous memory access, the **intended approach is a one-cycle hardware interlock (stall)** inserted by the hazard unit (holding PC and IF/ID while converting ID/EX into a bubble), pending M4/M5 integration and verification.
   - Note that this one-cycle stall is specific to the planned single-cycle memory design; alternate memory timing arrangements (e.g., multi-cycle memory, bus wait-states, or cache misses) would require their own corresponding stall durations.
4. **Memory Re-Execution Prevention on Hold**:
   - When `ex_mem_reg` is stalled (`en = 0`), it holds `mem_read` or `mem_write` high. The downstream memory stage (M4, Issue #18) and stall unit (M5, Issue #25) must ensure that a held memory operation is not re-executed repeatedly across stall cycles.
5. **Pending Agreements**:
   - Interface contracts with Milestone 4 (Data Memory, MEM stage) and Milestone 5 (Forwarding, Hazard, Flush) remain marked as **proposed integration interfaces pending final team confirmation** until integrated into the top-level processor.
