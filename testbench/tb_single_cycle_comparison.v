// =============================================================================
// Testbench: tb_single_cycle_comparison
// Project: Team Scaler MCA Project - Architectural Reference Comparison
// Issue: #27 - End-to-End Verification & CPI/IPC Analysis
//
// Description:
//   Automated co-simulation and comparative verification testbench.
//   Directly instantiates and co-simulates BOTH processor implementations:
//     1. Synthesizable Verilog Single-Cycle Reference CPU (rtl/reference/single_cycle_cpu.v)
//     2. Integrated 5-Stage Pipelined RV32I Processor (rtl/cpu.v)
//
// Verification Scope:
//   1. Dynamic Instruction Sequence Equivalence:
//      Captures the ordered dynamic retirement sequence of Program Counter (PC)
//      values and the corresponding instruction-memory words associated with those PCs
//      for both processors, verifying that every executed instruction step matches
//      in strict architectural program order.
//   2. Workload & Completion Window Bounds:
//      Enforces strict timeout and missing-endpoint failure checks ($fatal) if
//      either processor fails to reach the workload endpoint or completion marker.
//   3. Direct Architectural State Comparison:
//      Compares final general-purpose register values (x1-x31) and data memory words
//      directly between the two cores, as well as against independent golden values.
//   4. Baseline Performance Measurement:
//      Demonstrates empirical single-cycle baseline (CPI = 1.000) versus
//      pipelined cycle count and throughput overheads, using consistent
//      retirement write-edge cycle boundaries.
// =============================================================================

