// =============================================================================
// Testbench: tb_benchmark_accumulate
// Project: Team Scaler MCA Project - RV32I Pipelined Processor
// Issue: #27 - End-to-End Verification & CPI/IPC Analysis
//
// Description:
//   Self-checking verification harness for Benchmark 1 (Arithmetic &
//   Accumulator Loop).
//
//   Executes programs/benchmark_accumulate.hex on the integrated 5-stage CPU.
//   Verifies:
//     1. Sequential and iterative arithmetic execution (ADDI, ADD, SUB).
//     2. Dynamic verification of RAW forwarding selections at consumer PCs:
//        - EX->EX forwarding (FWD_EX_MEM = 2'b10) for x1 at 0x14 (ADD).
//        - MEM->EX forwarding (FWD_MEM_WB = 2'b01) for x1 at 0x18 (SUB).
//     3. Branch evaluation tied to specific instruction PCs:
//        - BNE at 0x1C taken exactly 4 times with target 0x10 and flush asserted.
//        - BNE at 0x1C not taken exactly 1 time on loop termination with flush deasserted.
//        - BEQ at 0x28 taken exactly 1 time with target 0x30 and flush asserted.
//        - Completion self-loop flushes isolated and accounted separately.
//     4. Wrong-path instruction squash (trap at 0x2C never writes state; x7 remains 0).
//     5. Architectural register file state verification (x1-x6, x7).
//     6. Register x0 read-zero and WB write-suppression invariant runtime checks.
//     7. Bounded cycle timeout protection against hang/infinite loop.
// =============================================================================

