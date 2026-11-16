# Write-Back (WB) Stage & Register File Interface Specification

**Module:** `wb_stage` (`rtl/stages/wb_stage.v`)  
**Status:** Implemented for Issue #20 (Milestone 4 — Memory Stage & Write-Back)

---

## 1. Overview

The Write-Back (WB) stage is the final stage of the 5-stage RISC-V pipelined processor (**IF** → **ID** → **EX** → **MEM** → **WB**). It receives the registered results from the `mem_wb_reg` pipeline register, multiplexes between computational and memory load results, suppresses invalid write side-effects, and drives the write port of the Instruction Decode (ID) register file.

```text
       ┌────────────┐
       │ mem_wb_reg │
       └──────┬─────┘
              │ alu_result, load_data, wb_from_mem, rd, reg_write, valid, pc
              ▼
       ┌────────────┐
       │  wb_stage  │
       └──────┬─────┘
              │ wb_write_en, wb_rd, wb_data
              ▼
       ┌───────────────┐
       │ register_file │ (in ID Stage)
       └───────────────┘
```

---

## 2. Port Interface

### Inputs (from `mem_wb_reg` outputs)

| Signal | Width | Direction | Consumer / Meaning |
|---|---:|:---:|---|
| `alu_result` | 32 | in | Computational arithmetic result from EX stage or effective address |
| `load_data` | 32 | in | Word read from `data_mem` during LW |
| `rd` | 5 | in | Destination register index |
| `pc` | 32 | in | Instruction PC metadata |
| `pc_plus4` | 32 | in | Sequential PC+4 metadata |
| `reg_write` | 1 | in | Register file write enable signal from decode control |
| `wb_from_mem` | 1 | in | Write-back multiplexer selector (`0`: ALU, `1`: Data Memory) |
| `valid` | 1 | in | Instruction validity flag (`1`: live instruction, `0`: bubble) |

### Outputs (to `register_file` in ID stage)

| Signal | Width | Direction | Connected Port in `register_file` | Description |
|---|---:|:---:|---|---|
| `wb_write_en` | 1 | out | `register_file.write_en` | Gated register file write enable |
| `wb_rd` | 5 | out | `register_file.rd` | Destination register index |
| `wb_data` | 32 | out | `register_file.write_data` | Multiplexed write-back data |

### Pass-through & Retirement Outputs (Debug / M5 Hazard / Accounting)

| Signal | Width | Direction | Description |
|---|---:|:---:|---|
| `pc_out` | 32 | out | Instruction PC of retiring instruction |
| `pc_plus4_out` | 32 | out | Sequential PC+4 of retiring instruction |
| `retired` | 1 | out | Asserted when a valid instruction retires this cycle (`retired = valid`) |

---

## 3. Multiplexing & Gating Rules

### 3.1 Write-Back Source Multiplexer
The 32-bit `wb_data` payload is selected combinationally based on `wb_from_mem`:

$$\text{wb\_data} = \begin{cases} 
\text{load\_data} & \text{if } \text{wb\_from\_mem} = 1 \text{ (LW)} \\ 
\text{alu\_result} & \text{if } \text{wb\_from\_mem} = 0 \text{ (ADD, SUB, ADDI)} 
\end{cases}$$

### 3.2 Write Enable Gating
To strictly enforce architectural state integrity, `wb_write_en` is asserted **if and only if** all three conditions are satisfied:
1. **Instruction is valid**: $\text{valid} = 1$ (pipeline bubbles or flushed instructions never write).
2. **Instruction writes a register**: $\text{reg_write} = 1$ (store `SW` and branch `BEQ`/`BNE` instructions do not assert `reg_write`).
3. **Target register is not x0**: $\text{rd} \neq 5'd0$ (writes to hardwired zero register `x0` are suppressed).

$$\text{wb\_write\_en} = \text{valid} \ \&\  \text{reg\_write} \ \&\  (\text{rd} \neq 5'd0)$$

---

## 4. Integration with M2 Register File

The outputs of `wb_stage` connect directly to the write port of M2's `register_file` (`rtl/stages/register_file.v`):
- **Write commit**: Storage update occurs on the rising clock edge (`posedge clk`) inside `register_file`.
- **Write-Through Bypass**: The register file provides internal combinational write-through bypass. If an instruction in the ID stage is reading register `rs == wb_rd` in the same cycle that WB is committing to `wb_rd`, `register_file` combinationally delivers `wb_data` on `rs_data`.

---

## 5. Verification

The unit and integration testbench `testbench/tb_wb_stage.v` verifies:
- ALU result selection (`wb_from_mem = 0`)
- Memory load data selection (`wb_from_mem = 1`)
- Side-effect suppression on disabled writes (`reg_write = 0`)
- Side-effect suppression on pipeline bubbles (`valid = 0`)
- Side-effect suppression on destination `x0` (`rd = 0`)
- Live clock-edge integration with `register_file` demonstrating commit, persistence, and write-through bypass.

### Running the Testbench
```bash
iverilog -g2012 -o simulation/tb_wb_stage.vvp \
    testbench/tb_wb_stage.v \
    rtl/stages/wb_stage.v \
    rtl/stages/register_file.v
vvp simulation/tb_wb_stage.vvp
```
