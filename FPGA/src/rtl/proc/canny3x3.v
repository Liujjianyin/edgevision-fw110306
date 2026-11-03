`timescale 1ns/1ps
// canny3x3.v -- gradient direction + non-maximum suppression + double
// threshold + one-pass hysteresis (weak edge kept when adjacent to strong).
module canny3x3 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de_i,
    input  wire signed [11:0] gx_i,
    input  wire signed [11:0] gy_i,
    input  wire [11:0] mag_i,
    input  wire [11:0] strong_i,
    input  wire [11:0] weak_i,
    output reg         edge_o,
    output reg         de_o
);
    wire [11:0] agx = gx_i[11] ? (~gx_i + 12'd1) : gx_i;
    wire [11:0] agy = gy_i[11] ? (~gy_i + 12'd1) : gy_i;

    // 0: horizontal, 1: vertical, 2: 45deg, 3: 135deg
    wire [15:0] agx5  = {4'b0, agx} + {2'b0, agx, 2'b0};
    wire [15:0] agy5  = {4'b0, agy} + {2'b0, agy, 2'b0};
    wire [15:0] agx12 = {4'b0, agx, 3'b0} + {4'b0, agx, 2'b0};
    wire [15:0] agy12 = {4'b0, agy, 3'b0} + {4'b0, agy, 2'b0};
    wire [1:0] dir = (agy12 < agx5) ? 2'd0 :
                     (agx12 < agy5) ? 2'd1 :
                     ((gx_i[11] ^ gy_i[11]) ? 2'd3 : 2'd2);

    wire [13:0] pack = {dir, mag_i};
    wire       w_de;
    wire [13:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;

    win3x3 #(.DW(14), .W(1920), .H(1080), .AW(11)) u_win (
        .clk(clk), .rst_n(rst_n),
        .de_i(de_i), .din(pack), .de_o(w_de),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22)
    );

    wire [11:0] c = p11[11:0];
    wire [1:0]  d = p11[13:12];

    reg [11:0] n1, n2;
    always @(*) begin
        case (d)
            2'd0: begin n1 = p10[11:0]; n2 = p12[11:0]; end
            2'd1: begin n1 = p01[11:0]; n2 = p21[11:0]; end
            2'd2: begin n1 = p02[11:0]; n2 = p20[11:0]; end
            default: begin n1 = p00[11:0]; n2 = p22[11:0]; end
        endcase
    end

    wire nms = ((c > n1) && (c >= n2)) || ((c >= n1) && (c > n2));
    wire is_strong = nms && (c >= strong_i);
    wire is_weak   = nms && (c >= weak_i);
    wire adj_strong = (p10[11:0] >= strong_i) || (p12[11:0] >= strong_i) ||
                      (p01[11:0] >= strong_i) || (p21[11:0] >= strong_i);

    wire canny_e = is_strong || (is_weak && adj_strong);

    always @(posedge clk) begin
        edge_o <= canny_e;
        de_o   <= w_de;
    end
endmodule






