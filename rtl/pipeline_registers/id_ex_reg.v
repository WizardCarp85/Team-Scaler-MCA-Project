module id_ex_reg (
    input wire clk,
    input wire rst,
    input wire en,
    input wire flush,
    input wire [31:0] pc_in,
    input wire [31:0] pc_plus4_in,
    input wire [31:0] rs1_data_in,
    input wire [31:0] rs2_data_in,
    input wire [31:0] imm_in,
    input wire [4:0] rs1_in,
    input wire [4:0] rs2_in,
    input wire [4:0] rd_in,
    input wire [2:0] funct3_in,
    input wire [6:0] funct7_in,
    input wire [1:0] alu_op_in,
    input wire [1:0] branch_type_in,
    input wire alu_src_imm_in,
    input wire mem_read_in,
    input wire mem_write_in,
    input wire reg_write_in,
    input wire wb_from_mem_in,
    input wire valid_in,
    output reg [31:0] pc_out,
    output reg [31:0] pc_plus4_out,
    output reg [31:0] rs1_data_out,
    output reg [31:0] rs2_data_out,
    output reg [31:0] imm_out,
    output reg [4:0] rs1_out,
    output reg [4:0] rs2_out,
    output reg [4:0] rd_out,
    output reg [2:0] funct3_out,
    output reg [6:0] funct7_out,
    output reg [1:0] alu_op_out,
    output reg [1:0] branch_type_out,
    output reg alu_src_imm_out,
    output reg mem_read_out,
    output reg mem_write_out,
    output reg reg_write_out,
    output reg wb_from_mem_out,
    output reg valid_out
);
    // Rising edge, synchronous active-high reset. A flush beats a hold.
    // Capturing an invalid entry clears the whole bundle like a flush.
    always @(posedge clk) begin
        if (rst || flush || (en && !valid_in)) begin
            pc_out <= 0;
            pc_plus4_out <= 0;
            rs1_data_out <= 0;
            rs2_data_out <= 0;
            imm_out <= 0;
            rs1_out <= 0;
            rs2_out <= 0;
            rd_out <= 0;
            funct3_out <= 0;
            funct7_out <= 0;
            alu_op_out <= 0;
            branch_type_out <= 0;
            alu_src_imm_out <= 0;
            mem_read_out <= 0;
            mem_write_out <= 0;
            reg_write_out <= 0;
            wb_from_mem_out <= 0;
            valid_out <= 0;
        end else if (en) begin
            pc_out <= pc_in;
            pc_plus4_out <= pc_plus4_in;
            rs1_data_out <= rs1_data_in;
            rs2_data_out <= rs2_data_in;
            imm_out <= imm_in;
            rs1_out <= rs1_in;
            rs2_out <= rs2_in;
            rd_out <= rd_in;
            funct3_out <= funct3_in;
            funct7_out <= funct7_in;
            alu_op_out <= alu_op_in;
            branch_type_out <= branch_type_in;
            alu_src_imm_out <= alu_src_imm_in;
            mem_read_out <= mem_read_in;
            mem_write_out <= mem_write_in;
            reg_write_out <= reg_write_in;
            wb_from_mem_out <= wb_from_mem_in;
            valid_out <= valid_in;
        end
    end
endmodule
