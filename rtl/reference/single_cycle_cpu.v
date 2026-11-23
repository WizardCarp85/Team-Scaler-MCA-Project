// =============================================================================
// Module: single_cycle_cpu
// Project: Team Scaler MCA Project - RISC-V Processor Reference Model
//
// Description:
//   A synthesizable, architectural single-cycle reference CPU implementing
//   the exact identical RV32I instruction subset as the 5-stage pipelined CPU:
//     - ADD, SUB (R-type)
//     - ADDI, LW (I-type)
//     - SW (S-type)
//     - BEQ, BNE (B-type)
//
// Performance Baseline:
//   Every instruction executes to completion in exactly one clock cycle.
//   CPI = 1.000, IPC = 1.000.
//   Serves as an empirical and architectural baseline to evaluate the throughput,
//   cycle-count, and CPI/IPC effects of 5-stage pipelining.
// =============================================================================

`timescale 1ns/1ps

module single_cycle_cpu #(
    parameter [31:0] RESET_VECTOR   = 32'h0000_0000,
    parameter integer IMEM_DEPTH    = 256,
    parameter         IMEM_INIT_FILE = "",
    parameter integer DMEM_DEPTH    = 256
)(
    input  wire        clk,
    input  wire        rst,

    // Observability & Verification Ports
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instr,
    output wire        debug_retired,
    output wire        debug_reg_write,
    output wire [4:0]  debug_rd,
    output wire [31:0] debug_wb_data,
    output wire [31:0] debug_mem_addr,
    output wire [31:0] debug_mem_write_data,
    output wire        debug_mem_read,
    output wire        debug_mem_write,
    output wire        debug_branch_taken,
    output wire [31:0] debug_branch_target
);

    // =========================================================================
    // 1. Program Counter
    // =========================================================================
    reg [31:0] pc;
    wire [31:0] pc_plus_4 = pc + 32'd4;
    wire [31:0] next_pc;

    // =========================================================================
    // 2. Instruction Memory
    // =========================================================================
    reg [31:0] imem [0:IMEM_DEPTH-1];
    integer init_i;

    initial begin
        for (init_i = 0; init_i < IMEM_DEPTH; init_i = init_i + 1)
            imem[init_i] = 32'h0000_0013; // RISC-V NOP (addi x0, x0, 0)
        if (IMEM_INIT_FILE != "")
            $readmemh(IMEM_INIT_FILE, imem);
    end

    wire [31:0] instr = imem[pc[31:2] % IMEM_DEPTH];

    // =========================================================================
    // 3. Instruction Decode & Field Extraction
    // =========================================================================
    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];
    wire [6:0] funct7 = instr[31:25];

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

    // Supported instruction decodes
    wire is_add  = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0000000);
    wire is_sub  = (opcode == 7'b0110011) && (funct3 == 3'b000) && (funct7 == 7'b0100000);
    wire is_addi = (opcode == 7'b0010011) && (funct3 == 3'b000);
    wire is_lw   = (opcode == 7'b0000011) && (funct3 == 3'b010);
    wire is_sw   = (opcode == 7'b0100011) && (funct3 == 3'b010);
    wire is_beq  = (opcode == 7'b1100011) && (funct3 == 3'b000);
    wire is_bne  = (opcode == 7'b1100011) && (funct3 == 3'b001);

    // =========================================================================
    // 4. Register File (x0 hardwired to zero, x1-x31 general purpose)
    // =========================================================================
    reg [31:0] registers [1:31];
    integer rf_i;

    initial begin
        for (rf_i = 1; rf_i < 32; rf_i = rf_i + 1)
            registers[rf_i] = 32'd0;
    end

    wire [31:0] rs1_data = (rs1 == 5'd0) ? 32'd0 : registers[rs1];
    wire [31:0] rs2_data = (rs2 == 5'd0) ? 32'd0 : registers[rs2];

    // =========================================================================
    // 5. ALU & Branch Logic
    // =========================================================================
    wire [31:0] alu_operand_a = rs1_data;
    wire [31:0] alu_operand_b = (is_addi || is_lw) ? imm_i :
                                (is_sw)            ? imm_s :
                                rs2_data;

    wire [31:0] alu_result = (is_sub) ? (alu_operand_a - alu_operand_b) :
                                        (alu_operand_a + alu_operand_b);

    wire branch_condition = (is_beq && (rs1_data == rs2_data)) ||
                           (is_bne && (rs1_data != rs2_data));
    wire branch_taken = (is_beq || is_bne) && branch_condition;
    wire [31:0] branch_target = pc + imm_b;

    assign next_pc = branch_taken ? branch_target : pc_plus_4;

    // =========================================================================
    // 6. Data Memory
    // =========================================================================
    reg [31:0] dmem [0:DMEM_DEPTH-1];
    integer dmem_i;

    initial begin
        for (dmem_i = 0; dmem_i < DMEM_DEPTH; dmem_i = dmem_i + 1)
            dmem[dmem_i] = 32'd0;
    end

    wire [31:0] mem_read_data = dmem[alu_result[31:2] % DMEM_DEPTH];

    always @(posedge clk) begin
        if (!rst && is_sw) begin
            dmem[alu_result[31:2] % DMEM_DEPTH] <= rs2_data;
        end
    end

    // =========================================================================
    // 7. Write-Back & Synchronous State Updates
    // =========================================================================
    wire [31:0] wb_data = is_lw ? mem_read_data : alu_result;
    wire reg_write_en = (is_add || is_sub || is_addi || is_lw) && (rd != 5'd0);

    always @(posedge clk) begin
        if (rst) begin
            pc <= RESET_VECTOR;
            for (rf_i = 1; rf_i < 32; rf_i = rf_i + 1)
                registers[rf_i] <= 32'd0;
        end else begin
            pc <= next_pc;
            if (reg_write_en)
                registers[rd] <= wb_data;
        end
    end

    // =========================================================================
    // 8. Output Diagnostics
    // =========================================================================
    assign debug_pc              = pc;
    assign debug_instr           = instr;
    assign debug_retired         = !rst;
    assign debug_reg_write       = reg_write_en;
    assign debug_rd              = rd;
    assign debug_wb_data         = wb_data;
    assign debug_mem_addr        = alu_result;
    assign debug_mem_write_data  = rs2_data;
    assign debug_mem_read        = is_lw;
    assign debug_mem_write       = is_sw;
    assign debug_branch_taken    = branch_taken;
    assign debug_branch_target   = branch_target;

endmodule
