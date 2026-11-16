// =============================================================================
// Self-checking testbench for mem_wb_reg.v (Issue #18)
//
// Run from the repository root:
//   iverilog -g2012 -o simulation/tb_mem_wb_reg.vvp \
//       testbench/tb_mem_wb_reg.v \
//       rtl/pipeline_registers/mem_wb_reg.v
//   vvp simulation/tb_mem_wb_reg.vvp
//
// Tests follow the same structure as tb_ex_mem_reg.v for consistency:
//   1. Reset                       — all outputs clear to 0
//   2. Active capture (LW entry)   — full bundle latched
//   3. Active capture (ALU entry)  — overwrite with new bundle
//   4. Hold (en = 0)               — outputs frozen across cycles
//   5. Flush (flush = 1, en = 1)   — bundle cleared
//   6. Flush beats hold            — flush wins even when en = 0
//   7. Reset beats hold            — rst wins even when en = 0
//   8. Bubble capture (valid_in=0) — all outputs clear; side-effects = 0
//   9. Hold beats bubble           — en=0 keeps valid entry despite valid_in=0
//  10. Walking-bit test            — capture / hold / flush for every payload bit
// =============================================================================
`timescale 1ns/1ps

module tb_mem_wb_reg;

    // -------------------------------------------------------------------------
    // DUT interface
    // -------------------------------------------------------------------------
    reg        clk            = 0;
    reg        rst            = 0;
    reg        en             = 1;
    reg        flush          = 0;

    reg [31:0] alu_result_in  = 0;
    reg [31:0] load_data_in   = 0;
    reg [4:0]  rd_in          = 0;
    reg [31:0] pc_in          = 0;
    reg [31:0] pc_plus4_in    = 0;
    reg        reg_write_in   = 0;
    reg        wb_from_mem_in = 0;
    reg        valid_in       = 0;

    wire [31:0] alu_result_out;
    wire [31:0] load_data_out;
    wire [4:0]  rd_out;
    wire [31:0] pc_out;
    wire [31:0] pc_plus4_out;
    wire        reg_write_out;
    wire        wb_from_mem_out;
    wire        valid_out;

    mem_wb_reg dut (
        .clk           (clk),
        .rst           (rst),
        .en            (en),
        .flush         (flush),
        .alu_result_in (alu_result_in),
        .load_data_in  (load_data_in),
        .rd_in         (rd_in),
        .pc_in         (pc_in),
        .pc_plus4_in   (pc_plus4_in),
        .reg_write_in  (reg_write_in),
        .wb_from_mem_in(wb_from_mem_in),
        .valid_in      (valid_in),
        .alu_result_out(alu_result_out),
        .load_data_out (load_data_out),
        .rd_out        (rd_out),
        .pc_out        (pc_out),
        .pc_plus4_out  (pc_plus4_out),
        .reg_write_out (reg_write_out),
        .wb_from_mem_out(wb_from_mem_out),
        .valid_out     (valid_out)
    );

    // -------------------------------------------------------------------------
    // Bundle packing: [alu_result | load_data | rd | pc | pc_plus4 |
    //                  reg_write | wb_from_mem | valid]
    // Total = 32+32+5+32+32+1+1+1 = 136 bits
    // Bit 0 = valid, bit 1 = wb_from_mem, bit 2 = reg_write, ...
    // -------------------------------------------------------------------------
    localparam WIDTH = 136;

    // Pack into a flat vector for comparison (LSB = valid)
    function [WIDTH-1:0] pack;
        input [31:0] alu_r;
        input [31:0] ld;
        input [4:0]  rd_;
        input [31:0] pc_;
        input [31:0] pc4_;
        input        rw;
        input        wfm;
        input        v;
        begin
            pack = {alu_r, ld, rd_, pc_, pc4_, rw, wfm, v};
        end
    endfunction

    // Flatten DUT outputs to same encoding
    wire [WIDTH-1:0] result;
    assign result = {alu_result_out, load_data_out, rd_out,
                     pc_out, pc_plus4_out,
                     reg_write_out, wb_from_mem_out, valid_out};

    // -------------------------------------------------------------------------
    // Clock: 10 ns period
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    integer errors     = 0;
    integer test_count = 0;

    task apply_bundle;
        input [WIDTH-1:0] bundle;
        begin
            {alu_result_in, load_data_in, rd_in,
             pc_in, pc_plus4_in,
             reg_write_in, wb_from_mem_in, valid_in} = bundle;
        end
    endtask

    task tick_and_check;
        input [WIDTH-1:0] expected;
        input [255:0]     name;
        begin
            @(posedge clk); #1;
            test_count = test_count + 1;
            if (result !== expected) begin
                $display("FAIL [%0d]: %0s", test_count, name);
                $display("  got      = %0h", result);
                $display("  expected = %0h", expected);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Predefined bundles
    // -------------------------------------------------------------------------
    // LW instruction: wb_from_mem=1, reg_write=1, valid=1
    wire [WIDTH-1:0] lw_entry;
    assign lw_entry = pack(32'h0, 32'hDEAD_BEEF, 5'd3,
                           32'h0000_0010, 32'h0000_0014,
                           1'b1, 1'b1, 1'b1);

    // R-type ALU instruction: wb_from_mem=0, reg_write=1, valid=1
    wire [WIDTH-1:0] alu_entry;
    assign alu_entry = pack(32'hCAFE_1234, 32'h0, 5'd7,
                            32'h0000_0020, 32'h0000_0024,
                            1'b1, 1'b0, 1'b1);

    // -------------------------------------------------------------------------
    // Walking-bit helper
    // -------------------------------------------------------------------------
    reg [WIDTH-1:0] walk_pattern;
    integer i;

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("simulation/tb_mem_wb_reg.vcd");
        $dumpvars(0, tb_mem_wb_reg);

        // =====================================================================
        // 1. Reset
        // =====================================================================
        rst = 1; en = 1; flush = 0;
        apply_bundle(lw_entry);
        tick_and_check({WIDTH{1'b0}}, "Reset clears all outputs");
        rst = 0;

        // =====================================================================
        // 2. Active capture — LW entry
        // =====================================================================
        apply_bundle(lw_entry);
        tick_and_check(lw_entry, "Capture LW entry");

        // =====================================================================
        // 3. Active capture — overwrite with ALU entry
        // =====================================================================
        apply_bundle(alu_entry);
        tick_and_check(alu_entry, "Capture ALU entry overwrites LW entry");

        // =====================================================================
        // 4. Hold (en = 0): output freezes across two cycles
        // =====================================================================
        en = 0;
        apply_bundle(lw_entry);  // change inputs — must NOT propagate
        tick_and_check(alu_entry, "Hold: inputs ignored when en=0 (cycle 1)");
        tick_and_check(alu_entry, "Hold: persists across multiple cycles");

        // =====================================================================
        // 5. Flush (flush=1, en=1) clears active bundle
        // =====================================================================
        en = 1; flush = 1;
        apply_bundle(alu_entry);
        tick_and_check({WIDTH{1'b0}}, "Flush clears bundle when en=1");
        flush = 0;

        // =====================================================================
        // 6. Flush beats hold (flush=1, en=0)
        // =====================================================================
        // First capture a valid entry
        apply_bundle(lw_entry);
        tick_and_check(lw_entry, "Capture LW entry before flush-beats-hold test");

        en = 0; flush = 1;
        apply_bundle(alu_entry);  // irrelevant — flush should win
        tick_and_check({WIDTH{1'b0}}, "Flush beats hold (clears when en=0)");
        flush = 0;

        // =====================================================================
        // 7. Reset beats hold (rst=1, en=0)
        // =====================================================================
        en = 1;
        apply_bundle(alu_entry);
        tick_and_check(alu_entry, "Capture ALU entry before reset-beats-hold test");

        en = 0; rst = 1;
        apply_bundle(lw_entry);
        tick_and_check({WIDTH{1'b0}}, "Reset beats hold (clears when en=0)");
        rst = 0; en = 1;

        // =====================================================================
        // 8. Bubble capture (valid_in=0, en=1): clears all outputs
        // =====================================================================
        apply_bundle(pack(32'hBADBAD00, 32'hDEADDEAD, 5'd31,
                          32'hFFFF0000, 32'hFFFF0004,
                          1'b1, 1'b1, 1'b0));  // valid = 0
        tick_and_check({WIDTH{1'b0}}, "Bubble input clears all outputs");

        // Verify side-effect controls are explicitly 0
        if (reg_write_out !== 1'b0 || wb_from_mem_out !== 1'b0 || valid_out !== 1'b0) begin
            $fatal(1, "FAIL: Bubble asserted side-effect controls");
        end

        // =====================================================================
        // 9. Hold beats bubble (valid_in=0, en=0): captured entry survives
        // =====================================================================
        en = 1;
        apply_bundle(alu_entry);
        tick_and_check(alu_entry, "Capture ALU entry before bubble-hold test");

        en = 0;
        apply_bundle(pack(32'hDEADC0DE, 32'hCAFEBABE, 5'd15,
                          32'h0000_2000, 32'h0000_2004,
                          1'b1, 1'b1, 1'b0));  // valid = 0 — should not replace
        tick_and_check(alu_entry, "Hold beats bubble (en=0 keeps valid entry)");
        tick_and_check(alu_entry, "Bubble-hold persists across multiple cycles");

        // Now enable — bubble should propagate and clear
        en = 1;
        tick_and_check({WIDTH{1'b0}}, "en=1 with valid_in=0 captures bubble");

        // =====================================================================
        // 10. Walking-bit test
        // =====================================================================
        for (i = 0; i < WIDTH; i = i + 1) begin
            // Bit 0 is valid; always set it so the register actually captures.
            // For i=0, only valid is set.
            walk_pattern      = {WIDTH{1'b0}};
            walk_pattern[0]   = 1'b1;   // valid_in = 1
            walk_pattern[i]   = 1'b1;   // payload bit i

            apply_bundle(walk_pattern);
            en = 1; flush = 0;
            tick_and_check(walk_pattern, "Walking bit active capture");

            // Hold: invert inputs — captured value must remain
            en = 0;
            apply_bundle(~walk_pattern);
            tick_and_check(walk_pattern, "Walking bit hold with inverted input");

            // Flush clears
            flush = 1;
            tick_and_check({WIDTH{1'b0}}, "Walking bit flush");
            flush = 0; en = 1;
        end

        // =====================================================================
        // Result summary
        // =====================================================================
        if (errors == 0)
            $display("PASS: all %0d MEM/WB pipeline register tests completed successfully", test_count);
        else
            $display("FAILED: %0d error(s) in %0d checks", errors, test_count);
        $finish;
    end

endmodule
