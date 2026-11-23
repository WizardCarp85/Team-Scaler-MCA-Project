// =============================================================================
// Testbench: tb_performance_cpi_ipc
// Project: Team Scaler MCA Project - RV32I 5-Stage Pipelined Processor
// Issue: #27 - End-to-End Verification & CPI/IPC Analysis
//
// Description:
//   Rigorous, reproducible CPI/IPC measurement harness for the integrated
//   5-stage pipelined CPU across all benchmark workloads:
//     1. Benchmark 1: Arithmetic & Accumulator Loop (benchmark_accumulate.hex)
//     2. Benchmark 2: Array Allocation & Memory Access (benchmark_load_store.hex)
//     3. Benchmark 3: Control Hazards & Dual Forwarding (benchmark_control_hazards.hex)
//
// Measurement Methodology & Window Definitions:
//   To eliminate ambiguity, this testbench measures and reports two distinct,
//   fully documented conventions:
//
//   [Convention A - Pure Workload Window (Excludes Halt Marker)]:
//     - Start: First posedge clk after reset deassertion (first IF fetch).
//     - End  : posedge clk on which the final algorithmic instruction retires
//              at the WB stage (debug_wb_retired && debug_wb_pc == LAST_WORKLOAD_PC).
//     - Retired Instructions: Exactly the dynamic instructions of the program workload.
//     - Cycles: Clock cycles elapsed during workload execution (includes pipeline
//               fill, hazards, and branch penalties; excludes halt loop).
//
//   [Convention B - Completion-Inclusive Window (Includes First Halt Retirement)]:
//     - Start: First posedge clk after reset deassertion.
//     - End  : posedge clk on which the halt self-loop instruction first retires
//              at the WB stage (debug_wb_retired && debug_wb_pc == HALT_PC).
//     - Retired Instructions: Workload instructions + 1 (the single halt retirement).
//     - Cycles: Total cycles to first halt retirement (includes 2 cycles for halt
//               to traverse EX->MEM->WB; excludes subsequent infinite looping).
//
// Formulas:
//   CPI = Measured Clock Cycles / Measured Retired Instructions
//   IPC = Measured Retired Instructions / Measured Clock Cycles
// =============================================================================

