# ID/EX interface

The module `id_ex_reg` captures one instruction on the rising clock edge. Every payload field has an `_in` and an `_out` port of the same width.

| Signals | Width each | Consumer and meaning |
|---|---:|---|
| pc, pc_plus4 | 32 | EX branch base and sequential PC metadata |
| rs1_data, rs2_data | 32 | EX operands before forwarding, including store data |
| imm | 32 | Sign-extended I/S immediate or signed B byte offset |
| rs1, rs2, rd | 5 | Forwarding comparisons, hazard detection and WB destination |
| funct3, funct7 | 3, 7 | Raw fields for EX ALU control |
| alu_op | 2 | 00 add/address, 01 register arithmetic, 10 branch comparison |
| alu_src_imm | 1 | Select immediate for ALU operand B |
| branch_type | 2 | 00 none, 01 BEQ, 10 BNE |
| mem_read, mem_write | 1 | LW and SW requests for MEM |
| reg_write, wb_from_mem | 1 | WB enable and source (1 selects load data) |
| valid | 1 | Live, supported instruction for side effects and retirement |

## Edge behavior in priority order

1. Synchronous active-high `rst` or asserted `flush` clears every output.
2. With `en=0`, all outputs hold.
3. With `en=1`, an invalid input clears every output. A valid input replaces the whole bundle.

For a load-use interlock, hold PC and IF/ID, flush ID/EX, and let the older load advance to EX/MEM. A taken branch in EX redirects the PC and flushes both younger boundaries. The optional ID/EX hold requires downstream coordination to avoid executing a held instruction twice.
