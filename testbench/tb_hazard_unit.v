// =============================================================================
// Testbench: tb_hazard_unit
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #22 - Load-Use Hazard Detection & Pipeline Stall Control
//
// Description:
//   Unit test verifying hazard_unit wrapper instantiation and equivalence.
// =============================================================================

`timescale 1ns/1ps

module tb_hazard_unit;

    reg  [4:0]  id_rs1;
    reg  [4:0]  id_rs2;
    reg         id_uses_rs1;
    reg         id_uses_rs2;
    reg         id_valid;
    reg  [4:0]  ex_rd;
    reg         ex_mem_read;
    reg         ex_reg_write;
    reg         ex_valid;
    reg  [4:0]  mem_rd;
    reg         mem_mem_read;
    reg         mem_reg_write;
    reg         mem_valid;
    reg         branch_taken;

    wire        stall;
    wire        pc_stall;
    wire        pc_en;
    wire        if_id_stall;
    wire        if_id_en;
    wire        id_ex_flush;
    wire        id_ex_bubble;

    integer test_count = 0;

    hazard_unit uut (
        .id_rs1         (id_rs1),
        .id_rs2         (id_rs2),
        .id_uses_rs1    (id_uses_rs1),
        .id_uses_rs2    (id_uses_rs2),
        .id_valid       (id_valid),
        .ex_rd          (ex_rd),
        .ex_mem_read    (ex_mem_read),
        .ex_reg_write   (ex_reg_write),
        .ex_valid       (ex_valid),
        .mem_rd         (mem_rd),
        .mem_mem_read   (mem_mem_read),
        .mem_reg_write  (mem_reg_write),
        .mem_valid      (mem_valid),
        .branch_taken   (branch_taken),
        .stall          (stall),
        .pc_stall       (pc_stall),
        .pc_en          (pc_en),
        .if_id_stall    (if_id_stall),
        .if_id_en       (if_id_en),
        .id_ex_flush    (id_ex_flush),
        .id_ex_bubble   (id_ex_bubble)
    );

    initial begin
        // Test 1: No hazard
        id_rs1 = 5'd1; id_rs2 = 5'd2; id_uses_rs1 = 1; id_uses_rs2 = 1; id_valid = 1;
        ex_rd = 5'd5; ex_mem_read = 1; ex_reg_write = 1; ex_valid = 1;
        mem_rd = 5'd0; mem_mem_read = 0; mem_reg_write = 0; mem_valid = 0;
        branch_taken = 0;
        #1;
        if (stall !== 1'b0 || pc_en !== 1'b1 || if_id_en !== 1'b1 || id_ex_flush !== 1'b0)
            $fatal(1, "FAIL tb_hazard_unit: No hazard test failed");
        test_count = test_count + 1;

        // Test 2: Load-use on rs1
        id_rs1 = 5'd5;
        #1;
        if (stall !== 1'b1 || pc_en !== 1'b0 || if_id_en !== 1'b0 || id_ex_flush !== 1'b1)
            $fatal(1, "FAIL tb_hazard_unit: Load-use on rs1 failed");
        test_count = test_count + 1;

        // Test 3: Load-use on rs2
        id_rs1 = 5'd1; id_rs2 = 5'd5;
        #1;
        if (stall !== 1'b1 || pc_en !== 1'b0 || if_id_en !== 1'b0 || id_ex_flush !== 1'b1)
            $fatal(1, "FAIL tb_hazard_unit: Load-use on rs2 failed");
        test_count = test_count + 1;

        // Test 4: rd = x0
        ex_rd = 5'd0;
        #1;
        if (stall !== 1'b0 || pc_en !== 1'b1)
            $fatal(1, "FAIL tb_hazard_unit: x0 test failed");
        test_count = test_count + 1;

        $display("PASS: all %0d hazard_unit alias tests completed successfully", test_count);
        $finish;
    end

endmodule
