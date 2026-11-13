`timescale 1ns/1ps
module tb_instruction_decoder;
    reg [31:0] instr;
    wire [6:0] opcode, funct7;
    wire [4:0] rd, rs1, rs2;
    wire [2:0] funct3;
    wire [31:0] imm;
    wire supported;
    integer cases = 0;

    instruction_decoder dut (
        .instr(instr), .opcode(opcode), .rd(rd), .funct3(funct3),
        .rs1(rs1), .rs2(rs2), .funct7(funct7), .imm(imm), .supported(supported)
    );

    task check;
        input [31:0] word;
        input expected_supported;
        input [31:0] expected_imm;
        begin
            instr = word;
            #1;
            if ({supported, imm} !== {expected_supported, expected_imm} ||
                {funct7, rs2, rs1, funct3, rd, opcode} !== word)
                $fatal(1, "instr=%h supported=%b expected=%b imm=%h expected=%h fields=%h",
                       word, supported, expected_supported, imm, expected_imm,
                       {funct7, rs2, rs1, funct3, rd, opcode});
            cases = cases + 1;
        end
    endtask

    initial begin
        check(32'h006283b3, 1'b1, 32'd0); // ADD x7,x5,x6
        check(32'h406283b3, 1'b1, 32'd0); // SUB x7,x5,x6
        check(32'h80028393, 1'b1, -32'sd2048); // ADDI
        check(32'h7ff28393, 1'b1, 32'sd2047); // ADDI
        check(32'hff42a383, 1'b1, -32'sd12); // LW
        check(32'h0142a383, 1'b1, 32'sd20); // LW
        check(32'h8062a023, 1'b1, -32'sd2048); // SW
        check(32'h7e62afa3, 1'b1, 32'sd2047); // SW
        check(32'hfc62aa23, 1'b1, -32'sd44); // SW
        check(32'h0262a223, 1'b1, 32'sd36); // SW
        check(32'h7e628fe3, 1'b1, 32'sd4094); // BEQ
        check(32'h80628063, 1'b1, -32'sd4096); // BEQ
        check(32'h006280e3, 1'b1, 32'sd2048); // BEQ
        check(32'hfe6297e3, 1'b1, -32'sd18); // BNE
        check(32'h02629563, 1'b1, 32'sd42); // BNE
        check(32'h026283b3, 1'b0, 32'd0); // Unsupported R-type funct7
        check(32'h006293b3, 1'b0, 32'd0); // Unsupported R-type funct3
        check(32'hfff29393, 1'b0, 32'd0); // Unsupported OP-IMM funct3
        check(32'hfff28383, 1'b0, 32'd0); // LB
        check(32'hfe629f23, 1'b0, 32'd0); // SH
        check(32'hfe62cee3, 1'b0, 32'd0); // BLT
        check(32'hffffffff, 1'b0, 32'd0); // Unknown opcode
        $display("PASS: %0d decoder vectors", cases);
        $finish;
    end
endmodule
