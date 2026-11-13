// IF-path fetch test using programs/if_test.hex (issue #5).
// Run from the repository root (see programs/README.md):
//   iverilog -g2012 -o simulation/tb_fetch.vvp testbench/tb_fetch.v \
//       rtl/stages/if_stage.v rtl/stages/pc.v rtl/stages/instr_mem.v
//   vvp simulation/tb_fetch.vvp
`timescale 1ns/1ps
module tb_fetch;

    reg         clk = 0, rst = 1, redirect = 0;
    reg  [31:0] target = 0;
    wire [31:0] pc, pc_plus4, instr;
    wire [31:0] next_pc = redirect ? target : pc_plus4;
    integer errors = 0, k;

    // Expected words, written independently of the hex file.
    reg [31:0] exp [0:7];
    initial begin
        exp[0] = 32'h00002083; exp[1] = 32'h00108133;
        exp[2] = 32'h00e00193; exp[3] = 32'h40310233;
        exp[4] = 32'h00310463; exp[5] = 32'h00002023;
        exp[6] = 32'h00202223; exp[7] = 32'hfe021ee3;
    end

    if_stage #(.DEPTH_WORDS(64), .INIT_FILE("programs/if_test.hex"))
        dut (.clk(clk), .rst(rst), .next_pc(next_pc),
             .pc(pc), .pc_plus4(pc_plus4), .instr(instr));

    always #5 clk = ~clk;

    task check_word(input [255:0] name, input [31:0] e_pc, input [31:0] e_instr);
        begin
            if (pc !== e_pc || pc_plus4 !== e_pc + 4 || instr !== e_instr) begin
                $display("FAIL: %0s got pc=%h pc4=%h instr=%h | exp pc=%h pc4=%h instr=%h",
                         name, pc, pc_plus4, instr, e_pc, e_pc + 4, e_instr);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("simulation/tb_fetch.vcd");
        $dumpvars(0, tb_fetch);

        // Reset
        repeat (2) @(posedge clk);
        #1 check_word("reset", 32'h0, exp[0]);

        // Sequential fetch of all 8 words, in order.
        @(negedge clk) rst = 0;
        for (k = 1; k < 8; k = k + 1) begin
            @(posedge clk); #1;
            check_word("sequential", 4 * k, exp[k]);
        end

        // Falls through into NOP fill after the image.
        @(posedge clk); #1 check_word("past image", 32'h20, 32'h0000_0013);

        // Redirect to 0x18 (the "done" store), then continue sequentially.
        @(negedge clk) begin redirect = 1; target = 32'h18; end
        @(posedge clk); #1 check_word("redirect", 32'h18, exp[6]);
        @(negedge clk) redirect = 0;
        @(posedge clk); #1 check_word("after redirect", 32'h1C, exp[7]);

        // Reset returns to word 0.
        @(negedge clk) rst = 1;
        @(posedge clk); #1 check_word("second reset", 32'h0, exp[0]);

        if (errors == 0) $display("PASS: tb_fetch");
        else             $display("FAILED: %0d error(s)", errors);
        $finish;
    end

endmodule
