`timescale 1ns/1ps
module tb_register_file;
    reg clk = 0, rst = 0, write_en = 0;
    reg [4:0] rd, rs1, rs2;
    reg [31:0] write_data;
    wire [31:0] rs1_data, rs2_data;
    integer i;

    register_file dut (.clk(clk), .rst(rst), .write_en(write_en), .rd(rd),
        .write_data(write_data), .rs1(rs1), .rs2(rs2),
        .rs1_data(rs1_data), .rs2_data(rs2_data));

    task tick;
        begin #2; clk = 1; #2; clk = 0; #2; end
    endtask

    task check;
        input [31:0] expected1, expected2;
        begin
            #1;
            if (rs1_data !== expected1 || rs2_data !== expected2)
                $fatal(1, "x%0d=%h expected %h; x%0d=%h expected %h",
                       rs1, rs1_data, expected1, rs2, rs2_data, expected2);
        end
    endtask

    initial begin
        rst = 1;
        tick;
        rst = 0;
        write_en = 1;
        for (i = 0; i < 32; i = i + 1) begin
            rd = i;
            write_data = 32'h80000000 + i;
            tick;
        end
        write_en = 0;
        for (i = 1; i < 32; i = i + 1) begin
            rs1 = i;
            rs2 = 32-i;
            check(32'h80000000 + i, 32'h80000000 + 32-i);
        end
        rs1 = 0; rs2 = 0; rd = 0; write_en = 1;
        check(0, 0);

        // Both ports see WB immediately. Cancel before the edge: no commit.
        rd = 7; rs1 = 7; rs2 = 7; write_data = 32'h12345678;
        check(write_data, write_data);
        write_en = 0;
        tick;
        check(32'h80000007, 32'h80000007);
        write_en = 1; rs2 = 8;
        tick;
        write_en = 0;
        check(32'h12345678, 32'h80000008);

        // Reset wins over an enabled write, and disables the bypass.
        rst = 1; write_en = 1; write_data = 32'hffffffff;
        check(32'h12345678, 32'h80000008);
        tick;
        write_en = 0; rst = 0;
        for (i = 0; i < 32; i = i + 1) begin
            rs1 = i; rs2 = 31-i; check(0, 0);
        end
        $display("PASS: register file reset, reads, writes, x0 and WB bypass");
        $finish;
    end
endmodule