`timescale 1ns/1ps

module tb_benchmark_accumulate;

    parameter IMEM_HEX = "programs/benchmark_accumulate.hex";
    parameter [31:0] DONE_PC = 32'h0000_0030;
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

    // Simulation metrics & event tracking
    integer cycle_count = 0;
    integer retired_count = 0;
    integer stall_cycles_detected = 0;
    integer total_flush_cycles = 0;
    integer test_count = 0;
    reg program_completed = 0;

    // PC-specific branch tracking
    integer loop_branch_taken_count = 0;     // BNE at 0x1C taken (target 0x10)
    integer loop_branch_not_taken_count = 0; // BNE at 0x1C not taken (fall-through)
    integer forward_branch_taken_count = 0;  // BEQ at 0x28 taken (target 0x30)
    integer halt_loop_flush_count = 0;       // BEQ at 0x30 completion self-loop

    // Specific forwarding path flags
    reg fwd_ex_mem_verified = 0; // Verified debug_forward_b == 2'b10 at 0x14
    reg fwd_mem_wb_verified = 0; // Verified debug_forward_b == 2'b01 at 0x18

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
                stall_cycles_detected <= stall_cycles_detected + 1;

            if (debug_flush)
                total_flush_cycles <= total_flush_cycles + 1;

            // -----------------------------------------------------------------
            // 1. PC-Specific Branch Event Tracking
            // -----------------------------------------------------------------
            if (debug_ex_valid) begin
                // BNE at 0x1C (loop back)
                if (debug_ex_pc == 32'h0000_001C) begin
                    if (debug_branch_taken) begin
                        if (debug_branch_target == 32'h0000_0010 && debug_flush)
                            loop_branch_taken_count <= loop_branch_taken_count + 1;
                    end else begin
                        if (!debug_flush)
                            loop_branch_not_taken_count <= loop_branch_not_taken_count + 1;
                    end
                end

                // BEQ at 0x28 (forward jump over trap)
                if (debug_ex_pc == 32'h0000_0028) begin
                    if (debug_branch_taken && debug_branch_target == 32'h0000_0030 && debug_flush)
                        forward_branch_taken_count <= forward_branch_taken_count + 1;
                end

                // BEQ at 0x30 (completion self-loop)
                if (debug_ex_pc == DONE_PC) begin
                    if (debug_branch_taken && debug_flush)
                        halt_loop_flush_count <= halt_loop_flush_count + 1;
                end
            end

            // -----------------------------------------------------------------
            // 2. Specific Forwarding Path Verification
            // -----------------------------------------------------------------
            if (debug_ex_valid) begin
                // At 0x14 (ADD x3, x3, x1): operand B (x1) must forward from EX/MEM (0x10 ADDI)
                if (debug_ex_pc == 32'h0000_0014 && debug_forward_b == 2'b10)
                    fwd_ex_mem_verified <= 1;

                // At 0x18 (SUB x4, x4, x1): operand B (x1) must forward from MEM/WB (0x10 ADDI)
                if (debug_ex_pc == 32'h0000_0018 && debug_forward_b == 2'b01)
                    fwd_mem_wb_verified <= 1;
            end

            // -----------------------------------------------------------------
            // 3. Register x0 Read and WB Write-Suppression Invariant Checks
            // -----------------------------------------------------------------
            // Check WB interface invariant: an enabled write is never sent to x0 regardless of data
            if (debug_wb_retired && debug_wb_reg_write && debug_wb_rd == 5'd0)
                x0_write_violation <= 1;

            // Check combinational register-file read ports in ID stage when accessing x0
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
        $dumpfile("simulation/tb_benchmark_accumulate.vcd");
        $dumpvars(0, tb_benchmark_accumulate);

        clk = 0;
        rst = 1;

        // Hold reset for 20ns
        #20;
        @(posedge clk);
        #1;
        rst = 0;

        $display("================================================================");
        $display("Starting Benchmark 1: Arithmetic & Accumulator Loop");
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
                $fatal(1, "TIMEOUT: tb_benchmark_accumulate exceeded cycle budget");
            end

            // Detect program completion when the halt self-loop reaches Write-Back
            if (debug_wb_retired && debug_wb_pc == DONE_PC) begin
                $display("[Cycle %03d] Detected retirement of halt self-loop at PC=%h", cycle_count, debug_wb_pc);
                program_completed = 1;
            end
        end

        // Wait 2 additional cycles to ensure all preceding pipeline stages
        // have completed write-back commitments before sampling architectural state.
        // Note: The CPU continues executing the halt self-loop at DONE_PC.
        repeat (2) @(posedge clk);
        #1;

        $display("\n================================================================");
        $display("Architectural State & Functional Verification");
        $display("================================================================");

        // Check 1: Register x1 = 5 (loop counter reached final index)
        if (uut.u_id_stage.registers.registers[1] !== 32'd5)
            $fatal(1, "FAIL Check 1: Register x1 (loop counter) expected 5, got %0d", uut.u_id_stage.registers.registers[1]);
        test_count = test_count + 1;
        $display("  [%02d] Register x1 = 5 (loop counter final index) PASS", test_count);

        // Check 2: Register x2 = 5 (loop limit)
        if (uut.u_id_stage.registers.registers[2] !== 32'd5)
            $fatal(1, "FAIL Check 2: Register x2 (loop limit) expected 5, got %0d", uut.u_id_stage.registers.registers[2]);
        test_count = test_count + 1;
        $display("  [%02d] Register x2 = 5 (loop limit constant) PASS", test_count);

        // Check 3: Register x3 = 15 (accumulated sum = 1+2+3+4+5)
        if (uut.u_id_stage.registers.registers[3] !== 32'd15)
            $fatal(1, "FAIL Check 3: Register x3 (accumulated sum) expected 15, got %0d", uut.u_id_stage.registers.registers[3]);
        test_count = test_count + 1;
        $display("  [%02d] Register x3 = 15 (accumulated sum sum(1..5)) PASS", test_count);

        // Check 4: Register x4 = 85 (running difference 100 - sum)
        if (uut.u_id_stage.registers.registers[4] !== 32'd85)
            $fatal(1, "FAIL Check 4: Register x4 (running diff) expected 85, got %0d", uut.u_id_stage.registers.registers[4]);
        test_count = test_count + 1;
        $display("  [%02d] Register x4 = 85 (running difference 100 - 15) PASS", test_count);

        // Check 5: Register x5 = 15 (copy of sum after loop exit fall-through)
        if (uut.u_id_stage.registers.registers[5] !== 32'd15)
            $fatal(1, "FAIL Check 5: Register x5 (sum copy) expected 15, got %0d", uut.u_id_stage.registers.registers[5]);
        test_count = test_count + 1;
        $display("  [%02d] Register x5 = 15 (fall-through sum copy) PASS", test_count);

        // Check 6: Register x6 = 85 (copy of diff after loop exit fall-through)
        if (uut.u_id_stage.registers.registers[6] !== 32'd85)
            $fatal(1, "FAIL Check 6: Register x6 (diff copy) expected 85, got %0d", uut.u_id_stage.registers.registers[6]);
        test_count = test_count + 1;
        $display("  [%02d] Register x6 = 85 (fall-through diff copy) PASS", test_count);

        // Check 7: Register x7 = 0 (trap instruction at 0x2C squashed by branch)
        if (uut.u_id_stage.registers.registers[7] !== 32'd0)
            $fatal(1, "FAIL Check 7: Register x7 polluted by squashed trap! Value: %0d", uut.u_id_stage.registers.registers[7]);
        test_count = test_count + 1;
        $display("  [%02d] Register x7 = 0 (wrong-path trap instruction 0x2C squashed) PASS", test_count);

        // Check 8: BNE at 0x1C taken branches (exactly 4 taken loop iterations)
        if (loop_branch_taken_count !== 4)
            $fatal(1, "FAIL Check 8: Expected exactly 4 taken BNE loop branches at 0x1C, got %0d", loop_branch_taken_count);
        test_count = test_count + 1;
        $display("  [%02d] BNE at 0x1C taken branches = 4 (target 0x10, flush asserted) PASS", test_count);

        // Check 9: BNE at 0x1C not-taken branch (exactly 1 loop exit fall-through)
        if (loop_branch_not_taken_count !== 1)
            $fatal(1, "FAIL Check 9: Expected exactly 1 not-taken BNE branch at 0x1C, got %0d", loop_branch_not_taken_count);
        test_count = test_count + 1;
        $display("  [%02d] BNE at 0x1C not-taken branch = 1 (fall-through without flush) PASS", test_count);

        // Check 10: BEQ at 0x28 taken forward branch (skipping trap)
        if (forward_branch_taken_count !== 1)
            $fatal(1, "FAIL Check 10: Expected exactly 1 forward BEQ taken branch at 0x28, got %0d", forward_branch_taken_count);
        test_count = test_count + 1;
        $display("  [%02d] BEQ at 0x28 forward branch = 1 (target 0x30, trap skipped) PASS", test_count);

        // Check 11: Specific RAW Forwarding Paths Verified
        if (!fwd_ex_mem_verified)
            $fatal(1, "FAIL Check 11: EX->EX forwarding (debug_forward_b=2'b10) was not detected at 0x14");
        if (!fwd_mem_wb_verified)
            $fatal(1, "FAIL Check 11: MEM->EX forwarding (debug_forward_b=2'b01) was not detected at 0x18");
        test_count = test_count + 1;
        $display("  [%02d] Specific RAW forwarding paths verified (EX->EX at 0x14, MEM->EX at 0x18) PASS", test_count);

        // Check 12: Register x0 WB write-suppression invariant and read-as-zero integrity
        if (x0_write_violation)
            $fatal(1, "FAIL Check 12: Enabled write to x0 (reg_write=1 for rd=x0) detected at WB interface!");
        if (x0_read_violation)
            $fatal(1, "FAIL Check 12: Non-zero read from x0 detected in ID stage!");
        test_count = test_count + 1;
        $display("  [%02d] Register x0 WB write-suppression invariant & read-as-zero PASS (directed register-file simulation test in tb_register_file)", test_count);

        $display("================================================================");
        $display("PASS: tb_benchmark_accumulate (all %0d checks passed)", test_count);
        $display("Diagnostic Simulation Counters (not validated CPI/IPC):");
        $display("  Total Clock Cycles    : %0d", cycle_count);
        $display("  Retired Instructions  : %0d", retired_count);
        $display("  Workload Branch Flushes: %0d (4 loop + 1 forward)", loop_branch_taken_count + forward_branch_taken_count);
        $display("  Halt Self-Loop Flushes : %0d", halt_loop_flush_count);
        $display("  Pipeline Stalls       : %0d", stall_cycles_detected);
        $display("================================================================");
        $finish;
    end

endmodule