`timescale 1ns/1ps

module tb_performance_cpi_ipc;

    reg clk;
    reg rst;

    // CPU debug signals
    wire [31:0] debug_if_pc, debug_if_instr;
    wire [31:0] debug_id_pc, debug_id_instr;
    wire        debug_id_valid;
    wire [31:0] debug_ex_pc, debug_ex_alu_result;
    wire        debug_ex_valid;
    wire [31:0] debug_mem_pc, debug_mem_addr, debug_mem_write_data;
    wire        debug_mem_read, debug_mem_write, debug_mem_valid;
    wire [31:0] debug_wb_pc, debug_wb_data;
    wire        debug_wb_reg_write, debug_wb_retired;
    wire [4:0]  debug_wb_rd;
    wire        debug_stall, debug_flush, debug_branch_taken;
    wire [31:0] debug_branch_target;
    wire [1:0]  debug_forward_a, debug_forward_b;

    reg [1023:0] current_test_name;
    reg [31:0]   halt_pc;
    reg [31:0]   last_workload_pc;

    // Top-Level CPU Instance
    cpu #(
        .RESET_VECTOR   (32'h0000_0000),
        .IMEM_DEPTH     (256),
        .IMEM_INIT_FILE (""),
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

    always #5 clk = ~clk;

    // Measurement Counters
    integer total_cycles;
    integer retired_instructions;
    integer stall_cycles;
    integer flush_cycles;
    integer workload_flush_cycles;

    integer win_a_cycles;
    integer win_a_retired;
    integer win_a_stalls;
    integer win_a_flushes;
    reg     win_a_captured;

    integer win_b_cycles;
    integer win_b_retired;
    integer win_b_stalls;
    integer win_b_flushes;
    reg     win_b_captured;

    // Cycle Monitor
    always @(posedge clk) begin
        if (!rst) begin
            total_cycles <= total_cycles + 1;

            if (debug_wb_retired)
                retired_instructions <= retired_instructions + 1;
            if (debug_stall)
                stall_cycles <= stall_cycles + 1;
            if (debug_flush) begin
                flush_cycles <= flush_cycles + 1;
                // Separate workload-attributed branch flushes from completion-marker flushes
                if (debug_ex_pc != halt_pc)
                    workload_flush_cycles <= workload_flush_cycles + 1;
            end

            // Capture Convention A: At retirement of last workload instruction
            // Note on cycle boundary:
            // Under the documented convention counting from the first post-reset rising edge
            // through the WB retirement/write edge inclusively, total_cycles + 1 captures the
            // cycle completing at this edge where the instruction's state update commits.
            if (!win_a_captured && debug_wb_retired && debug_wb_pc == last_workload_pc) begin
                win_a_cycles   <= total_cycles + 1;
                win_a_retired  <= retired_instructions + 1;
                win_a_stalls   <= stall_cycles + (debug_stall ? 1 : 0);
                win_a_flushes  <= workload_flush_cycles + ((debug_flush && debug_ex_pc != halt_pc) ? 1 : 0);
                win_a_captured <= 1;
            end

            // Capture Convention B: At first retirement of halt self-loop
            if (!win_b_captured && debug_wb_retired && debug_wb_pc == halt_pc) begin
                win_b_cycles   <= total_cycles + 1;
                win_b_retired  <= retired_instructions + 1;
                win_b_stalls   <= stall_cycles + (debug_stall ? 1 : 0);
                win_b_flushes  <= flush_cycles + (debug_flush ? 1 : 0);
                win_b_captured <= 1;
            end
        end
    end

    // Task to run and measure one benchmark program
    task run_benchmark;
        input [1023:0] name;
        input [1023:0] hex_file;
        input [31:0]   halt_addr;
        input [31:0]   last_pc;
        integer i;
        real cpi_a, ipc_a, cpi_b, ipc_b;
        begin
            current_test_name = name;
            halt_pc = halt_addr;
            last_workload_pc = last_pc;

            // Reset state and clear all per-window counters for every benchmark run
            total_cycles = 0;
            retired_instructions = 0;
            stall_cycles = 0;
            flush_cycles = 0;
            workload_flush_cycles = 0;

            win_a_cycles   = 0;
            win_a_retired  = 0;
            win_a_stalls   = 0;
            win_a_flushes  = 0;
            win_a_captured = 0;

            win_b_cycles   = 0;
            win_b_retired  = 0;
            win_b_stalls   = 0;
            win_b_flushes  = 0;
            win_b_captured = 0;

            // Clear memories
            for (i = 0; i < 256; i = i + 1) begin
                uut.u_if_stage.u_instr_mem.mem[i] = 32'h0000_0013;
                uut.u_mem_stage.u_data_mem.mem[i] = 32'd0;
            end

            // Load hex image
            $readmemh(hex_file, uut.u_if_stage.u_instr_mem.mem);

            // Assert synchronous reset and release cleanly away from clock edge
            rst = 1;
            repeat (3) @(posedge clk);
            #2;
            rst = 0;

            // Wait until both windows captured or timeout
            while ((!win_a_captured || !win_b_captured) && total_cycles < 500) begin
                @(posedge clk);
                #1;
            end

            // Strict failure checks for missing endpoints
            if (!win_a_captured) begin
                $fatal(1, "ERROR: Benchmark %0s timed out before reaching workload endpoint (0x%08h)!", name, last_pc);
            end

            if (!win_b_captured) begin
                $fatal(1, "ERROR: Benchmark %0s timed out before reaching halt condition (0x%08h)!", name, halt_addr);
            end

            // Guard against division by zero or invalid counters
            if (win_a_retired <= 0 || win_a_cycles <= 0) begin
                $fatal(1, "ERROR: Benchmark %0s has invalid workload counts (cycles=%0d, retired=%0d)!", name, win_a_cycles, win_a_retired);
            end

            if (win_b_retired <= 0 || win_b_cycles <= 0) begin
                $fatal(1, "ERROR: Benchmark %0s has invalid completion counts (cycles=%0d, retired=%0d)!", name, win_b_cycles, win_b_retired);
            end

            // Calculate metrics
            cpi_a = win_a_cycles * 1.0 / win_a_retired;
            ipc_a = win_a_retired * 1.0 / win_a_cycles;

            cpi_b = win_b_cycles * 1.0 / win_b_retired;
            ipc_b = win_b_retired * 1.0 / win_b_cycles;

            $display("----------------------------------------------------------------");
            $display("Benchmark: %0s", name);
            $display("Hex File : %0s", hex_file);
            $display("Halt PC  : 0x%08h | Last Workload PC: 0x%08h", halt_addr, last_pc);
            $display("----------------------------------------------------------------");
            $display("  [Convention A - Pure Workload Window (Excludes Halt Marker)]");
            $display("    Measured Clock Cycles       : %0d", win_a_cycles);
            $display("    Measured Retired Instrs     : %0d", win_a_retired);
            $display("    Stall Cycles Detected       : %0d", win_a_stalls);
            $display("    Flush Cycles Detected       : %0d", win_a_flushes);
            $display("    Measured CPI                : %0.4f", cpi_a);
            $display("    Measured IPC                : %0.4f", ipc_a);
            $display("");
            $display("  [Convention B - Completion-Inclusive Window (Includes Halt Marker)]");
            $display("    Measured Clock Cycles       : %0d", win_b_cycles);
            $display("    Measured Retired Instrs     : %0d", win_b_retired);
            $display("    Stall Cycles Detected       : %0d", win_b_stalls);
            $display("    Flush Cycles Detected       : %0d", win_b_flushes);
            $display("    Measured CPI                : %0.4f", cpi_b);
            $display("    Measured IPC                : %0.4f", ipc_b);
            $display("----------------------------------------------------------------");
            $display("");
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;

        $display("================================================================");
        $display("5-STAGE PIPELINED CPU - REPRODUCIBLE CPI / IPC MEASUREMENT");
        $display("================================================================");
        $display("");

        // =====================================================================
        // Microtest 1: Single Workload Instruction Fill/Drain & Boundary Check
        //   Instruction 0 (0x00): ADDI x1, x0, 42
        //   Instruction 1 (0x04): BEQ  x0, x0, 0  (Halt Self-Loop Marker)
        // Expected Workload Window (Conv. A):
        //   - Retired Instructions: exactly 1
        //   - Elapsed Clock Cycles: exactly 5 (IF=1, ID=2, EX=3, MEM=4, WB write edge=5)
        //   - Stall Cycles        : exactly 0
        //   - Workload Flushes    : exactly 0 (Halt flush in EX at cycle 4 is NOT attributed to workload)
        //   - Measured CPI        : exactly 5.0000
        // =====================================================================
        run_benchmark(
            "Microtest 1: Single Instruction (ADDI)",
            "programs/microtest_one_instr.hex",
            32'h0000_0004,
            32'h0000_0000
        );
        if (win_a_cycles !== 5 || win_a_retired !== 1)
            $fatal(1, "FAIL Microtest 1 expected counts (expected cycles=5, retired=1, got cycles=%0d, retired=%0d)", win_a_cycles, win_a_retired);
        if (win_a_flushes !== 0)
            $fatal(1, "FAIL Microtest 1 misattributed completion marker flush to workload (got %0d)", win_a_flushes);
        if (uut.u_id_stage.registers.registers[1] !== 32'd42)
            $fatal(1, "FAIL Microtest 1 architectural state x1 !== 42");

        // =====================================================================
        // Microtest 2: 4-Instruction Load-Use Interlock & Boundary Validation
        //   0x00: ADDI x1, x0, 10
        //   0x04: SW   x1, 0(x0)
        //   0x08: LW   x2, 0(x0)
        //   0x0C: ADD  x3, x2, x1  (Dependent on x2 -> exactly 1 stall cycle)
        //   0x10: BEQ  x0, x0, 0   (Halt Marker)
        // Expected Workload Window (Conv. A):
        //   - Retired Instructions: exactly 4
        //   - Elapsed Clock Cycles: exactly 9 (4 base + 4 fill + 1 stall)
        //   - Stall Cycles        : exactly 1
        //   - Workload Flushes    : exactly 0
        //   - Measured CPI        : 9 / 4 = 2.2500
        // =====================================================================
        run_benchmark(
            "Microtest 2: Load-Use Hazard Interlock",
            "programs/microtest_load_use.hex",
            32'h0000_0010,
            32'h0000_000C
        );
        if (win_a_cycles !== 9 || win_a_retired !== 4 || win_a_stalls !== 1)
            $fatal(1, "FAIL Microtest 2 expected counts (expected cycles=9, retired=4, stalls=1, got cycles=%0d, retired=%0d, stalls=%0d)", win_a_cycles, win_a_retired, win_a_stalls);
        if (win_a_flushes !== 0)
            $fatal(1, "FAIL Microtest 2 misattributed completion marker flush to workload (got %0d)", win_a_flushes);
        if (uut.u_id_stage.registers.registers[3] !== 32'd20)
            $fatal(1, "FAIL Microtest 2 architectural state x3 !== 20");

        // =====================================================================
        // Full Verification Benchmarks
        // =====================================================================
        // Benchmark 1: Arithmetic & Accumulator Loop
        // Halt PC = 0x30, Last Workload PC = 0x28 (forward branch over trap)
        run_benchmark(
            "Benchmark 1: Accumulator Loop",
            "programs/benchmark_accumulate.hex",
            32'h0000_0030,
            32'h0000_0028
        );

        // Benchmark 2: Array Allocation & Memory Access
        // Halt PC = 0x54, Last Workload PC = 0x4C (forward branch over trap)
        run_benchmark(
            "Benchmark 2: Load/Store & Memory Sequence",
            "programs/benchmark_load_store.hex",
            32'h0000_0054,
            32'h0000_004C
        );

        // Benchmark 3: Control Hazards & Dual Forwarding
        // Halt PC = 0x5C, Last Workload PC = 0x54 (forward branch over trap)
        run_benchmark(
            "Benchmark 3: Control Hazards & Dual Forwarding",
            "programs/benchmark_control_hazards.hex",
            32'h0000_005C,
            32'h0000_0054
        );

        $display("================================================================");
        $display("CPI / IPC MEASUREMENTS COMPLETE - ALL BENCHMARKS EVALUATED");
        $display("================================================================");
        $finish;
    end

endmodule
