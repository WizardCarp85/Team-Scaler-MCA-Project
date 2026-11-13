`timescale 1ns/1ps

module tb_alu;
    reg  [31:0] a;
    reg  [31:0] b;
    reg  [3:0]  alu_ctrl;
    wire [31:0] result;
    wire        equal;
    wire        zero;

    integer test_count = 0;
    integer op;

    // Operation codes matching alu.v parameters
    localparam [3:0] ALU_ADD = 4'b0000;
    localparam [3:0] ALU_SUB = 4'b0001;

    // Instantiate Unit Under Test (UUT)
    alu dut (
        .a(a),
        .b(b),
        .alu_ctrl(alu_ctrl),
        .result(result),
        .equal(equal),
        .zero(zero)
    );

    // Verification task
    task check;
        input [31:0] op_a;
        input [31:0] op_b;
        input [3:0]  ctrl;
        input [31:0] exp_result;
        input        exp_equal;
        input        exp_zero;
        input [127:0] test_name;
        begin
            a = op_a;
            b = op_b;
            alu_ctrl = ctrl;
            #1;
            if (result !== exp_result || equal !== exp_equal || zero !== exp_zero) begin
                $fatal(1, "FAIL [%0s]: a=%h b=%h ctrl=%b | res=%h (exp %h) eq=%b (exp %b) z=%b (exp %b)",
                       test_name, a, b, alu_ctrl, result, exp_result, equal, exp_equal, zero, exp_zero);
            end
            test_count = test_count + 1;
        end
    endtask

    initial begin
        // ====================================================================
        // 1. ADD: Zero & Positive Operands
        // ====================================================================
        check(32'd0, 32'd0, ALU_ADD, 32'd0, 1'b1, 1'b1, "ADD 0 + 0");
        check(32'd10, 32'd25, ALU_ADD, 32'd35, 1'b0, 1'b0, "ADD positive");
        check(32'd42, 32'd0, ALU_ADD, 32'd42, 1'b0, 1'b0, "ADD positive + 0");
        check(32'd0, 32'd42, ALU_ADD, 32'd42, 1'b0, 1'b0, "ADD 0 + positive");
        check(32'd12345, 32'd67890, ALU_ADD, 32'd80235, 1'b0, 1'b0, "ADD large pos");

        // ====================================================================
        // 2. ADD: Negative Two's-Complement Operands
        // ====================================================================
        check(32'd100, -32'sd25, ALU_ADD, 32'd75, 1'b0, 1'b0, "ADD pos + neg");
        check(32'd25, -32'sd100, ALU_ADD, -32'sd75, 1'b0, 1'b0, "ADD pos + neg (neg res)");
        check(-32'sd10, -32'sd20, ALU_ADD, -32'sd30, 1'b0, 1'b0, "ADD neg + neg");
        check(-32'sd100, 32'd25, ALU_ADD, -32'sd75, 1'b0, 1'b0, "ADD neg + pos");
        // Sum resulting in zero with unequal inputs (tests equal != zero)
        check(32'sd50, -32'sd50, ALU_ADD, 32'd0, 1'b0, 1'b1, "ADD pos + neg = 0");
        check(-32'sd1234, 32'sd1234, ALU_ADD, 32'd0, 1'b0, 1'b1, "ADD neg + pos = 0");

        // ====================================================================
        // 3. ADD: ADDI and LW/SW Effective-Address Calculations
        // ====================================================================
        // Register ADD: rs1 + rs2
        check(32'h0000000A, 32'h00000014, ALU_ADD, 32'h0000001E, 1'b0, 1'b0, "ADD reg+reg");
        // ADDI: positive immediate
        check(32'd10, 32'sd14, ALU_ADD, 32'd24, 1'b0, 1'b0, "ADDI pos imm");
        // ADDI: negative immediate
        check(32'd15, -32'sd20, ALU_ADD, -32'sd5, 1'b0, 1'b0, "ADDI neg imm");
        // ADDI to zero register x0
        check(32'd0, -32'sd1, ALU_ADD, 32'hFFFFFFFF, 1'b0, 1'b0, "ADDI x0 + -1");
        // LW/SW: base address + zero offset
        check(32'h00010000, 32'd0, ALU_ADD, 32'h00010000, 1'b0, 1'b0, "LW/SW offset 0");
        // LW/SW: base address + positive word offset
        check(32'h00010000, 32'd4, ALU_ADD, 32'h00010004, 1'b0, 1'b0, "LW/SW pos offset +4");
        // LW/SW: base address + negative word offset
        check(32'h00010000, -32'sd4, ALU_ADD, 32'h0000FFFC, 1'b0, 1'b0, "LW/SW neg offset -4");
        // LW/SW: max positive 12-bit immediate (+2047)
        check(32'h00002000, 32'sd2047, ALU_ADD, 32'h000027FF, 1'b0, 1'b0, "LW/SW max pos imm");
        // LW/SW: min negative 12-bit immediate (-2048)
        check(32'h00002000, -32'sd2048, ALU_ADD, 32'h00001800, 1'b0, 1'b0, "LW/SW min neg imm");

        // ====================================================================
        // 4. ADD: Carry and Overflow Bit Patterns
        // ====================================================================
        // Signed positive overflow wraps to negative (no trap)
        check(32'h7FFFFFFF, 32'd1, ALU_ADD, 32'h80000000, 1'b0, 1'b0, "ADD pos overflow +1");
        check(32'h7FFFFFFF, 32'h7FFFFFFF, ALU_ADD, 32'hFFFFFFFE, 1'b1, 1'b0, "ADD max pos + max pos");
        // Signed negative overflow wraps to positive (no trap)
        check(32'h80000000, -32'sd1, ALU_ADD, 32'h7FFFFFFF, 1'b0, 1'b0, "ADD neg overflow -1");
        // Min negative + min negative wraps to 0
        check(32'h80000000, 32'h80000000, ALU_ADD, 32'h00000000, 1'b1, 1'b1, "ADD min neg + min neg");
        // Unsigned carry out discarded
        check(32'hFFFFFFFF, 32'd1, ALU_ADD, 32'h00000000, 1'b0, 1'b1, "ADD carry out wrap to 0");
        check(32'hFFFFFFFF, 32'hFFFFFFFF, ALU_ADD, 32'hFFFFFFFE, 1'b1, 1'b0, "ADD max unsigned");

        // ====================================================================
        // 5. SUB: Zero & Positive Operands
        // ====================================================================
        check(32'd0, 32'd0, ALU_SUB, 32'd0, 1'b1, 1'b1, "SUB 0 - 0");
        check(32'd100, 32'd100, ALU_SUB, 32'd0, 1'b1, 1'b1, "SUB equal pos = 0");
        check(32'd50, 32'd20, ALU_SUB, 32'd30, 1'b0, 1'b0, "SUB pos - pos (pos)");
        check(32'd20, 32'd50, ALU_SUB, -32'sd30, 1'b0, 1'b0, "SUB pos - pos (neg)");
        check(32'd100, 32'd0, ALU_SUB, 32'd100, 1'b0, 1'b0, "SUB pos - 0");
        check(32'd0, 32'd1, ALU_SUB, 32'hFFFFFFFF, 1'b0, 1'b0, "SUB 0 - 1");

        // ====================================================================
        // 6. SUB: Negative Two's-Complement Operands
        // ====================================================================
        check(-32'sd50, -32'sd50, ALU_SUB, 32'd0, 1'b1, 1'b1, "SUB equal neg = 0");
        check(32'd50, -32'sd20, ALU_SUB, 32'd70, 1'b0, 1'b0, "SUB pos - neg");
        check(-32'sd20, 32'd50, ALU_SUB, -32'sd70, 1'b0, 1'b0, "SUB neg - pos");
        check(-32'sd50, -32'sd20, ALU_SUB, -32'sd30, 1'b0, 1'b0, "SUB neg - neg (neg)");
        check(-32'sd20, -32'sd50, ALU_SUB, 32'd30, 1'b0, 1'b0, "SUB neg - neg (pos)");

        // ====================================================================
        // 7. SUB: Carry, Borrow and Overflow Bit Patterns
        // ====================================================================
        // Signed negative underflow wraps to positive
        check(32'h80000000, 32'd1, ALU_SUB, 32'h7FFFFFFF, 1'b0, 1'b0, "SUB min neg - 1");
        // Signed positive overflow wraps to negative
        check(32'h7FFFFFFF, -32'sd1, ALU_SUB, 32'h80000000, 1'b0, 1'b0, "SUB max pos - (-1)");
        // Unsigned borrow/underflow
        check(32'h00000000, 32'hFFFFFFFF, ALU_SUB, 32'h00000001, 1'b0, 1'b0, "SUB 0 - max unsgnd");
        check(32'hFFFFFFFF, 32'hFFFFFFFF, ALU_SUB, 32'h00000000, 1'b1, 1'b1, "SUB max - max");
        check(32'h80000000, 32'h80000000, ALU_SUB, 32'h00000000, 1'b1, 1'b1, "SUB min - min");

        // ====================================================================
        // 8. Equality Flag: Equal and Unequal Input Patterns
        // ====================================================================
        // Equal pairs across diverse bit patterns
        check(32'h12345678, 32'h12345678, ALU_ADD, 32'h2468ACF0, 1'b1, 1'b0, "EQ pos identical");
        check(32'hFEDCBA98, 32'hFEDCBA98, ALU_ADD, 32'hFDB97530, 1'b1, 1'b0, "EQ neg identical");
        check(32'h7FFFFFFF, 32'h7FFFFFFF, ALU_ADD, 32'hFFFFFFFE, 1'b1, 1'b0, "EQ max pos identical");
        check(32'h80000000, 32'h80000000, ALU_SUB, 32'h00000000, 1'b1, 1'b1, "EQ min neg identical");
        check(32'hFFFFFFFF, 32'hFFFFFFFF, ALU_SUB, 32'h00000000, 1'b1, 1'b1, "EQ all-ones identical");
        // Unequal pairs differing by single bits
        check(32'h00000000, 32'h00000001, ALU_ADD, 32'h00000001, 1'b0, 1'b0, "NEQ diff LSB");
        check(32'h00000000, 32'h80000000, ALU_ADD, 32'h80000000, 1'b0, 1'b0, "NEQ diff MSB");
        check(32'h00001000, 32'h00000000, ALU_ADD, 32'h00001000, 1'b0, 1'b0, "NEQ diff mid bit");
        check(32'h55555555, 32'hAAAAAAAA, ALU_ADD, 32'hFFFFFFFF, 1'b0, 1'b0, "NEQ alternating bits");
        check(32'd42, 32'd99, ALU_SUB, -32'sd57, 1'b0, 1'b0, "NEQ arbitrary");

        // ====================================================================
        // 9. Unused Operation Codes (4'b0010 through 4'b1111)
        //    Must deterministically and safely output result = 32'h00000000,
        //    while equal flag continues to correctly reflect (a == b).
        // ====================================================================
        for (op = 2; op <= 15; op = op + 1) begin
            // Test with unequal inputs
            check(32'hA5A5A5A5, 32'h5A5A5A5A, op[3:0], 32'h00000000, 1'b0, 1'b1, "Unused code (neq)");
            // Test with equal inputs
            check(32'h12345678, 32'h12345678, op[3:0], 32'h00000000, 1'b1, 1'b1, "Unused code (eq)");
        end

        // ====================================================================
        // Final Summary
        // ====================================================================
        $display("PASS: all %0d ALU tests completed successfully", test_count);
        $finish;
    end

endmodule
