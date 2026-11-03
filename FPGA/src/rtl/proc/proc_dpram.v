`timescale 1ns/1ps
// simple synchronous dual-port RAM: one write port, one read port
module proc_dpram #(
    parameter integer DW = 9,
    parameter integer AW = 10
)(
    input  wire          clk,
    input  wire          we,
    input  wire [DW-1:0] din,
    input  wire [AW-1:0] waddr,
    input  wire [AW-1:0] raddr,
    output reg  [DW-1:0] dout
);
    reg [DW-1:0] mem [0:(1<<AW)-1];

    always @(posedge clk) begin
        if (we) mem[waddr] <= din;
        dout <= mem[raddr];
    end
endmodule
