`timescale 1ns/1ps
//=============================================================================
// sobel3x3.v -- 3x3 Sobel gradient, 1 window/clock, 3-stage pipeline
//
//   Gx = (p02 + 2*p12 + p22) - (p00 + 2*p10 + p20)      right - left
//   Gy = (p20 + 2*p21 + p22) - (p00 + 2*p01 + p02)      bottom - top
//   G  = |Gx| + |Gy|                  (no square, no square-root)
//
// * x2 is a left shift; no multipliers, no dividers.
// * Threshold compare is a parameter (synthesis-time); a runtime port is
//   provided too so the on-board key / UART can change it live.
//=============================================================================
module sobel3x3 #(
    parameter [11:0] THRESH = 12'd64
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        de_i,
    input  wire [7:0]  p00, p01, p02,
    input  wire [7:0]  p10, p11, p12,
    input  wire [7:0]  p20, p21, p22,

    input  wire [11:0] thresh_i,      // runtime threshold (ignored if 0 -> use THRESH)
    input  wire        thresh_en,

    output reg         de_o,
    output reg  [11:0] gx_o,          // signed two's complement
    output reg  [11:0] gy_o,          // signed two's complement
    output reg  [11:0] gmag_o,        // |Gx| + |Gy|  (0..2040)
    output reg  [7:0]  gsat_o,        // magnitude saturated to 8 bits
    output reg         edge_o         // thresholded binary edge
);

    // ---------------- stage 1: column sums (x2 via shift) ----------------
    wire [10:0] pos_x_w = {3'd0, p02} + {2'd0, p12, 1'b0} + {3'd0, p22};
    wire [10:0] neg_x_w = {3'd0, p00} + {2'd0, p10, 1'b0} + {3'd0, p20};
    wire [10:0] pos_y_w = {3'd0, p20} + {2'd0, p21, 1'b0} + {3'd0, p22};
    wire [10:0] neg_y_w = {3'd0, p00} + {2'd0, p01, 1'b0} + {3'd0, p02};

    reg [10:0] pos_x, neg_x, pos_y, neg_y;
    reg        de_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pos_x <= 11'd0; neg_x <= 11'd0;
            pos_y <= 11'd0; neg_y <= 11'd0;
            de_s1 <= 1'b0;
        end else begin
            pos_x <= pos_x_w;
            neg_x <= neg_x_w;
            pos_y <= pos_y_w;
            neg_y <= neg_y_w;
            de_s1 <= de_i;
        end
    end

    // ---------------- stage 2: differences, |.|, sum ---------------------
    wire        gx_ge  = (pos_x >= neg_x);
    wire [10:0] gx_mag = gx_ge ? (pos_x - neg_x) : (neg_x - pos_x);
    wire [10:0] gx_sgn = gx_ge ? (pos_x - neg_x) : ~(neg_x - pos_x) + 11'd1;

    wire        gy_ge  = (pos_y >= neg_y);
    wire [10:0] gy_mag = gy_ge ? (pos_y - neg_y) : (neg_y - pos_y);
    wire [10:0] gy_sgn = gy_ge ? (pos_y - neg_y) : ~(neg_y - pos_y) + 11'd1;

    reg [11:0] gx_s2, gy_s2, mag_s2;
    reg        de_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gx_s2  <= 12'd0;
            gy_s2  <= 12'd0;
            mag_s2 <= 12'd0;
            de_s2  <= 1'b0;
        end else begin
            gx_s2  <= {{1{gx_sgn[10]}}, gx_sgn};
            gy_s2  <= {{1{gy_sgn[10]}}, gy_sgn};
            mag_s2 <= {1'b0, gx_mag} + {1'b0, gy_mag};
            de_s2  <= de_s1;
        end
    end

    // ---------------- stage 3: saturation + threshold -------------------
    wire [11:0] thr = thresh_en ? thresh_i : THRESH;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_o   <= 1'b0;
            gx_o   <= 12'd0;
            gy_o   <= 12'd0;
            gmag_o <= 12'd0;
            gsat_o <= 8'd0;
            edge_o <= 1'b0;
        end else begin
            de_o   <= de_s2;
            gx_o   <= gx_s2;
            gy_o   <= gy_s2;
            gmag_o <= mag_s2;
            gsat_o <= (mag_s2 > 12'd255) ? 8'd255 : mag_s2[7:0];
            edge_o <= (mag_s2 >= thr);
        end
    end

endmodule
