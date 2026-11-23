// =============================================================================
// Testbench: tb_benchmark_control_hazards
// Project: Team Scaler MCA Project - RV32I 5-Stage Pipelined Processor
// Issue: #27 - End-to-End Verification & CPI/IPC Analysis
//
// Description:
//   Self-checking verification suite for control-hazard dynamics, branch
//   predictions, dual RAW forwarding, and back-to-back memory access.
//   Executes programs/benchmark_control_hazards.hex on the integrated CPU.
//
// Verifies:
//   1. Conditional BEQ not-taken (fall-through without pipeline flush).
//   2. Conditional BEQ taken (pipeline redirect + 2-stage squash of wrong-path).
//   3. Conditional BNE not-taken (fall-through without pipeline flush).
//   4. Conditional BNE taken (pipeline redirect + 2-stage squash of wrong-path).
//   5. Immediate back-to-back Store-to-Load data dependency (SW then LW at same addr).
//   6. Synchronous 1-cycle load-use interlock stall at LW 0x44 / ADD 0x48.
//   7. Simultaneous dual RAW forwarding: Operand A from MEM/WB and Operand B from EX/MEM.
//   8. Complete side-effect suppression of 7 wrong-path trap instructions (x5, x6, x7, x9, x10, x11, x17).
//   9. Register x0 WB write-suppression invariant and read-as-zero integrity.
//  10. Deterministic program completion detection and bounded cycle timeout.
// =============================================================================

