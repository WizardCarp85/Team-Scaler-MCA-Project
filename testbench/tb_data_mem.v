// Self-checking testbench for data_mem.v (issue #17).
// Run from the repository root:
//   iverilog -g2012 -o simulation/tb_data_mem.vvp testbench/tb_data_mem.v rtl/stages/data_mem.v
//   vvp simulation/tb_data_mem.vvp
`timescale 1ns/1ps
module tb_data_mem;

    reg         clk = 0, mem_read = 0, mem_write = 0;
    reg  [31:0] addr = 0, write_data = 0;
    wire [31:0] read_data;
    wire        access_fault;
    integer errors = 0;

    data_mem #(.DEPTH_WORDS(16)) dut (.clk(clk), .mem_read(mem_read), .mem_write(mem_write),
        .addr(addr), .write_data(write_data), .read_data(read_data), .access_fault(access_fault));

    always #5 clk = ~clk;

    task check(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL: %0s got=%h expected=%h", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    // Store: drive on negedge, written at the next posedge.
    task sw(input [31:0] a, input [31:0] d);
        begin
            @(negedge clk);
            addr = a; write_data = d; mem_write = 1; mem_read = 0;
            @(negedge clk);
            mem_write = 0;
        end
    endtask

    // Load: combinational read.
    task lw(input [31:0] a);
        begin
            addr = a; mem_read = 1; mem_write = 0; #1;
        end
    endtask

    initial begin
        $dumpfile("simulation/tb_data_mem.vcd");
        $dumpvars(0, tb_data_mem);

        // Initial contents are zero.
        lw(32'h0); check("init word0", read_data, 0);

        // Write then read several addresses; address-to-word mapping.
        sw(32'h0,  32'hAAAA_0000);
        sw(32'h4,  32'hBBBB_0004);
        sw(32'h3C, 32'hCCCC_003C);   // last word (index 15)
        lw(32'h0);  check("read 0x0",  read_data, 32'hAAAA_0000);
        lw(32'h4);  check("read 0x4",  read_data, 32'hBBBB_0004);
        lw(32'h3C); check("read 0x3C", read_data, 32'hCCCC_003C);
        lw(32'h8);  check("untouched 0x8", read_data, 0);
        check("no fault valid", access_fault, 0);

        // Overwrite changes only the selected word.
        sw(32'h4, 32'h1234_5678);
        lw(32'h0); check("neighbour 0x0 intact", read_data, 32'hAAAA_0000);
        lw(32'h4); check("overwrite 0x4", read_data, 32'h1234_5678);

        // Disabled write: mem_write low, data/address change, nothing stored.
        @(negedge clk); addr = 32'h8; write_data = 32'hDEAD_BEEF; mem_write = 0;
        @(negedge clk);
        lw(32'h8); check("write disabled", read_data, 0);

        // Read disabled returns 0.
        addr = 32'h0; mem_read = 0; #1;
        check("read disabled", read_data, 0);
        check("no fault idle", access_fault, 0);

        // Write not visible before the clock edge (edge-triggered).
        @(negedge clk); addr = 32'hC; write_data = 32'h5555_5555; mem_write = 1; mem_read = 1; #1;
        check("no write before edge", read_data, 0);
        @(negedge clk); mem_write = 0; #1;
        check("write after edge", read_data, 32'h5555_5555);

        // Misaligned read: returns 0, flags fault.
        lw(32'h1); check("misaligned read data", read_data, 0); check("misaligned read fault", access_fault, 1);
        lw(32'h6); check("misaligned 0x6 data", read_data, 0);  check("misaligned 0x6 fault", access_fault, 1);

        // Misaligned write: ignored, no word changes.
        sw(32'h5, 32'hBAD0_BAD0);
        mem_read = 0; mem_write = 0;
        lw(32'h4); check("0x4 after misaligned sw", read_data, 32'h1234_5678);
        lw(32'h8); check("0x8 after misaligned sw", read_data, 0);

        // Out of range (depth 16 words = 0x40 bytes).
        lw(32'h40);        check("oob read data", read_data, 0); check("oob read fault", access_fault, 1);
        lw(32'h8000_0000); check("far oob read", read_data, 0);  check("far oob fault", access_fault, 1);
        sw(32'h40, 32'hBAD0_BAD0);   // would alias to word 0 if wrongly truncated
        lw(32'h0); check("oob write did not alias", read_data, 32'hAAAA_0000);
        check("no fault valid again", access_fault, 0);

        if (errors == 0) $display("PASS: tb_data_mem");
        else             $display("FAILED: %0d error(s)", errors);
        $finish;
    end

endmodule
