// supported comes from instruction_decoder (including funct7 validation).
// valid_in comes from IF/ID. Unsupported words and bubbles clear every output.
module main_control (
    input  wire       valid_in,
    input  wire       supported,
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    output reg        valid,
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        wb_from_mem,
    output reg        alu_src_imm,
    output reg  [1:0] alu_op,
    output reg  [1:0] branch_type
);
    // alu_op: 00 add/address, 01 register arithmetic (M3 uses funct7),
    // 10 branch compare. branch_type: 00 none, 01 BEQ, 10 BNE.
    always @* begin
        valid = 0;
        reg_write = 0;
        mem_read = 0;
        mem_write = 0;
        wb_from_mem = 0;
        alu_src_imm = 0;
        alu_op = 2'b00;
        branch_type = 2'b00;
        if (valid_in && supported) begin
            case (opcode)
                7'h33: begin // ADD, SUB
                    valid = 1;
                    reg_write = 1;
                    alu_op = 2'b01;
                end
                7'h13: begin // ADDI
                    valid = 1;
                    reg_write = 1;
                    alu_src_imm = 1;
                end
                7'h03: begin // LW
                    valid = 1;
                    reg_write = 1;
                    mem_read = 1;
                    wb_from_mem = 1;
                    alu_src_imm = 1;
                end
                7'h23: begin // SW
                    valid = 1;
                    mem_write = 1;
                    alu_src_imm = 1;
                end
                7'h63: begin // BEQ, BNE
                    valid = 1;
                    alu_op = 2'b10;
                    branch_type = funct3 == 3'b000 ? 2'b01 : 2'b10;
                end
                default: ;
            endcase
        end
    end
endmodule
