// Self-checking testbench for if_stage.v (issue #3).
// Run from the repository root:
//   iverilog -g2012 -o simulation/tb_if_stage.vvp testbench/tb_if_stage.v \
//       rtl/stages/if_stage.v rtl/stages/pc.v rtl/stages/instr_mem.v
//   vvp simulation/tb_if_stage.vvp
`timescale 1ns/1ps
module tb_if_stage;

    reg         clk = 0, rst = 1;
    reg         redirect = 0;
    reg  [31:0] target = 0;
    wire [31:0] pc, pc_plus4, instr;
    wire [31:0] next_pc = redirect ? target : pc_plus4;  // stand-in for top-level mux
    integer errors = 0;

    if_stage #(.DEPTH_WORDS(16), .INIT_FILE("testbench/fixtures/pc_imem_test.hex"))
        dut (.clk(clk), .rst(rst), .next_pc(next_pc),
             .pc(pc), .pc_plus4(pc_plus4), .instr(instr));

    always #5 clk = ~clk;

    task check_fetch(input [255:0] name, input [31:0] e_pc, input [31:0] e_instr);
        begin
            if (pc !== e_pc || pc_plus4 !== e_pc + 4 || instr !== e_instr) begin
                $display("FAIL: %0s got pc=%h pc4=%h instr=%h | exp pc=%h pc4=%h instr=%h",
                         name, pc, pc_plus4, instr, e_pc, e_pc + 4, e_instr);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("simulation/tb_if_stage.vcd");
        $dumpvars(0, tb_if_stage);

        repeat (2) @(posedge clk);
        #1 check_fetch("reset", 32'h0, 32'h1111_1111);

        @(negedge clk) rst = 0;
        @(posedge clk); #1 check_fetch("seq 1", 32'h4, 32'h2222_2222);
        @(posedge clk); #1 check_fetch("seq 2", 32'h8, 32'h3333_3333);
        @(posedge clk); #1 check_fetch("seq 3", 32'hC, 32'h4444_4444);

        // Redirect back to 0x4 (as a taken branch would).
        @(negedge clk) begin redirect = 1; target = 32'h4; end
        @(posedge clk); #1 check_fetch("redirect", 32'h4, 32'h2222_2222);
        @(negedge clk) redirect = 0;
        @(posedge clk); #1 check_fetch("after redirect", 32'h8, 32'h3333_3333);

        // Reset mid-run.
        @(negedge clk) rst = 1;
        @(posedge clk); #1 check_fetch("mid-run reset", 32'h0, 32'h1111_1111);

        if (errors == 0) $display("PASS: tb_if_stage");
        else             $display("FAILED: %0d error(s)", errors);
        $finish;
    end

endmodule
