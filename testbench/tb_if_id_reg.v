// Self-checking testbench for if_id_reg.v (issue #4).
// Run from the repository root:
//   iverilog -g2012 -o simulation/tb_if_id_reg.vvp \
//       testbench/tb_if_id_reg.v rtl/pipeline_registers/if_id_reg.v
//   vvp simulation/tb_if_id_reg.vvp
`timescale 1ns/1ps
module tb_if_id_reg;

    reg         clk = 0, rst = 1, en = 1, flush = 0;
    reg  [31:0] pc_in = 0, pc4_in = 0, instr_in = 0;
    wire [31:0] pc_out, pc4_out, instr_out;
    wire        valid_out;
    integer errors = 0;

    if_id_reg dut (.clk(clk), .rst(rst), .en(en), .flush(flush),
                   .pc_in(pc_in), .pc_plus4_in(pc4_in), .instr_in(instr_in),
                   .pc_out(pc_out), .pc_plus4_out(pc4_out),
                   .instr_out(instr_out), .valid_out(valid_out));

    always #5 clk = ~clk;

    task check_out(input [127:0] name, input [31:0] pc, input [31:0] pc4,
                input [31:0] instr, input v);
        begin
            if (pc_out !== pc || pc4_out !== pc4 || instr_out !== instr || valid_out !== v) begin
                $display("FAIL: %0s got pc=%h pc4=%h instr=%h v=%b | exp pc=%h pc4=%h instr=%h v=%b",
                         name, pc_out, pc4_out, instr_out, valid_out, pc, pc4, instr, v);
                errors = errors + 1;
            end
        end
    endtask

    // Apply inputs on negedge, check just after the next posedge.
    task drive(input r, input e, input f, input [31:0] pc, input [31:0] instr);
        begin
            @(negedge clk);
            rst = r; en = e; flush = f;
            pc_in = pc; pc4_in = pc + 4; instr_in = instr;
            @(posedge clk); #1;
        end
    endtask

    localparam NOP = 32'h0000_0013;

    initial begin
        $dumpfile("simulation/tb_if_id_reg.vcd");
        $dumpvars(0, tb_if_id_reg);

        // Reset
        drive(1, 1, 0, 32'h100, 32'hAAAA_0001);
        check_out("reset", 0, 0, NOP, 0);

        // Normal capture on consecutive cycles: fields stay aligned.
        drive(0, 1, 0, 32'h00, 32'hA0000000);
        check_out("capture 0", 32'h00, 32'h04, 32'hA0000000, 1);
        drive(0, 1, 0, 32'h04, 32'hA0000004);
        check_out("capture 1", 32'h04, 32'h08, 32'hA0000004, 1);
        drive(0, 1, 0, 32'h08, 32'hA0000008);
        check_out("capture 2", 32'h08, 32'h0C, 32'hA0000008, 1);

        // Stall: hold all fields while inputs change.
        drive(0, 0, 0, 32'h0C, 32'hA000000C);
        check_out("stall 1", 32'h08, 32'h0C, 32'hA0000008, 1);
        drive(0, 0, 0, 32'h10, 32'hA0000010);
        check_out("stall 2", 32'h08, 32'h0C, 32'hA0000008, 1);

        // Resume capture.
        drive(0, 1, 0, 32'h10, 32'hA0000010);
        check_out("resume", 32'h10, 32'h14, 32'hA0000010, 1);

        // Flush: NOP + metadata cleared.
        drive(0, 1, 1, 32'h14, 32'hA0000014);
        check_out("flush", 0, 0, NOP, 0);

        // Capture after flush works.
        drive(0, 1, 0, 32'h20, 32'hA0000020);
        check_out("capture after flush", 32'h20, 32'h24, 32'hA0000020, 1);

        // Priority: flush beats stall.
        drive(0, 0, 1, 32'h24, 32'hA0000024);
        check_out("flush + stall", 0, 0, NOP, 0);

        // Priority: reset beats flush and stall.
        drive(0, 1, 0, 32'h30, 32'hA0000030);
        drive(1, 0, 1, 32'h34, 32'hA0000034);
        check_out("reset + flush + stall", 0, 0, NOP, 0);
        drive(1, 1, 0, 32'h38, 32'hA0000038);
        check_out("reset + capture", 0, 0, NOP, 0);

        if (errors == 0) $display("PASS: tb_if_id_reg");
        else             $display("FAILED: %0d error(s)", errors);
        $finish;
    end

endmodule
