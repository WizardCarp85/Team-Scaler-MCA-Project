// =============================================================================
// Testbench: tb_benchmark_load_store
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #27 - End-to-End Verification & CPI/IPC Analysis
//
// Description:
//   Self-checking verification harness for Benchmark 2 (Memory & Array
//   Access Sequence).
//
//   Executes programs/benchmark_load_store.hex on the integrated 5-stage CPU.
//   Verifies:
//     1. Base pointer arithmetic and word indexing (ADDI).
//     2. Array storage into data memory (SW) at offsets (0x40, 0x44, 0x48, 0x4C, 0x50).
//     3. Array loading from data memory (LW).
//     4. Location-specific verification of each of the 3 intended load-use stall events:
//        - Hazard 1: LW x5 at 0x28 stalling consumer ADD at 0x2C.
//        - Hazard 2: LW x7 at 0x30 stalling consumer ADD at 0x34.
//        - Hazard 3: LW x10 at 0x44 stalling consumer SUB at 0x48.
//        - Guarantees 0 spurious or unrelated stall cycles occur.
//     5. Location-specific verification of RAW forwarding paths:
//        - MEM->EX forwarding of loaded x5 into ADD at 0x2C (debug_forward_a = 2'b01).
//        - EX->EX forwarding of computed x8 into store write data at 0x38 (debug_forward_b = 2'b10).
//        - MEM->EX forwarding of computed x8 into SUB at 0x3C (debug_forward_a = 2'b01).
//     6. Store-to-load ordering: SW to 12(x1) followed later by LW from 12(x1).
//     7. Branch evaluation tied to instruction PC:
//        - BEQ at 0x4C taken forward branch to 0x54 (skipping trap; flush asserted).
//        - Completion self-loop flushes isolated and accounted separately.
//     8. Side-effect suppression (trap at 0x50 squashed; x12 remains 0).
//     9. Complete architectural state verification (registers x1-x12, data memory words 16-20).
//    10. Register x0 read-zero and WB write-suppression invariant runtime checks.
//    11. Bounded cycle timeout protection against hang/infinite loop.
// =============================================================================

