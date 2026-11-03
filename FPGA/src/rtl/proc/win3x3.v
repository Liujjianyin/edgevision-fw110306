`timescale 1ns/1ps
//=============================================================================
// win3x3.v -- 3x3 sliding window from exactly TWO line buffers
//
// Two line buffers of W bytes (BRAM friendly):
//   mem_a : old contents = row y-1   (receives row y as it streams)
//   mem_b : old contents = row y-2   (receives row y-1 one cycle later)
// Because a synchronous read returns the OLD contents, at the moment column k
// of row y is being written we simultaneously obtain column k of row y-1 and
// row y-2. Together with the live pixel that is all three rows of column k.
//
// Three 3-deep column registers then build the window:
//   beat centre column c = k-1, using columns k-2 (left), k-1 (mid), k (right)
//   -> one beat per cycle, 2 cycles after the corresponding input pixel.
//
// Beats per row: W. The beat for centre column W-1 needs column W which never
// arrives, so it is emitted one cycle later (in the blanking gap) with the
// right column replicated -> the input needs >= 1 idle cycle between rows.
//
// Edge replication:
//   left  column  : beat c==0   -> left  = mid
//   right column  : beat c==W-1 -> right = mid
//   top row       : centre row 0 -> top = mid            (row -1 == row 0)
//   bottom row    : centre row H-1 -> one replay pass after the last input
//                   row re-reads mem_a/mem_b with bottom = mid
//=============================================================================
module win3x3 #(
    parameter integer W  = 640,
    parameter integer H  = 480,
    parameter integer AW = 10,
    parameter integer DW = 8
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       de_i,
    input  wire [DW-1:0] din,

    output reg        de_o,
    output reg [DW-1:0]  p00, p01, p02,
    output reg [DW-1:0]  p10, p11, p12,
    output reg [DW-1:0]  p20, p21, p22
);

    localparam integer LASTX = W - 1;

    reg [DW-1:0] mem_a [0:W-1];
    reg [DW-1:0] mem_b [0:W-1];

    // ---------------- control ----------------
    reg        rep;              // replaying the final row
    reg [AW-1:0] col;            // column being read
    reg [AW:0]   row;            // input row index (normal mode)
    reg [2:0]    drain;          // idle cycles inserted before the replay starts

    wire adv = rep ? 1'b1 : de_i;

    // ---------------- pipeline flags (declared before use) ----------------
    reg          adv_d1, rep_d1;
    reg [AW-1:0] col_d1;
    reg [AW:0]   row_d1;
    reg [DW-1:0]    din_d1;

    // ---------------- stage 1: buffer reads ----------------
    reg [DW-1:0] q0, q1;            // row y-1 , row y-2  at column `col`
    always @(posedge clk) begin
        q0 <= mem_a[col];
        q1 <= mem_b[col];
    end

    always @(posedge clk) if (adv && !rep)       mem_a[col] <= din;
    always @(posedge clk) if (adv_d1 && !rep_d1) mem_b[col_d1] <= q0;

    // ---------------- stage 2: column registers (hold k-1 and k-2) ------
    reg [DW-1:0] a2, a1;            // mid row  (row y-1)
    reg [DW-1:0] b2, b1;            // top row  (row y-2)
    reg [DW-1:0] c2, c1;            // bot row  (row y)

    // =====================================================================
    // counters / replay
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col   <= {AW{1'b0}};
            row   <= {(AW+1){1'b0}};
            rep   <= 1'b0;
            drain <= 3'd0;
        end else if (!rep) begin
            if (drain != 3'd0) begin
                // let the last row's tail beat and pipeline drain before replay
                drain <= drain - 3'd1;
                if (drain == 3'd1) rep <= 1'b1;
            end else if (de_i) begin
                if (col == LASTX[AW-1:0]) begin
                    col <= {AW{1'b0}};
                    // wrap to the next frame; the old drain/replay path froze
                    // the window on the last row and the image never updated
                    row <= (row == H - 1) ? {(AW+1){1'b0}} : row + 1'b1;
                end else begin
                    col <= col + 1'b1;
                end
            end
        end else begin
            if (col == LASTX[AW-1:0]) rep <= 1'b0;     // replay finished
            else                     col <= col + 1'b1;
        end
    end

    // =====================================================================
    // pipeline registers
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adv_d1 <= 1'b0; rep_d1 <= 1'b0;
            col_d1 <= {AW{1'b0}}; row_d1 <= {(AW+1){1'b0}};
            din_d1 <= 8'd0;
            a2 <= 8'd0; a1 <= 8'd0;
            b2 <= 8'd0; b1 <= 8'd0;
            c2 <= 8'd0; c1 <= 8'd0;
        end else begin
            adv_d1 <= adv;
            rep_d1 <= rep;
            col_d1 <= col;
            row_d1 <= row;
            din_d1 <= din;

            if (adv) begin
                a2 <= a1; a1 <= q0;
                b2 <= b1; b1 <= q1;
                c2 <= c1; c1 <= rep ? q0 : din_d1;
            end
        end
    end

    // =====================================================================
    // beat generation
    // =====================================================================
    // regular beat: column k >= 1, and centre row >= 0
    wire col_ok   = (col_d1 != {AW{1'b0}});
    wire row_ok   = rep_d1 || (row_d1 != 0);
    wire beat_reg = adv_d1 && col_ok && row_ok;

    // tail beat: the window for centre column W-1 has no column W, so the right
    // column is replicated. Its values are captured at the LAST regular beat
    // (when column W-1 is still the "newest" value) and emitted one cycle later.
    reg  tail;
    reg [DW-1:0] tp00, tp01, tp02, tp10, tp11, tp12, tp20, tp21, tp22;

    // ---- window column sources (declared before use) -------------------
    // NOTE: the bottom row is replicated only while replaying. `rep` clears on
    // the cycle the replay's last column is fetched, but the tail snapshot is
    // taken one cycle LATER -- so the replication must persist through `rep_d1`
    // as well. Without the `rep_d1` term the last two columns of the final row
    // fall back to `din_d1`, which equals the correct value only by accident in
    // a simple unit test (it is stale stream data in the real pipeline).
    wire [DW-1:0] mid_new = q0;
    wire [DW-1:0] bot_new = (rep || rep_d1) ? q0 : din_d1;
    wire       top_rep = !rep_d1 && (row_d1 <= 1);
    wire [DW-1:0] top_new = top_rep ? q0 : q1;
    wire [DW-1:0] top_l   = top_rep ? a2 : b2;
    wire [DW-1:0] top_m   = top_rep ? a1 : b1;
    wire [DW-1:0] mid_l   = a2;
    wire [DW-1:0] mid_m   = a1;
    wire [DW-1:0] bot_l   = c2;
    wire [DW-1:0] bot_m   = c1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tail <= 1'b0;
            tp00 <= 8'd0; tp01 <= 8'd0; tp02 <= 8'd0;
            tp10 <= 8'd0; tp11 <= 8'd0; tp12 <= 8'd0;
            tp20 <= 8'd0; tp21 <= 8'd0; tp22 <= 8'd0;
        end else begin
            tail <= beat_reg && (col_d1 == LASTX[AW-1:0]);
            if (beat_reg && (col_d1 == LASTX[AW-1:0])) begin
                tp00 <= top_m; tp01 <= top_new; tp02 <= top_new;
                tp10 <= mid_m; tp11 <= mid_new; tp12 <= mid_new;
                tp20 <= bot_m; tp21 <= bot_new; tp22 <= bot_new;
            end
        end
    end

    wire beat   = beat_reg || tail;
    wire first_b = beat_reg && (col_d1 == 1'b1);   // col == 1 -> centre column 0

    always @(posedge clk) begin
        de_o <= beat;
        if (tail) begin
            p00 <= tp00; p01 <= tp01; p02 <= tp02;
            p10 <= tp10; p11 <= tp11; p12 <= tp12;
            p20 <= tp20; p21 <= tp21; p22 <= tp22;
        end else if (beat_reg) begin
            if (first_b) begin
                p00 <= top_m; p01 <= top_m; p02 <= top_new;
                p10 <= mid_m; p11 <= mid_m; p12 <= mid_new;
                p20 <= bot_m; p21 <= bot_m; p22 <= bot_new;
            end else begin
                p00 <= top_l; p01 <= top_m; p02 <= top_new;
                p10 <= mid_l; p11 <= mid_m; p12 <= mid_new;
                p20 <= bot_l; p21 <= bot_m; p22 <= bot_new;
            end
        end
    end

endmodule

