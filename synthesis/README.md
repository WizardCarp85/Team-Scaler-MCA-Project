# Synthesis, Resource Utilization & Timing Analysis Guide

**Project:** Team Scaler MCA Project — 5-Stage Pipelined RISC-V Processor  
**Target Architecture:** RV32I Subset (ADD, SUB, ADDI, LW, SW, BEQ, BNE)  
**Top Module:** `cpu` ([`rtl/cpu.v`](../rtl/cpu.v))  

---

## 1. Toolchain & Environment Status

> [!IMPORTANT]
> **Current Status: Pending Local Toolchain Execution**  
> In the current development container environment, FPGA synthesis tools (such as Xilinx Vivado, Intel Quartus Prime, and Yosys) are not installed. To prevent unverified claims or fabricated numbers, **no speculative LUT, FF, BRAM, or $F_{\max}$ values are claimed as measured hardware results**.
>
> Reproducible scripts and constraints have been implemented below so that any team member or evaluator with Vivado or Yosys installed can execute the flow and record authentic post-implementation metrics.

---

## 2. Target FPGA Platform

- **Recommended Board:** Digilent Basys 3 Artix-7 FPGA Trainer Board
- **Target Part:** `xc7a35tcpg236-1` (Xilinx Artix-7 family)
- **Target Clock:** 100 MHz oscillator ($T_{\text{clk}} = 10.0\,\text{ns}$)
- **Default Constraints:** [`synthesis/constraints.xdc`](constraints.xdc)

---

## 3. Synthesis with Xilinx Vivado (Non-Project Batch Mode)

### 3.1 Prerequisites
- Xilinx Vivado (2020.1 or later recommended).
- Ensure `vivado` is added to your system `PATH`.

### 3.2 Running Vivado Synthesis
Run the provided TCL batch script from the repository root:
```bash
vivado -mode batch -source synthesis/synth_vivado.tcl
```

### 3.3 What the Script Does
The script [`synthesis/synth_vivado.tcl`](synth_vivado.tcl):
1. Reads all RTL source files (`rtl/cpu.v`, `rtl/stages/*.v`, `rtl/pipeline_registers/*.v`).
2. Applies the timing constraint ($100\,\text{MHz}$ clock constraint on `clk`).
3. Executes out-of-context (OOC) synthesis targeting `xc7a35tcpg236-1`.
4. Runs implementation (logic optimization, placement, routing).
5. Generates:
   - Resource utilization report: `synthesis/utilization_report.txt` (LUT, FF, BRAM counts).
   - Timing summary report: `synthesis/timing_summary.txt` (Setup Slack, Hold Slack, $F_{\max}$).

---

## 4. Generic Synthesis with Yosys Open-Source Synthesis

### 4.1 Prerequisites
- Yosys Open SYnthesis Suite (`brew install yosys` on macOS or `apt-get install yosys` on Ubuntu).

### 4.2 Running Yosys
Run the Yosys synthesis script from the repository root:
```bash
yosys -s synthesis/synth_yosys.ys
```

### 4.3 What the Script Does
The script [`synthesis/synth_yosys.ys`](synth_yosys.ys):
1. Reads the SystemVerilog/Verilog 2005 sources.
2. Elaborates the top module `cpu`.
3. Performs generic tech mapping and constant folding.
4. Reports generic cell counts (number of AND, OR, XOR, MUX, DFF primitives) and estimated gate counts.

---

## 5. Distinction Between Simulation Clock and FPGA $F_{\max}$

- **Simulation Clock:** The simulation testbenches use `always #5 clk = ~clk;` representing a 100 MHz virtual clock period ($10\,\text{ns}$). This simulation period is an arbitrary software timing scale for Icarus Verilog and does **not** represent verified FPGA timing closure.
- **FPGA $F_{\max}$:** Real hardware maximum operating frequency can only be determined through post-placement static timing analysis (STA) in Vivado or Quartus:
  $$F_{\max} = \frac{1}{T_{\text{clk}} - \text{Worst Negative Slack (WNS)}}$$
  This measurement will be added once Vivado synthesis is executed on a host with the Xilinx EDA suite installed.
