`timescale 1ns/1ps
//=============================================================================
// ddr_ctrl_uart.v -- UART command receiver for the DDR3 frame buffer
//
// The four board buttons are all taken (display mode, threshold +/-, algorithm),
// so the frame-buffer features are driven from a host over the serial line
// instead. Nothing on the buttons changes.
//
// Wire format: 115200 baud, 8N1, one command byte per action.
//
//   F/U: freeze/resume live. @/A/B: save still slot 0/1/2.
//   `/a/b: show saved still 0/1/2. V: record 15 consecutive frames.
//   P: loop playback at 5 fps. C: clear saved validity and resume live.
//   Commands are case-sensitive ASCII bytes; TX returns framed ACK/status.
//
// CLK_HZ must be the clock actually driving this module; DIV = CLK_HZ/baud.
//=============================================================================
module ddr_ctrl_uart #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer BAUD   = 115_200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire rx,                 // raw serial input, idle high
    output reg        cmd_valid,   // 1-cycle pulse per accepted command
    output reg [2:0]  cmd_op,      // command code
    output reg [1:0]  cmd_arg,     // slot index for save/show
    output reg  step,               // 1-cycle pulse: advance one bank
    output reg  [1:0] bank_sel,     // last requested bank
    output reg  [7:0] last_cmd,     // last accepted command, for diagnostics
    output reg        video_cmd_valid,
    output reg  [3:0] video_cmd
);

    localparam integer DIV = CLK_HZ / BAUD;      // 25e6/115200 = 217

    //------------------------------------------------------------------
    // 2-flop synchroniser + start-bit detect
    //------------------------------------------------------------------
    reg rx_m, rx_s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_m <= 1'b1; rx_s <= 1'b1; end
        else        begin rx_m <= rx;   rx_s <= rx_m; end
    end

    reg [15:0] cnt;
    reg [3:0]  bitn;
    reg [7:0]  sh;

    reg        busy;
    reg        rx_done;
    reg [7:0]  rx_byte;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy    <= 1'b0;
            cnt     <= 16'd0;
            bitn    <= 4'd0;
            sh      <= 8'd0;
            rx_done <= 1'b0;
            rx_byte <= 8'd0;
        end else begin
            rx_done <= 1'b0;

            if (!busy) begin
                // wait for the falling edge of the start bit
                if (!rx_s) begin
                    busy <= 1'b1;
                    cnt  <= DIV / 2;          // sample in the middle of the start bit
                    bitn <= 4'd0;
                end
            end else begin
                if (cnt == 0) begin
                    cnt <= DIV - 1;
                    if (bitn == 4'd0) begin
                        // middle of start bit: confirm it is still low
                        if (rx_s) busy <= 1'b0;          // glitch, abort
                        else      bitn <= 4'd1;
                    end else if (bitn <= 4'd8) begin
                        sh   <= {rx_s, sh[7:1]};          // LSB first
                        bitn <= bitn + 4'd1;
                    end else begin
                        // stop bit
                        busy    <= 1'b0;
                        rx_done <= rx_s; // Reject framing errors / a held-low break.
                        rx_byte <= sh;
                    end
                end else begin
                    cnt <= cnt - 16'd1;
                end
            end
        end
    end

    //------------------------------------------------------------------
    // command decode
    //------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_valid <= 1'b0;
            cmd_op    <= 3'd0;
            cmd_arg   <= 2'd0;
            step     <= 1'b0;
            bank_sel <= 2'd0;
            last_cmd <= 8'd0;
            video_cmd_valid <= 1'b0;
            video_cmd <= 4'd0;
        end else begin
            cmd_valid <= 1'b0;
            video_cmd_valid <= 1'b0;
            if (rx_done) begin
                last_cmd <= rx_byte;
                cmd_arg <= 2'd0;
                // PC image controls. These are absolute settings where possible.
                case (rx_byte)
                    8'h54: begin video_cmd <= 4'd11; video_cmd_valid <= 1'b1; end // T snapshot
                    8'h44: begin video_cmd <= 4'd8; video_cmd_valid <= 1'b1; end // D detection on
                    8'h64: begin video_cmd <= 4'd9; video_cmd_valid <= 1'b1; end // d detection off
                    8'h4a: begin video_cmd <= 4'd10; video_cmd_valid <= 1'b1; end // J empty-cloth capture
                    8'h4b: begin video_cmd <= 4'd0; video_cmd_valid <= 1'b1; end // K: color
                    8'h47: begin video_cmd <= 4'd1; video_cmd_valid <= 1'b1; end // G: edges
                    8'h2b: begin video_cmd <= 4'd2; video_cmd_valid <= 1'b1; end // +: threshold up
                    8'h2d: begin video_cmd <= 4'd3; video_cmd_valid <= 1'b1; end // -: threshold down
                    8'h53: begin video_cmd <= 4'd4; video_cmd_valid <= 1'b1; end // S: Sobel
                    8'h59: begin video_cmd <= 4'd5; video_cmd_valid <= 1'b1; end // Y: Canny
                    8'h4d: begin video_cmd <= 4'd6; video_cmd_valid <= 1'b1; end // M: median on
                    8'h6d: begin video_cmd <= 4'd7; video_cmd_valid <= 1'b1; end // m: median off
                    default: ;
                endcase
                case (rx_byte)
                    8'h46: begin cmd_op <= 3'd0; cmd_valid <= 1'b1; end   // 'F'
                    8'h55: begin cmd_op <= 3'd1; cmd_valid <= 1'b1; end   // 'U'
                    8'h40: begin cmd_op <= 3'd2; cmd_arg <= 2'd0; cmd_valid <= 1'b1; end
                    8'h41: begin cmd_op <= 3'd2; cmd_arg <= 2'd1; cmd_valid <= 1'b1; end
                    8'h42: begin cmd_op <= 3'd2; cmd_arg <= 2'd2; cmd_valid <= 1'b1; end
                    8'h56: begin cmd_op <= 3'd3; cmd_valid <= 1'b1; end   // 'V'
                    8'h50: begin cmd_op <= 3'd4; cmd_valid <= 1'b1; end   // 'P'
                    8'h43: begin cmd_op <= 3'd6; cmd_valid <= 1'b1; end   // 'C'
                    8'h60: begin cmd_op <= 3'd5; cmd_arg <= 2'd0; cmd_valid <= 1'b1; end
                    8'h61: begin cmd_op <= 3'd5; cmd_arg <= 2'd1; cmd_valid <= 1'b1; end
                    8'h62: begin cmd_op <= 3'd5; cmd_arg <= 2'd2; cmd_valid <= 1'b1; end
                    8'h3f: begin cmd_op <= 3'd7; cmd_valid <= 1'b1; end   // '?' query only
                    default: ;
                endcase
            end
        end
    end

endmodule


