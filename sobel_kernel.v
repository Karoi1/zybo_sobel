`timescale 1ns / 1ps

module sobel_kernel(
    p00,
    p01,
    p02,
    p10,
    p11,
    p12,
    p20,
    p21,
    p22,
    mag
    );
    input [7:0] p00;
    input [7:0] p01;
    input [7:0] p02;
    input [7:0] p10;
    input [7:0] p11;
    input [7:0] p12;
    input [7:0] p20;
    input [7:0] p21;
    input [7:0] p22;
    output[7:0] mag;
    
    wire signed [10:0] gx, gy;
    wire        [10:0] gx_abs, gy_abs;
    wire        [10:0] mag_raw;
    
    assign gx = (p02 + {p12,1'b0} + p22) - (p00 + {p10,1'b0} + p20);
    assign gy = (p20 + {p21,1'b0} + p22) - (p00 + {p01,1'b0} + p02);
    
    assign gx_abs = gx[10] ? (~gx+1) : gx;
    assign gy_abs = gy[10] ? (~gy+1) : gy;
    
    assign mag_raw = gx_abs+gy_abs;
    assign mag     = (mag_raw > 255) ? 8'd255 : mag_raw[7:0];
    
endmodule
