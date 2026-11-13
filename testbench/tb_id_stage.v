`timescale 1ns/1ps
module tb_id_stage;
    reg clk = 0, rst = 1, fetch_flush = 0, wb_write_en = 0;
    reg [31:0] fetch_pc = 0, fetch_instr = 0, wb_data = 0;
    reg [4:0] wb_rd = 0;
    wire [31:0] id_pc, id_pc_plus4, id_instr;
    wire id_valid, uses_rs1, uses_rs2;
    wire [31:0] pc, ex_pc;
    wire [31:0] pc_plus4, ex_pc_plus4;
    wire [31:0] rs1_data, ex_rs1_data;
    wire [31:0] rs2_data, ex_rs2_data;
    wire [31:0] imm, ex_imm;
    wire [4:0] rs1, ex_rs1;
    wire [4:0] rs2, ex_rs2;
    wire [4:0] rd, ex_rd;
    wire [2:0] funct3, ex_funct3;
    wire [6:0] funct7, ex_funct7;
    wire [1:0] alu_op, ex_alu_op;
    wire [1:0] branch_type, ex_branch_type;
    wire alu_src_imm, ex_alu_src_imm;
    wire mem_read, ex_mem_read;
    wire mem_write, ex_mem_write;
    wire reg_write, ex_reg_write;
    wire wb_from_mem, ex_wb_from_mem;
    wire valid, ex_valid;
    if_id_reg if_id (.clk(clk), .rst(rst), .en(1'b1), .flush(fetch_flush),
        .pc_in(fetch_pc), .pc_plus4_in(fetch_pc + 32'd4), .instr_in(fetch_instr),
        .pc_out(id_pc), .pc_plus4_out(id_pc_plus4), .instr_out(id_instr), .valid_out(id_valid));
    id_stage dut (.clk(clk), .rst(rst), .instr_in(id_instr), .pc_in(id_pc),
        .pc_plus4_in(id_pc_plus4), .valid_in(id_valid), .wb_write_en(wb_write_en),
        .wb_rd(wb_rd), .wb_data(wb_data), .uses_rs1(uses_rs1), .uses_rs2(uses_rs2),
        .pc(pc),
        .pc_plus4(pc_plus4),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .imm(imm),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .funct3(funct3),
        .funct7(funct7),
        .alu_op(alu_op),
        .branch_type(branch_type),
        .alu_src_imm(alu_src_imm),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .reg_write(reg_write),
        .wb_from_mem(wb_from_mem),
        .valid(valid)
    );
    id_ex_reg id_ex (.clk(clk), .rst(rst), .en(1'b1), .flush(1'b0),
        .pc_in(pc), .pc_out(ex_pc),
        .pc_plus4_in(pc_plus4), .pc_plus4_out(ex_pc_plus4),
        .rs1_data_in(rs1_data), .rs1_data_out(ex_rs1_data),
        .rs2_data_in(rs2_data), .rs2_data_out(ex_rs2_data),
        .imm_in(imm), .imm_out(ex_imm),
        .rs1_in(rs1), .rs1_out(ex_rs1),
        .rs2_in(rs2), .rs2_out(ex_rs2),
        .rd_in(rd), .rd_out(ex_rd),
        .funct3_in(funct3), .funct3_out(ex_funct3),
        .funct7_in(funct7), .funct7_out(ex_funct7),
        .alu_op_in(alu_op), .alu_op_out(ex_alu_op),
        .branch_type_in(branch_type), .branch_type_out(ex_branch_type),
        .alu_src_imm_in(alu_src_imm), .alu_src_imm_out(ex_alu_src_imm),
        .mem_read_in(mem_read), .mem_read_out(ex_mem_read),
        .mem_write_in(mem_write), .mem_write_out(ex_mem_write),
        .reg_write_in(reg_write), .reg_write_out(ex_reg_write),
        .wb_from_mem_in(wb_from_mem), .wb_from_mem_out(ex_wb_from_mem),
        .valid_in(valid), .valid_out(ex_valid)
    );
    task tick;
        begin #2; clk = 1; #1; clk = 0; #1; end
    endtask

    initial begin
        tick;
        rst = 0;
        fetch_pc = 16; fetch_instr = 32'h006283b3; // ADD x7,x5,x6
        wb_rd = 5; wb_data = 42; wb_write_en = 1;
        tick;
        wb_rd = 6; wb_data = 17; // WB to second ADD source during ID
        #1;
        if ({uses_rs1, uses_rs2} !== 2'b11) $fatal(1,"ADD source usage");
        fetch_pc = 20; fetch_instr = 32'hfe62ae23; // SW x6,-4(x5)
        tick;
        if ({ex_pc, ex_pc_plus4, ex_rs1_data, ex_rs2_data} !== {32'd16,32'd20,32'd42,32'd17} ||
            {ex_rs1,ex_rs2,ex_rd,ex_funct3,ex_funct7} !== {5'd5,5'd6,5'd7,3'd0,7'd0} ||
            {ex_valid,ex_reg_write,ex_alu_op} !== 4'b1101) $fatal(1,"ADD bundle/WB bypass");
        wb_write_en = 0;
        fetch_pc = 24; fetch_instr = 32'h00628393; // ADDI x7,x5,6
        tick;
        if ({ex_valid,ex_mem_write,ex_reg_write,ex_mem_read,ex_alu_src_imm} !== 5'b11001 ||
            ex_imm !== -32'sd4 || ex_rs2_data !== 17) $fatal(1,"SW bundle");
        if ({uses_rs1,uses_rs2} !== 2'b10 || rs2 !== 6) $fatal(1,"I-type source usage");
        fetch_pc = 28; fetch_instr = 32'h0042a383; // LW x7,4(x5)
        tick;
        if (ex_imm !== 6 || ex_rs1_data !== 42) $fatal(1,"ADDI operands");
        fetch_pc = 32; fetch_instr = 32'hfe629ee3; // BNE x5,x6,-4
        tick;
        if ({ex_valid,ex_mem_read,ex_mem_write,ex_reg_write,ex_wb_from_mem} !== 5'b11011 ||
            ex_imm !== 4) $fatal(1,"LW controls");
        fetch_pc = 36; fetch_instr = 32'hffffffff;
        tick;
        if (ex_branch_type !== 2'b10 || ex_imm !== -32'sd4 ||
            ex_reg_write !== 0 || ex_mem_write !== 0) $fatal(1,"BNE bundle");
        if ({valid,uses_rs1,uses_rs2,reg_write,mem_write} !== 0) $fatal(1,"illegal word");
        fetch_instr = 32'h00000013; // real ADDI x0,x0,0
        tick;
        if (ex_valid !== 0 || ex_reg_write !== 0 || ex_mem_write !== 0) $fatal(1,"illegal entry");
        fetch_flush = 1;
        tick;
        if (ex_valid !== 1 || ex_rd !== 0 || ex_imm !== 0) $fatal(1,"valid NOP");
        tick;
        if (ex_valid !== 0 || ex_reg_write !== 0 || ex_mem_write !== 0) $fatal(1,"flushed NOP");
        $display("PASS: IF/ID to ID/EX, WB bypass, hazards metadata and safe bubbles");
        $finish;
    end
endmodule