`timescale 1ns/1ps

module tb_benchmark_load_store;

    parameter IMEM_HEX = "programs/benchmark_load_store.hex";
    parameter [31:0] DONE_PC = 32'h0000_0054;
    parameter MAX_CYCLES = 500;

    reg         clk;
    reg         rst;

    // Debug & Observability Outputs
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
        .RESET_VECTOR  (32'h0000_0000),
        .IMEM_DEPTH    (256),
        .IMEM_INIT_FILE(IMEM_HEX),
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

    // Clock generator (10ns period -> 100 MHz)
    always #5 clk = ~clk;

    // Simulation metrics & tracking
    integer cycle_count = 0;
    integer retired_count = 0;
    integer total_stall_cycles = 0;
    integer total_flush_cycles = 0;
    integer test_count = 0;
    reg program_completed = 0;

    // Specific load-use hazard tracking
    integer stall_hazard1_cycles = 0; // LW x5 at 0x28 / ADD at 0x2C
    integer stall_hazard2_cycles = 0; // LW x7 at 0x30 / ADD at 0x34
    integer stall_hazard3_cycles = 0; // LW x10 at 0x44 / SUB at 0x48
    integer other_stalls_count  = 0; // Any unexpected stall

    // Specific forwarding path flags
    reg fwd_mem_wb_load_x5_verified = 0; // At 0x2C: debug_forward_a == 2'b01
    reg fwd_ex_mem_store_x8_verified = 0; // At 0x38: debug_forward_b == 2'b10
    reg fwd_mem_wb_sub_x8_verified   = 0; // At 0x3C: debug_forward_a == 2'b01

    // Branch tracking
    integer workload_branch_taken_count = 0; // BEQ at 0x4C taken (target 0x54)
    integer halt_loop_flush_count = 0;       // BEQ at 0x54 completion self-loop

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
            // 1. Location-Specific Load-Use Stall Detection
            // -----------------------------------------------------------------
            if (debug_stall) begin
                if (debug_ex_pc == 32'h0000_0028 && debug_id_pc == 32'h0000_002C)
                    stall_hazard1_cycles <= stall_hazard1_cycles + 1;
                else if (debug_ex_pc == 32'h0000_0030 && debug_id_pc == 32'h0000_0034)
                    stall_hazard2_cycles <= stall_hazard2_cycles + 1;
                else if (debug_ex_pc == 32'h0000_0044 && debug_id_pc == 32'h0000_0048)
                    stall_hazard3_cycles <= stall_hazard3_cycles + 1;
                else
                    other_stalls_count <= other_stalls_count + 1;
            end

            // -----------------------------------------------------------------
            // 2. Location-Specific Forwarding Detection
            // -----------------------------------------------------------------
            if (debug_ex_valid) begin
                // At 0x2C (ADD x6, x5, x4): operand A (x5) forwarded from MEM/WB
                if (debug_ex_pc == 32'h0000_002C && debug_forward_a == 2'b01)
                    fwd_mem_wb_load_x5_verified <= 1;

                // At 0x38 (SW x8, 12(x1)): operand B (x8 store data) forwarded from EX/MEM
                if (debug_ex_pc == 32'h0000_0038 && debug_forward_b == 2'b10)
                    fwd_ex_mem_store_x8_verified <= 1;

                // At 0x3C (SUB x9, x8, x4): operand A (x8) forwarded from MEM/WB
                if (debug_ex_pc == 32'h0000_003C && debug_forward_a == 2'b01)
                    fwd_mem_wb_sub_x8_verified <= 1;
            end

            // -----------------------------------------------------------------
            // 3. Branch Event Tracking
            // -----------------------------------------------------------------
            if (debug_ex_valid) begin
                // BEQ at 0x4C (forward jump over trap)
                if (debug_ex_pc == 32'h0000_004C) begin
                    if (debug_branch_taken && debug_branch_target == 32'h0000_0054 && debug_flush)
                        workload_branch_taken_count <= workload_branch_taken_count + 1;
                end

                // BEQ at 0x54 (completion self-loop)
                if (debug_ex_pc == DONE_PC) begin
                    if (debug_branch_taken && debug_flush)
                        halt_loop_flush_count <= halt_loop_flush_count + 1;
                end
            end

            // -----------------------------------------------------------------
            // 4. Register x0 Read and WB Write-Suppression Invariant Checks
            // -----------------------------------------------------------------
            // Check WB interface invariant: an enabled write is never sent to x0 regardless of data
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
        $dumpfile("simulation/tb_benchmark_load_store.vcd");
        $dumpvars(0, tb_benchmark_load_store);

        clk = 0;
        rst = 1;

        // Hold reset for 20ns
        #20;
        @(posedge clk);
        #1;
        rst = 0;

        $display("================================================================");
        $display("Starting Benchmark 2: Memory & Array Access Sequence");
        $display("Image: %s", IMEM_HEX);
        $display("Halt Address: 0x%08x | Timeout Limit: %0d cycles", DONE_PC, MAX_CYCLES);
        $display("================================================================");

        // Run CPU and wait for completion condition or timeout
        while (!program_completed) begin
            @(posedge clk);
            #1;

            // Log instruction progression per cycle
            $display("[Cycle %03d] IF_PC=%h ID_PC=%h EX_PC=%h MEM_PC=%h WB_PC=%h | Retire=%b (rd=x%0d, data=%0d) | Stall=%b Flush=%b Taken=%b",
                     cycle_count, debug_if_pc, debug_id_pc, debug_ex_pc, debug_mem_pc, debug_wb_pc,
                     debug_wb_retired, debug_wb_rd, debug_wb_data, debug_stall, debug_flush, debug_branch_taken);

            // Bounded cycle timeout
            if (cycle_count >= MAX_CYCLES) begin
                $display("\n[ERROR] Simulation reached maximum cycle limit (%0d) without reaching halt PC %h", MAX_CYCLES, DONE_PC);
                $fatal(1, "TIMEOUT: tb_benchmark_load_store exceeded cycle budget");
            end

            // Detect program completion when the halt self-loop reaches Write-Back
            if (debug_wb_retired && debug_wb_pc == DONE_PC) begin
                $display("[Cycle %03d] Detected retirement of halt self-loop at PC=%h", cycle_count, debug_wb_pc);
                program_completed = 1;
            end
        end

        // Wait 2 additional cycles to ensure all preceding pipeline stages
        // have completed write-back and memory commitments before sampling architectural state.
        // Note: The CPU continues executing the halt self-loop at DONE_PC.
        repeat (2) @(posedge clk);
        #1;

        $display("\n================================================================");
        $display("Architectural State & Functional Verification");
        $display("================================================================");

        // ---------------------------------------------------------------------
        // Register File Checks
        // ---------------------------------------------------------------------
        // Check 1: Register x1 = 64 (0x40, array base pointer)
        if (uut.u_id_stage.registers.registers[1] !== 32'd64)
            $fatal(1, "FAIL Check 1: Register x1 expected 64, got %0d", uut.u_id_stage.registers.registers[1]);
        test_count = test_count + 1;
        $display("  [%02d] Register x1 = 64 (0x40 base pointer) PASS", test_count);

        // Check 2: Register x2 = 68 (0x44, pointer to element 1)
        if (uut.u_id_stage.registers.registers[2] !== 32'd68)
            $fatal(1, "FAIL Check 2: Register x2 expected 68, got %0d", uut.u_id_stage.registers.registers[2]);
        test_count = test_count + 1;
        $display("  [%02d] Register x2 = 68 (0x44 element 1 pointer) PASS", test_count);

        // Check 3: Register x3 = 72 (0x48, pointer to element 2)
        if (uut.u_id_stage.registers.registers[3] !== 32'd72)
            $fatal(1, "FAIL Check 3: Register x3 expected 72, got %0d", uut.u_id_stage.registers.registers[3]);
        test_count = test_count + 1;
        $display("  [%02d] Register x3 = 72 (0x48 element 2 pointer) PASS", test_count);

        // Check 4: Register x4 = 10 (reloaded value 0)
        if (uut.u_id_stage.registers.registers[4] !== 32'd10)
            $fatal(1, "FAIL Check 4: Register x4 expected 10, got %0d", uut.u_id_stage.registers.registers[4]);
        test_count = test_count + 1;
        $display("  [%02d] Register x4 = 10 (loaded element 0) PASS", test_count);

        // Check 5: Register x5 = 25 (loaded value 1)
        if (uut.u_id_stage.registers.registers[5] !== 32'd25)
            $fatal(1, "FAIL Check 5: Register x5 expected 25, got %0d", uut.u_id_stage.registers.registers[5]);
        test_count = test_count + 1;
        $display("  [%02d] Register x5 = 25 (loaded element 1) PASS", test_count);

        // Check 6: Register x6 = 35 (intermediate sum 25 + 10 after load-use stall)
        if (uut.u_id_stage.registers.registers[6] !== 32'd35)
            $fatal(1, "FAIL Check 6: Register x6 expected 35, got %0d", uut.u_id_stage.registers.registers[6]);
        test_count = test_count + 1;
        $display("  [%02d] Register x6 = 35 (intermediate sum 25 + 10 after load-use stall) PASS", test_count);

        // Check 7: Register x7 = 40 (loaded value 2)
        if (uut.u_id_stage.registers.registers[7] !== 32'd40)
            $fatal(1, "FAIL Check 7: Register x7 expected 40, got %0d", uut.u_id_stage.registers.registers[7]);
        test_count = test_count + 1;
        $display("  [%02d] Register x7 = 40 (loaded element 2) PASS", test_count);

        // Check 8: Register x8 = 75 (total sum 35 + 40)
        if (uut.u_id_stage.registers.registers[8] !== 32'd75)
            $fatal(1, "FAIL Check 8: Register x8 expected 75, got %0d", uut.u_id_stage.registers.registers[8]);
        test_count = test_count + 1;
        $display("  [%02d] Register x8 = 75 (total accumulated sum 10 + 25 + 40) PASS", test_count);

        // Check 9: Register x9 = 65 (difference 75 - 10)
        if (uut.u_id_stage.registers.registers[9] !== 32'd65)
            $fatal(1, "FAIL Check 9: Register x9 expected 65, got %0d", uut.u_id_stage.registers.registers[9]);
        test_count = test_count + 1;
        $display("  [%02d] Register x9 = 65 (difference 75 - 10) PASS", test_count);

        // Check 10: Register x10 = 75 (store-to-load ordering verification from mem[0x4C])
        if (uut.u_id_stage.registers.registers[10] !== 32'd75)
            $fatal(1, "FAIL Check 10: Register x10 expected 75, got %0d", uut.u_id_stage.registers.registers[10]);
        test_count = test_count + 1;
        $display("  [%02d] Register x10 = 75 (store-to-load ordering verified) PASS", test_count);

        // Check 11: Register x11 = 0 (subtraction 75 - 75 after load-use stall)
        if (uut.u_id_stage.registers.registers[11] !== 32'd0)
            $fatal(1, "FAIL Check 11: Register x11 expected 0, got %0d", uut.u_id_stage.registers.registers[11]);
        test_count = test_count + 1;
        $display("  [%02d] Register x11 = 0 (subtraction after second load-use stall) PASS", test_count);

        // Check 12: Register x12 = 0 (trap at 0x50 squashed by branch)
        if (uut.u_id_stage.registers.registers[12] !== 32'd0)
            $fatal(1, "FAIL Check 12: Register x12 polluted by squashed trap! Value: %0d", uut.u_id_stage.registers.registers[12]);
        test_count = test_count + 1;
        $display("  [%02d] Register x12 = 0 (wrong-path trap instruction 0x50 squashed) PASS", test_count);

        // ---------------------------------------------------------------------
        // Data Memory Contents Checks
        // ---------------------------------------------------------------------
        // Check 13: mem[0x40] (word 16) = 10
        if (uut.u_mem_stage.u_data_mem.mem[16] !== 32'd10)
            $fatal(1, "FAIL Check 13: Data memory word 16 (0x40) expected 10, got %0d", uut.u_mem_stage.u_data_mem.mem[16]);
        test_count = test_count + 1;
        $display("  [%02d] Data Memory[word 16] (byte 0x40) = 10 PASS", test_count);

        // Check 14: mem[0x44] (word 17) = 25
        if (uut.u_mem_stage.u_data_mem.mem[17] !== 32'd25)
            $fatal(1, "FAIL Check 14: Data memory word 17 (0x44) expected 25, got %0d", uut.u_mem_stage.u_data_mem.mem[17]);
        test_count = test_count + 1;
        $display("  [%02d] Data Memory[word 17] (byte 0x44) = 25 PASS", test_count);

        // Check 15: mem[0x48] (word 18) = 40
        if (uut.u_mem_stage.u_data_mem.mem[18] !== 32'd40)
            $fatal(1, "FAIL Check 15: Data memory word 18 (0x48) expected 40, got %0d", uut.u_mem_stage.u_data_mem.mem[18]);
        test_count = test_count + 1;
        $display("  [%02d] Data Memory[word 18] (byte 0x48) = 40 PASS", test_count);

        // Check 16: mem[0x4C] (word 19) = 75
        if (uut.u_mem_stage.u_data_mem.mem[19] !== 32'd75)
            $fatal(1, "FAIL Check 16: Data memory word 19 (0x4C) expected 75, got %0d", uut.u_mem_stage.u_data_mem.mem[19]);
        test_count = test_count + 1;
        $display("  [%02d] Data Memory[word 19] (byte 0x4C) = 75 (stored sum) PASS", test_count);

        // Check 17: mem[0x50] (word 20) = 65
        if (uut.u_mem_stage.u_data_mem.mem[20] !== 32'd65)
            $fatal(1, "FAIL Check 17: Data memory word 20 (0x50) expected 65, got %0d", uut.u_mem_stage.u_data_mem.mem[20]);
        test_count = test_count + 1;
        $display("  [%02d] Data Memory[word 20] (byte 0x50) = 65 (stored diff) PASS", test_count);

        // ---------------------------------------------------------------------
        // Location-Specific Hazard & Control Checks
        // ---------------------------------------------------------------------
        // Check 18: Load-use hazard 1 (LW at 0x28 / ADD at 0x2C)
        if (stall_hazard1_cycles !== 1)
            $fatal(1, "FAIL Check 18: Expected exactly 1 load-use stall cycle between LW at 0x28 and ADD at 0x2C, got %0d", stall_hazard1_cycles);
        test_count = test_count + 1;
        $display("  [%02d] Load-use hazard 1 verified at LW 0x28 / ADD 0x2C (exactly 1 stall cycle) PASS", test_count);

        // Check 19: Load-use hazard 2 (LW at 0x30 / ADD at 0x34)
        if (stall_hazard2_cycles !== 1)
            $fatal(1, "FAIL Check 19: Expected exactly 1 load-use stall cycle between LW at 0x30 and ADD at 0x34, got %0d", stall_hazard2_cycles);
        test_count = test_count + 1;
        $display("  [%02d] Load-use hazard 2 verified at LW 0x30 / ADD 0x34 (exactly 1 stall cycle) PASS", test_count);

        // Check 20: Load-use hazard 3 (LW at 0x44 / SUB at 0x48)
        if (stall_hazard3_cycles !== 1)
            $fatal(1, "FAIL Check 20: Expected exactly 1 load-use stall cycle between LW at 0x44 and SUB at 0x48, got %0d", stall_hazard3_cycles);
        test_count = test_count + 1;
        $display("  [%02d] Load-use hazard 3 verified at LW 0x44 / SUB 0x48 (exactly 1 stall cycle) PASS", test_count);

        // Check 21: No spurious/unrelated stalls occurred
        if (other_stalls_count !== 0)
            $fatal(1, "FAIL Check 21: Unexpected/spurious stall cycles detected: %0d", other_stalls_count);
        test_count = test_count + 1;
        $display("  [%02d] Spurious stall immunity verified (other stalls = 0) PASS", test_count);

        // Check 22: Forwarding paths verified
        if (!fwd_mem_wb_load_x5_verified)
            $fatal(1, "FAIL Check 22: MEM->EX forwarding of loaded x5 was NOT detected at 0x2C");
        if (!fwd_ex_mem_store_x8_verified)
            $fatal(1, "FAIL Check 22: EX->EX forwarding of store data x8 was NOT detected at 0x38");
        if (!fwd_mem_wb_sub_x8_verified)
            $fatal(1, "FAIL Check 22: MEM->EX forwarding of computed x8 was NOT detected at 0x3C");
        test_count = test_count + 1;
        $display("  [%02d] Location-specific forwarding paths verified (at 0x2C, 0x38, 0x3C) PASS", test_count);

        // Check 23: Workload branch verified (BEQ at 0x4C taken to 0x54)
        if (workload_branch_taken_count !== 1)
            $fatal(1, "FAIL Check 23: Expected exactly 1 taken BEQ branch at 0x4C, got %0d", workload_branch_taken_count);
        test_count = test_count + 1;
        $display("  [%02d] BEQ at 0x4C forward branch = 1 (target 0x54, trap skipped) PASS", test_count);

        // Check 24: Register x0 WB write-suppression invariant and read-as-zero integrity
        if (x0_write_violation)
            $fatal(1, "FAIL Check 24: Enabled write to x0 (reg_write=1 for rd=x0) detected at WB interface!");
        if (x0_read_violation)
            $fatal(1, "FAIL Check 24: Non-zero read from x0 detected in ID stage!");
        test_count = test_count + 1;
        $display("  [%02d] Register x0 WB write-suppression invariant & read-as-zero PASS (directed register-file simulation test in tb_register_file)", test_count);

        $display("================================================================");
        $display("PASS: tb_benchmark_load_store (all %0d checks passed)", test_count);
        $display("Diagnostic Simulation Counters (not validated CPI/IPC):");
        $display("  Total Clock Cycles    : %0d", cycle_count);
        $display("  Retired Instructions  : %0d", retired_count);
        $display("  Load-Use Stall Cycles : %0d (3 verified hazards)", total_stall_cycles);
        $display("  Workload Branch Flushes: %0d (1 forward jump)", workload_branch_taken_count);
        $display("  Halt Self-Loop Flushes : %0d", halt_loop_flush_count);
        $display("================================================================");
        $finish;
    end

endmodule