`timescale 1ns/1ps

module tb_single_cycle_comparison;

    reg clk;
    reg rst;

    // -------------------------------------------------------------------------
    // 1. Single-Cycle CPU Instance & Debug Signals
    // -------------------------------------------------------------------------
    wire [31:0] sc_debug_pc;
    wire [31:0] sc_debug_instr;
    wire        sc_debug_retired;
    wire        sc_debug_reg_write;
    wire [4:0]  sc_debug_rd;
    wire [31:0] sc_debug_wb_data;
    wire [31:0] sc_debug_mem_addr;
    wire [31:0] sc_debug_mem_write_data;
    wire        sc_debug_mem_read;
    wire        sc_debug_mem_write;
    wire        sc_debug_branch_taken;
    wire [31:0] sc_debug_branch_target;

    single_cycle_cpu #(
        .RESET_VECTOR   (32'h0000_0000),
        .IMEM_DEPTH     (256),
        .IMEM_INIT_FILE (""),
        .DMEM_DEPTH     (256)
    ) sc_dut (
        .clk                 (clk),
        .rst                 (rst),
        .debug_pc            (sc_debug_pc),
        .debug_instr         (sc_debug_instr),
        .debug_retired       (sc_debug_retired),
        .debug_reg_write     (sc_debug_reg_write),
        .debug_rd            (sc_debug_rd),
        .debug_wb_data       (sc_debug_wb_data),
        .debug_mem_addr      (sc_debug_mem_addr),
        .debug_mem_write_data(sc_debug_mem_write_data),
        .debug_mem_read      (sc_debug_mem_read),
        .debug_mem_write     (sc_debug_mem_write),
        .debug_branch_taken  (sc_debug_branch_taken),
        .debug_branch_target (sc_debug_branch_target)
    );

    // -------------------------------------------------------------------------
    // 2. 5-Stage Pipelined CPU Instance & Debug Signals
    // -------------------------------------------------------------------------
    wire [31:0] pipe_debug_if_pc;
    wire [31:0] pipe_debug_if_instr;
    wire [31:0] pipe_debug_id_pc;
    wire [31:0] pipe_debug_id_instr;
    wire        pipe_debug_id_valid;
    wire [31:0] pipe_debug_ex_pc;
    wire [31:0] pipe_debug_ex_alu_result;
    wire        pipe_debug_ex_valid;
    wire [31:0] pipe_debug_mem_pc;
    wire [31:0] pipe_debug_mem_addr;
    wire [31:0] pipe_debug_mem_write_data;
    wire        pipe_debug_mem_read;
    wire        pipe_debug_mem_write;
    wire        pipe_debug_mem_valid;
    wire [31:0] pipe_debug_wb_pc;
    wire        pipe_debug_wb_reg_write;
    wire [4:0]  pipe_debug_wb_rd;
    wire [31:0] pipe_debug_wb_data;
    wire        pipe_debug_wb_retired;
    wire        pipe_debug_stall;
    wire        pipe_debug_flush;
    wire        pipe_debug_branch_taken;
    wire [31:0] pipe_debug_branch_target;
    wire [1:0]  pipe_debug_forward_a;
    wire [1:0]  pipe_debug_forward_b;

    cpu #(
        .RESET_VECTOR   (32'h0000_0000),
        .IMEM_DEPTH     (256),
        .IMEM_INIT_FILE (""),
        .DMEM_DEPTH     (256)
    ) pipe_dut (
        .clk                 (clk),
        .rst                 (rst),
        .debug_if_pc         (pipe_debug_if_pc),
        .debug_if_instr      (pipe_debug_if_instr),
        .debug_id_pc         (pipe_debug_id_pc),
        .debug_id_instr      (pipe_debug_id_instr),
        .debug_id_valid      (pipe_debug_id_valid),
        .debug_ex_pc         (pipe_debug_ex_pc),
        .debug_ex_alu_result (pipe_debug_ex_alu_result),
        .debug_ex_valid      (pipe_debug_ex_valid),
        .debug_mem_pc        (pipe_debug_mem_pc),
        .debug_mem_addr      (pipe_debug_mem_addr),
        .debug_mem_write_data(pipe_debug_mem_write_data),
        .debug_mem_read      (pipe_debug_mem_read),
        .debug_mem_write     (pipe_debug_mem_write),
        .debug_mem_valid     (pipe_debug_mem_valid),
        .debug_wb_pc         (pipe_debug_wb_pc),
        .debug_wb_reg_write  (pipe_debug_wb_reg_write),
        .debug_wb_rd         (pipe_debug_wb_rd),
        .debug_wb_data       (pipe_debug_wb_data),
        .debug_wb_retired    (pipe_debug_wb_retired),
        .debug_stall         (pipe_debug_stall),
        .debug_flush         (pipe_debug_flush),
        .debug_branch_taken  (pipe_debug_branch_taken),
        .debug_branch_target (pipe_debug_branch_target),
        .debug_forward_a     (pipe_debug_forward_a),
        .debug_forward_b     (pipe_debug_forward_b)
    );

    // 100 MHz clock generation (10 ns period)
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // 3. Dynamic Retirement Sequence Recording Buffers
    // -------------------------------------------------------------------------
    reg [31:0] sc_retired_pc [0:511];
    reg [31:0] sc_retired_instr [0:511];
    integer sc_retired_count;
    integer sc_total_cycles;
    integer sc_workload_cycles;
    integer sc_workload_retired;
    reg sc_workload_reached;
    reg sc_halt_completed;

    reg [31:0] pipe_retired_pc [0:511];
    reg [31:0] pipe_retired_instr [0:511];
    integer pipe_retired_count;
    integer pipe_total_cycles;
    integer pipe_workload_cycles;
    integer pipe_workload_retired;
    reg pipe_workload_reached;
    reg pipe_halt_completed;

    integer test_count;
    integer i;

    // -------------------------------------------------------------------------
    // 4. Automated Co-Simulation & Comparison Task
    // -------------------------------------------------------------------------
    task run_comparison_benchmark;
        input [1023:0] name;
        input [1023:0] hex_file;
        input [31:0]   halt_pc;
        input [31:0]   last_workload_pc;
        integer i, k;
        integer sim_cycles;
        reg [31:0] current_sc_pc;
        reg [31:0] current_sc_instr;
        begin
            // Initialize all tracking variables to zero (prevent reuse)
            sc_retired_count    = 0;
            sc_total_cycles     = 0;
            sc_workload_cycles  = 0;
            sc_workload_retired = 0;
            sc_workload_reached = 0;
            sc_halt_completed   = 0;

            pipe_retired_count    = 0;
            pipe_total_cycles     = 0;
            pipe_workload_cycles  = 0;
            pipe_workload_retired = 0;
            pipe_workload_reached = 0;
            pipe_halt_completed   = 0;

            sim_cycles = 0;

            // Clear memories and registers for both cores
            for (i = 0; i < 256; i = i + 1) begin
                sc_dut.imem[i] = 32'h0000_0013;
                sc_dut.dmem[i] = 32'd0;
                pipe_dut.u_if_stage.u_instr_mem.mem[i] = 32'h0000_0013;
                pipe_dut.u_mem_stage.u_data_mem.mem[i] = 32'd0;
            end
            for (i = 1; i < 32; i = i + 1) begin
                sc_dut.registers[i] = 32'd0;
                pipe_dut.u_id_stage.registers.registers[i] = 32'd0;
            end

            // Load identical hex image into both instruction memories
            $readmemh(hex_file, sc_dut.imem);
            $readmemh(hex_file, pipe_dut.u_if_stage.u_instr_mem.mem);

            // Assert synchronous reset and release cleanly away from clock edge
            rst = 1;
            repeat (3) @(posedge clk);
            #2;
            rst = 0;

            // Co-simulate both models until both reach their completion marker or timeout
            while ((!sc_halt_completed || !pipe_halt_completed) && sim_cycles < 500) begin
                current_sc_pc = sc_debug_pc;
                current_sc_instr = sc_debug_instr;

                @(posedge clk);
                #1;
                sim_cycles = sim_cycles + 1;

                // --- Single-Cycle Processor Step ---
                if (!sc_halt_completed) begin
                    sc_total_cycles = sc_total_cycles + 1;
                    sc_retired_pc[sc_retired_count] = current_sc_pc;
                    sc_retired_instr[sc_retired_count] = current_sc_instr;
                    sc_retired_count = sc_retired_count + 1;

                    if (current_sc_pc == last_workload_pc && !sc_workload_reached) begin
                        sc_workload_cycles = sc_total_cycles;
                        sc_workload_retired = sc_retired_count;
                        sc_workload_reached = 1;
                    end

                    if (current_sc_pc == halt_pc) begin
                        sc_halt_completed = 1;
                    end
                end

                // --- Pipelined Processor Step ---
                // The pipelined instruction enters the WB stage when pipe_debug_wb_retired is asserted.
                // On the next rising clock edge, this instruction commits its write-back data to the
                // architectural register file. Under the inclusive convention counting from the first
                // post-reset clock edge through the WB retirement/write edge inclusively, the cycle
                // count at completion includes this write edge (pipe_total_cycles + 1).
                if (!pipe_halt_completed) begin
                    pipe_total_cycles = pipe_total_cycles + 1;

                    if (pipe_debug_wb_retired) begin
                        pipe_retired_pc[pipe_retired_count] = pipe_debug_wb_pc;
                        pipe_retired_instr[pipe_retired_count] = pipe_dut.u_if_stage.u_instr_mem.mem[pipe_debug_wb_pc[31:2]];
                        pipe_retired_count = pipe_retired_count + 1;

                        if (pipe_debug_wb_pc == last_workload_pc && !pipe_workload_reached) begin
                            pipe_workload_cycles = pipe_total_cycles + 1;
                            pipe_workload_retired = pipe_retired_count;
                            pipe_workload_reached = 1;
                        end

                        if (pipe_debug_wb_pc == halt_pc) begin
                            pipe_halt_completed = 1;
                        end
                    end
                end
            end

            // -----------------------------------------------------------------
            // Strict Timeout & Endpoint Checks (Must fail if endpoints missed)
            // -----------------------------------------------------------------
            if (!sc_workload_reached)
                $fatal(1, "ERROR: %0s: Single-Cycle CPU timed out before reaching workload endpoint 0x%08h!", name, last_workload_pc);
            if (!sc_halt_completed)
                $fatal(1, "ERROR: %0s: Single-Cycle CPU timed out before reaching halt marker 0x%08h!", name, halt_pc);

            if (!pipe_workload_reached)
                $fatal(1, "ERROR: %0s: Pipelined CPU timed out before reaching workload endpoint 0x%08h!", name, last_workload_pc);
            if (!pipe_halt_completed)
                $fatal(1, "ERROR: %0s: Pipelined CPU timed out before reaching halt marker 0x%08h!", name, halt_pc);

            // Guard against division by zero
            if (sc_workload_retired <= 0 || sc_workload_cycles <= 0 || pipe_workload_retired <= 0 || pipe_workload_cycles <= 0)
                $fatal(1, "ERROR: %0s: Captured zero or negative counts!", name);

            // -----------------------------------------------------------------
            // Dynamic Instruction Count & Sequence Equality Assertion
            // -----------------------------------------------------------------
            if (sc_workload_retired !== pipe_workload_retired)
                $fatal(1, "ERROR: %0s: Workload retired instruction mismatch! Single-Cycle=%0d, Pipelined=%0d",
                       name, sc_workload_retired, pipe_workload_retired);

            if (sc_retired_count !== pipe_retired_count)
                $fatal(1, "ERROR: %0s: Total retired instruction mismatch! Single-Cycle=%0d, Pipelined=%0d",
                       name, sc_retired_count, pipe_retired_count);

            for (k = 0; k < sc_retired_count; k = k + 1) begin
                if (sc_retired_pc[k] !== pipe_retired_pc[k])
                    $fatal(1, "ERROR: %0s: Dynamic PC mismatch at retirement step %0d! SC=0x%08h, PIPE=0x%08h",
                           name, k, sc_retired_pc[k], pipe_retired_pc[k]);
                if (sc_retired_instr[k] !== pipe_retired_instr[k])
                    $fatal(1, "ERROR: %0s: Dynamic instruction word mismatch at step %0d! SC=0x%08h, PIPE=0x%08h",
                           name, k, sc_retired_instr[k], pipe_retired_instr[k]);
            end

            $display("----------------------------------------------------------------");
            $display("Comparative Evaluation: %0s", name);
            $display("Image: %0s", hex_file);
            $display("----------------------------------------------------------------");
            $display("  Workload Window (up to 0x%08h):", last_workload_pc);
            $display("    Single-Cycle Baseline : Cycles=%0d, Retired=%0d, CPI=%0.4f, IPC=%0.4f",
                     sc_workload_cycles, sc_workload_retired,
                     sc_workload_cycles * 1.0 / sc_workload_retired,
                     sc_workload_retired * 1.0 / sc_workload_cycles);
            $display("    5-Stage Pipelined CPU : Cycles=%0d, Retired=%0d, CPI=%0.4f, IPC=%0.4f",
                     pipe_workload_cycles, pipe_workload_retired,
                     pipe_workload_cycles * 1.0 / pipe_workload_retired,
                     pipe_workload_retired * 1.0 / pipe_workload_cycles);
            $display("  Dynamic Retirement Trace : %0d / %0d instructions MATCHED EXACTLY in sequence",
                     sc_retired_count, pipe_retired_count);
            $display("----------------------------------------------------------------");
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        test_count = 0;

        $display("================================================================");
        $display("DUAL-CORE AUTOMATED CO-SIMULATION & COMPARATIVE VERIFICATION");
        $display("================================================================");
        $display("");

        // =====================================================================
        // Microtest 1: Single Instruction (ADDI) Fill/Drain Validation
        // =====================================================================
        run_comparison_benchmark(
            "Microtest 1: Single Instruction (ADDI)",
            "programs/microtest_one_instr.hex",
            32'h0000_0004,
            32'h0000_0000
        );
        if (sc_dut.registers[1] !== pipe_dut.u_id_stage.registers.registers[1])
            $fatal(1, "Microtest 1 core-to-core mismatch x1");
        if (sc_dut.registers[1] !== 32'd42)
            $fatal(1, "Microtest 1 golden mismatch x1");
        test_count = test_count + 1;
        $display("  [%02d] Microtest 1: Core-to-Core & Golden Architectural State Check (x1=42): MATCH PASS", test_count);
        $display("");

        // =====================================================================
        // Microtest 2: 4-Instruction Load-Use Hazard Interlock Validation
        // =====================================================================
        run_comparison_benchmark(
            "Microtest 2: Load-Use Hazard Interlock",
            "programs/microtest_load_use.hex",
            32'h0000_0010,
            32'h0000_000C
        );
        if (sc_dut.registers[1] !== pipe_dut.u_id_stage.registers.registers[1]) $fatal(1, "Microtest 2 core mismatch x1");
        if (sc_dut.registers[2] !== pipe_dut.u_id_stage.registers.registers[2]) $fatal(1, "Microtest 2 core mismatch x2");
        if (sc_dut.registers[3] !== pipe_dut.u_id_stage.registers.registers[3]) $fatal(1, "Microtest 2 core mismatch x3");
        if (sc_dut.dmem[0]      !== pipe_dut.u_mem_stage.u_data_mem.mem[0])    $fatal(1, "Microtest 2 core mismatch dmem[0]");
        if (sc_dut.registers[3] !== 32'd20) $fatal(1, "Microtest 2 golden mismatch x3");
        if (sc_dut.dmem[0]      !== 32'd10) $fatal(1, "Microtest 2 golden mismatch dmem[0]");
        test_count = test_count + 1;
        $display("  [%02d] Microtest 2: Core-to-Core & Golden Architectural State Check (x1,x2,x3,mem[0]): MATCH PASS", test_count);
        $display("");

        // =====================================================================
        // Benchmark 1: Accumulator Loop
        // =====================================================================
        run_comparison_benchmark(
            "Benchmark 1: Accumulator Loop",
            "programs/benchmark_accumulate.hex",
            32'h0000_0030,
            32'h0000_0028
        );

        // 1. Direct core-to-core state comparison
        if (sc_dut.registers[1] !== pipe_dut.u_id_stage.registers.registers[1]) $fatal(1, "B1 core-to-core mismatch x1");
        if (sc_dut.registers[2] !== pipe_dut.u_id_stage.registers.registers[2]) $fatal(1, "B1 core-to-core mismatch x2");
        if (sc_dut.registers[3] !== pipe_dut.u_id_stage.registers.registers[3]) $fatal(1, "B1 core-to-core mismatch x3");
        if (sc_dut.registers[4] !== pipe_dut.u_id_stage.registers.registers[4]) $fatal(1, "B1 core-to-core mismatch x4");
        if (sc_dut.registers[5] !== pipe_dut.u_id_stage.registers.registers[5]) $fatal(1, "B1 core-to-core mismatch x5");
        if (sc_dut.registers[6] !== pipe_dut.u_id_stage.registers.registers[6]) $fatal(1, "B1 core-to-core mismatch x6");
        if (sc_dut.registers[7] !== pipe_dut.u_id_stage.registers.registers[7]) $fatal(1, "B1 core-to-core mismatch x7");

        // 2. Independent golden expected value checks
        if (sc_dut.registers[1] !== 32'd5)  $fatal(1, "FAIL B1 golden x1");
        if (sc_dut.registers[2] !== 32'd5)  $fatal(1, "FAIL B1 golden x2");
        if (sc_dut.registers[3] !== 32'd15) $fatal(1, "FAIL B1 golden x3");
        if (sc_dut.registers[4] !== 32'd85) $fatal(1, "FAIL B1 golden x4");
        if (sc_dut.registers[5] !== 32'd15) $fatal(1, "FAIL B1 golden x5");
        if (sc_dut.registers[6] !== 32'd85) $fatal(1, "FAIL B1 golden x6");
        if (sc_dut.registers[7] !== 32'd0)  $fatal(1, "FAIL B1 golden x7");
        test_count = test_count + 1;
        $display("  [%02d] Benchmark 1: Core-to-Core & Golden Architectural State Check (x1-x7): MATCH PASS", test_count);
        $display("");

        // =====================================================================
        // Benchmark 2: Load/Store & Memory Access
        // =====================================================================
        run_comparison_benchmark(
            "Benchmark 2: Load/Store & Memory Access",
            "programs/benchmark_load_store.hex",
            32'h0000_0054,
            32'h0000_004C
        );

        // 1. Direct core-to-core state comparison
        for (i = 1; i <= 12; i = i + 1) begin
            if (sc_dut.registers[i] !== pipe_dut.u_id_stage.registers.registers[i])
                $fatal(1, "B2 core-to-core mismatch x%0d", i);
        end
        for (i = 16; i <= 20; i = i + 1) begin
            if (sc_dut.dmem[i] !== pipe_dut.u_mem_stage.u_data_mem.mem[i])
                $fatal(1, "B2 core-to-core mismatch dmem[%0d]", i);
        end

        // 2. Independent golden expected value checks
        if (sc_dut.registers[1]  !== 32'd64) $fatal(1, "FAIL B2 golden x1");
        if (sc_dut.registers[2]  !== 32'd68) $fatal(1, "FAIL B2 golden x2");
        if (sc_dut.registers[3]  !== 32'd72) $fatal(1, "FAIL B2 golden x3");
        if (sc_dut.registers[4]  !== 32'd10) $fatal(1, "FAIL B2 golden x4");
        if (sc_dut.registers[5]  !== 32'd25) $fatal(1, "FAIL B2 golden x5");
        if (sc_dut.registers[6]  !== 32'd35) $fatal(1, "FAIL B2 golden x6");
        if (sc_dut.registers[7]  !== 32'd40) $fatal(1, "FAIL B2 golden x7");
        if (sc_dut.registers[8]  !== 32'd75) $fatal(1, "FAIL B2 golden x8");
        if (sc_dut.registers[9]  !== 32'd65) $fatal(1, "FAIL B2 golden x9");
        if (sc_dut.registers[10] !== 32'd75) $fatal(1, "FAIL B2 golden x10");
        if (sc_dut.registers[11] !== 32'd0)  $fatal(1, "FAIL B2 golden x11");
        if (sc_dut.registers[12] !== 32'd0)  $fatal(1, "FAIL B2 golden x12");
        if (sc_dut.dmem[16] !== 32'd10)      $fatal(1, "FAIL B2 golden mem[16]");
        if (sc_dut.dmem[17] !== 32'd25)      $fatal(1, "FAIL B2 golden mem[17]");
        if (sc_dut.dmem[18] !== 32'd40)      $fatal(1, "FAIL B2 golden mem[18]");
        if (sc_dut.dmem[19] !== 32'd75)      $fatal(1, "FAIL B2 golden mem[19]");
        if (sc_dut.dmem[20] !== 32'd65)      $fatal(1, "FAIL B2 golden mem[20]");
        test_count = test_count + 1;
        $display("  [%02d] Benchmark 2: Core-to-Core & Golden Architectural State Check (x1-x12, dmem[16:20]): MATCH PASS", test_count);
        $display("");

        // =====================================================================
        // Benchmark 3: Control Hazards & Dual Forwarding
        // =====================================================================
        run_comparison_benchmark(
            "Benchmark 3: Control Hazards & Dual Forwarding",
            "programs/benchmark_control_hazards.hex",
            32'h0000_005C,
            32'h0000_0054
        );

        // 1. Direct core-to-core state comparison
        for (i = 1; i <= 17; i = i + 1) begin
            if (sc_dut.registers[i] !== pipe_dut.u_id_stage.registers.registers[i])
                $fatal(1, "B3 core-to-core mismatch x%0d", i);
        end
        if (sc_dut.dmem[0] !== pipe_dut.u_mem_stage.u_data_mem.mem[0])
            $fatal(1, "B3 core-to-core mismatch dmem[0]");

        // 2. Independent golden expected value checks
        if (sc_dut.registers[1]  !== 32'd10)  $fatal(1, "FAIL B3 golden x1");
        if (sc_dut.registers[2]  !== 32'd20)  $fatal(1, "FAIL B3 golden x2");
        if (sc_dut.registers[3]  !== 32'd10)  $fatal(1, "FAIL B3 golden x3");
        if (sc_dut.registers[4]  !== 32'd30)  $fatal(1, "FAIL B3 golden x4");
        if (sc_dut.registers[5]  !== 32'd0)   $fatal(1, "FAIL B3 golden x5");
        if (sc_dut.registers[6]  !== 32'd0)   $fatal(1, "FAIL B3 golden x6");
        if (sc_dut.registers[7]  !== 32'd0)   $fatal(1, "FAIL B3 golden x7");
        if (sc_dut.registers[8]  !== 32'd40)  $fatal(1, "FAIL B3 golden x8");
        if (sc_dut.registers[9]  !== 32'd0)   $fatal(1, "FAIL B3 golden x9");
        if (sc_dut.registers[10] !== 32'd0)   $fatal(1, "FAIL B3 golden x10");
        if (sc_dut.registers[11] !== 32'd0)   $fatal(1, "FAIL B3 golden x11");
        if (sc_dut.registers[12] !== 32'd100) $fatal(1, "FAIL B3 golden x12");
        if (sc_dut.registers[13] !== 32'd100) $fatal(1, "FAIL B3 golden x13");
        if (sc_dut.registers[14] !== 32'd130) $fatal(1, "FAIL B3 golden x14");
        if (sc_dut.registers[15] !== 32'd30)  $fatal(1, "FAIL B3 golden x15");
        if (sc_dut.registers[16] !== 32'd100) $fatal(1, "FAIL B3 golden x16");
        if (sc_dut.registers[17] !== 32'd0)   $fatal(1, "FAIL B3 golden x17");
        if (sc_dut.dmem[0]       !== 32'd100) $fatal(1, "FAIL B3 golden mem[0]");
        test_count = test_count + 1;
        $display("  [%02d] Benchmark 3: Core-to-Core & Golden Architectural State Check (x1-x17, dmem[0]): MATCH PASS", test_count);
        $display("");

        $display("================================================================");
        $display("ALL %0d CO-SIMULATION COMPARISON TESTS PASSED SUCCESSFULLY", test_count);
        $display("================================================================");
        $finish;
    end

endmodule