`timescale 1ns/1ps

module tb_benchmark_control_hazards;

    reg clk;
    reg rst;

    // CPU Observability & Debug Interfaces
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

    // Instantiate Top-Level CPU
    cpu #(
        .RESET_VECTOR   (32'h0000_0000),
        .IMEM_DEPTH     (256),
        .IMEM_INIT_FILE ("programs/benchmark_control_hazards.hex"),
        .DMEM_DEPTH     (256)
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

    // Clock generator (10ns period -> 100 MHz)
    always #5 clk = ~clk;

    // Simulation metrics & tracking
    integer cycle_count = 0;
    integer retired_count = 0;
    integer total_stall_cycles = 0;
    integer total_flush_cycles = 0;
    integer test_count = 0;
    reg program_completed = 0;

    // Specific branch evaluation tracking
    integer beq_0x0c_not_taken_count = 0; // BEQ at 0x0C not taken (fall-through)
    integer beq_0x14_taken_count     = 0; // BEQ at 0x14 taken (target 0x24)
    integer bne_0x24_not_taken_count = 0; // BNE at 0x24 not taken (fall-through)
    integer bne_0x2c_taken_count     = 0; // BNE at 0x2C taken (target 0x3C)
    integer beq_0x54_taken_count     = 0; // BEQ at 0x54 taken (target 0x5C)
    integer halt_loop_flush_count    = 0; // BEQ at 0x5C halt self-loop

    // Hazard & Forwarding tracking
    integer load_use_stall_cycles = 0;   // Stall between LW 0x44 and ADD 0x48
    integer spurious_stall_count  = 0;   // Any other stall
    reg dual_forwarding_verified  = 0;   // At 0x50: fwd_a==2'b01 && fwd_b==2'b10

    // x0 runtime check flags
    reg x0_write_violation = 0;
    reg x0_read_violation  = 0;

    // Cycle Monitor and Event Logger
    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;

            if (debug_wb_retired)
                retired_count <= retired_count + 1;

            if (debug_stall)
                total_stall_cycles <= total_stall_cycles + 1;

            if (debug_flush)
                total_flush_cycles <= total_flush_cycles + 1;

            // -----------------------------------------------------------------
            // 1. Branch Evaluation Tracking
            // -----------------------------------------------------------------
            if (debug_ex_valid) begin
                // BEQ at 0x0C (not taken)
                if (debug_ex_pc == 32'h0000_000C) begin
                    if (!debug_branch_taken && !debug_flush)
                        beq_0x0c_not_taken_count <= beq_0x0c_not_taken_count + 1;
                end

                // BEQ at 0x14 (taken to 0x24)
                if (debug_ex_pc == 32'h0000_0014) begin
                    if (debug_branch_taken && debug_branch_target == 32'h0000_0024 && debug_flush)
                        beq_0x14_taken_count <= beq_0x14_taken_count + 1;
                end

                // BNE at 0x24 (not taken)
                if (debug_ex_pc == 32'h0000_0024) begin
                    if (!debug_branch_taken && !debug_flush)
                        bne_0x24_not_taken_count <= bne_0x24_not_taken_count + 1;
                end

                // BNE at 0x2C (taken to 0x3C)
                if (debug_ex_pc == 32'h0000_002C) begin
                    if (debug_branch_taken && debug_branch_target == 32'h0000_003C && debug_flush)
                        bne_0x2c_taken_count <= bne_0x2c_taken_count + 1;
                end

                // BEQ at 0x54 (taken to 0x5C)
                if (debug_ex_pc == 32'h0000_0054) begin
                    if (debug_branch_taken && debug_branch_target == 32'h0000_005C && debug_flush)
                        beq_0x54_taken_count <= beq_0x54_taken_count + 1;
                end

                // BEQ at 0x5C (completion self-loop)
                if (debug_ex_pc == 32'h0000_005C) begin
                    if (debug_branch_taken && debug_branch_target == 32'h0000_005C)
                        halt_loop_flush_count <= halt_loop_flush_count + 1;
                end

                // Dual RAW Forwarding check at 0x50 (SUB x16, x14, x15)
                if (debug_ex_pc == 32'h0000_0050) begin
                    if (debug_forward_a == 2'b01 && debug_forward_b == 2'b10)
                        dual_forwarding_verified <= 1;
                end
            end

            // -----------------------------------------------------------------
            // 2. Load-Use Stall Tracking
            // -----------------------------------------------------------------
            if (debug_stall) begin
                if (debug_ex_pc == 32'h0000_0044 && debug_id_pc == 32'h0000_0048)
                    load_use_stall_cycles <= load_use_stall_cycles + 1;
                else
                    spurious_stall_count <= spurious_stall_count + 1;
            end

            // -----------------------------------------------------------------
            // 3. Register x0 Read and WB Write-Suppression Invariant Checks
            // -----------------------------------------------------------------
            if (debug_wb_retired && debug_wb_reg_write && debug_wb_rd == 5'd0)
                x0_write_violation <= 1;

            if (debug_id_valid) begin
                if (debug_id_instr[19:15] == 5'd0 && uut.u_id_stage.registers.rs1_data !== 32'd0)
                    x0_read_violation <= 1;
                if (debug_id_instr[24:20] == 5'd0 && uut.u_id_stage.registers.rs2_data !== 32'd0)
                    x0_read_violation <= 1;
            end
        end
    end

    // Simulation Execution and Verification
    initial begin
        $dumpfile("simulation/tb_benchmark_control_hazards.vcd");
        $dumpvars(0, tb_benchmark_control_hazards);

        clk = 0;
        rst = 1;

        $display("================================================================");
        $display("Starting Benchmark 3: Control Hazards & Dual Forwarding");
        $display("Image: programs/benchmark_control_hazards.hex");
        $display("Halt Address: 0x0000005C | Timeout Limit: 500 cycles");
        $display("================================================================");

        #20;
        @(posedge clk);
        rst = 0;

        // Run until program completion or timeout
        while (!program_completed && cycle_count < 500) begin
            @(posedge clk);
            #1;
            if (debug_wb_retired && debug_wb_pc == 32'h0000_005C) begin
                $display("[Cycle %03d] Detected retirement of halt self-loop at PC=%08h", cycle_count, debug_wb_pc);
                program_completed = 1;
            end
        end

        if (!program_completed) begin
            $fatal(1, "ERROR: Simulation timed out after %0d cycles without reaching halt condition!", cycle_count);
        end

        // Settle for 2 clock cycles
        @(posedge clk);
        @(posedge clk);
        #1;

        $display("");
        $display("================================================================");
        $display("Architectural State & Functional Verification");
        $display("================================================================");

        // Check 1: Register x1 = 10
        if (uut.u_id_stage.registers.registers[1] !== 32'd10)
            $fatal(1, "FAIL Check 01: Expected x1=10, got %0d", uut.u_id_stage.registers.registers[1]);
        test_count = test_count + 1;
        $display("  [%02d] Register x1 = 10 PASS", test_count);

        // Check 2: Register x2 = 20
        if (uut.u_id_stage.registers.registers[2] !== 32'd20)
            $fatal(1, "FAIL Check 02: Expected x2=20, got %0d", uut.u_id_stage.registers.registers[2]);
        test_count = test_count + 1;
        $display("  [%02d] Register x2 = 20 PASS", test_count);

        // Check 3: Register x3 = 10
        if (uut.u_id_stage.registers.registers[3] !== 32'd10)
            $fatal(1, "FAIL Check 03: Expected x3=10, got %0d", uut.u_id_stage.registers.registers[3]);
        test_count = test_count + 1;
        $display("  [%02d] Register x3 = 10 PASS", test_count);

        // Check 4: BEQ at 0x0C not taken (fall-through)
        if (beq_0x0c_not_taken_count !== 1)
            $fatal(1, "FAIL Check 04: Expected exactly 1 not-taken BEQ at 0x0C, got %0d", beq_0x0c_not_taken_count);
        test_count = test_count + 1;
        $display("  [%02d] BEQ at 0x0C not-taken fall-through = 1 PASS", test_count);

        // Check 5: Register x4 = 30 (fall-through executed)
        if (uut.u_id_stage.registers.registers[4] !== 32'd30)
            $fatal(1, "FAIL Check 05: Expected x4=30, got %0d", uut.u_id_stage.registers.registers[4]);
        test_count = test_count + 1;
        $display("  [%02d] Register x4 = 30 (fall-through executed) PASS", test_count);

        // Check 6: BEQ at 0x14 taken (target 0x24)
        if (beq_0x14_taken_count !== 1)
            $fatal(1, "FAIL Check 06: Expected exactly 1 taken BEQ at 0x14, got %0d", beq_0x14_taken_count);
        test_count = test_count + 1;
        $display("  [%02d] BEQ at 0x14 forward branch taken = 1 (target 0x24) PASS", test_count);

        // Check 7: Traps 1, 2, 3 squashed (x5=0, x6=0, x7=0)
        if (uut.u_id_stage.registers.registers[5] !== 32'd0 ||
            uut.u_id_stage.registers.registers[6] !== 32'd0 ||
            uut.u_id_stage.registers.registers[7] !== 32'd0)
            $fatal(1, "FAIL Check 07: Traps 1-3 were NOT properly squashed! x5=%0d, x6=%0d, x7=%0d",
                   uut.u_id_stage.registers.registers[5],
                   uut.u_id_stage.registers.registers[6],
                   uut.u_id_stage.registers.registers[7]);
        test_count = test_count + 1;
        $display("  [%02d] Wrong-path trap instructions 0x18, 0x1C, 0x20 squashed (x5=0, x6=0, x7=0) PASS", test_count);

        // Check 8: BNE at 0x24 not taken (fall-through)
        if (bne_0x24_not_taken_count !== 1)
            $fatal(1, "FAIL Check 08: Expected exactly 1 not-taken BNE at 0x24, got %0d", bne_0x24_not_taken_count);
        test_count = test_count + 1;
        $display("  [%02d] BNE at 0x24 not-taken fall-through = 1 PASS", test_count);

        // Check 9: Register x8 = 40 (fall-through executed)
        if (uut.u_id_stage.registers.registers[8] !== 32'd40)
            $fatal(1, "FAIL Check 09: Expected x8=40, got %0d", uut.u_id_stage.registers.registers[8]);
        test_count = test_count + 1;
        $display("  [%02d] Register x8 = 40 (fall-through executed) PASS", test_count);

        // Check 10: BNE at 0x2C taken (target 0x3C)
        if (bne_0x2c_taken_count !== 1)
            $fatal(1, "FAIL Check 10: Expected exactly 1 taken BNE at 0x2C, got %0d", bne_0x2c_taken_count);
        test_count = test_count + 1;
        $display("  [%02d] BNE at 0x2C forward branch taken = 1 (target 0x3C) PASS", test_count);

        // Check 11: Traps 4, 5, 6 squashed (x9=0, x10=0, x11=0)
        if (uut.u_id_stage.registers.registers[9] !== 32'd0 ||
            uut.u_id_stage.registers.registers[10] !== 32'd0 ||
            uut.u_id_stage.registers.registers[11] !== 32'd0)
            $fatal(1, "FAIL Check 11: Traps 4-6 were NOT properly squashed! x9=%0d, x10=%0d, x11=%0d",
                   uut.u_id_stage.registers.registers[9],
                   uut.u_id_stage.registers.registers[10],
                   uut.u_id_stage.registers.registers[11]);
        test_count = test_count + 1;
        $display("  [%02d] Wrong-path trap instructions 0x30, 0x34, 0x38 squashed (x9=0, x10=0, x11=0) PASS", test_count);

        // Check 12: Register x12 = 100
        if (uut.u_id_stage.registers.registers[12] !== 32'd100)
            $fatal(1, "FAIL Check 12: Expected x12=100, got %0d", uut.u_id_stage.registers.registers[12]);
        test_count = test_count + 1;
        $display("  [%02d] Register x12 = 100 PASS", test_count);

        // Check 13: Data Memory word 0 = 100
        if (uut.u_mem_stage.u_data_mem.mem[0] !== 32'd100)
            $fatal(1, "FAIL Check 13: Data memory word 0 expected 100, got %0d", uut.u_mem_stage.u_data_mem.mem[0]);
        test_count = test_count + 1;
        $display("  [%02d] Data Memory[word 0] = 100 (SW verified) PASS", test_count);

        // Check 14: Register x13 = 100 (immediate LW after SW)
        if (uut.u_id_stage.registers.registers[13] !== 32'd100)
            $fatal(1, "FAIL Check 14: Expected x13=100 (immediate LW), got %0d", uut.u_id_stage.registers.registers[13]);
        test_count = test_count + 1;
        $display("  [%02d] Register x13 = 100 (immediate back-to-back Store-to-Load) PASS", test_count);

        // Check 15: Load-use stall (exactly 1 cycle)
        if (load_use_stall_cycles !== 1)
            $fatal(1, "FAIL Check 15: Expected exactly 1 load-use stall cycle, got %0d", load_use_stall_cycles);
        test_count = test_count + 1;
        $display("  [%02d] Load-use hazard verified at LW 0x44 / ADD 0x48 (exactly 1 stall cycle) PASS", test_count);

        // Check 16: Spurious stall count = 0
        if (spurious_stall_count !== 0)
            $fatal(1, "FAIL Check 16: Unexpected spurious stalls detected: %0d", spurious_stall_count);
        test_count = test_count + 1;
        $display("  [%02d] Spurious stall immunity verified (other stalls = 0) PASS", test_count);

        // Check 17: Register x14 = 130
        if (uut.u_id_stage.registers.registers[14] !== 32'd130)
            $fatal(1, "FAIL Check 17: Expected x14=130, got %0d", uut.u_id_stage.registers.registers[14]);
        test_count = test_count + 1;
        $display("  [%02d] Register x14 = 130 (ADD with MEM/WB forwarded operand) PASS", test_count);

        // Check 18: Register x15 = 30
        if (uut.u_id_stage.registers.registers[15] !== 32'd30)
            $fatal(1, "FAIL Check 18: Expected x15=30, got %0d", uut.u_id_stage.registers.registers[15]);
        test_count = test_count + 1;
        $display("  [%02d] Register x15 = 30 PASS", test_count);

        // Check 19: Dual RAW forwarding at 0x50 verified
        if (!dual_forwarding_verified)
            $fatal(1, "FAIL Check 19: Dual RAW forwarding (fwd_a=2'b01 and fwd_b=2'b10) NOT observed at 0x50");
        test_count = test_count + 1;
        $display("  [%02d] Simultaneous dual RAW forwarding verified at SUB 0x50 PASS", test_count);

        // Check 20: Register x16 = 100
        if (uut.u_id_stage.registers.registers[16] !== 32'd100)
            $fatal(1, "FAIL Check 20: Expected x16=100, got %0d", uut.u_id_stage.registers.registers[16]);
        test_count = test_count + 1;
        $display("  [%02d] Register x16 = 100 PASS", test_count);

        // Check 21: BEQ at 0x54 taken (target 0x5C)
        if (beq_0x54_taken_count !== 1)
            $fatal(1, "FAIL Check 21: Expected exactly 1 taken BEQ at 0x54, got %0d", beq_0x54_taken_count);
        test_count = test_count + 1;
        $display("  [%02d] BEQ at 0x54 forward branch taken = 1 (target 0x5C) PASS", test_count);

        // Check 22: Trap 7 squashed (x17=0)
        if (uut.u_id_stage.registers.registers[17] !== 32'd0)
            $fatal(1, "FAIL Check 22: Trap 7 was NOT squashed! x17=%0d", uut.u_id_stage.registers.registers[17]);
        test_count = test_count + 1;
        $display("  [%02d] Wrong-path trap instruction 0x58 squashed (x17=0) PASS", test_count);

        // Check 23: Register x0 WB write-suppression invariant and read-as-zero integrity
        if (x0_write_violation)
            $fatal(1, "FAIL Check 23: Enabled write to x0 (reg_write=1 for rd=x0) detected at WB interface!");
        if (x0_read_violation)
            $fatal(1, "FAIL Check 23: Non-zero read from x0 detected in ID stage!");
        test_count = test_count + 1;
        $display("  [%02d] Register x0 WB write-suppression invariant & read-as-zero PASS (directed register-file simulation test in tb_register_file)", test_count);

        $display("================================================================");
        $display("PASS: tb_benchmark_control_hazards (all %0d checks passed)", test_count);
        $display("Diagnostic Simulation Counters (not validated CPI/IPC):");
        $display("  Total Clock Cycles    : %0d", cycle_count);
        $display("  Retired Instructions  : %0d", retired_count);
        $display("  Load-Use Stall Cycles : %0d (exactly 1 verified hazard)", load_use_stall_cycles);
        $display("  Workload Branch Flushes: %0d (3 taken branches)", beq_0x14_taken_count + bne_0x2c_taken_count + beq_0x54_taken_count);
        $display("  Halt Self-Loop Flushes : %0d", halt_loop_flush_count);
        $display("================================================================");
        $finish;
    end

endmodule
