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
            if (debug_flush)
                flush_cycles <= flush_cycles + 1;

            // Capture Convention A: At retirement of last workload instruction
            if (!win_a_captured && debug_wb_retired && debug_wb_pc == last_workload_pc) begin
                win_a_cycles   <= total_cycles + 1;
                win_a_retired  <= retired_instructions + 1;
                win_a_stalls   <= stall_cycles + (debug_stall ? 1 : 0);
                win_a_flushes  <= flush_cycles + (debug_flush ? 1 : 0);
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

            // Reset state
            total_cycles = 0;
            retired_instructions = 0;
            stall_cycles = 0;
            flush_cycles = 0;
            win_a_captured = 0;
            win_b_captured = 0;

            // Clear memories
            for (i = 0; i < 256; i = i + 1) begin
                uut.u_if_stage.u_instr_mem.mem[i] = 32'h0000_0013;
                uut.u_mem_stage.u_data_mem.mem[i] = 32'd0;
            end

            // Load hex image
            $readmemh(hex_file, uut.u_if_stage.u_instr_mem.mem);

            // Assert synchronous reset
            rst = 1;
            #20;
            @(posedge clk);
            rst = 0;

            // Wait until both windows captured or timeout
            while ((!win_a_captured || !win_b_captured) && total_cycles < 500) begin
                @(posedge clk);
                #1;
            end

            if (!win_b_captured) begin
                $fatal(1, "ERROR: Benchmark %0s timed out before reaching halt condition!", name);
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
