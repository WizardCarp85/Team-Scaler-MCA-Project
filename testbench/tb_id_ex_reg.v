`timescale 1ns/1ps
module tb_id_ex_reg;
    reg clk = 0, rst = 0, flush = 0, en = 1;
    localparam WIDTH = 195;
    reg [WIDTH-1:0] entry;
    wire [WIDTH-1:0] result;
    wire [31:0] pc_in, pc_out;
    wire [31:0] pc_plus4_in, pc_plus4_out;
    wire [31:0] rs1_data_in, rs1_data_out;
    wire [31:0] rs2_data_in, rs2_data_out;
    wire [31:0] imm_in, imm_out;
    wire [4:0] rs1_in, rs1_out;
    wire [4:0] rs2_in, rs2_out;
    wire [4:0] rd_in, rd_out;
    wire [2:0] funct3_in, funct3_out;
    wire [6:0] funct7_in, funct7_out;
    wire [1:0] alu_op_in, alu_op_out;
    wire [1:0] branch_type_in, branch_type_out;
    wire alu_src_imm_in, alu_src_imm_out;
    wire mem_read_in, mem_read_out;
    wire mem_write_in, mem_write_out;
    wire reg_write_in, reg_write_out;
    wire wb_from_mem_in, wb_from_mem_out;
    wire valid_in, valid_out;
    assign {pc_in, pc_plus4_in, rs1_data_in, rs2_data_in,
            imm_in, rs1_in, rs2_in, rd_in,
            funct3_in, funct7_in, alu_op_in, branch_type_in,
            alu_src_imm_in, mem_read_in, mem_write_in, reg_write_in,
            wb_from_mem_in, valid_in} = entry;
    assign result = {pc_out, pc_plus4_out, rs1_data_out, rs2_data_out,
            imm_out, rs1_out, rs2_out, rd_out,
            funct3_out, funct7_out, alu_op_out, branch_type_out,
            alu_src_imm_out, mem_read_out, mem_write_out, reg_write_out,
            wb_from_mem_out, valid_out};
    id_ex_reg dut (
        .clk(clk), .rst(rst), .en(en), .flush(flush),
        .pc_in(pc_in), .pc_out(pc_out),
        .pc_plus4_in(pc_plus4_in), .pc_plus4_out(pc_plus4_out),
        .rs1_data_in(rs1_data_in), .rs1_data_out(rs1_data_out),
        .rs2_data_in(rs2_data_in), .rs2_data_out(rs2_data_out),
        .imm_in(imm_in), .imm_out(imm_out),
        .rs1_in(rs1_in), .rs1_out(rs1_out),
        .rs2_in(rs2_in), .rs2_out(rs2_out),
        .rd_in(rd_in), .rd_out(rd_out),
        .funct3_in(funct3_in), .funct3_out(funct3_out),
        .funct7_in(funct7_in), .funct7_out(funct7_out),
        .alu_op_in(alu_op_in), .alu_op_out(alu_op_out),
        .branch_type_in(branch_type_in), .branch_type_out(branch_type_out),
        .alu_src_imm_in(alu_src_imm_in), .alu_src_imm_out(alu_src_imm_out),
        .mem_read_in(mem_read_in), .mem_read_out(mem_read_out),
        .mem_write_in(mem_write_in), .mem_write_out(mem_write_out),
        .reg_write_in(reg_write_in), .reg_write_out(reg_write_out),
        .wb_from_mem_in(wb_from_mem_in), .wb_from_mem_out(wb_from_mem_out),
        .valid_in(valid_in), .valid_out(valid_out)
    );

    task tick_and_check;
        input [WIDTH-1:0] expected;
        begin
            #2; clk = 1; #1;
            if (result !== expected)
                $fatal(1, "ID/EX bundle=%h expected=%h", result, expected);
            clk = 0;
        end
    endtask

    integer i;
    initial begin
        entry = {WIDTH{1'b1}};
        rst = 1; tick_and_check(0);
        rst = 0; tick_and_check(entry);
        // Walk one bit across every data and control field with valid asserted.
        for (i = 1; i < WIDTH; i = i + 1) begin
            entry = 1; entry[i] = 1; tick_and_check(entry);
        end
        entry = 13; tick_and_check(entry);
        entry = 0; en = 0; tick_and_check(13);
        flush = 1; tick_and_check(0);
        flush = 0; en = 1;
        entry = {WIDTH{1'b1}}; tick_and_check(entry);
        entry[0] = 0; tick_and_check(0); // Invalid input with write enables high
        entry[0] = 1; tick_and_check(entry);
        en = 0; rst = 1; tick_and_check(0);
        $display("PASS: ID/EX capture, hold, flush, reset and invalid entries");
        $finish;
    end
endmodule
