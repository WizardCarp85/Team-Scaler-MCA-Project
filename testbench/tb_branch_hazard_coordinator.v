// =============================================================================
// Testbench: tb_branch_hazard_coordinator
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #23 - Branch Redirect, Flush & Hazard Stall Coordination Logic
//
// Description:
//   Unit test verifying branch_hazard_coordinator wrapper instantiation and
//   port/behavioral equivalence.
// =============================================================================

`timescale 1ns/1ps

module tb_branch_hazard_coordinator;

    reg  [31:0] pc;
    reg  [31:0] pc_plus4;
    reg         branch_taken;
    reg  [31:0] branch_target;
    reg         stall_req;

    wire [31:0] next_pc;
    wire [1:0]  pc_src;
    wire        pc_en;
    wire        if_id_flush;
    wire        if_id_en;
    wire        id_ex_flush;
    wire        id_ex_en;
    wire        stall_out;
    wire        flush_out;

    integer test_count = 0;

    localparam [1:0] PC_PLUS4  = 2'b00;
    localparam [1:0] PC_BRANCH = 2'b01;
    localparam [1:0] PC_HOLD   = 2'b10;

    branch_hazard_coordinator #(
        .PC_PLUS4 (PC_PLUS4),
        .PC_BRANCH(PC_BRANCH),
        .PC_HOLD  (PC_HOLD)
    ) uut (
        .pc           (pc),
        .pc_plus4     (pc_plus4),
        .branch_taken (branch_taken),
        .branch_target(branch_target),
        .stall_req    (stall_req),
        .next_pc      (next_pc),
        .pc_src       (pc_src),
        .pc_en        (pc_en),
        .if_id_flush  (if_id_flush),
        .if_id_en     (if_id_en),
        .id_ex_flush  (id_ex_flush),
        .id_ex_en     (id_ex_en),
        .stall_out    (stall_out),
        .flush_out    (flush_out)
    );

    initial begin
        // Test 1: Normal sequential progression
        pc = 32'h0000_0004; pc_plus4 = 32'h0000_0008;
        branch_taken = 0; branch_target = 32'h0000_0020;
        stall_req = 0;
        #1;
        if (next_pc !== 32'h0000_0008 || pc_src !== PC_PLUS4 || pc_en !== 1'b1 ||
            if_id_flush !== 1'b0 || if_id_en !== 1'b1 ||
            id_ex_flush !== 1'b0 || id_ex_en !== 1'b1 ||
            stall_out !== 1'b0 || flush_out !== 1'b0)
            $fatal(1, "FAIL tb_branch_hazard_coordinator: Test 1 failed");
        test_count = test_count + 1;

        // Test 2: Stall active
        stall_req = 1;
        #1;
        if (next_pc !== 32'h0000_0004 || pc_src !== PC_HOLD || pc_en !== 1'b0 ||
            if_id_flush !== 1'b0 || if_id_en !== 1'b0 ||
            id_ex_flush !== 1'b1 || id_ex_en !== 1'b1 ||
            stall_out !== 1'b1 || flush_out !== 1'b0)
            $fatal(1, "FAIL tb_branch_hazard_coordinator: Test 2 failed");
        test_count = test_count + 1;

        // Test 3: Branch taken overrides stall
        branch_taken = 1;
        #1;
        if (next_pc !== 32'h0000_0020 || pc_src !== PC_BRANCH || pc_en !== 1'b1 ||
            if_id_flush !== 1'b1 || if_id_en !== 1'b1 ||
            id_ex_flush !== 1'b1 || id_ex_en !== 1'b1 ||
            stall_out !== 1'b0 || flush_out !== 1'b1)
            $fatal(1, "FAIL tb_branch_hazard_coordinator: Test 3 failed");
        test_count = test_count + 1;

        // Test 4: Branch taken without stall
        stall_req = 0;
        #1;
        if (next_pc !== 32'h0000_0020 || pc_src !== PC_BRANCH || pc_en !== 1'b1 ||
            if_id_flush !== 1'b1 || if_id_en !== 1'b1 ||
            id_ex_flush !== 1'b1 || id_ex_en !== 1'b1 ||
            stall_out !== 1'b0 || flush_out !== 1'b1)
            $fatal(1, "FAIL tb_branch_hazard_coordinator: Test 4 failed");
        test_count = test_count + 1;

        $display("PASS: all %0d branch_hazard_coordinator alias tests completed successfully", test_count);
        $finish;
    end

endmodule
