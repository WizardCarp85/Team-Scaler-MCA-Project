// =============================================================================
// Module: cpu
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #26 - Top-Level Pipelined CPU Integration
//
// Description:
//   Top-level module integrating the classic 5-stage RISC-V (RV32I subset)
//   in-order pipelined processor:
//     - Instruction Fetch  (IF)  : if_stage (pc + instr_mem + pc+4)
//     - IF/ID Pipeline Reg       : if_id_reg
//     - Instruction Decode (ID)  : id_stage (instruction_decoder + register_file + main_control)
//     - ID/EX Pipeline Reg       : id_ex_reg
//     - Execute            (EX)  : ex_stage (alu + alu_control + branch_unit + forwarding muxes)
//     - EX/MEM Pipeline Reg      : ex_mem_reg
//     - Memory             (MEM) : mem_stage (data_mem + address checking)
//     - MEM/WB Pipeline Reg      : mem_wb_reg
//     - Write-Back         (WB)  : wb_stage (multiplexer + side-effect gating)
//     - Hazard Control           : hazard_detection (load-use stall interlock)
//     - Forwarding Unit          : forwarding_unit (EX-to-EX, MEM-to-EX bypass)
//     - Branch Coordinator       : branch_controller (branch redirect & wrong-path flush)
//
// Supported ISA Subset:
//   ADD, SUB, ADDI, LW, SW, BEQ, BNE
//
// Parameters:
//   RESET_VECTOR    - Initial program counter on reset (default 32'h0000_0000)
//   IMEM_DEPTH      - Instruction memory depth in words (default 256)
//   IMEM_INIT_FILE  - Optional hex image file for instruction memory ($readmemh)
//   DMEM_DEPTH      - Data memory depth in words (default 256 = 1 KiB)
//   DMEM_INIT_FILE  - Optional hex image file for data memory ($readmemh)
// =============================================================================

