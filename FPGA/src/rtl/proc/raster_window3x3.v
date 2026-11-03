`timescale 1ns/1ps
// Continuous-raster window: blanking clocks are part of the line delay.
// Center latency is LINE_TOTAL+2 clocks. RAM contents need no reset.
module raster_window3x3 #(parameter DW=35, LINE_TOTAL=2200)(
 input wire clk,rst_n,input wire [DW-1:0] din,
 output wire ready,
 output reg [DW-1:0] p00,p01,p02,p10,p11,p12,p20,p21,p22);
 localparam AW=$clog2(LINE_TOTAL);
 reg [DW-1:0] line0[0:LINE_TOTAL-1],line1[0:LINE_TOTAL-1];
 reg [AW-1:0] ptr=0,ptr_d=0;
 reg [DW-1:0] q0,q1,cur;
 reg [AW+1:0] warm=0;
 assign ready=(warm==2*LINE_TOTAL+4);
 always @(posedge clk) begin
  q0<=line0[ptr];q1<=line1[ptr];cur<=din;
  line0[ptr]<=din;
  // q0 belongs to ptr_d, not the current address.
  line1[ptr_d]<=q0;
  ptr_d<=ptr;
  p00<=p01;p01<=p02;p02<=q1;
  p10<=p11;p11<=p12;p12<=q0;
  p20<=p21;p21<=p22;p22<=cur;
  if(!rst_n) begin ptr<=0;ptr_d<=0;warm<=0;end
  else begin
   ptr<=(ptr==LINE_TOTAL-1)?0:ptr+1'b1;
   if(!ready) warm<=warm+1'b1;
  end
 end
endmodule
