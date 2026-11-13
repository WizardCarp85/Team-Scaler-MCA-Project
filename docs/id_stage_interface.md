# Instruction Decode integration

Connect M1's IF/ID outputs `instr_out`, `pc_out`, `pc_plus4_out` and `valid_out` to the corresponding `*_in` ports on `id_stage`. ID preserves the IF/ID valid bit for supported instructions. A fetched ADDI x0,x0,0 is valid. The same word with IF/ID validity cleared is a bubble.

Connect M4's valid-qualified WB register enable, destination index and value to `wb_write_en`, `wb_rd[4:0]` and `wb_data[31:0]`. These inputs describe an older instruction and are independent of ID validity. Writes commit on the rising edge. A matching read sees the enabled WB value before that edge, so ID/EX captures the current operand. Reset is synchronous and active high.

Each output listed in the [ID/EX interface](id_ex_interface.md) connects directly to the matching `_in` port on a separate `id_ex_reg` instance. The top level owns that instance and supplies its enable and flush. Decode computes operands and controls combinationally.

M5 can use the ID-stage `rs1`, `rs2`, `rd` and `valid` outputs directly. Qualify each source comparison with its `uses_rs1` or `uses_rs2` flag. All supported instructions consume rs1. ADD, SUB, SW, BEQ and BNE also consume rs2. ADDI and LW carry immediate bits in the raw rs2 field. Unsupported words and bubbles disable both source-use flags and all side effects.
