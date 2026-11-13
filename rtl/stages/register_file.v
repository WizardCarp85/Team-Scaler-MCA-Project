module register_file (
    input  wire        clk,
    input  wire        rst,
    input  wire        write_en,
    input  wire [4:0]  rd,
    input  wire [31:0] write_data,
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
    // x0 has no storage. Reset clears x1-x31 on the rising edge.
    reg [31:0] registers [1:31];
    integer i;
    wire writing = write_en && !rst && rd != 5'd0;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 1; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end else if (writing) begin
            registers[rd] <= write_data;
        end
    end

    // Write-through lets ID/EX sample a matching WB value on the same edge.
    // The bypass is combinational. Only a rising edge updates storage.
    assign rs1_data = rs1 == 0 ? 32'd0 :
                      writing && rs1 == rd ? write_data : registers[rs1];
    assign rs2_data = rs2 == 0 ? 32'd0 :
                      writing && rs2 == rd ? write_data : registers[rs2];
endmodule
