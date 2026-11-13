`timescale 1ns/1ps

module tb_ex_mem_reg;
    reg clk = 0;
    reg rst = 0;
    reg en = 1;
    reg flush = 0;

    localparam WIDTH = 138;
    reg  [WIDTH-1:0] entry;
    wire [WIDTH-1:0] result;

    wire [31:0] alu_result_in, alu_result_out;
    wire [31:0] store_data_in, store_data_out;
    wire [4:0]  rd_in, rd_out;
    wire [31:0] pc_in, pc_out;
    wire [31:0] pc_plus4_in, pc_plus4_out;
    wire        mem_read_in, mem_read_out;
    wire        mem_write_in, mem_write_out;
    wire        reg_write_in, reg_write_out;
    wire        wb_from_mem_in, wb_from_mem_out;
    wire        valid_in, valid_out;

    integer test_count = 0;
    integer i;

    assign {alu_result_in, store_data_in, rd_in, pc_in, pc_plus4_in,
            mem_read_in, mem_write_in, reg_write_in, wb_from_mem_in, valid_in} = entry;

    assign result = {alu_result_out, store_data_out, rd_out, pc_out, pc_plus4_out,
                     mem_read_out, mem_write_out, reg_write_out, wb_from_mem_out, valid_out};

    ex_mem_reg dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .flush(flush),
        .alu_result_in(alu_result_in),
        .alu_result_out(alu_result_out),
        .store_data_in(store_data_in),
        .store_data_out(store_data_out),
        .rd_in(rd_in),
        .rd_out(rd_out),
        .pc_in(pc_in),
        .pc_out(pc_out),
        .pc_plus4_in(pc_plus4_in),
        .pc_plus4_out(pc_plus4_out),
        .mem_read_in(mem_read_in),
        .mem_read_out(mem_read_out),
        .mem_write_in(mem_write_in),
        .mem_write_out(mem_write_out),
        .reg_write_in(reg_write_in),
        .reg_write_out(reg_write_out),
        .wb_from_mem_in(wb_from_mem_in),
        .wb_from_mem_out(wb_from_mem_out),
        .valid_in(valid_in),
        .valid_out(valid_out)
    );

    task tick_and_check;
        input [WIDTH-1:0] expected;
        input [159:0]     test_name;
        begin
            #2; clk = 1; #1;
            if (result !== expected) begin
                $fatal(1, "FAIL [%0s]: bundle=%h expected=%h", test_name, result, expected);
            end
            clk = 0;
            test_count = test_count + 1;
        end
    endtask

    // Helper functions to construct 138-bit test vectors
    function [WIDTH-1:0] pack;
        input [31:0] a_res;
        input [31:0] s_data;
        input [4:0]  dst;
        input [31:0] p_pc;
        input [31:0] p_pc4;
        input        m_read;
        input        m_write;
        input        r_write;
        input        wb_sel;
        input        v;
        begin
            pack = {a_res, s_data, dst, p_pc, p_pc4, m_read, m_write, r_write, wb_sel, v};
        end
    endfunction

    reg [WIDTH-1:0] alu_entry, sw_entry, lw_entry;
    reg [WIDTH-1:0] walk_pattern;

    initial begin
        // Construct representative instruction bundles:
        // 1. ALU instruction (e.g. ADD x7, x5, x6): result=42, store=0, rd=7, pc=1000, pc+4=1004, reg_write=1, valid=1
        alu_entry = pack(32'd42, 32'd0, 5'd7, 32'h00001000, 32'h00001004, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1);
        // 2. SW instruction (e.g. SW x6, 4(x5)): addr=0x10000, store=0xDEADBEEF, rd=0, pc=1004, pc+4=1008, mem_write=1, valid=1
        sw_entry  = pack(32'h00010000, 32'hDEADBEEF, 5'd0, 32'h00001004, 32'h00001008, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1);
        // 3. LW instruction (e.g. LW x1, 0(x5)): addr=0x10004, store=0, rd=1, pc=1008, pc+4=100C, mem_read=1, reg_write=1, wb=1, valid=1
        lw_entry  = pack(32'h00010004, 32'd0, 5'd1, 32'h00001008, 32'h0000100C, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1);

        // ====================================================================
        // 1. Reset Behavior
        // ====================================================================
        entry = {WIDTH{1'b1}};
        rst = 1; en = 1; flush = 0;
        tick_and_check({WIDTH{1'b0}}, "Reset clears all fields with all-1 inputs");

        // ====================================================================
        // 2. Normal Capture of Consecutive Distinct Entries
        // ====================================================================
        rst = 0;
        // Capture ALU entry
        entry = alu_entry;
        tick_and_check(alu_entry, "Normal capture of ALU entry");

        // Capture Store entry (consecutive)
        entry = sw_entry;
        tick_and_check(sw_entry, "Consecutive capture of Store entry");

        // Capture Load entry (consecutive)
        entry = lw_entry;
        tick_and_check(lw_entry, "Consecutive capture of Load entry");

        // ====================================================================
        // 3. Hold Behavior (en = 0)
        // ====================================================================
        // Outputs currently hold lw_entry; present alu_entry with en=0
        entry = alu_entry;
        en = 0;
        tick_and_check(lw_entry, "Hold keeps previous Load bundle when en=0");
        tick_and_check(lw_entry, "Hold persists across multiple cycles");

        // ====================================================================
        // 4. Flush Behavior (flush = 1, en = 1)
        // ====================================================================
        en = 1;
        entry = alu_entry;
        flush = 1;
        tick_and_check({WIDTH{1'b0}}, "Flush clears active bundle when en=1");
        flush = 0;

        // ====================================================================
        // 5. Reset & Flush Priority Over Hold (en = 0)
        // ====================================================================
        // Capture ALU entry first
        entry = alu_entry;
        tick_and_check(alu_entry, "Capture ALU entry before hold-priority tests");

        // Flush while held (flush=1, en=0): flush MUST beat hold
        entry = sw_entry;
        en = 0;
        flush = 1;
        tick_and_check({WIDTH{1'b0}}, "Flush beats hold (clears bundle when en=0)");
        flush = 0;

        // Re-capture SW entry
        en = 1;
        entry = sw_entry;
        tick_and_check(sw_entry, "Re-capture Store entry");

        // Reset while held (rst=1, en=0): reset MUST beat hold
        entry = alu_entry;
        en = 0;
        rst = 1;
        tick_and_check({WIDTH{1'b0}}, "Reset beats hold (clears bundle when en=0)");
        rst = 0;
        en = 1;

        // ====================================================================
        // 6. Invalid-Input Bubble (valid_in = 0, en = 1)
        //    Must capture cleared bundle; side-effect controls must be 0
        // ====================================================================
        // Present invalid entry with write enables and memory controls asserted
        entry = pack(32'hBAADBEEF, 32'hDEADDEAD, 5'd31, 32'hFFFF0000, 32'hFFFF0004,
                     1'b1, 1'b1, 1'b1, 1'b1, 1'b0); // valid=0
        tick_and_check({WIDTH{1'b0}}, "Bubble input clears all outputs & suppresses writes");

        // Verify side-effect controls explicitly
        if (mem_read_out !== 1'b0 || mem_write_out !== 1'b0 ||
            reg_write_out !== 1'b0 || valid_out !== 1'b0) begin
            $fatal(1, "FAIL: Bubble asserted side-effect controls");
        end

        // ====================================================================
        // 7. Hold Priority Over Invalid-Input Bubble (valid_in=0 with en=0)
        //    Proves hold has priority over invalid-input bubble capture.
        // ====================================================================
        // Capture valid ALU entry first
        en = 1; flush = 0;
        entry = alu_entry;
        tick_and_check(alu_entry, "Capture valid ALU entry before bubble-hold test");

        // Set en=0 and present an invalid-input bubble (valid_in=0 with side-effects high)
        en = 0;
        entry = pack(32'hDEADBEEF, 32'hCAFE1234, 5'd15, 32'h00002000, 32'h00002004,
                     1'b1, 1'b1, 1'b1, 1'b1, 1'b0); // valid=0
        tick_and_check(alu_entry, "valid_in=0 with en=0 holds existing entry (hold beats bubble)");
        tick_and_check(alu_entry, "Bubble-hold persists across multiple cycles");

        // Now enable capture (en=1) with valid_in=0: bubble is now captured and clears outputs
        en = 1;
        tick_and_check({WIDTH{1'b0}}, "en=1 with valid_in=0 captures bubble and clears bundle");

        // ====================================================================
        // 8. Comprehensive Walking Bit Test:
        //    For each payload bit:
        //      - Capture: active entry with bit set is captured.
        //      - Hold: input is modified with en=0; captured value holds.
        //      - Clear: assert flush and verify entire bundle clears.
        // ====================================================================
        for (i = 0; i < WIDTH; i = i + 1) begin
            // 1. Capture single-bit payload with valid_in=1
            walk_pattern = {WIDTH{1'b0}};
            walk_pattern[0] = 1'b1; // valid_in = 1
            walk_pattern[i] = 1'b1; // payload bit i
            entry = walk_pattern;
            en = 1; flush = 0;
            tick_and_check(walk_pattern, "Walking bit active capture");

            // 2. Hold: change input with en=0 and verify captured bundle remains unchanged
            en = 0;
            entry = ~walk_pattern;
            tick_and_check(walk_pattern, "Walking bit hold with inverted input");

            // 3. Clear: assert flush and verify entire bundle clears
            flush = 1;
            tick_and_check({WIDTH{1'b0}}, "Walking bit clear with flush");
            flush = 0; en = 1;
        end

        // Clean finish
        $display("PASS: all %0d EX/MEM pipeline register tests completed successfully", test_count);
        $finish;
    end

endmodule