`timescale 1ns/1ps

module cpu #(
    parameter [31:0] RESET_VECTOR   = 32'h0000_0000,
    parameter        IMEM_DEPTH     = 256,
    parameter        IMEM_INIT_FILE = "",
    parameter        DMEM_DEPTH     = 256,
    parameter        DMEM_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        rst,

    // -------------------------------------------------------------------------
    // Debug & Observability Outputs
    // -------------------------------------------------------------------------
    // Stage PCs and Status
    output wire [31:0] debug_if_pc,
    output wire [31:0] debug_if_instr,
    output wire [31:0] debug_id_pc,
    output wire [31:0] debug_id_instr,
    output wire        debug_id_valid,
    output wire [31:0] debug_ex_pc,
    output wire [31:0] debug_ex_alu_result,
    output wire        debug_ex_valid,
    output wire [31:0] debug_mem_pc,
    output wire [31:0] debug_mem_addr,
    output wire [31:0] debug_mem_write_data,
    output wire        debug_mem_read,
    output wire        debug_mem_write,
    output wire        debug_mem_valid,
    output wire [31:0] debug_wb_pc,
    output wire        debug_wb_reg_write,
    output wire [4:0]  debug_wb_rd,
    output wire [31:0] debug_wb_data,
    output wire        debug_wb_retired,

    // Pipeline Control & Hazard Diagnostics
    output wire        debug_stall,
    output wire        debug_flush,
    output wire        debug_branch_taken,
    output wire [31:0] debug_branch_target,
    output wire [1:0]  debug_forward_a,
    output wire [1:0]  debug_forward_b
);

    // =========================================================================
    // 1. INSTRUCTION FETCH (IF) STAGE
    // =========================================================================
    wire [31:0] if_next_pc;
    wire [31:0] if_pc;
    wire [31:0] if_pc_plus4;
    wire [31:0] if_instr;

    if_stage #(
        .RESET_VECTOR(RESET_VECTOR),
        .DEPTH_WORDS (IMEM_DEPTH),
        .INIT_FILE   (IMEM_INIT_FILE)
    ) u_if_stage (
        .clk     (clk),
        .rst     (rst),
        .next_pc (if_next_pc),
        .pc      (if_pc),
        .pc_plus4(if_pc_plus4),
        .instr   (if_instr)
    );

    // =========================================================================
    // 2. IF/ID PIPELINE BOUNDARY REGISTER
    // =========================================================================
    wire        if_id_en;
    wire        if_id_flush;
    wire [31:0] id_pc_in;
    wire [31:0] id_pc_plus4_in;
    wire [31:0] id_instr_in;
    wire        id_valid_in;

    if_id_reg u_if_id_reg (
        .clk         (clk),
        .rst         (rst),
        .en          (if_id_en),
        .flush       (if_id_flush),
        .pc_in       (if_pc),
        .pc_plus4_in (if_pc_plus4),
        .instr_in    (if_instr),
        .pc_out      (id_pc_in),
        .pc_plus4_out(id_pc_plus4_in),
        .instr_out   (id_instr_in),
        .valid_out   (id_valid_in)
    );

    // =========================================================================
    // 3. INSTRUCTION DECODE (ID) STAGE
    // =========================================================================
    // Feedback signals from WB Stage to Register File
    wire        wb_write_en;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    wire        id_uses_rs1;
    wire        id_uses_rs2;
    wire [31:0] id_pc;
    wire [31:0] id_pc_plus4;
    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;
    wire [31:0] id_imm;
    wire [4:0]  id_rs1;
    wire [4:0]  id_rs2;
    wire [4:0]  id_rd;
    wire [2:0]  id_funct3;
    wire [6:0]  id_funct7;
    wire [1:0]  id_alu_op;
    wire [1:0]  id_branch_type;
    wire        id_alu_src_imm;
    wire        id_mem_read;
    wire        id_mem_write;
    wire        id_reg_write;
    wire        id_wb_from_mem;
    wire        id_valid;

    id_stage u_id_stage (
        .clk          (clk),
        .rst          (rst),
        .instr_in     (id_instr_in),
        .pc_in        (id_pc_in),
        .pc_plus4_in  (id_pc_plus4_in),
        .valid_in     (id_valid_in),
        .wb_write_en  (wb_write_en),
        .wb_rd        (wb_rd),
        .wb_data      (wb_data),
        .uses_rs1     (id_uses_rs1),
        .uses_rs2     (id_uses_rs2),
        .pc           (id_pc),
        .pc_plus4     (id_pc_plus4),
        .rs1_data     (id_rs1_data),
        .rs2_data     (id_rs2_data),
        .imm          (id_imm),
        .rs1          (id_rs1),
        .rs2          (id_rs2),
        .rd           (id_rd),
        .funct3       (id_funct3),
        .funct7       (id_funct7),
        .alu_op       (id_alu_op),
        .branch_type  (id_branch_type),
        .alu_src_imm  (id_alu_src_imm),
        .mem_read     (id_mem_read),
        .mem_write    (id_mem_write),
        .reg_write    (id_reg_write),
        .wb_from_mem  (id_wb_from_mem),
        .valid        (id_valid)
    );

    // =========================================================================
    // 4. ID/EX PIPELINE BOUNDARY REGISTER
    // =========================================================================
    wire        id_ex_en;
    wire        id_ex_flush;
    wire [31:0] ex_pc_in;
    wire [31:0] ex_pc_plus4_in;
    wire [31:0] ex_rs1_data_in;
    wire [31:0] ex_rs2_data_in;
    wire [31:0] ex_imm_in;
    wire [4:0]  ex_rs1_in;
    wire [4:0]  ex_rs2_in;
    wire [4:0]  ex_rd_in;
    wire [2:0]  ex_funct3_in;
    wire [6:0]  ex_funct7_in;
    wire [1:0]  ex_alu_op_in;
    wire [1:0]  ex_branch_type_in;
    wire        ex_alu_src_imm_in;
    wire        ex_mem_read_in;
    wire        ex_mem_write_in;
    wire        ex_reg_write_in;
    wire        ex_wb_from_mem_in;
    wire        ex_valid_in;

    id_ex_reg u_id_ex_reg (
        .clk            (clk),
        .rst            (rst),
        .en             (id_ex_en),
        .flush          (id_ex_flush),
        .pc_in          (id_pc),
        .pc_plus4_in    (id_pc_plus4),
        .rs1_data_in    (id_rs1_data),
        .rs2_data_in    (id_rs2_data),
        .imm_in         (id_imm),
        .rs1_in         (id_rs1),
        .rs2_in         (id_rs2),
        .rd_in          (id_rd),
        .funct3_in      (id_funct3),
        .funct7_in      (id_funct7),
        .alu_op_in      (id_alu_op),
        .branch_type_in (id_branch_type),
        .alu_src_imm_in (id_alu_src_imm),
        .mem_read_in    (id_mem_read),
        .mem_write_in   (id_mem_write),
        .reg_write_in   (id_reg_write),
        .wb_from_mem_in (id_wb_from_mem),
        .valid_in       (id_valid),
        .pc_out         (ex_pc_in),
        .pc_plus4_out   (ex_pc_plus4_in),
        .rs1_data_out   (ex_rs1_data_in),
        .rs2_data_out   (ex_rs2_data_in),
        .imm_out        (ex_imm_in),
        .rs1_out        (ex_rs1_in),
        .rs2_out        (ex_rs2_in),
        .rd_out         (ex_rd_in),
        .funct3_out     (ex_funct3_in),
        .funct7_out     (ex_funct7_in),
        .alu_op_out     (ex_alu_op_in),
        .branch_type_out(ex_branch_type_in),
        .alu_src_imm_out(ex_alu_src_imm_in),
        .mem_read_out   (ex_mem_read_in),
        .mem_write_out  (ex_mem_write_in),
        .reg_write_out  (ex_reg_write_in),
        .wb_from_mem_out(ex_wb_from_mem_in),
        .valid_out      (ex_valid_in)
    );

    // =========================================================================
    // 5. EXECUTION (EX) STAGE & FORWARDING MULTIPLEXERS
    // =========================================================================
    wire [1:0]  forward_a;
    wire [1:0]  forward_b;
    wire [31:0] ex_mem_alu_result_out; // forwarded from EX/MEM boundary
    wire [31:0] ex_alu_result;
    wire        ex_branch_taken;
    wire [31:0] ex_branch_target;
    wire [31:0] ex_store_data;
    wire [4:0]  ex_rd;
    wire [31:0] ex_pc;
    wire [31:0] ex_pc_plus4;
    wire [4:0]  ex_rs1;
    wire [4:0]  ex_rs2;
    wire        ex_mem_read;
    wire        ex_mem_write;
    wire        ex_reg_write;
    wire        ex_wb_from_mem;
    wire        ex_valid;

    ex_stage u_ex_stage (
        .pc_in           (ex_pc_in),
        .pc_plus4_in     (ex_pc_plus4_in),
        .rs1_data_in     (ex_rs1_data_in),
        .rs2_data_in     (ex_rs2_data_in),
        .imm_in          (ex_imm_in),
        .rs1_in          (ex_rs1_in),
        .rs2_in          (ex_rs2_in),
        .rd_in           (ex_rd_in),
        .funct3_in       (ex_funct3_in),
        .funct7_in       (ex_funct7_in),
        .alu_op_in       (ex_alu_op_in),
        .branch_type_in  (ex_branch_type_in),
        .alu_src_imm_in  (ex_alu_src_imm_in),
        .mem_read_in     (ex_mem_read_in),
        .mem_write_in    (ex_mem_write_in),
        .reg_write_in    (ex_reg_write_in),
        .wb_from_mem_in  (ex_wb_from_mem_in),
        .valid_in        (ex_valid_in),
        .forward_a       (forward_a),
        .forward_b       (forward_b),
        .forward_mem_data(ex_mem_alu_result_out),
        .forward_wb_data (wb_data),
        .alu_result      (ex_alu_result),
        .branch_taken    (ex_branch_taken),
        .branch_target   (ex_branch_target),
        .store_data      (ex_store_data),
        .rd              (ex_rd),
        .pc              (ex_pc),
        .pc_plus4        (ex_pc_plus4),
        .rs1             (ex_rs1),
        .rs2             (ex_rs2),
        .mem_read        (ex_mem_read),
        .mem_write       (ex_mem_write),
        .reg_write       (ex_reg_write),
        .wb_from_mem     (ex_wb_from_mem),
        .valid           (ex_valid)
    );

    // =========================================================================
    // 6. EX/MEM PIPELINE BOUNDARY REGISTER
    // =========================================================================
    wire [31:0] mem_store_data_in;
    wire [4:0]  mem_rd_in;
    wire [31:0] mem_pc_in;
    wire [31:0] mem_pc_plus4_in;
    wire        mem_read_in;
    wire        mem_write_in;
    wire        mem_reg_write_in;
    wire        mem_wb_from_mem_in;
    wire        mem_valid_in;

    ex_mem_reg u_ex_mem_reg (
        .clk           (clk),
        .rst           (rst),
        .en            (1'b1), // Advances normally during load-use stall
        .flush         (1'b0),
        .alu_result_in (ex_alu_result),
        .store_data_in (ex_store_data),
        .rd_in         (ex_rd),
        .pc_in         (ex_pc),
        .pc_plus4_in   (ex_pc_plus4),
        .mem_read_in   (ex_mem_read),
        .mem_write_in  (ex_mem_write),
        .reg_write_in  (ex_reg_write),
        .wb_from_mem_in(ex_wb_from_mem),
        .valid_in      (ex_valid),
        .alu_result_out(ex_mem_alu_result_out),
        .store_data_out(mem_store_data_in),
        .rd_out        (mem_rd_in),
        .pc_out        (mem_pc_in),
        .pc_plus4_out  (mem_pc_plus4_in),
        .mem_read_out  (mem_read_in),
        .mem_write_out (mem_write_in),
        .reg_write_out (mem_reg_write_in),
        .wb_from_mem_out(mem_wb_from_mem_in),
        .valid_out     (mem_valid_in)
    );

    // =========================================================================
    // 7. MEMORY (MEM) STAGE
    // =========================================================================
    wire [31:0] mem_alu_result_out;
    wire [31:0] mem_load_data_out;
    wire [4:0]  mem_rd_out;
    wire [31:0] mem_pc_out;
    wire [31:0] mem_pc_plus4_out;
    wire        mem_reg_write_out;
    wire        mem_wb_from_mem_out;
    wire        mem_valid_out;
    wire        mem_access_fault;

    mem_stage #(
        .MEM_DEPTH_WORDS(DMEM_DEPTH),
        .MEM_INIT_FILE  (DMEM_INIT_FILE)
    ) u_mem_stage (
        .clk            (clk),
        .alu_result     (ex_mem_alu_result_out),
        .store_data     (mem_store_data_in),
        .rd             (mem_rd_in),
        .pc             (mem_pc_in),
        .pc_plus4       (mem_pc_plus4_in),
        .mem_read       (mem_read_in),
        .mem_write      (mem_write_in),
        .reg_write      (mem_reg_write_in),
        .wb_from_mem    (mem_wb_from_mem_in),
        .valid          (mem_valid_in),
        .alu_result_out (mem_alu_result_out),
        .load_data_out  (mem_load_data_out),
        .rd_out         (mem_rd_out),
        .pc_out         (mem_pc_out),
        .pc_plus4_out   (mem_pc_plus4_out),
        .reg_write_out  (mem_reg_write_out),
        .wb_from_mem_out(mem_wb_from_mem_out),
        .valid_out      (mem_valid_out),
        .access_fault   (mem_access_fault)
    );

    // =========================================================================
    // 8. MEM/WB PIPELINE BOUNDARY REGISTER
    // =========================================================================
    wire [31:0] wb_alu_result;
    wire [31:0] wb_load_data;
    wire [4:0]  wb_stage_rd;
    wire [31:0] wb_stage_pc;
    wire [31:0] wb_stage_pc_plus4;
    wire        wb_stage_reg_write;
    wire        wb_stage_wb_from_mem;
    wire        wb_stage_valid;

    mem_wb_reg u_mem_wb_reg (
        .clk            (clk),
        .rst            (rst),
        .en             (1'b1),
        .flush          (1'b0),
        .alu_result_in  (mem_alu_result_out),
        .load_data_in   (mem_load_data_out),
        .rd_in          (mem_rd_out),
        .pc_in          (mem_pc_out),
        .pc_plus4_in    (mem_pc_plus4_out),
        .reg_write_in   (mem_reg_write_out),
        .wb_from_mem_in (mem_wb_from_mem_out),
        .valid_in       (mem_valid_out),
        .alu_result_out (wb_alu_result),
        .load_data_out  (wb_load_data),
        .rd_out         (wb_stage_rd),
        .pc_out         (wb_stage_pc),
        .pc_plus4_out   (wb_stage_pc_plus4),
        .reg_write_out  (wb_stage_reg_write),
        .wb_from_mem_out(wb_stage_wb_from_mem),
        .valid_out      (wb_stage_valid)
    );

    // =========================================================================
    // 9. WRITE-BACK (WB) STAGE
    // =========================================================================
    wire [31:0] retired_pc;
    wire [31:0] retired_pc_plus4;
    wire        retired_valid;

    wb_stage u_wb_stage (
        .alu_result  (wb_alu_result),
        .load_data   (wb_load_data),
        .rd          (wb_stage_rd),
        .pc          (wb_stage_pc),
        .pc_plus4    (wb_stage_pc_plus4),
        .reg_write   (wb_stage_reg_write),
        .wb_from_mem (wb_stage_wb_from_mem),
        .valid       (wb_stage_valid),
        .wb_write_en (wb_write_en),
        .wb_rd       (wb_rd),
        .wb_data     (wb_data),
        .pc_out      (retired_pc),
        .pc_plus4_out(retired_pc_plus4),
        .retired     (retired_valid)
    );

    // =========================================================================
    // 10. HAZARD DETECTION UNIT (M5)
    // =========================================================================
    wire hazard_stall;

    hazard_detection u_hazard_detection (
        .id_rs1       (id_rs1),
        .id_rs2       (id_rs2),
        .id_uses_rs1  (id_uses_rs1),
        .id_uses_rs2  (id_uses_rs2),
        .id_valid     (id_valid),
        .ex_rd        (ex_rd_in),
        .ex_mem_read  (ex_mem_read_in),
        .ex_reg_write (ex_reg_write_in),
        .ex_valid     (ex_valid_in),
        .mem_rd       (mem_rd_in),
        .mem_mem_read (mem_read_in),
        .mem_reg_write(mem_reg_write_in),
        .mem_valid    (mem_valid_in),
        .branch_taken (ex_branch_taken),
        .stall        (hazard_stall),
        .pc_stall     (),
        .pc_en        (),
        .if_id_stall  (),
        .if_id_en     (),
        .id_ex_flush  (),
        .id_ex_bubble ()
    );

    // =========================================================================
    // 11. OPERAND FORWARDING UNIT (M5)
    // =========================================================================
    forwarding_unit u_forwarding_unit (
        .id_ex_rs1       (ex_rs1_in),
        .id_ex_rs2       (ex_rs2_in),
        .id_ex_valid     (ex_valid_in),
        .ex_mem_rd       (mem_rd_in),
        .ex_mem_reg_write(mem_reg_write_in),
        .ex_mem_mem_read (mem_read_in),
        .ex_mem_valid    (mem_valid_in),
        .mem_wb_rd       (wb_stage_rd),
        .mem_wb_reg_write(wb_stage_reg_write),
        .mem_wb_valid    (wb_stage_valid),
        .forward_a       (forward_a),
        .forward_b       (forward_b)
    );

    // =========================================================================
    // 12. BRANCH REDIRECT, FLUSH & STALL COORDINATOR (M5)
    // =========================================================================
    wire coord_stall_out;
    wire coord_flush_out;

    branch_controller u_branch_controller (
        .pc           (if_pc),
        .pc_plus4     (if_pc_plus4),
        .branch_taken (ex_branch_taken),
        .branch_target(ex_branch_target),
        .stall_req    (hazard_stall),
        .next_pc      (if_next_pc),
        .pc_src       (),
        .pc_en        (),
        .if_id_flush  (if_id_flush),
        .if_id_en     (if_id_en),
        .id_ex_flush  (id_ex_flush),
        .id_ex_en     (id_ex_en),
        .stall_out    (coord_stall_out),
        .flush_out    (coord_flush_out)
    );

    // =========================================================================
    // 13. DEBUG & OBSERVABILITY PORT ASSIGNMENTS
    // =========================================================================
    assign debug_if_pc          = if_pc;
    assign debug_if_instr       = if_instr;

    assign debug_id_pc          = id_pc;
    assign debug_id_instr       = id_instr_in;
    assign debug_id_valid       = id_valid;

    assign debug_ex_pc          = ex_pc;
    assign debug_ex_alu_result  = ex_alu_result;
    assign debug_ex_valid       = ex_valid;

    assign debug_mem_pc         = mem_pc_out;
    assign debug_mem_addr       = ex_mem_alu_result_out;
    assign debug_mem_write_data = mem_store_data_in;
    assign debug_mem_read       = mem_read_in;
    assign debug_mem_write      = mem_write_in;
    assign debug_mem_valid      = mem_valid_out;

    assign debug_wb_pc          = retired_pc;
    assign debug_wb_reg_write   = wb_write_en;
    assign debug_wb_rd          = wb_rd;
    assign debug_wb_data        = wb_data;
    assign debug_wb_retired     = retired_valid;

    assign debug_stall          = coord_stall_out;
    assign debug_flush          = coord_flush_out;
    assign debug_branch_taken   = ex_branch_taken;
    assign debug_branch_target  = ex_branch_target;
    assign debug_forward_a      = forward_a;
    assign debug_forward_b      = forward_b;

endmodule
