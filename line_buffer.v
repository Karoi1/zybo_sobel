`timescale 1ns / 1ps


module line_buffer(
    clk,
    rst_n,
    data_in,
    valid_in,
    data_out,
    valid_out
);
    input clk;
    input rst_n;
    input [31:0] data_in;
    input valid_in;
    output [31:0] data_out;
    output valid_out;
    
    parameter width = 32;
    parameter depth = 160;
    
    reg [width-1:0] mem [0:depth-1];
    reg [$clog2(depth):0] wr_ptr;
    reg [$clog2(depth+1):0] valid_cnt;
    reg valid_out_reg;
    
    always@(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            valid_cnt <= 0;
            valid_out_reg <= 0;
        end
        else begin
            if (valid_in) begin
                mem[wr_ptr] <= data_in;
                wr_ptr <= (wr_ptr == depth - 1) ? 0 : wr_ptr+1'b1;
            end
            if (valid_in && valid_cnt < depth) begin
                valid_cnt <= valid_cnt + 1'b1;
            end
        end
        valid_out_reg <= ((valid_cnt == depth) && valid_in);
    end
    assign data_out = mem[wr_ptr];
    assign valid_out = (valid_cnt == depth);

endmodule
