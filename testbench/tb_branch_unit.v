`timescale 1ns/1ps

module tb_branch_unit;
    reg         valid;
    reg  [1:0]  branch_type;
    reg  [31:0] pc;
    reg  [31:0] imm;
    reg  [31:0] op_a;
    reg  [31:0] op_b;
    wire        branch_taken;
    wire [31:0] branch_target;

    integer test_count = 0;

    localparam [1:0] BRANCH_NONE = 2'b00;
    localparam [1:0] BRANCH_BEQ  = 2'b01;
    localparam [1:0] BRANCH_BNE  = 2'b10;
    localparam [1:0] BRANCH_RESV = 2'b11;

    branch_unit dut (
        .valid(valid),
        .branch_type(branch_type),
        .pc(pc),
        .imm(imm),
        .op_a(op_a),
        .op_b(op_b),
        .branch_taken(branch_taken),
        .branch_target(branch_target)
    );

    task check;
        input        v;
        input [1:0]  b_type;
        input [31:0] in_pc;
        input [31:0] in_imm;
        input [31:0] a;
        input [31:0] b;
        input        exp_taken;
        input [31:0] exp_target;
        input [191:0] test_name;
        begin
            valid = v;
            branch_type = b_type;
            pc = in_pc;
            imm = in_imm;
            op_a = a;
            op_b = b;
            #1;
            if (branch_taken !== exp_taken || branch_target !== exp_target) begin
                $fatal(1, "FAIL [%0s]: v=%b type=%b pc=%h imm=%h a=%h b=%h | taken=%b (exp %b) target=%h (exp %h)",
                       test_name, valid, branch_type, pc, imm, op_a, op_b,
                       branch_taken, exp_taken, branch_target, exp_target);
            end
            test_count = test_count + 1;
        end
    endtask

    initial begin
        // ====================================================================
        // 1. BEQ: Branch if Equal (branch_type = 2'b01)
        // ====================================================================
        // Equal operands -> taken = 1
        check(1'b1, BRANCH_BEQ, 32'h00001000, 32'sd8, 32'd42, 32'd42,
              1'b1, 32'h00001008, "BEQ equal pos operands -> taken");
        check(1'b1, BRANCH_BEQ, 32'h00001000, 32'sd16, 32'd0, 32'd0,
              1'b1, 32'h00001010, "BEQ equal zero operands -> taken");
        check(1'b1, BRANCH_BEQ, 32'h00001000, -32'sd4, -32'sd10, -32'sd10,
              1'b1, 32'h00000FFC, "BEQ equal neg operands -> taken");
        check(1'b1, BRANCH_BEQ, 32'h00001000, 32'sd0, 32'hFFFFFFFF, 32'hFFFFFFFF,
              1'b1, 32'h00001000, "BEQ equal max unsigned -> taken");

        // Unequal operands -> taken = 0
        check(1'b1, BRANCH_BEQ, 32'h00001000, 32'sd8, 32'd42, 32'd99,
              1'b0, 32'h00001008, "BEQ unequal pos operands -> not taken");
        check(1'b1, BRANCH_BEQ, 32'h00001000, 32'sd8, 32'd0, 32'd1,
              1'b0, 32'h00001008, "BEQ unequal diff LSB -> not taken");
        check(1'b1, BRANCH_BEQ, 32'h00001000, 32'sd8, 32'd0, 32'h80000000,
              1'b0, 32'h00001008, "BEQ unequal diff MSB -> not taken");
        check(1'b1, BRANCH_BEQ, 32'h00001000, 32'sd8, 32'sd50, -32'sd50,
              1'b0, 32'h00001008, "BEQ unequal opposite signs -> not taken");

        // ====================================================================
        // 2. BNE: Branch if Not Equal (branch_type = 2'b10)
        // ====================================================================
        // Unequal operands -> taken = 1
        check(1'b1, BRANCH_BNE, 32'h00002000, 32'sd4, 32'd10, 32'd20,
              1'b1, 32'h00002004, "BNE unequal pos operands -> taken");
        check(1'b1, BRANCH_BNE, 32'h00002000, -32'sd8, 32'd0, 32'd4,
              1'b1, 32'h00001FF8, "BNE unequal zero vs pos -> taken");
        check(1'b1, BRANCH_BNE, 32'h00002000, 32'sd12, 32'sd100, -32'sd100,
              1'b1, 32'h0000200C, "BNE unequal pos vs neg -> taken");
        check(1'b1, BRANCH_BNE, 32'h00002000, 32'sd0, 32'h12345678, 32'h87654321,
              1'b1, 32'h00002000, "BNE unequal arbitrary -> taken");

        // Equal operands -> taken = 0
        check(1'b1, BRANCH_BNE, 32'h00002000, 32'sd4, 32'd42, 32'd42,
              1'b0, 32'h00002004, "BNE equal pos operands -> not taken");
        check(1'b1, BRANCH_BNE, 32'h00002000, 32'sd4, 32'd0, 32'd0,
              1'b0, 32'h00002004, "BNE equal zero operands -> not taken");
        check(1'b1, BRANCH_BNE, 32'h00002000, 32'sd4, -32'sd15, -32'sd15,
              1'b0, 32'h00002004, "BNE equal neg operands -> not taken");
        check(1'b1, BRANCH_BNE, 32'h00002000, 32'sd4, 32'hFFFFFFFF, 32'hFFFFFFFF,
              1'b0, 32'h00002004, "BNE equal max unsigned -> not taken");

        // ====================================================================
        // 3. No-Branch Type (branch_type = 2'b00)
        // ====================================================================
        check(1'b1, BRANCH_NONE, 32'h00003000, 32'sd8, 32'd15, 32'd15,
              1'b0, 32'h00003008, "No-branch with equal operands -> not taken");
        check(1'b1, BRANCH_NONE, 32'h00003000, 32'sd8, 32'd15, 32'd25,
              1'b0, 32'h00003008, "No-branch with unequal operands -> not taken");

        // ====================================================================
        // 4. Reserved Branch Type (branch_type = 2'b11)
        // ====================================================================
        check(1'b1, BRANCH_RESV, 32'h00003000, 32'sd8, 32'd15, 32'd15,
              1'b0, 32'h00003008, "Reserved branch with equal operands -> not taken");
        check(1'b1, BRANCH_RESV, 32'h00003000, 32'sd8, 32'd15, 32'd25,
              1'b0, 32'h00003008, "Reserved branch with unequal operands -> not taken");

        // ====================================================================
        // 5. Invalid / Bubble Inputs (valid = 0)
        //    Must NEVER assert branch_taken even if inputs would otherwise take.
        // ====================================================================
        check(1'b0, BRANCH_BEQ, 32'h00001000, 32'sd8, 32'd42, 32'd42,
              1'b0, 32'h00001008, "valid=0: BEQ equal inputs must NOT take branch");
        check(1'b0, BRANCH_BNE, 32'h00002000, 32'sd8, 32'd10, 32'd20,
              1'b0, 32'h00002008, "valid=0: BNE unequal inputs must NOT take branch");
        check(1'b0, BRANCH_NONE, 32'h00003000, 32'sd0, 32'd0, 32'd0,
              1'b0, 32'h00003000, "valid=0: No-branch bubble");
        check(1'b0, BRANCH_RESV, 32'h00003000, 32'sd0, 32'd0, 32'd0,
              1'b0, 32'h00003000, "valid=0: Reserved branch bubble");

        // ====================================================================
        // 6. Target Address Calculations: Positive, Negative, Zero, Aligned
        // ====================================================================
        // Zero offset
        check(1'b1, BRANCH_BEQ, 32'h00000100, 32'd0, 32'd1, 32'd1,
              1'b1, 32'h00000100, "Target: zero offset");
        // Positive offset (+8)
        check(1'b1, BRANCH_BEQ, 32'h00000100, 32'sd8, 32'd1, 32'd1,
              1'b1, 32'h00000108, "Target: positive offset +8");
        // Positive offset (+40)
        check(1'b1, BRANCH_BEQ, 32'h00000100, 32'sd40, 32'd1, 32'd1,
              1'b1, 32'h00000128, "Target: positive offset +40");
        // Negative offset (-4)
        check(1'b1, BRANCH_BNE, 32'h00000100, -32'sd4, 32'd1, 32'd2,
              1'b1, 32'h000000FC, "Target: negative offset -4");
        // Negative offset (-16)
        check(1'b1, BRANCH_BNE, 32'h00000100, -32'sd16, 32'd1, 32'd2,
              1'b1, 32'h000000F0, "Target: negative offset -16");
        // Max positive 12-bit B-immediate (+4094)
        check(1'b1, BRANCH_BEQ, 32'h00010000, 32'sd4094, 32'd1, 32'd1,
              1'b1, 32'h00010FFE, "Target: max positive B-imm +4094");
        // Min negative 12-bit B-immediate (-4096)
        check(1'b1, BRANCH_BEQ, 32'h00010000, -32'sd4096, 32'd1, 32'd1,
              1'b1, 32'h0000F000, "Target: min negative B-imm -4096");

        // ====================================================================
        // 7. Case proving PC, NOT PC+4, is the target base
        //    For instruction at PC = 0x20 with imm = 8:
        //    Correct target = 0x20 + 8 = 0x28.
        //    Erroneous (PC+4 based) target would be 0x24 + 8 = 0x2C.
        // ====================================================================
        check(1'b1, BRANCH_BEQ, 32'h00000020, 32'sd8, 32'd5, 32'd5,
              1'b1, 32'h00000028, "Proving PC base: 0x20 + 8 = 0x28 (not PC+4 base 0x2C)");

        // ====================================================================
        // 8. Case proving the byte offset is NOT shifted again
        //    imm is already a byte offset (e.g. 8).
        //    Correct target = 0x1000 + 8 = 0x1008.
        //    Erroneously shifted (imm << 1) would yield 0x1010.
        //    Erroneously shifted (imm << 2) would yield 0x1020.
        // ====================================================================
        check(1'b1, BRANCH_BEQ, 32'h00001000, 32'sd8, 32'd7, 32'd7,
              1'b1, 32'h00001008, "Proving no extra shift on pos imm: 0x1000 + 8 = 0x1008");
        check(1'b1, BRANCH_BNE, 32'h00001000, -32'sd4, 32'd7, 32'd8,
              1'b1, 32'h00000FFC, "Proving no extra shift on neg imm: 0x1000 + (-4) = 0x0FFC");

        // ====================================================================
        // 9. 32-bit Target Wraparound
        // ====================================================================
        // Positive overflow wraparound
        check(1'b1, BRANCH_BEQ, 32'hFFFFFFF0, 32'sd32, 32'd1, 32'd1,
              1'b1, 32'h00000010, "Target positive overflow wraparound");
        // Negative underflow wraparound
        check(1'b1, BRANCH_BNE, 32'h00000004, -32'sd8, 32'd1, 32'd2,
              1'b1, 32'hFFFFFFFC, "Target negative underflow wraparound");

        // ====================================================================
        // Final Summary
        // ====================================================================
        $display("PASS: all %0d branch unit tests completed successfully", test_count);
        $finish;
    end

endmodule
