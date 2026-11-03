`timescale 1ns/1ps
// RGB -> gray -> Sobel -> split: left = colour original,
// right = colour original + red edges of the SAME 960-wide crop.
// Also: AEC, ROI bbox, circle/rect OSD.
module proc_split (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_de,
    input  wire        i_hs,
    input  wire        i_vs,
    input  wire [7:0]  i_r,
    input  wire [7:0]  i_g,
    input  wire [7:0]  i_b,
    input  wire [11:0] thresh_i,
  input  wire        mode_col_i,
  input  wire        algo_canny_i, // 1 = Canny edges on the main picture, 0 = Sobel   // 1 = colour picture with red edges
    output wire [7:0]  o_r,
    output wire [7:0]  o_g,
    output wire [7:0]  o_b,
    output wire        o_de,
    output wire        o_hs,
    output wire        o_vs
);
    // the vendor top's hdmi_tx_rdata is actually B and hdmi_tx_bdata is R
    // (debayer output order is b,g,r), so swap R/B at the input
    wire [8:0] ysum = {1'b0, i_b[7:2]} + {1'b0, i_g[7:1]}
                    + {2'b0, i_g[7:3]} + {2'b0, i_r[7:3]};
    wire [7:0] gray = ysum[8] ? 8'hFF : ysum[7:0];

    wire        w_de;
    wire [7:0]  p00, p01, p02, p10, p11, p12, p20, p21, p22;

    win3x3 #(.DW(8), .W(1920), .H(1080), .AW(11)) u_win (
        .clk(clk), .rst_n(rst_n),
        .de_i(i_de), .din(gray),
        .de_o(w_de),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22)
    );

    // ---- 3x3 median before Sobel (advanced item 1) ----
    wire        med_de;
    wire [7:0]  med_gray;
    median3x3 u_med (
        .clk(clk), .rst_n(rst_n),
        .de_i(w_de),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .de_o(med_de), .med_o(med_gray), .min_o(), .max_o()
    );

    wire        q_de;
    wire [7:0]  q00, q01, q02, q10, q11, q12, q20, q21, q22;
    win3x3 #(.DW(8), .W(1920), .H(1080), .AW(11)) u_win2 (
        .clk(clk), .rst_n(rst_n),
        .de_i(med_de), .din(med_gray),
        .de_o(q_de),
        .p00(q00), .p01(q01), .p02(q02),
        .p10(q10), .p11(q11), .p12(q12),
        .p20(q20), .p21(q21), .p22(q22)
    );

    wire        s_de;
    wire [11:0] s_gx, s_gy, s_mag;
    wire [7:0]  s_sat;
    wire        s_edge;

    reg [11:0] thresh_eff = 12'd96;

    sobel3x3 #(.THRESH(96)) u_sobel (
        .clk(clk), .rst_n(rst_n),
        .de_i(q_de),
    .p00(q00), .p01(q01), .p02(q02),
    .p10(q10), .p11(q11), .p12(q12),
    .p20(q20), .p21(q21), .p22(q22),
        .thresh_i(thresh_i), .thresh_en(1'b1),
        .de_o(s_de), .gx_o(s_gx), .gy_o(s_gy), .gmag_o(s_mag),
        .gsat_o(s_sat), .edge_o(s_edge)
    );

    // Canny: direction + NMS + double threshold + one-pass hysteresis
    wire [11:0] cs = {thresh_i[7:0], 1'b0};
    wire [11:0] canny_strong = cs;
    wire [11:0] canny_weak = (canny_strong >> 1) + (canny_strong >> 3);
    wire canny_edge, canny_de;
    canny3x3 u_canny (
        .clk(clk), .rst_n(rst_n),
        .de_i(s_de), .gx_i(s_gx), .gy_i(s_gy), .mag_i(s_mag),
        .strong_i(canny_strong), .weak_i(canny_weak),
        .edge_o(canny_edge), .de_o(canny_de)
    );

// ---- edge source for the whole display path ----------------------------
// The Canny result existed but was never connected to anything: every downstream
// stage took e_src_bit straight from the Sobel block. Selecting the source here is
// all that is needed to put Canny on screen.
wire e_src_de  = algo_canny_i ? canny_de   : s_de;
wire e_src_bit = algo_canny_i ? canny_edge : s_edge;


    // x / y coordinates
    reg [11:0] x, y;
    reg        hs_d;
    always @(posedge clk) begin
        hs_d <= i_hs;
        if (i_vs)              y <= 12'd0;
        else if (i_hs & ~hs_d) y <= y + 12'd1;

        if (!i_de) x <= 12'd0;
        else       x <= x + 12'd1;
    end

    // delay coordinates / gray / colour / sync by 5 clocks
    reg [11:0] xd1, xd2, xd3, xd4, xd5;
    reg [11:0] yd1, yd2, yd3, yd4, yd5;
    reg [7:0]  gd1, gd2, gd3, gd4, gd5;
    reg [7:0]  rd1, rd2, rd3, rd4, rd5;
    reg [7:0]  gd1c, gd2c, gd3c, gd4c, gd5c;
    reg [7:0]  bd1, bd2, bd3, bd4, bd5;
    reg        hd1, hd2, hd3, hd4, hd5;
    reg        vd1, vd2, vd3, vd4, vd5;

    always @(posedge clk) begin
        xd1 <= x;    xd2 <= xd1; xd3 <= xd2; xd4 <= xd3; xd5 <= xd4;
        yd1 <= y;    yd2 <= yd1; yd3 <= yd2; yd4 <= yd3; yd5 <= yd4;
        gd1 <= gray; gd2 <= gd1; gd3 <= gd2; gd4 <= gd3; gd5 <= gd4;
        rd1 <= i_b;  rd2 <= rd1; rd3 <= rd2; rd4 <= rd3; rd5 <= rd4;
        gd1c <= i_g; gd2c <= gd1c; gd3c <= gd2c; gd4c <= gd3c; gd5c <= gd4c;
        bd1 <= i_r;  bd2 <= bd1; bd3 <= bd2; bd4 <= bd3; bd5 <= bd4;
        hd1 <= i_hs; hd2 <= hd1; hd3 <= hd2; hd4 <= hd3; hd5 <= hd4;
        vd1 <= i_vs; vd2 <= vd1; vd3 <= vd2; vd4 <= vd3; vd5 <= vd4;
    end

    // colour gamma 0.7 + white balance (lift blue, slight red boost)
    // 2x digital gain before gamma
    wire [7:0] r_in = rd5;
    wire [7:0] g_in = gd5c;
    wire [7:0] b_in = bd5;

    wire [7:0] gr, gg, gb;
    gamma_lut8 u_gr (.clk(clk), .x(r_in),  .y(gr));
    gamma_lut8 u_gg (.clk(clk), .x(g_in),  .y(gg));
    gamma_lut8 u_gb (.clk(clk), .x(b_in),  .y(gb));

    // white balance: suppress the green cast (R 1.19, G 0.875, B 1.125)
    wire [9:0] rw = {1'b0, gr} + {2'b0, gr[7:2]} + {3'b0, gr[7:3]};   // R x1.375
    wire [9:0] gw = {1'b0, gg} - {3'b0, gg[7:3]};               // G x0.875
    wire [9:0] bw = {1'b0, gb} + {4'b0, gb[7:4]};               // B x1.0625
    wire [7:0] r_o = (rw > 10'd255) ? 8'hFF : rw[7:0];
    wire [7:0] b_o = (bw > 10'd255) ? 8'hFF : bw[7:0];
    wire [7:0] g_o = (gw > 10'd255) ? 8'hFF : gw[7:0];

    // saturation boost 2.0x around luma
    function [7:0] sat15;
        input [7:0] c;
        input [7:0] y;
        reg [8:0] d;
        begin
            if (c >= y) begin
                d = {1'b0, c} - {1'b0, y};
                sat15 = ({1'b0, c} + {1'b0, d[8:2]} > 9'd255)
                      ? 8'hFF : (c + d[8:3]);
            end else begin
                d = {1'b0, y} - {1'b0, c};
                sat15 = ({1'b0, d[8:2]} > {1'b0, c})
                      ? 8'd0 : (c - d[8:3]);
            end
        end
    endfunction

    // contrast 1.25 around mid-grey (kills the hazy look)
    function [7:0] contrast;
        input [7:0] c;
        reg [8:0] d;
        begin
            if (c >= 8'd128) begin
                d = {1'b0, c} - 9'd128;
                contrast = ({1'b0, c} + {1'b0, d[8:2]} > 9'd255)
                         ? 8'hFF : (c + d[8:3]);
            end else begin
                d = 9'd128 - {1'b0, c};
                contrast = ({1'b0, d[8:2]} > {1'b0, c})
                         ? 8'd0 : (c - d[8:3]);
            end
        end
    endfunction

    wire [7:0] r_c = contrast(r_o);
    wire [7:0] g_c = contrast(g_o);
    wire [7:0] b_c = contrast(b_o);

    wire [9:0] ysum2 = {2'b0, r_c} + {1'b0, g_c, 1'b0} + {2'b0, b_c};
    wire [7:0] yl    = ysum2[9:2];

    wire [7:0] r_s = sat15(r_c, yl);
    wire [7:0] g_s = sat15(g_c, yl);
    wire [7:0] b_s = sat15(b_c, yl);

    // 960 x {colour 24 + edge 1} line buffer, 2x horizontal downsample
    // The colour store is 960 wide (2x horizontally downsampled). In colour mode the
// whole 1920-wide screen is addressed with xd5[10:1], so every stored pixel is
// shown twice and the picture fills the screen once instead of folding back on
// itself at x=960 (which used to paint two copies side by side).
wire [9:0] raddr = mode_col_i ? xd5[10:1]
                             : ((xd5 < 12'd960) ? xd5[9:0] : (xd5[9:0] - 10'd960));
    wire [24:0] lb_dout;

    proc_dpram #(.DW(25), .AW(10)) u_lb (
        .clk(clk), .we(e_src_de && (xd5[0] == 1'b0)),
        .din({e_src_bit, r_s, g_s, b_s}), .waddr(xd5[10:1]),
        .raddr(raddr), .dout(lb_dout)
    );

    // AEC for the edge threshold
    reg        vs_d2;
    always @(posedge clk) vs_d2 <= i_vs;
    wire fend = i_vs & ~vs_d2;

    reg [19:0] asum;
    reg [12:0] acnt;
    reg [2:0]  agc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            asum <= 20'd0; acnt <= 13'd0; agc <= 3'd0;
            thresh_eff <= 12'd96;
        end else if (fend) begin
            asum <= 20'd0;
            acnt <= 13'd0;
            if (asum[19:12] > 8'd180) begin
                agc <= 3'd2; thresh_eff <= 12'd96;
            end else if (asum[19:12] > 8'd90) begin
                agc <= 3'd1; thresh_eff <= 12'd96;
            end else if (asum[19:12] > 8'd45) begin
                agc <= 3'd3; thresh_eff <= 12'd64;
            end else begin
                agc <= 3'd4; thresh_eff <= 12'd48;
            end
        end else if (e_src_de && (acnt < 13'd4096)) begin
            asum <= asum + {12'd0, gd5};
            acnt <= acnt + 13'd1;
        end
    end

    // ROI bbox of edges
    wire roi = (xd5 >= 12'd200) && (xd5 < 12'd1720)
            && (yd5 >= 12'd200) && (yd5 < 12'd880);

    reg [11:0] minx, maxx, miny, maxy;
    reg [23:0] ecnt;
    reg [11:0] l_minx, l_maxx, l_miny, l_maxy;
    reg [23:0] l_ecnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            minx <= 12'hFFF; maxx <= 12'd0; miny <= 12'hFFF; maxy <= 12'd0;
            ecnt <= 24'd0;
            l_minx <= 12'hFFF; l_maxx <= 12'd0; l_miny <= 12'hFFF; l_maxy <= 12'd0;
            l_ecnt <= 24'd0;
        end else if (fend) begin
            l_minx <= minx; l_maxx <= maxx; l_miny <= miny; l_maxy <= maxy;
            l_ecnt <= ecnt;
            minx <= 12'hFFF; maxx <= 12'd0; miny <= 12'hFFF; maxy <= 12'd0;
            ecnt <= 24'd0;
        end else if (e_src_de && e_src_bit && roi) begin
            if (xd5 < minx) minx <= xd5;
            if (xd5 > maxx) maxx <= xd5;
            if (yd5 < miny) miny <= yd5;
            if (yd5 > maxy) maxy <= yd5;
            ecnt <= ecnt + 24'd1;
        end
    end

    wire [11:0] bw = (l_maxx >= l_minx) ? (l_maxx - l_minx + 12'd1) : 12'd0;
    wire [11:0] bh = (l_maxy >= l_miny) ? (l_maxy - l_miny + 12'd1) : 12'd0;
    wire [23:0] box = bw * bh;
    wire [23:0] e4  = l_ecnt << 2;
    wire [23:0] e2  = l_ecnt << 1;

    wire shape_valid = (l_ecnt > 24'd100) && (bw > 12'd20) && (bh > 12'd20)
                    && (bw < 12'd540) && (bh < 12'd660);
    wire circle = shape_valid
               && ({bw, 2'b00} > (bh + {bh, 1'b0}))
               && ({bh, 2'b00} > (bw + {bw, 1'b0}))
               && (e4 > box) && (e2 < box);

    // pad by 4 px for a tighter fit
    wire [11:0] bx0 = (l_minx > 12'd4) ? (l_minx - 12'd4) : 12'd0;
    wire [11:0] bx1 = (l_maxx < 12'd1915) ? (l_maxx + 12'd4) : 12'd1919;
    wire [11:0] by0 = (l_miny > 12'd4) ? (l_miny - 12'd4) : 12'd0;
    wire [11:0] by1 = (l_maxy < 12'd1075) ? (l_maxy + 12'd4) : 12'd1079;

    wire in_box = (xd5 >= bx0) && (xd5 <= bx1)
               && (yd5 >= by0) && (yd5 <= by1);
    wire border = in_box && ((xd5 < bx0 + 12'd4) || (xd5 > bx1 - 12'd4)
                          || (yd5 < by0 + 12'd4) || (yd5 > by1 - 12'd4));
    wire topbar = in_box && (yd5 < by0 + 12'd10);

    wire in_roi = (xd5 >= 12'd200) && (xd5 < 12'd1720)
               && (yd5 >= 12'd200) && (yd5 < 12'd880);
    wire roi_border = in_roi && ((xd5 < 12'd204) || (xd5 >= 12'd1716)
                              || (yd5 < 12'd204) || (yd5 >= 12'd876));

    // split: left = grey original, right = colour + red edges
    wire [7:0] lb_r = lb_dout[23:16];
    wire [7:0] lb_g = lb_dout[15:8];
    wire [7:0] lb_b = lb_dout[7:0];

    wire [8:0] gsum = {1'b0, lb_r[7:2]} + {1'b0, lb_g[7:1]}
                    + {2'b0, lb_g[7:3]} + {2'b0, lb_b[7:3]};
    wire [7:0] lb_gray = gsum[8] ? 8'hFF : gsum[7:0];

    // restored: full-screen 1920x1080 colour + red edges
    // 2-line delay of the edge bit so red edges sit exactly on the colour
    reg hs_e_d;
    always @(posedge clk) hs_e_d <= hd5;
    wire hs_e_rise = hd5 & ~hs_e_d;

    reg wr_bank_e;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_bank_e <= 1'b0;
        else if (hs_e_rise) wr_bank_e <= ~wr_bank_e;
    end

    wire [10:0] e_waddr = (xd5[10:0] >= 11'd3) ? (xd5[10:0] - 11'd3) : 11'd0;

    wire ed0, ed1r, ed1;
    wire ed2r, ed2b, ed2;
    wire ed3r, ed3b, ed3;
    wire ed4r, ed4b, ed4;
    wire ed5r, ed5b, ed5;
    wire ed6r, ed6b, ed6;

    proc_dpram #(.DW(1), .AW(11)) u_e0 (
        .clk(clk), .we(e_src_de && ~wr_bank_e), .din(e_src_bit),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed0)
    );
    proc_dpram #(.DW(1), .AW(11)) u_e1 (
        .clk(clk), .we(e_src_de && wr_bank_e), .din(e_src_bit),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed1r)
    );
    assign ed1 = wr_bank_e ? ed0 : ed1r;

    proc_dpram #(.DW(1), .AW(11)) u_e2 (
        .clk(clk), .we(e_src_de && ~wr_bank_e), .din(ed1),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed2r)
    );
    proc_dpram #(.DW(1), .AW(11)) u_e3 (
        .clk(clk), .we(e_src_de && wr_bank_e), .din(ed1),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed2b)
    );
    assign ed2 = wr_bank_e ? ed2r : ed2b;

    proc_dpram #(.DW(1), .AW(11)) u_e4 (
        .clk(clk), .we(e_src_de && ~wr_bank_e), .din(ed2),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed3r)
    );
    proc_dpram #(.DW(1), .AW(11)) u_e5 (
        .clk(clk), .we(e_src_de && wr_bank_e), .din(ed2),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed3b)
    );
    assign ed3 = wr_bank_e ? ed3r : ed3b;

    proc_dpram #(.DW(1), .AW(11)) u_e6 (
        .clk(clk), .we(e_src_de && ~wr_bank_e), .din(ed3),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed4r)
    );
    proc_dpram #(.DW(1), .AW(11)) u_e7 (
        .clk(clk), .we(e_src_de && wr_bank_e), .din(ed3),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed4b)
    );
    assign ed4 = wr_bank_e ? ed4r : ed4b;

    proc_dpram #(.DW(1), .AW(11)) u_e8 (
        .clk(clk), .we(e_src_de && ~wr_bank_e), .din(ed4),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed5r)
    );
    proc_dpram #(.DW(1), .AW(11)) u_e9 (
        .clk(clk), .we(e_src_de && wr_bank_e), .din(ed4),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed5b)
    );
    assign ed5 = wr_bank_e ? ed5r : ed5b;

    proc_dpram #(.DW(1), .AW(11)) u_e10 (
        .clk(clk), .we(e_src_de && ~wr_bank_e), .din(ed5),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed6r)
    );
    proc_dpram #(.DW(1), .AW(11)) u_e11 (
        .clk(clk), .we(e_src_de && wr_bank_e), .din(ed5),
        .waddr(e_waddr), .raddr(xd5[10:0]), .dout(ed6b)
    );
    assign ed6 = wr_bank_e ? ed6r : ed6b;

    // colour and edges come from the same line buffer write, so they are
// aligned by construction - no extra delay line is needed
// hide edges where the pixel is a blown-out highlight, otherwise the red
// fills the whole specular blob on the jewellery instead of its outline
wire specular = (lb_r > 8'd215) && (lb_g > 8'd215) && (lb_b > 8'd215);
wire edge_show = ed4 && !specular;

wire [23:0] full_col  = mode_col_i
                        ? (edge_show ? 24'hFF0000 : {lb_r, lb_g, lb_b})
                        : (ed4 ? 24'hFFFFFF : 24'h000000);
    wire [23:0] full_col2 = full_col;


    // ---- 320x180 grayscale PiP in the top-right corner ----
    reg vd5_d;
    always @(posedge clk) vd5_d <= vd5;
    wire vd5_rise = vd5 & ~vd5_d;

    reg [2:0] pip_xm;
    always @(posedge clk) begin
        if (!s_de) pip_xm <= 3'd0;
        else if (pip_xm == 3'd5) pip_xm <= 3'd0;
        else pip_xm <= pip_xm + 3'd1;
    end

    reg [2:0] pip_ym;
    always @(posedge clk) begin
        if (vd5_rise) pip_ym <= 3'd0;
        else if (hs_e_rise) begin
            if (pip_ym == 3'd5) pip_ym <= 3'd0;
            else pip_ym <= pip_ym + 3'd1;
        end
    end

    reg [8:0] pip_wx;
    reg [7:0] pip_wy;
    always @(posedge clk) begin
        if (!rst_n) begin
            pip_wx <= 9'd0;
            pip_wy <= 8'd0;
        end else begin
            if (!s_de) pip_wx <= 9'd0;
            else if (pip_xm == 3'd0)
                pip_wx <= (pip_wx == 9'd319) ? 9'd0 : pip_wx + 9'd1;

            if (vd5_rise) pip_wy <= 8'd0;
            else if (hs_e_rise && (pip_ym == 3'd0))
                pip_wy <= (pip_wy == 8'd179) ? 8'd0 : pip_wy + 8'd1;
        end
    end

    wire pip_we = e_src_de && (pip_xm == 3'd0) && (pip_ym == 3'd0);
    wire [16:0] pip_waddr = ({8'b0, pip_wy} << 8) + ({8'b0, pip_wy} << 6)
                          + {8'b0, pip_wx};

    reg [7:0] pip_din_r;
    always @(posedge clk) if (pip_we) pip_din_r <= gd5;

    wire pip_in = (xd5 >= 12'd1560) && (xd5 < 12'd1880) &&
                  (yd5 >= 12'd40)   && (yd5 < 12'd220);
    wire [10:0] pip_rx = xd5[10:0] - 11'd1560;
    wire [10:0] pip_ry = yd5[10:0] - 11'd40;
    wire [16:0] pip_raddr = pip_in
        ? (({6'b0, pip_ry} << 8) + ({6'b0, pip_ry} << 6) + {6'b0, pip_rx})
        : 17'd0;

    reg [16:0] pip_waddr_r, pip_raddr_r;
    reg        pip_we_r, pip_in_r1, pip_in_r2;
    reg [23:0] full_col_r1, full_col_r2;
    reg        s_de_r1, s_de_r2, hd5_r1, hd5_r2, vd5_r1, vd5_r2;
    reg [10:0] xd5_r1, xd5_r2, yd5_r1, yd5_r2;

    always @(posedge clk) begin
        pip_waddr_r <= pip_waddr;
        pip_raddr_r <= pip_raddr;
        pip_we_r    <= pip_we;
        pip_in_r1   <= pip_in;
        pip_in_r2   <= pip_in_r1;
        full_col_r1 <= full_col2;
        full_col_r2 <= full_col_r1;
        s_de_r1 <= s_de; s_de_r2 <= s_de_r1;
        hd5_r1  <= hd5;  hd5_r2  <= hd5_r1;
        vd5_r1  <= vd5;  vd5_r2  <= vd5_r1;
        xd5_r1  <= xd5;  xd5_r2  <= xd5_r1;
        yd5_r1  <= yd5;  yd5_r2  <= yd5_r1;
    end

    wire [7:0] pip_gray;
    proc_dpram #(.DW(8), .AW(16)) u_pip (
        .clk(clk), .we(pip_we_r), .din(pip_din_r),
        .waddr(pip_waddr_r), .raddr(pip_raddr_r), .dout(pip_gray)
    );

    wire pip_border = pip_in &&
        ((xd5 < 12'd1562) || (xd5 >= 12'd1878) ||
         (yd5 < 12'd42)   || (yd5 >= 12'd218));

    wire [23:0] pip_col  = pip_border ? 24'hFFFFFF
                          : {pip_gray, pip_gray, pip_gray};
    wire [23:0] disp_col = pip_in ? pip_col : full_col;

    // 1-D unsharp: 2*center - average(left,right)
    function [7:0] sharp1;
        input [7:0] c, l, r;
        reg [8:0] avg;
        reg signed [9:0] d, o;
        begin
            avg = ({1'b0, l} + {1'b0, r}) >> 1;
            d = $signed({1'b0, c}) - $signed({1'b0, avg});
            o = $signed({1'b0, c}) + d;
            sharp1 = (o < 0) ? 8'd0 : (o > 255) ? 8'd255 : o[7:0];
        end
    endfunction

    reg [7:0] sr1, sr2, sg1, sg2, sb1, sb2;
    always @(posedge clk) begin
        sr1 <= disp_col[23:16]; sr2 <= sr1;
        sg1 <= disp_col[15:8];  sg2 <= sg1;
        sb1 <= disp_col[7:0];   sb2 <= sb1;
    end

    reg [23:0] disp_col_r;
    reg o_de_r, o_hs_r, o_vs_r;
    always @(posedge clk) begin
        disp_col_r <= disp_col;
        o_de_r <= s_de;
        o_hs_r <= hd5;
        o_vs_r <= vd5;
    end

    assign o_r  = disp_col_r[23:16];
    assign o_g  = disp_col_r[15:8];
    assign o_b  = disp_col_r[7:0];
    assign o_de = o_de_r;
    assign o_hs = o_hs_r;
    assign o_vs = o_vs_r;
endmodule






































