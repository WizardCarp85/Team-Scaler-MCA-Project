`timescale 1ns/1ps

module tb_alu_control;
    reg  [1:0] alu_op;
    reg  [2:0] funct3;
    reg  [6:0] funct7;
    wire [3:0] alu_ctrl;

    integer test_count = 0;
    integer i;

    // Expected control codes matching alu.v parameters
    localparam [3:0] ALU_ADD = 4'b0000;
    localparam [3:0] ALU_SUB = 4'b0001;

    // Instantiate Unit Under Test (UUT)
    alu_control dut (
        .alu_op(alu_op),
        .funct3(funct3),
        .funct7(funct7),
        .alu_ctrl(alu_ctrl)
    );

    // Verification task
    task check;
        input [1:0]   op;
        input [2:0]   f3;
        input [6:0]   f7;
        input [3:0]   exp_ctrl;
        input [159:0] test_name;
        begin
            alu_op = op;
            funct3 = f3;
            funct7 = f7;
            #1;
            if (alu_ctrl !== exp_ctrl) begin
                $fatal(1, "FAIL [%0s]: alu_op=%b funct3=%b funct7=%h | alu_ctrl=%b (expected %b)",
                       test_name, alu_op, funct3, funct7, alu_ctrl, exp_ctrl);
            end
            test_count = test_count + 1;
        end
    endtask

    initial begin
        // ====================================================================
        // 1. R-Type Arithmetic: ADD & SUB (alu_op = 2'b01)
        // ====================================================================
        check(2'b01, 3'b000, 7'h00, ALU_ADD, "R-type ADD (funct3=0, funct7=00)");
        check(2'b01, 3'b000, 7'h20, ALU_SUB, "R-type SUB (funct3=0, funct7=20)");

        // ====================================================================
        // 2. Add / Address Class (alu_op = 2'b00): ADDI, LW, SW
        //    Must unconditionally map to ALU_ADD. Arbitrary bits in the funct7
        //    position (which are actually immediate bits) MUST NOT change the
        //    operation, even when funct7 == 7'h20.
        // ====================================================================
        // Standard ADDI (funct3=000) with 0 immediate
        check(2'b00, 3'b000, 7'h00, ALU_ADD, "ADDI with imm[11:5]=00");
        // ADDI where immediate bits [11:5] happen to be 7'h20 (MUST NOT select SUB!)
        check(2'b00, 3'b000, 7'h20, ALU_ADD, "ADDI with imm[11:5]=20 (crucial: not SUB)");
        // ADDI with negative immediate (sign bits = 7'h7F)
        check(2'b00, 3'b000, 7'h7F, ALU_ADD, "ADDI with negative immediate");
        // LW (funct3=010) with various immediate bit patterns
        check(2'b00, 3'b010, 7'h00, ALU_ADD, "LW with offset=0");
        check(2'b00, 3'b010, 7'h20, ALU_ADD, "LW with offset bit 5 set (not SUB)");
        check(2'b00, 3'b010, 7'h7F, ALU_ADD, "LW with negative offset");
        // SW (funct3=010) with various immediate bit patterns
        check(2'b00, 3'b010, 7'h00, ALU_ADD, "SW with offset=0");
        check(2'b00, 3'b010, 7'h20, ALU_ADD, "SW with offset bit 5 set (not SUB)");
        check(2'b00, 3'b010, 7'h7F, ALU_ADD, "SW with negative offset");
        // Arbitrary immediate bit patterns across diverse funct7/funct3 combinations
        check(2'b00, 3'b001, 7'h55, ALU_ADD, "Add/address arbitrary funct 1");
        check(2'b00, 3'b100, 7'h2A, ALU_ADD, "Add/address arbitrary funct 2");
        check(2'b00, 3'b111, 7'h40, ALU_ADD, "Add/address arbitrary funct 3");
        check(2'b00, 3'b011, 7'h01, ALU_ADD, "Add/address arbitrary funct 4");

        // ====================================================================
        // 3. Invalid R-Type funct Combinations (alu_op = 2'b01)
        //    Must safely default to ALU_ADD and NEVER select ALU_SUB.
        // ====================================================================
        // funct3=000 with invalid funct7
        check(2'b01, 3'b000, 7'h01, ALU_ADD, "Invalid R-type funct7=01");
        check(2'b01, 3'b000, 7'h21, ALU_ADD, "Invalid R-type funct7=21");
        check(2'b01, 3'b000, 7'h08, ALU_ADD, "Invalid R-type funct7=08");
        check(2'b01, 3'b000, 7'h7F, ALU_ADD, "Invalid R-type funct7=7F");
        check(2'b01, 3'b000, 7'h40, ALU_ADD, "Invalid R-type funct7=40");

        // Unsupported funct3 with funct7=7'h00 and funct7=7'h20
        check(2'b01, 3'b001, 7'h00, ALU_ADD, "Unsupported R-type SLL (funct3=001, f7=00)");
        check(2'b01, 3'b001, 7'h20, ALU_ADD, "Unsupported R-type SLL (funct3=001, f7=20)");
        check(2'b01, 3'b010, 7'h00, ALU_ADD, "Unsupported R-type SLT (funct3=010, f7=00)");
        check(2'b01, 3'b010, 7'h20, ALU_ADD, "Unsupported R-type SLT (funct3=010, f7=20)");
        check(2'b01, 3'b011, 7'h00, ALU_ADD, "Unsupported R-type SLTU (funct3=011, f7=00)");
        check(2'b01, 3'b011, 7'h20, ALU_ADD, "Unsupported R-type SLTU (funct3=011, f7=20)");
        check(2'b01, 3'b100, 7'h00, ALU_ADD, "Unsupported R-type XOR (funct3=100, f7=00)");
        check(2'b01, 3'b100, 7'h20, ALU_ADD, "Unsupported R-type XOR (funct3=100, f7=20)");
        check(2'b01, 3'b101, 7'h00, ALU_ADD, "Unsupported R-type SRL (funct3=101, f7=00)");
        check(2'b01, 3'b101, 7'h20, ALU_ADD, "Unsupported R-type SRA (funct3=101, f7=20)");
        check(2'b01, 3'b110, 7'h00, ALU_ADD, "Unsupported R-type OR (funct3=110, f7=00)");
        check(2'b01, 3'b110, 7'h20, ALU_ADD, "Unsupported R-type OR (funct3=110, f7=20)");
        check(2'b01, 3'b111, 7'h00, ALU_ADD, "Unsupported R-type AND (funct3=111, f7=00)");
        check(2'b01, 3'b111, 7'h20, ALU_ADD, "Unsupported R-type AND (funct3=111, f7=20)");
        check(2'b01, 3'b111, 7'h7F, ALU_ADD, "Unsupported R-type AND (funct3=111, f7=7F)");

        // ====================================================================
        // 4. Branch Comparison Class (alu_op = 2'b10)
        //    Deterministic safe default ALU_ADD. Branch evaluation handled by
        //    Issue #14. Must NEVER select SUB even with funct7=7'h20.
        // ====================================================================
        check(2'b10, 3'b000, 7'h00, ALU_ADD, "BEQ with funct7=00");
        check(2'b10, 3'b000, 7'h20, ALU_ADD, "BEQ with funct7=20 (not SUB)");
        check(2'b10, 3'b001, 7'h00, ALU_ADD, "BNE with funct7=00");
        check(2'b10, 3'b001, 7'h20, ALU_ADD, "BNE with funct7=20 (not SUB)");
        check(2'b10, 3'b100, 7'h7F, ALU_ADD, "BLT branch placeholder");
        check(2'b10, 3'b101, 7'h55, ALU_ADD, "BGE branch placeholder");

        // ====================================================================
        // 5. Reserved / Unused alu_op Class (alu_op = 2'b11)
        //    Must deterministically and safely default to ALU_ADD.
        // ====================================================================
        check(2'b11, 3'b000, 7'h00, ALU_ADD, "Unused alu_op 2'b11 (f3=000, f7=00)");
        check(2'b11, 3'b000, 7'h20, ALU_ADD, "Unused alu_op 2'b11 (f3=000, f7=20)");
        check(2'b11, 3'b010, 7'h7F, ALU_ADD, "Unused alu_op 2'b11 (f3=010, f7=7F)");
        check(2'b11, 3'b111, 7'h55, ALU_ADD, "Unused alu_op 2'b11 (f3=111, f7=55)");

        // ====================================================================
        // Final Summary
        // ====================================================================
        $display("PASS: all %0d ALU control decoder tests completed successfully", test_count);
        $finish;
    end

endmodule
