`timescale 1ns/1ps

module tb_ex_stage;
    // ID/EX inputs
    reg  [31:0] pc_in;
    reg  [31:0] pc_plus4_in;
    reg  [31:0] rs1_data_in;
    reg  [31:0] rs2_data_in;
    reg  [31:0] imm_in;
    reg  [4:0]  rs1_in;
    reg  [4:0]  rs2_in;
    reg  [4:0]  rd_in;
    reg  [2:0]  funct3_in;
    reg  [6:0]  funct7_in;
    reg  [1:0]  alu_op_in;
    reg  [1:0]  branch_type_in;
    reg         alu_src_imm_in;
    reg         mem_read_in;
    reg         mem_write_in;
    reg         reg_write_in;
    reg         wb_from_mem_in;
    reg         valid_in;

    // Forwarding inputs
    reg  [1:0]  forward_a;
    reg  [1:0]  forward_b;
    reg  [31:0] forward_mem_data;
    reg  [31:0] forward_wb_data;

    // Outputs
    wire [31:0] alu_result;
    wire        branch_taken;
    wire [31:0] branch_target;
    wire [31:0] store_data;
    wire [4:0]  rd;
    wire [31:0] pc;
    wire [31:0] pc_plus4;
    wire [4:0]  rs1;
    wire [4:0]  rs2;
    wire        mem_read;
    wire        mem_write;
    wire        reg_write;
    wire        wb_from_mem;
    wire        valid;

    integer test_count = 0;

    localparam [1:0] FWD_ID_EX  = 2'b00;
    localparam [1:0] FWD_MEM_WB = 2'b01;
    localparam [1:0] FWD_EX_MEM = 2'b10;

    // Instantiate Unit Under Test (UUT)
    ex_stage dut (
        .pc_in(pc_in),
        .pc_plus4_in(pc_plus4_in),
        .rs1_data_in(rs1_data_in),
        .rs2_data_in(rs2_data_in),
        .imm_in(imm_in),
        .rs1_in(rs1_in),
        .rs2_in(rs2_in),
        .rd_in(rd_in),
        .funct3_in(funct3_in),
        .funct7_in(funct7_in),
        .alu_op_in(alu_op_in),
        .branch_type_in(branch_type_in),
        .alu_src_imm_in(alu_src_imm_in),
        .mem_read_in(mem_read_in),
        .mem_write_in(mem_write_in),
        .reg_write_in(reg_write_in),
        .wb_from_mem_in(wb_from_mem_in),
        .valid_in(valid_in),

        .forward_a(forward_a),
        .forward_b(forward_b),
        .forward_mem_data(forward_mem_data),
        .forward_wb_data(forward_wb_data),

        .alu_result(alu_result),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .store_data(store_data),
        .rd(rd),
        .pc(pc),
        .pc_plus4(pc_plus4),
        .rs1(rs1),
        .rs2(rs2),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .reg_write(reg_write),
        .wb_from_mem(wb_from_mem),
        .valid(valid)
    );

    // Initialize all inputs
    task reset_inputs;
        begin
            pc_in = 32'd0;
            pc_plus4_in = 32'd4;
            rs1_data_in = 32'd0;
            rs2_data_in = 32'd0;
            imm_in = 32'd0;
            rs1_in = 5'd0;
            rs2_in = 5'd0;
            rd_in = 5'd0;
            funct3_in = 3'd0;
            funct7_in = 7'd0;
            alu_op_in = 2'b00;
            branch_type_in = 2'b00;
            alu_src_imm_in = 1'b0;
            mem_read_in = 1'b0;
            mem_write_in = 1'b0;
            reg_write_in = 1'b0;
            wb_from_mem_in = 1'b0;
            valid_in = 1'b1;

            forward_a = FWD_ID_EX;
            forward_b = FWD_ID_EX;
            forward_mem_data = 32'd0;
            forward_wb_data = 32'd0;
        end
    endtask

    initial begin
        reset_inputs();

        // ====================================================================
        // 1. R-Type ADD (x7 = x5 + x6)
        // ====================================================================
        pc_in = 32'h00001000; pc_plus4_in = 32'h00001004;
        rs1_in = 5'd5; rs2_in = 5'd6; rd_in = 5'd7;
        rs1_data_in = 32'd15; rs2_data_in = 32'd25;
        alu_op_in = 2'b01; funct3_in = 3'b000; funct7_in = 7'h00;
        alu_src_imm_in = 1'b0; reg_write_in = 1'b1; valid_in = 1'b1;
        #1;
        if (alu_result !== 32'd40 || store_data !== 32'd25 || rd !== 5'd7 ||
            reg_write !== 1'b1 || mem_read !== 1'b0 || mem_write !== 1'b0 ||
            rs1 !== 5'd5 || rs2 !== 5'd6 || valid !== 1'b1)
            $fatal(1, "FAIL: R-type ADD");
        test_count = test_count + 1;

        // ====================================================================
        // 2. R-Type SUB (x7 = x5 - x6)
        // ====================================================================
        rs1_data_in = 32'd50; rs2_data_in = 32'd20;
        funct7_in = 7'h20;
        #1;
        if (alu_result !== 32'd30 || store_data !== 32'd20)
            $fatal(1, "FAIL: R-type SUB");
        test_count = test_count + 1;

        // ====================================================================
        // 3. I-Type ADDI (x7 = x5 + -10)
        // ====================================================================
        reset_inputs();
        rs1_data_in = 32'd100; imm_in = -32'sd10;
        alu_src_imm_in = 1'b1; alu_op_in = 2'b00;
        reg_write_in = 1'b1; rd_in = 5'd7;
        #1;
        if (alu_result !== 32'd90 || reg_write !== 1'b1)
            $fatal(1, "FAIL: ADDI");
        test_count = test_count + 1;

        // ====================================================================
        // 4. LW Effective Address Calculation
        // ====================================================================
        reset_inputs();
        rs1_data_in = 32'h00010000; imm_in = 32'd8;
        alu_src_imm_in = 1'b1; alu_op_in = 2'b00;
        mem_read_in = 1'b1; reg_write_in = 1'b1; wb_from_mem_in = 1'b1;
        rd_in = 5'd1;
        #1;
        if (alu_result !== 32'h00010008 || mem_read !== 1'b1 ||
            wb_from_mem !== 1'b1 || reg_write !== 1'b1 || mem_write !== 1'b0)
            $fatal(1, "FAIL: LW effective address");
        test_count = test_count + 1;

        // ====================================================================
        // 5. SW Effective Address and Store Data (Unforwarded)
        // ====================================================================
        reset_inputs();
        rs1_data_in = 32'h00010000; imm_in = 32'd12;
        rs2_data_in = 32'hDEADBEEF;
        alu_src_imm_in = 1'b1; alu_op_in = 2'b00;
        mem_write_in = 1'b1;
        #1;
        if (alu_result !== 32'h0001000C || store_data !== 32'hDEADBEEF ||
            mem_write !== 1'b1 || reg_write !== 1'b0)
            $fatal(1, "FAIL: SW unforwarded");
        test_count = test_count + 1;

        // ====================================================================
        // 6. SW with Forwarded Store Data while ALU uses Immediate
        //    (Crucial: store_data must get forwarded rs2, ALU gets immediate)
        // ====================================================================
        reset_inputs();
        rs1_data_in = 32'h00010000; imm_in = 32'd16;
        rs2_data_in = 32'h00000000; // Stale register value
        forward_b = FWD_EX_MEM;
        forward_mem_data = 32'hCAFEBABE; // Fresh forwarded store value
        alu_src_imm_in = 1'b1; alu_op_in = 2'b00;
        mem_write_in = 1'b1;
        #1;
        if (alu_result !== 32'h00010010)
            $fatal(1, "FAIL: SW ALU address did not use immediate");
        if (store_data !== 32'hCAFEBABE)
            $fatal(1, "FAIL: SW store_data did not receive forwarded rs2 value");
        test_count = test_count + 1;

        // ====================================================================
        // 7. Forwarding on ALU Operand A (EX/MEM and MEM/WB)
        // ====================================================================
        reset_inputs();
        alu_op_in = 2'b01; funct3_in = 3'b000; funct7_in = 7'h00; // ADD
        rs1_data_in = 32'd0; rs2_data_in = 32'd10;
        forward_a = FWD_EX_MEM; forward_mem_data = 32'd42;
        #1;
        if (alu_result !== 32'd52)
            $fatal(1, "FAIL: Forward A from EX/MEM");
        test_count = test_count + 1;

        forward_a = FWD_MEM_WB; forward_wb_data = 32'd99;
        #1;
        if (alu_result !== 32'd109)
            $fatal(1, "FAIL: Forward A from MEM/WB");
        test_count = test_count + 1;

        // ====================================================================
        // 8. Forwarding on ALU Operand B (EX/MEM and MEM/WB)
        // ====================================================================
        reset_inputs();
        alu_op_in = 2'b01; funct3_in = 3'b000; funct7_in = 7'h00; // ADD
        rs1_data_in = 32'd10; rs2_data_in = 32'd0;
        forward_b = FWD_EX_MEM; forward_mem_data = 32'd25;
        #1;
        if (alu_result !== 32'd35)
            $fatal(1, "FAIL: Forward B from EX/MEM");
        test_count = test_count + 1;

        forward_b = FWD_MEM_WB; forward_wb_data = 32'd70;
        #1;
        if (alu_result !== 32'd80)
            $fatal(1, "FAIL: Forward B from MEM/WB");
        test_count = test_count + 1;

        // ====================================================================
        // 9. Simultaneous Forwarding on Both Operands
        // ====================================================================
        forward_a = FWD_EX_MEM; forward_mem_data = 32'd50;
        forward_b = FWD_MEM_WB; forward_wb_data = 32'd30;
        #1;
        if (alu_result !== 32'd80)
            $fatal(1, "FAIL: Simultaneous Forward A and B");
        test_count = test_count + 1;

        // ====================================================================
        // 10. BEQ / BNE Branch Evaluation and Forwarding
        // ====================================================================
        reset_inputs();
        pc_in = 32'h00000040; imm_in = 32'sd8;
        branch_type_in = 2'b01; // BEQ
        rs1_data_in = 32'd100; rs2_data_in = 32'd100; // Equal
        #1;
        if (branch_taken !== 1'b1 || branch_target !== 32'h00000048)
            $fatal(1, "FAIL: BEQ taken without forwarding");
        test_count = test_count + 1;

        rs2_data_in = 32'd200; // Unequal
        #1;
        if (branch_taken !== 1'b0 || branch_target !== 32'h00000048)
            $fatal(1, "FAIL: BEQ not-taken without forwarding");
        test_count = test_count + 1;

        // BEQ equal through forwarding on operand A
        forward_a = FWD_EX_MEM; forward_mem_data = 32'd200; // Now equal to rs2_data_in
        #1;
        if (branch_taken !== 1'b1)
            $fatal(1, "FAIL: BEQ equal via Forward A");
        test_count = test_count + 1;

        // BNE unequal through forwarding on operand B
        reset_inputs();
        pc_in = 32'h00000080; imm_in = -32'sd4;
        branch_type_in = 2'b10; // BNE
        rs1_data_in = 32'd50; rs2_data_in = 32'd50; // Initially equal
        #1;
        if (branch_taken !== 1'b0 || branch_target !== 32'h0000007C)
            $fatal(1, "FAIL: BNE equal (not taken)");
        test_count = test_count + 1;

        forward_b = FWD_MEM_WB; forward_wb_data = 32'd51; // Now unequal
        #1;
        if (branch_taken !== 1'b1 || branch_target !== 32'h0000007C)
            $fatal(1, "FAIL: BNE unequal via Forward B");
        test_count = test_count + 1;

        // ====================================================================
        // 11. Pass-Through Metadata and Indices
        // ====================================================================
        reset_inputs();
        pc_in = 32'h00002000; pc_plus4_in = 32'h00002004;
        rs1_in = 5'd11; rs2_in = 5'd12; rd_in = 5'd13;
        #1;
        if (pc !== 32'h00002000 || pc_plus4 !== 32'h00002004 ||
            rs1 !== 5'd11 || rs2 !== 5'd12 || rd !== 5'd13)
            $fatal(1, "FAIL: Metadata pass-through");
        test_count = test_count + 1;

        // ====================================================================
        // 12. Invalid / Bubble Inputs and Side-Effect Suppression (valid_in = 0)
        // ====================================================================
        reset_inputs();
        valid_in = 1'b0;
        // Set all side-effect enables and branch condition true
        branch_type_in = 2'b01; rs1_data_in = 32'd42; rs2_data_in = 32'd42;
        mem_read_in = 1'b1; mem_write_in = 1'b1;
        reg_write_in = 1'b1; wb_from_mem_in = 1'b1;
        #1;
        if (valid !== 1'b0)
            $fatal(1, "FAIL: valid flag was not 0");
        if (branch_taken !== 1'b0)
            $fatal(1, "FAIL: branch_taken asserted on bubble");
        if (mem_read !== 1'b0 || mem_write !== 1'b0 ||
            reg_write !== 1'b0 || wb_from_mem !== 1'b0)
            $fatal(1, "FAIL: Side-effect controls not suppressed on bubble");
        test_count = test_count + 1;

        // ====================================================================
        // Final Summary
        // ====================================================================
        $display("PASS: all %0d EX stage datapath tests completed successfully", test_count);
        $finish;
    end

endmodule
