`timescale 1ns/1ps
//=============================================================================
// ddr_save_ctrl.v -- still-frame slots, video recording and playback on DDR3
//
// The DDR holds three regions, all handled by the existing frame_buffer:
//
//   LIVE  : 3 banks used as the normal triple buffer
//   SLOTS : 3 single-frame slots for the "single frame save" button
//   VIDEO : up to 26 frames recorded by the "save video" button
//
// Nothing in the data path is touched. A capture simply overrides the write
// start address of the frame_buffer for the duration of one frame (or N frames
// for video), so the frame lands in the save region instead of the live bank.
// Reading works the same way: the read start address is overridden to point at
// a saved slot or a video frame.
//
// Frame boundaries come from the write engine's own frame-complete pulse, so
// this module lives in the core (axi) clock domain and needs no crossing for
// the handshake. Capturing on the exact write boundary is what keeps the
// first saved frame from being half written.
//
// Commands (one pulse each):
//   op 0  freeze        picture stops, saved data untouched
//   op 1  unfreeze      resume live, SAVED DATA IS KEPT
//   op 2  save slot     arg = 0..2, capture the next frame into that slot
//   op 3  save video    capture the next NVID frames, overwriting the old video
//   op 4  play          loop the recorded video at PLAY_FPS
//   op 5  show slot     arg = 0..2, display that saved still forever
//   op 6  clear         forget everything that was saved
//=============================================================================
module ddr_save_ctrl #(
    parameter integer FRAME_LEN  = 2_074_112,      // 960*1080*16/8 + 0x200
    parameter [31:0]  SLOT_BASE  = 32'h0060_0000,
    parameter [31:0]  VIDEO_BASE = 32'h0100_0000,
    parameter integer NSLOT       = 3,
    parameter integer NVID        = 26,
    parameter integer CLK_HZ      = 100_000_000,   // core clock
    parameter integer PLAY_FPS    = 5
)(
    input  wire        clk,          // AXI/core clock (100 MHz)
    input  wire        rst_n,
    input  wire        vs,           // write-engine frame-complete pulse (axi domain)
    input  wire        rd_done,      // read-engine frame-complete pulse (axi domain)

    input  wire        cmd_valid,    // 1-cycle pulse
    input  wire [2:0]  cmd_op,
    input  wire [1:0]  cmd_arg,

    output reg         rd_hold,      // 1 = read bank frozen
    output reg         rd_addr_en,
    output reg  [31:0] rd_addr_ovr,
    output reg         wr_addr_en,
    output reg  [31:0] wr_addr_ovr,

    output reg  [3:0]  state,        // 0 idle, 1 frozen, 2 saving, 3 video, 4 playing, 5 still
    output reg  [4:0]  prog,         // frames captured so far (0..26)
    output reg         saved_valid,  // at least one slot / video holds data
    output reg  [2:0]  slot_valid,   // one bit per still slot
    output reg         video_valid
);

    localparam integer CYC_PER_FRAME = CLK_HZ / PLAY_FPS;   // 200 ms at 5 fps

    // The AXI port is 128 bit wide and the write engine bursts 128 beats, i.e.
    // 2048 bytes per burst. FRAME_LEN (2 074 112) is NOT a multiple of 2048, so
    // addressing slots as base + k*FRAME_LEN puts slot 1 half way into a burst.
    // The write then straddles the slot boundary, which showed up as a violent
    // flash while saving that slot and a torn picture when displaying it.
    // Use a 2048-aligned stride for every region instead.
    localparam integer BURST_BYTES  = 2048;
    localparam integer FRAME_STRIDE = ((FRAME_LEN + BURST_BYTES - 1) / BURST_BYTES) * BURST_BYTES;

    localparam [31:0] SLOT_ADDR0 = SLOT_BASE;
    localparam [31:0] SLOT_ADDR1 = SLOT_BASE + FRAME_STRIDE;
    localparam [31:0] SLOT_ADDR2 = SLOT_BASE + 2 * FRAME_STRIDE;

    function [31:0] slot_addr(input [1:0] k);
        begin
            case (k)
                2'd0:    slot_addr = SLOT_ADDR0;
                2'd1:    slot_addr = SLOT_ADDR1;
                default: slot_addr = SLOT_ADDR2;
            endcase
        end
    endfunction

    // Precomputed like the slots: keeps the multiplier out of the address path,
    // which is what pushed the timing slack negative.
    localparam [31:0] VIDEO_ADDR0  = VIDEO_BASE +  0 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR1  = VIDEO_BASE +  1 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR2  = VIDEO_BASE +  2 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR3  = VIDEO_BASE +  3 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR4  = VIDEO_BASE +  4 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR5  = VIDEO_BASE +  5 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR6  = VIDEO_BASE +  6 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR7  = VIDEO_BASE +  7 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR8  = VIDEO_BASE +  8 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR9  = VIDEO_BASE +  9 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR10 = VIDEO_BASE + 10 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR11 = VIDEO_BASE + 11 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR12 = VIDEO_BASE + 12 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR13 = VIDEO_BASE + 13 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR14 = VIDEO_BASE + 14 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR15 = VIDEO_BASE + 15 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR16 = VIDEO_BASE + 16 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR17 = VIDEO_BASE + 17 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR18 = VIDEO_BASE + 18 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR19 = VIDEO_BASE + 19 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR20 = VIDEO_BASE + 20 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR21 = VIDEO_BASE + 21 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR22 = VIDEO_BASE + 22 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR23 = VIDEO_BASE + 23 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR24 = VIDEO_BASE + 24 * FRAME_STRIDE;
    localparam [31:0] VIDEO_ADDR25 = VIDEO_BASE + 25 * FRAME_STRIDE;

    function [31:0] video_addr(input [4:0] n);
        begin
            case (n)
                5'd0:  video_addr = VIDEO_ADDR0;   5'd1:  video_addr = VIDEO_ADDR1;
                5'd2:  video_addr = VIDEO_ADDR2;   5'd3:  video_addr = VIDEO_ADDR3;
                5'd4:  video_addr = VIDEO_ADDR4;   5'd5:  video_addr = VIDEO_ADDR5;
                5'd6:  video_addr = VIDEO_ADDR6;   5'd7:  video_addr = VIDEO_ADDR7;
                5'd8:  video_addr = VIDEO_ADDR8;   5'd9:  video_addr = VIDEO_ADDR9;
                5'd10: video_addr = VIDEO_ADDR10;  5'd11: video_addr = VIDEO_ADDR11;
                5'd12: video_addr = VIDEO_ADDR12;  5'd13: video_addr = VIDEO_ADDR13;
                5'd14: video_addr = VIDEO_ADDR14;  5'd15: video_addr = VIDEO_ADDR15;
                5'd16: video_addr = VIDEO_ADDR16;  5'd17: video_addr = VIDEO_ADDR17;
                5'd18: video_addr = VIDEO_ADDR18;  5'd19: video_addr = VIDEO_ADDR19;
                5'd20: video_addr = VIDEO_ADDR20;  5'd21: video_addr = VIDEO_ADDR21;
                5'd22: video_addr = VIDEO_ADDR22;  5'd23: video_addr = VIDEO_ADDR23;
                5'd24: video_addr = VIDEO_ADDR24;  default: video_addr = VIDEO_ADDR25;
            endcase
        end
    endfunction

    // ---------------- vsync edge ----------------
    reg vs_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) vs_d <= 1'b0;
        else        vs_d <= vs;

    wire fend = vs & ~vs_d;          // one pulse per camera frame

    // ---------------- FSM ----------------
    localparam [2:0] S_IDLE = 3'd0, S_FREEZE = 3'd1, S_SAVE1 = 3'd2,
                     S_REC   = 3'd3, S_PLAY   = 3'd4, S_STILL  = 3'd5;

    reg [2:0]  st;
    reg [7:0]  rec_cnt;
    reg [1:0]  slot_idx;
    reg [4:0]  play_idx;

    reg [25:0] play_cnt;
    reg        armed;      // capture armed, waiting for the next frame boundary
    reg        rd_hold_prev;   // restore this when the capture finishes
    reg [31:0] rd_addr_pend;
    reg        rd_pend_en;   // a new read address is waiting for the next read boundary

    // pulse into the read bank switch so the read engine restarts
    reg        step_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            armed<=1'b0; rd_hold_prev<=1'b0; rd_addr_pend<=0; rd_pend_en<=0;
            st         <= S_IDLE;
            rec_cnt    <= 8'd0;
            slot_idx   <= 2'd0;
            play_idx   <= 5'd0;
            play_cnt   <= 26'd0;
            rd_hold    <= 1'b0;
            rd_addr_en <= 1'b0;
            rd_addr_ovr<= 32'd0;
            wr_addr_en <= 1'b0;
            wr_addr_ovr<= 32'd0;
            step_r     <= 1'b0;
            state      <= 4'd0;
            prog       <= 5'd0;
            saved_valid<= 1'b0;
            slot_valid <= 3'd0;
            video_valid<= 1'b0;
        end else begin
            step_r <= 1'b0;

            // ---------------- commands ----------------
            if (cmd_valid) begin
                case (cmd_op)
                    // ---- freeze: picture only ----
                    3'd0: begin
                        armed      <= 1'b0;
                        wr_addr_en <= 1'b0;
                        rd_pend_en <= 1'b0;
                        st         <= S_FREEZE;
                        rd_hold    <= 1'b1;
                        rd_addr_en <= 1'b0;
                    end
                    // ---- unfreeze: everything back to live, saved data KEPT ----
                    3'd1: begin
                        rd_pend_en <= 1'b0;
                        armed      <= 1'b0;
                        st         <= S_IDLE;
                        rd_hold    <= 1'b0;
                        rd_addr_en <= 1'b0;
                        wr_addr_en <= 1'b0;
                    end
                    // ---- save one frame into a slot ----
                    3'd2: begin
                        // a slot that already holds a frame is NOT overwritten:
                        // saving again would write into the same DDR area while the
                        // display may still be reading it. Clear first instead.
                        if (cmd_arg < NSLOT && !slot_valid[cmd_arg]) begin
                            rd_hold_prev <= rd_hold;
                            rd_hold      <= 1'b1;   // hold the display during the capture
                            st         <= S_SAVE1;
                            slot_idx   <= cmd_arg;
                            wr_addr_ovr<= slot_addr(cmd_arg);
                            wr_addr_en <= 1'b0;   // arm now, enable at the next boundary
                            armed      <= 1'b1;
                            prog       <= 5'd0;
                        end
                    end
                    // ---- record the video ----
                    3'd3: begin
                        video_valid<= 1'b0;
                        saved_valid<= |slot_valid;
                        rd_addr_en <= 1'b0;
                        rd_pend_en <= 1'b0;
                        rd_hold_prev <= rd_hold;
                        rd_hold      <= 1'b1;
                        st         <= S_REC;
                        rec_cnt    <= 8'd0;
                        wr_addr_ovr<= VIDEO_BASE;
                        wr_addr_en <= 1'b0;
                        armed      <= 1'b1;
                        prog       <= 5'd0;
                    end
                    // ---- playback ----
                    3'd4: begin
                        if (video_valid) begin
                            armed      <= 1'b0;
                            wr_addr_en <= 1'b0;
                            rd_pend_en <= 1'b0;
                            st         <= S_PLAY;
                            rd_hold    <= 1'b1;
                            rd_addr_en <= 1'b1;
                            play_idx   <= 5'd0;
                            play_cnt   <= 26'd0;
                            rd_addr_ovr<= VIDEO_BASE;
                        end
                    end
                    // ---- show a saved still ----
                    3'd5: begin
                        if (cmd_arg < NSLOT && slot_valid[cmd_arg]) begin
                            armed      <= 1'b0;
                            wr_addr_en <= 1'b0;
                            st         <= S_STILL;
                            rd_hold    <= 1'b1;
                            rd_addr_en <= 1'b1;
                            // The read engine latches start_addr per frame.
                            // Change enable and address atomically for that latch.
                            rd_addr_ovr <= slot_addr(cmd_arg);
                            rd_pend_en  <= 1'b0;
                        end
                    end
                    // ---- clear ----
                    3'd6: begin
                        rd_pend_en <= 1'b0;
                        armed      <= 1'b0;
                        st         <= S_IDLE;
                        rd_hold    <= 1'b0;
                        rd_addr_en <= 1'b0;
                        wr_addr_en <= 1'b0;
                        saved_valid<= 1'b0;
                        slot_valid <= 3'd0;      // every still slot becomes empty again
                        video_valid<= 1'b0;
                        prog       <= 5'd0;
                    end
                    default: ;
                endcase
            end

            // ---- read-address changes take effect only between read frames ----
            if (!cmd_valid && rd_done && rd_pend_en) begin
                rd_addr_ovr <= rd_addr_pend;
                rd_pend_en  <= 1'b0;
            end

            // ---------------- frame-boundary work ----------------
            if (fend && !cmd_valid) begin
                case (st)
                    S_SAVE1: begin
                        if (armed) begin
                            // the whole next frame goes into the slot
                            armed      <= 1'b0;
                            wr_addr_en <= 1'b1;
                        end else begin
                            wr_addr_en <= 1'b0;
                            saved_valid<= 1'b1;
                            case (slot_idx)
                                2'd0: slot_valid[0] <= 1'b1;
                                2'd1: slot_valid[1] <= 1'b1;
                                default: slot_valid[2] <= 1'b1;
                            endcase
                            prog       <= 5'd1;
                            rd_hold    <= rd_hold_prev;   // release the display
                            st         <= S_IDLE;
                        end
                    end
                    S_REC: begin
                        if (armed) begin
                            armed      <= 1'b0;
                            wr_addr_en <= 1'b1;
                        end else if (rec_cnt == NVID - 1) begin
                            wr_addr_en <= 1'b0;
                            saved_valid<= 1'b1;
                            video_valid<= 1'b1;
                            prog       <= NVID;
                            rd_hold    <= rd_hold_prev;   // release the display
                            st         <= S_IDLE;
                        end else begin
                            rec_cnt    <= rec_cnt + 8'd1;
                            wr_addr_ovr<= video_addr(rec_cnt[4:0] + 5'd1);
                            prog       <= rec_cnt[4:0] + 5'd1;
                        end
                    end
                    default: ;
                endcase
            end

            // ---------------- playback timing ----------------
            if (st == S_PLAY && !cmd_valid) begin
                if (play_cnt >= CYC_PER_FRAME - 1) begin
                    play_cnt <= 26'd0;
                    if (play_idx == NVID - 1) play_idx <= 5'd0;
                    else                      play_idx <= play_idx + 5'd1;
                    if (play_idx == NVID - 1) rd_addr_pend <= video_addr(5'd0);
                    else                      rd_addr_pend <= video_addr(play_idx + 5'd1);
                    rd_pend_en <= 1'b1;
                end else begin
                    play_cnt <= play_cnt + 26'd1;
                end
            end

            // ---------------- state / progress for the host ----------------
            case (st)
                S_IDLE:   state <= 4'd0;
                S_FREEZE: state <= 4'd1;
                S_SAVE1:  state <= 4'd2;
                S_REC:    state <= 4'd3;
                S_PLAY:   state <= 4'd4;
                S_STILL:  state <= 4'd5;
                default:  state <= 4'd0;
            endcase
        end
    end


endmodule
