// =============================================================================
// Testbench: tb_forwarding
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #24 - EX-Stage Forwarding & Bypass Logic
//
// Description:
//   Unit test verifying forwarding wrapper instantiation and equivalence.
// =============================================================================

`timescale 1ns/1ps

module tb_forwarding;

    reg  [4:0]  id_ex_rs1;
    reg  [4:0]  id_ex_rs2;
    reg         id_ex_valid;
    reg  [4:0]  ex_mem_rd;
    reg         ex_mem_reg_write;
    reg         ex_mem_mem_read;
    reg         ex_mem_valid;
    reg  [4:0]  mem_wb_rd;
    reg         mem_wb_reg_write;
    reg         mem_wb_valid;

    wire [1:0]  forward_a;
    wire [1:0]  forward_b;

    integer test_count = 0;

    localparam [1:0] FWD_ID_EX  = 2'b00;
    localparam [1:0] FWD_MEM_WB = 2'b01;
    localparam [1:0] FWD_EX_MEM = 2'b10;

    forwarding #(
        .FWD_ID_EX (FWD_ID_EX),
        .FWD_MEM_WB(FWD_MEM_WB),
        .FWD_EX_MEM(FWD_EX_MEM)
    ) uut (
        .id_ex_rs1        (id_ex_rs1),
        .id_ex_rs2        (id_ex_rs2),
        .id_ex_valid      (id_ex_valid),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_mem_read  (ex_mem_mem_read),
        .ex_mem_valid     (ex_mem_valid),
        .mem_wb_rd        (mem_wb_rd),
        .mem_wb_reg_write (mem_wb_reg_write),
        .mem_wb_valid     (mem_wb_valid),
        .forward_a        (forward_a),
        .forward_b        (forward_b)
    );

    initial begin
        // Test 1: No match -> FWD_ID_EX
        id_ex_rs1 = 5'd1; id_ex_rs2 = 5'd2; id_ex_valid = 1'b1;
        ex_mem_rd = 5'd3; ex_mem_reg_write = 1'b1; ex_mem_mem_read = 1'b0; ex_mem_valid = 1'b1;
        mem_wb_rd = 5'd4; mem_wb_reg_write = 1'b1; mem_wb_valid = 1'b1;
        #1;
        if (forward_a !== FWD_ID_EX || forward_b !== FWD_ID_EX)
            $fatal(1, "FAIL tb_forwarding: No match failed");
        test_count = test_count + 1;

        // Test 2: EX/MEM match on rs1
        id_ex_rs1 = 5'd3;
        #1;
        if (forward_a !== FWD_EX_MEM || forward_b !== FWD_ID_EX)
            $fatal(1, "FAIL tb_forwarding: EX/MEM match on rs1 failed");
        test_count = test_count + 1;

        // Test 3: MEM/WB match on rs2
        id_ex_rs2 = 5'd4;
        #1;
        if (forward_a !== FWD_EX_MEM || forward_b !== FWD_MEM_WB)
            $fatal(1, "FAIL tb_forwarding: MEM/WB match on rs2 failed");
        test_count = test_count + 1;

        // Test 4: Priority check (both match rs1 -> EX/MEM wins)
        mem_wb_rd = 5'd3;
        #1;
        if (forward_a !== FWD_EX_MEM)
            $fatal(1, "FAIL tb_forwarding: Priority check failed");
        test_count = test_count + 1;

        // Test 5: x0 check (rd = 0 -> no forward)
        ex_mem_rd = 5'd0; mem_wb_rd = 5'd0; id_ex_rs1 = 5'd0;
        #1;
        if (forward_a !== FWD_ID_EX)
            $fatal(1, "FAIL tb_forwarding: x0 suppression failed");
        test_count = test_count + 1;

        $display("PASS: all %0d forwarding alias tests completed successfully", test_count);
        $finish;
    end

endmodule
