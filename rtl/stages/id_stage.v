module id_stage (
    input wire clk,
    input wire rst,
    input wire [31:0] instr_in, pc_in, pc_plus4_in,
    input wire valid_in,
    input wire wb_write_en,
    input wire [4:0] wb_rd,
    input wire [31:0] wb_data,
    output wire uses_rs1, uses_rs2,
    output wire [31:0] pc,
    output wire [31:0] pc_plus4,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    output wire [31:0] imm,
    output wire [4:0] rs1,
    output wire [4:0] rs2,
    output wire [4:0] rd,
    output wire [2:0] funct3,
    output wire [6:0] funct7,
    output wire [1:0] alu_op,
    output wire [1:0] branch_type,
    output wire alu_src_imm,
    output wire mem_read,
    output wire mem_write,
    output wire reg_write,
    output wire wb_from_mem,
    output wire valid
);
    wire [6:0] opcode;
    wire supported;
    assign pc = pc_in;
    assign pc_plus4 = pc_plus4_in;

    instruction_decoder decoder (
        .instr(instr_in), .opcode(opcode), .rd(rd), .funct3(funct3),
        .rs1(rs1), .rs2(rs2), .funct7(funct7), .imm(imm), .supported(supported)
    );
    register_file registers (
        .clk(clk), .rst(rst), .write_en(wb_write_en), .rd(wb_rd),
        .write_data(wb_data), .rs1(rs1), .rs2(rs2),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );
    main_control control (
        .valid_in(valid_in), .supported(supported), .opcode(opcode), .funct3(funct3),
        .valid(valid), .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .wb_from_mem(wb_from_mem), .alu_src_imm(alu_src_imm),
        .alu_op(alu_op), .branch_type(branch_type)
    );

    // Immediate bits overlap the rs2 field on I-type words.
    assign uses_rs1 = valid;
    assign uses_rs2 = valid && (opcode == 7'h33 || mem_write || branch_type != 0);
endmodule
