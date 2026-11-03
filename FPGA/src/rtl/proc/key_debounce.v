`timescale 1ns/1ps
// 20 ms debounce for an active-low push button (weak pull-up, press = 0)
module key_debounce #(
    parameter integer CLK_HZ      = 148_500_000,
    parameter integer DEBOUNCE_MS = 20
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  pressed
);
    localparam integer CNT = (CLK_HZ / 1000) * DEBOUNCE_MS;

    reg [24:0] cnt;
    reg        key_s1, key_s2;

    always @(posedge clk) begin
        key_s1 <= key_n;
        key_s2 <= key_s1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= 25'd0;
            pressed <= 1'b1;
        end else if (key_s2 != pressed) begin
            if (cnt >= CNT - 1) begin
                cnt     <= 25'd0;
                pressed <= key_s2;
            end else begin
                cnt <= cnt + 25'd1;
            end
        end else begin
            cnt <= 25'd0;
        end
    end
endmodule
