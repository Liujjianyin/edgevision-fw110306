`timescale 1ns/1ps
//=============================================================================
// gauss5x5.v -- separable 5x5 gaussian, one pixel per clock
//
// Kernel [1 4 6 4 1] / 16 applied horizontally then vertically, which is the
// classic approximation of a gaussian with sigma ~ 1.2.
//
// Why this instead of the 3x3 median that was there before: the median removes
// speckle but preserves the staircase structure of the original pixels, so the
// contour stays jagged. A 5x5 gaussian rounds the iso-lines, and that is what
// makes the edge look smooth. Measured offline (4x zoom) the 5x5 version gives
// visibly cleaner, continuous contours than the median.
//
// Storage: 4 line buffers of W bytes (960 -> ~4 RAM10 blocks).
//
//   row0 闁冲厜鍋撻柍?//   row1  闁?  horizontal 5-tap per row, then vertical 5-tap
//   row2  闁?  -> centre pixel of the 5x5, delayed by 2 lines
//   row3  闁?//   row4 闁冲厜鍋撻柍?//=============================================================================
module gauss5x5 #(
    parameter integer W  = 960,
    parameter integer AW = 10
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de_i,          // data enable, high for each valid pixel
    input  wire [7:0]  din,
    output wire        de_o,
    output wire [7:0]  dout
);

    // ------------------------------------------------------------------
    // 4 line buffers: r0=oldest ... r4=newest, r4+din is the newest row
    // ------------------------------------------------------------------
    reg [7:0] lb0 [0:W-1];
    reg [7:0] lb1 [0:W-1];
    reg [7:0] lb2 [0:W-1];
    reg [7:0] lb3 [0:W-1];

    reg [AW-1:0] x;                    // column counter, reset by the de gap
    // Deterministic start. On hardware the block RAM powers up cleared, but in
    // simulation the line buffers are X until the first pass writes them, and
    // those X values propagate into the gradient and the edge map.
    integer ii;
    initial begin
        for (ii = 0; ii < W; ii = ii + 1) begin
            lb0[ii] = 8'd0;
            lb1[ii] = 8'd0;
            lb2[ii] = 8'd0;
            lb3[ii] = 8'd0;
        end
    end
    wire [7:0] r0 = lb0[x];
    wire [7:0] r1 = lb1[x];
    wire [7:0] r2 = lb2[x];
    wire [7:0] r3 = lb3[x];
    wire [7:0] r4 = din;

    always @(posedge clk) begin
        if (de_i) begin
            lb0[x] <= lb1[x];
            lb1[x] <= lb2[x];
            lb2[x] <= lb3[x];
            lb3[x] <= din;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      x <= {AW{1'b0}};
        else if (!de_i)  x <= {AW{1'b0}};
        else if (x == W-1) x <= {AW{1'b0}};
        else             x <= x + 1'b1;
    end

    // ------------------------------------------------------------------
    // horizontal 5-tap on each of the 5 rows
    // the taps are kept in 5-deep shift registers of every row
    // ------------------------------------------------------------------
    reg [7:0] h0a,h0b,h0c,h0d;
    reg [7:0] h1a,h1b,h1c,h1d;
    reg [7:0] h2a,h2b,h2c,h2d;
    reg [7:0] h3a,h3b,h3c,h3d;
    reg [7:0] h4a,h4b,h4c,h4d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h0a<=8'd0; h0b<=8'd0; h0c<=8'd0; h0d<=8'd0;
            h1a<=8'd0; h1b<=8'd0; h1c<=8'd0; h1d<=8'd0;
            h2a<=8'd0; h2b<=8'd0; h2c<=8'd0; h2d<=8'd0;
            h3a<=8'd0; h3b<=8'd0; h3c<=8'd0; h3d<=8'd0;
            h4a<=8'd0; h4b<=8'd0; h4c<=8'd0; h4d<=8'd0;
        end else if (de_i) begin
            h0a<=r0; h0b<=h0a; h0c<=h0b; h0d<=h0c;
            h1a<=r1; h1b<=h1a; h1c<=h1b; h1d<=h1c;
            h2a<=r2; h2b<=h2a; h2c<=h2b; h2d<=h2c;
            h3a<=r3; h3b<=h3a; h3c<=h3b; h3d<=h3c;
            h4a<=r4; h4b<=h4a; h4c<=h4b; h4d<=h4c;
        end
    end

    // [1 4 6 4 1] = (a + 4b + 6c + 4d + e)  -> 12 bit
    function [11:0] hsum(input [7:0] a, b, c, d, e);
        reg [11:0] s;
        begin
            s = {4'd0, a} + {4'd0, e}
              + {2'd0, b, 2'd0} + {2'd0, d, 2'd0}          // 4b, 4d
              + {2'd0, c, 2'd0} + {3'd0, c, 1'b0};         // 6c = 4c + 2c
            hsum = s;
        end
    endfunction

    wire [11:0] s0 = hsum(h0d, h0c, h0b, h0a, r0);
    wire [11:0] s1 = hsum(h1d, h1c, h1b, h1a, r1);
    wire [11:0] s2 = hsum(h2d, h2c, h2b, h2a, r2);
    wire [11:0] s3 = hsum(h3d, h3c, h3b, h3a, r3);
    wire [11:0] s4 = hsum(h4d, h4c, h4b, h4a, r4);

    // ------------------------------------------------------------------
    // vertical 5-tap, total weight 256 -> shift right by 8
    // ------------------------------------------------------------------
    wire [15:0] vsum = {4'd0, s0} + {4'd0, s4}
                     + {2'd0, s1, 2'd0} + {2'd0, s3, 2'd0}
                     + {2'd0, s2, 2'd0} + {3'd0, s2, 1'b0};   // 6 * s2

    assign dout = vsum[15:8];

    // ------------------------------------------------------------------
    // data enable: the centre of the window is valid 2 lines + 2 pixels late
    // ------------------------------------------------------------------
    reg d1, d2, d3, d4;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin d1<=1'b0; d2<=1'b0; d3<=1'b0; d4<=1'b0; end
        else        begin d1<=de_i; d2<=d1; d3<=d2; d4<=d3; end
    end
    assign de_o = d4;

endmodule
