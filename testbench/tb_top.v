// =============================================================================
// Testbench: tb_top
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #26 - Top-Level Pipelined CPU Integration
//
// Description:
//   Verification testbench for top.v wrapper confirming port/structural equivalence
//   with cpu.v.
// =============================================================================

`timescale 1ns/1ps

module tb_top;

    reg         clk;
    reg         rst;

    wire [31:0] debug_if_pc;
    wire [31:0] debug_if_instr;
    wire [31:0] debug_id_pc;
    wire [31:0] debug_id_instr;
    wire        debug_id_valid;
    wire [31:0] debug_ex_pc;
    wire [31:0] debug_ex_alu_result;
    wire        debug_ex_valid;
    wire [31:0] debug_mem_pc;
    wire [31:0] debug_mem_addr;
    wire [31:0] debug_mem_write_data;
    wire        debug_mem_read;
    wire        debug_mem_write;
    wire        debug_mem_valid;
    wire [31:0] debug_wb_pc;
    wire        debug_wb_reg_write;
    wire [4:0]  debug_wb_rd;
    wire [31:0] debug_wb_data;
    wire        debug_wb_retired;

    wire        debug_stall;
    wire        debug_flush;
    wire        debug_branch_taken;
    wire [31:0] debug_branch_target;
    wire [1:0]  debug_forward_a;
    wire [1:0]  debug_forward_b;

    top #(
        .RESET_VECTOR  (32'h0000_0000),
        .IMEM_DEPTH    (256),
        .IMEM_INIT_FILE(""),
        .DMEM_DEPTH    (256),
        .DMEM_INIT_FILE("")
    ) uut (
        .clk                 (clk),
        .rst                 (rst),
        .debug_if_pc         (debug_if_pc),
        .debug_if_instr      (debug_if_instr),
        .debug_id_pc         (debug_id_pc),
        .debug_id_instr      (debug_id_instr),
        .debug_id_valid      (debug_id_valid),
        .debug_ex_pc         (debug_ex_pc),
        .debug_ex_alu_result (debug_ex_alu_result),
        .debug_ex_valid      (debug_ex_valid),
        .debug_mem_pc        (debug_mem_pc),
        .debug_mem_addr      (debug_mem_addr),
        .debug_mem_write_data(debug_mem_write_data),
        .debug_mem_read      (debug_mem_read),
        .debug_mem_write     (debug_mem_write),
        .debug_mem_valid     (debug_mem_valid),
        .debug_wb_pc         (debug_wb_pc),
        .debug_wb_reg_write  (debug_wb_reg_write),
        .debug_wb_rd         (debug_wb_rd),
        .debug_wb_data       (debug_wb_data),
        .debug_wb_retired    (debug_wb_retired),
        .debug_stall         (debug_stall),
        .debug_flush         (debug_flush),
        .debug_branch_taken  (debug_branch_taken),
        .debug_branch_target (debug_branch_target),
        .debug_forward_a     (debug_forward_a),
        .debug_forward_b     (debug_forward_b)
    );

    always #5 clk = ~clk;

    // Helper functions for RV32I encoding
    function [31:0] encode_addi(input [11:0] imm, input [4:0] rs1, input [4:0] rd);
        encode_addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    localparam [31:0] INSTR_NOP = 32'h0000_0013;

    integer i;
    integer test_count = 0;

    initial begin
        clk = 0;
        rst = 1;

        for (i = 0; i < 256; i = i + 1) begin
            uut.u_cpu.u_if_stage.u_instr_mem.mem[i] = INSTR_NOP;
            uut.u_cpu.u_mem_stage.u_data_mem.mem[i] = 32'd0;
        end

        // 0x00: ADDI x1, x0, 42
        uut.u_cpu.u_if_stage.u_instr_mem.mem[0] = encode_addi(12'd42, 5'd0, 5'd1);

        #20;
        @(posedge clk);
        #1;
        rst = 0;

        // Run for 10 cycles
        repeat (10) begin
            @(posedge clk);
            #1;
        end

        // Verify that x1 = 42 was written
        if (uut.u_cpu.u_id_stage.registers.registers[1] !== 32'd42)
            $fatal(1, "FAIL tb_top: Expected x1=42, got %0d", uut.u_cpu.u_id_stage.registers.registers[1]);
        test_count = test_count + 1;

        $display("PASS: all %0d top wrapper tests completed successfully", test_count);
        $finish;
    end

endmodule
