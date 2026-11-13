// Raw fields are always available. Downstream control must qualify any side
// effects with supported and the IF/ID valid bit.
module instruction_decoder (
    input  wire [31:0] instr,
    output wire [6:0]  opcode,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [6:0]  funct7,
    output reg  [31:0] imm,
    output reg         supported
);
    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    always @* begin
        imm = 32'd0;
        supported = 1'b0;
        case (opcode)
            7'h33: supported = funct3 == 3'b000 &&
                               (funct7 == 7'h00 || funct7 == 7'h20); // ADD, SUB
            7'h13, 7'h03: begin
                if ((opcode == 7'h13 && funct3 == 3'b000) || // ADDI
                    (opcode == 7'h03 && funct3 == 3'b010)) begin // LW
                    supported = 1'b1;
                    imm = {{20{instr[31]}}, instr[31:20]};
                end
            end
            7'h23: if (funct3 == 3'b010) begin // SW
                supported = 1'b1;
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end
            7'h63: if (funct3 == 3'b000 || funct3 == 3'b001) begin // BEQ, BNE
                supported = 1'b1;
                imm = {{19{instr[31]}}, instr[31], instr[7],
                       instr[30:25], instr[11:8], 1'b0};
            end
            default: ; // Unsupported opcode
        endcase
    end
endmodule
