# Project Demo Video

This directory contains the documentation and access link to the demonstration video for the **Team Scaler MCA Project** (5-Stage Pipelined RV32I Processor in Verilog).

---

## Demonstration Video Link

The project demonstration video is hosted on Google Drive:

- **Google Drive Folder:** [Team Scaler MCA Project Demo Video](https://drive.google.com/drive/folders/1EgOdLGRiIbfGNEMWvCw3mpRqaSgrbESI?usp=sharing)
- **Direct Link:** `https://drive.google.com/drive/folders/1EgOdLGRiIbfGNEMWvCw3mpRqaSgrbESI?usp=sharing`

---

## Topics Covered in the Demo
1. **Architecture & Pipeline Overview:**
   - 5-stage in-order RISC-V (RV32I subset) processor architecture (IF, ID, EX, MEM, WB).
   - Structural stage wrappers and synchronous pipeline boundary registers (IF/ID, ID/EX, EX/MEM, MEM/WB).
2. **Hazard Handling & Interlock Controls:**
   - Load-use RAW hazard detection with synchronous PC hold, IF/ID hold, and ID/EX bubble insertion.
   - EX-stage operand forwarding resolving RAW dependencies from EX/MEM and MEM/WB boundaries with youngest-producer priority.
   - Branch target calculation and condition evaluation (BEQ, BNE) in EX with synchronous flushing of wrong-path instructions.
3. **Simulation & Verification Walkthrough:**
   - Compiling and executing test suites using Icarus Verilog (`iverilog` / `vvp`).
   - Visualizing cycle-accurate timing and waveform evidence in GTKWave.
