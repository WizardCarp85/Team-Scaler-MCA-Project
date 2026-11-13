`timescale 1ns/1ps
module tb_main_control;
    reg [31:0] instr;
    reg valid_in;
    wire supported, valid, reg_write, mem_read, mem_write, wb_from_mem, alu_src_imm;
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [1:0] alu_op, branch_type;

    instruction_decoder decoder (.instr(instr), .opcode(opcode),
        .funct3(funct3), .supported(supported));
    main_control dut (.valid_in(valid_in), .supported(supported),
        .opcode(opcode), .funct3(funct3), .valid(valid), .reg_write(reg_write),
        .mem_read(mem_read), .mem_write(mem_write), .wb_from_mem(wb_from_mem),
        .alu_src_imm(alu_src_imm), .alu_op(alu_op), .branch_type(branch_type));
    wire [9:0] controls = {valid, reg_write, mem_read, mem_write, wb_from_mem,
                           alu_src_imm, alu_op, branch_type};
    task check;
        input [31:0] word;
        input [9:0] expected;
        begin
            instr = word;
            #1;
            if (controls !== expected)
                $fatal(1, "instr=%h valid_in=%b controls=%b expected=%b",
                       instr, valid_in, controls, expected);
        end
    endtask

    initial begin
        valid_in = 1;
        // Truth table: valid, reg_write, mem_read, mem_write, wb_from_mem,
        // alu_src_imm, alu_op[1:0], branch_type[1:0].
        check(32'h006283b3, 10'b1_1_0_0_0_0_01_00); // ADD
        check(32'h406283b3, 10'b1_1_0_0_0_0_01_00); // SUB
        check(32'hfff28393, 10'b1_1_0_0_0_1_00_00); // ADDI
        check(32'h0042a383, 10'b1_1_1_0_1_1_00_00); // LW
        check(32'h0062a223, 10'b1_0_0_1_0_1_00_00); // SW
        check(32'h00628263, 10'b1_0_0_0_0_0_10_01); // BEQ
        check(32'h00629263, 10'b1_0_0_0_0_0_10_10); // BNE
        check(32'h026283b3, 0); // MUL
        check(32'h0062c263, 0); // BLT
        check(32'h00629223, 0); // SH
        check(32'h00000000, 0); // unsupported opcode
        valid_in = 0;
        check(32'h0042a383, 0); // invalid load
        check(32'h0062a223, 0); // invalid store
        $display("PASS: seven control rows, unsupported encodings and bubbles");
        $finish;
    end
endmodule
