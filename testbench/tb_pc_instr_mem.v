// Self-checking testbench for pc.v and instr_mem.v (issue #2).
// Run from the repository root:
//   iverilog -g2012 -o simulation/tb_pc_instr_mem.vvp \
//       testbench/tb_pc_instr_mem.v rtl/stages/pc.v rtl/stages/instr_mem.v
//   vvp simulation/tb_pc_instr_mem.vvp
// Waveform: gtkwave simulation/tb_pc_instr_mem.vcd
`timescale 1ns/1ps
module tb_pc_instr_mem;

    reg         clk = 0;
    reg         rst = 1;
    reg  [31:0] next_pc = 0;
    wire [31:0] pc;
    wire [31:0] instr;

    integer errors = 0;

    pc #(.RESET_VECTOR(32'h0)) u_pc (.clk(clk), .rst(rst), .next_pc(next_pc), .pc(pc));
    instr_mem #(.DEPTH_WORDS(16), .INIT_FILE("testbench/fixtures/pc_imem_test.hex"))
        u_im (.addr(pc), .instr(instr));

    always #5 clk = ~clk;

    task check(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL: %0s got=%h expected=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    // Drive on negedge, sample after the following posedge settles.
    initial begin
        $dumpfile("simulation/tb_pc_instr_mem.vcd");
        $dumpvars(0, tb_pc_instr_mem);

        // Reset: PC at reset vector while rst held, even with next_pc nonzero.
        next_pc = 32'h0000_0100;
        repeat (2) @(posedge clk);
        #1 check("reset pc", pc, 32'h0);
        check("reset instr", instr, 32'h1111_1111);

        // Release reset, sequential advance by 4.
        @(negedge clk) rst = 0;
        next_pc = pc + 4;
        @(posedge clk); #1;
        check("pc after 1", pc, 32'h4);
        check("instr @4", instr, 32'h2222_2222);

        @(negedge clk) next_pc = pc + 4;
        @(posedge clk); #1;
        check("pc after 2", pc, 32'h8);
        check("instr @8", instr, 32'h3333_3333);

        @(negedge clk) next_pc = pc + 4;
        @(posedge clk); #1;
        check("pc after 3", pc, 32'hC);
        check("instr @C", instr, 32'h4444_4444);

        // Externally selected next PC (redirect back to 0x4).
        @(negedge clk) next_pc = 32'h4;
        @(posedge clk); #1;
        check("redirect pc", pc, 32'h4);
        check("redirect instr", instr, 32'h2222_2222);

        // Unwritten in-range word defaults to NOP.
        @(negedge clk) next_pc = 32'h10;
        @(posedge clk); #1;
        check("uninit word is NOP", instr, 32'h0000_0013);

        // Out-of-range address (depth 16 words = 0x40 bytes) returns NOP.
        @(negedge clk) next_pc = 32'h0000_0040;
        @(posedge clk); #1;
        check("out-of-range instr", instr, 32'h0000_0013);
        @(negedge clk) next_pc = 32'h8000_0000;
        @(posedge clk); #1;
        check("far out-of-range instr", instr, 32'h0000_0013);

        // Mid-run reset returns to the reset vector.
        @(negedge clk) rst = 1;
        @(posedge clk); #1;
        check("mid-run reset pc", pc, 32'h0);

        if (errors == 0) $display("PASS: tb_pc_instr_mem");
        else             $display("FAILED: %0d error(s)", errors);
        $finish;
    end

endmodule
