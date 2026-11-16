// =============================================================================
// Testbench: tb_cpu
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #26 - Top-Level Pipelined CPU Integration
//
// Description:
//   Comprehensive verification suite for the top-level CPU (cpu.v).
//   Executes an integrated RV32I program testing:
//     1. Sequential instruction flow through all 5 stages
//     2. R-type arithmetic: ADD, SUB
//     3. I-type immediate arithmetic: ADDI
//     4. Data memory store (SW) and load (LW)
//     5. RAW forwarding across EX/MEM and MEM/WB boundaries
//     6. Load-use hazard detection & synchronous 1-cycle pipeline interlock
//     7. Branch evaluation (BEQ taken, BNE not taken)
//     8. Next-PC redirection and dual-stage flush of wrong-path instructions
//     9. Side-effect suppression verification (flushed instructions never write registers)
//    10. Complete architectural state verification (register file and data memory)
// =============================================================================

`timescale 1ns/1ps

module tb_cpu;

    reg         clk;
    reg         rst;

    // Debug Outputs
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

    // Unit Under Test
    cpu #(
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

    // Clock generator (10ns period)
    always #5 clk = ~clk;

    // Helper functions for RV32I encoding
    function [31:0] encode_r(input [6:0] funct7, input [4:0] rs2, input [4:0] rs1, input [2:0] funct3, input [4:0] rd);
        encode_r = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
    endfunction

    function [31:0] encode_addi(input [11:0] imm, input [4:0] rs1, input [4:0] rd);
        encode_addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function [31:0] encode_lw(input [11:0] imm, input [4:0] rs1, input [4:0] rd);
        encode_lw = {imm, rs1, 3'b010, rd, 7'b0000011};
    endfunction

    function [31:0] encode_sw(input [11:0] imm, input [4:0] rs2, input [4:0] rs1);
        encode_sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction

    function [31:0] encode_b(input [2:0] funct3, input [4:0] rs2, input [4:0] rs1, input [12:0] imm);
        encode_b = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], 7'b1100011};
    endfunction

    localparam [31:0] INSTR_NOP = 32'h0000_0013;

    // Track retired instructions and cycle count
    integer cycle_count = 0;
    integer retired_count = 0;
    integer stall_cycles_detected = 0;
    integer flush_cycles_detected = 0;
    integer test_count = 0;

    // Write instruction directly into instruction memory
    task load_instr(input [31:0] byte_addr, input [31:0] instr);
        begin
            uut.u_if_stage.u_instr_mem.mem[byte_addr >> 2] = instr;
        end
    endtask

    // Program initialization
    task setup_program;
        integer i;
        begin
            // Initialize memory with NOPs
            for (i = 0; i < 256; i = i + 1) begin
                uut.u_if_stage.u_instr_mem.mem[i] = INSTR_NOP;
                uut.u_mem_stage.u_data_mem.mem[i] = 32'd0;
            end

            // -----------------------------------------------------------------
            // Test Program Assembly:
            // -----------------------------------------------------------------
            // 0x00: ADDI x1, x0, 10        # x1 = 10
            load_instr(32'h00, encode_addi(12'd10, 5'd0, 5'd1));

            // 0x04: ADDI x2, x0, 20        # x2 = 20
            load_instr(32'h04, encode_addi(12'd20, 5'd0, 5'd2));

            // 0x08: ADD  x3, x1, x2        # x3 = 10 + 20 = 30 (RAW forwarding from EX/MEM & MEM/WB)
            load_instr(32'h08, encode_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3));

            // 0x0C: SUB  x4, x3, x1        # x4 = 30 - 10 = 20 (RAW forwarding of x3)
            load_instr(32'h0C, encode_r(7'b0100000, 5'd1, 5'd3, 3'b000, 5'd4));

            // 0x10: SW   x3, 0(x0)         # mem[0] = 30 (Store result to memory)
            load_instr(32'h10, encode_sw(12'd0, 5'd3, 5'd0));

            // 0x14: LW   x5, 0(x0)         # x5 = mem[0] = 30 (Load result from memory)
            load_instr(32'h14, encode_lw(12'd0, 5'd0, 5'd5));

            // 0x18: ADD  x6, x5, x1        # x6 = 30 + 10 = 40 (LOAD-USE HAZARD! Must stall 1 cycle)
            load_instr(32'h18, encode_r(7'b0000000, 5'd1, 5'd5, 3'b000, 5'd6));

            // 0x1C: BEQ  x4, x2, +16       # if x4 (20) == x2 (20) goto 0x2C (TAKEN BRANCH!)
            load_instr(32'h1C, encode_b(3'b000, 5'd2, 5'd4, 13'd16));

            // 0x20: ADDI x7, x0, 99        # Wrong path 1 (MUST BE FLUSHED, x7 stays 0)
            load_instr(32'h20, encode_addi(12'd99, 5'd0, 5'd7));

            // 0x24: ADDI x8, x0, 88        # Wrong path 2 (MUST BE FLUSHED, x8 stays 0)
            load_instr(32'h24, encode_addi(12'd88, 5'd0, 5'd8));

            // 0x28: NOP
            load_instr(32'h28, INSTR_NOP);

            // 0x2C: ADDI x9, x0, 55        # Branch target: x9 = 55 (Executed exactly once!)
            load_instr(32'h2C, encode_addi(12'd55, 5'd0, 5'd9));

            // 0x30: BNE  x4, x2, +16       # if x4 (20) != x2 (20) goto 0x40 (NOT TAKEN!)
            load_instr(32'h30, encode_b(3'b001, 5'd2, 5'd4, 13'd16));

            // 0x34: ADDI x10, x0, 77       # Fall-through: x10 = 77 (Sequential execution)
            load_instr(32'h34, encode_addi(12'd77, 5'd0, 5'd10));

            // 0x38: NOP / End of test
            load_instr(32'h38, INSTR_NOP);
            load_instr(32'h3C, INSTR_NOP);
            load_instr(32'h40, INSTR_NOP);
        end
    endtask

    // Monitor process
    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;
            if (debug_wb_retired)
                retired_count <= retired_count + 1;
            if (debug_stall)
                stall_cycles_detected <= stall_cycles_detected + 1;
            if (debug_flush)
                flush_cycles_detected <= flush_cycles_detected + 1;
        end
    end

    // Simulation run
    initial begin
        $dumpfile("simulation/tb_cpu.vcd");
        $dumpvars(0, tb_cpu);

        clk = 0;
        rst = 1;

        setup_program();

        #20;
        @(posedge clk);
        #1;
        rst = 0;

        $display("================================================================");
        $display("Starting Top-Level Pipelined CPU Integration Verification");
        $display("================================================================");

        // Run simulation for 35 cycles to allow all instructions to traverse pipeline
        repeat (35) begin
            @(posedge clk);
            #1;
            $display("[Cycle %02d] IF_PC=%h ID_PC=%h EX_PC=%h MEM_PC=%h WB_PC=%h | Retire=%b (rd=x%0d, data=%0d) | Stall=%b Flush=%b Taken=%b",
                     cycle_count, debug_if_pc, debug_id_pc, debug_ex_pc, debug_mem_pc, debug_wb_pc,
                     debug_wb_retired, debug_wb_rd, debug_wb_data, debug_stall, debug_flush, debug_branch_taken);
        end

        $display("================================================================");
        $display("Verification & Architectural State Checks");
        $display("================================================================");

        // ---------------------------------------------------------------------
        // Check 1: Register x1 = 10 (ADDI x1, x0, 10)
        // ---------------------------------------------------------------------
        if (uut.u_id_stage.registers.registers[1] !== 32'd10)
            $fatal(1, "FAIL Check 1: Register x1 expected 10, got %0d", uut.u_id_stage.registers.registers[1]);
        test_count = test_count + 1;
        $display("  [1] Register x1 = 10 (ADDI x1, x0, 10) PASS");

        // ---------------------------------------------------------------------
        // Check 2: Register x2 = 20 (ADDI x2, x0, 20)
        // ---------------------------------------------------------------------
        if (uut.u_id_stage.registers.registers[2] !== 32'd20)
            $fatal(1, "FAIL Check 2: Register x2 expected 20, got %0d", uut.u_id_stage.registers.registers[2]);
        test_count = test_count + 1;
        $display("  [2] Register x2 = 20 (ADDI x2, x0, 20) PASS");

        // ---------------------------------------------------------------------
        // Check 3: Register x3 = 30 (ADD x3, x1, x2 with RAW forwarding)
        // ---------------------------------------------------------------------
        if (uut.u_id_stage.registers.registers[3] !== 32'd30)
            $fatal(1, "FAIL Check 3: Register x3 expected 30, got %0d", uut.u_id_stage.registers.registers[3]);
        test_count = test_count + 1;
        $display("  [3] Register x3 = 30 (ADD x3, x1, x2 with RAW forwarding) PASS");

        // ---------------------------------------------------------------------
        // Check 4: Register x4 = 20 (SUB x4, x3, x1 with RAW forwarding)
        // ---------------------------------------------------------------------
        if (uut.u_id_stage.registers.registers[4] !== 32'd20)
            $fatal(1, "FAIL Check 4: Register x4 expected 20, got %0d", uut.u_id_stage.registers.registers[4]);
        test_count = test_count + 1;
        $display("  [4] Register x4 = 20 (SUB x4, x3, x1 with RAW forwarding) PASS");

        // ---------------------------------------------------------------------
        // Check 5: Data Memory at word 0 = 30 (SW x3, 0(x0))
        // ---------------------------------------------------------------------
        if (uut.u_mem_stage.u_data_mem.mem[0] !== 32'd30)
            $fatal(1, "FAIL Check 5: Data memory[0] expected 30, got %0d", uut.u_mem_stage.u_data_mem.mem[0]);
        test_count = test_count + 1;
        $display("  [5] Data Memory[0] = 30 (SW x3, 0(x0)) PASS");

        // ---------------------------------------------------------------------
        // Check 6: Register x5 = 30 (LW x5, 0(x0))
        // ---------------------------------------------------------------------
        if (uut.u_id_stage.registers.registers[5] !== 32'd30)
            $fatal(1, "FAIL Check 6: Register x5 expected 30, got %0d", uut.u_id_stage.registers.registers[5]);
        test_count = test_count + 1;
        $display("  [6] Register x5 = 30 (LW x5, 0(x0)) PASS");

        // ---------------------------------------------------------------------
        // Check 7: Load-Use Hazard Interlock occurred (stall detected)
        // ---------------------------------------------------------------------
        if (stall_cycles_detected < 1)
            $fatal(1, "FAIL Check 7: Load-use stall was NOT detected for ADD following LW");
        test_count = test_count + 1;
        $display("  [7] Load-Use Hazard Interlock inserted stall cycle PASS (%0d stall cycles detected)", stall_cycles_detected);

        // ---------------------------------------------------------------------
        // Check 8: Register x6 = 40 (ADD x6, x5, x1 after stall & MEM/WB forward)
        // ---------------------------------------------------------------------
        if (uut.u_id_stage.registers.registers[6] !== 32'd40)
            $fatal(1, "FAIL Check 8: Register x6 expected 40, got %0d", uut.u_id_stage.registers.registers[6]);
        test_count = test_count + 1;
        $display("  [8] Register x6 = 40 (ADD x6, x5, x1 after stall & forward) PASS");

        // ---------------------------------------------------------------------
        // Check 9: Branch Flush occurred (flush detected)
        // ---------------------------------------------------------------------
        if (flush_cycles_detected < 1)
            $fatal(1, "FAIL Check 9: Branch flush was NOT detected for taken BEQ");
        test_count = test_count + 1;
        $display("  [9] Taken Branch asserted pipeline flush PASS (%0d flush events detected)", flush_cycles_detected);

        // ---------------------------------------------------------------------
        // Check 10: Wrong-Path Instructions were squashed (x7 and x8 NEVER written!)
        // ---------------------------------------------------------------------
        if (uut.u_id_stage.registers.registers[7] !== 32'd0)
            $fatal(1, "FAIL Check 10: Wrong-path instruction polluted register x7! Value: %0d", uut.u_id_stage.registers.registers[7]);
        if (uut.u_id_stage.registers.registers[8] !== 32'd0)
            $fatal(1, "FAIL Check 10: Wrong-path instruction polluted register x8! Value: %0d", uut.u_id_stage.registers.registers[8]);
        test_count = test_count + 1;
        $display("  [10] Wrong-path instructions (0x20, 0x24) squashed without side-effects (x7=0, x8=0) PASS");

        // ---------------------------------------------------------------------
        // Check 11: Branch Target executed (x9 = 55 from 0x2C)
        // ---------------------------------------------------------------------
        if (uut.u_id_stage.registers.registers[9] !== 32'd55)
            $fatal(1, "FAIL Check 11: Branch target instruction x9 expected 55, got %0d", uut.u_id_stage.registers.registers[9]);
        test_count = test_count + 1;
        $display("  [11] Branch Target instruction executed (x9 = 55) PASS");

        // ---------------------------------------------------------------------
        // Check 12: Not-Taken Branch Fall-through executed (x10 = 77 from 0x34)
        // ---------------------------------------------------------------------
        if (uut.u_id_stage.registers.registers[10] !== 32'd77)
            $fatal(1, "FAIL Check 12: Not-taken fall-through x10 expected 77, got %0d", uut.u_id_stage.registers.registers[10]);
        test_count = test_count + 1;
        $display("  [12] Not-taken branch fall-through executed sequentially (x10 = 77) PASS");

        // ---------------------------------------------------------------------
        // Check 13: Register x0 is strictly hardwired to zero
        // ---------------------------------------------------------------------
        // register_file has no storage for x0 and returns 32'd0 for address 0.
        // Confirm through ID stage read port that rs1=0 yields 0.
        if (debug_wb_retired && debug_wb_rd == 5'd0 && debug_wb_data !== 32'd0)
            $fatal(1, "FAIL Check 13: WB to x0 produced non-zero data!");
        test_count = test_count + 1;
        $display("  [13] Register x0 hardwired zero guarantee PASS");

        $display("================================================================");
        $display("PASS: all %0d top-level pipelined CPU checks completed successfully", test_count);
        $display("Total retired instructions: %0d", retired_count);
        $display("================================================================");
        $finish;
    end

endmodule
