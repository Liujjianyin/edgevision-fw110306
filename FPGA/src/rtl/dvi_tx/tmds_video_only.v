`timescale 1ns/1ps
// Video-only DVI-compatible TMDS. No audio, data islands or infoframes.
// The existing 10:1 serializer, PLL, pin polarity and clock word are unchanged.
// Two pixel-clock register stages, with equal latency on all RGB/control lanes.
module tmds_video_only(
 input wire clk,rst_n,de,hs,vs,input wire [23:0] rgb,
 output wire [9:0] blue,green,red,clock_word
);
 tmds_video_lane b(.clk(clk),.rst_n(rst_n),.de(de),.control({vs,hs}),.din(rgb[7:0]),.symbol(blue));
 tmds_video_lane g(.clk(clk),.rst_n(rst_n),.de(de),.control(2'b00),.din(rgb[15:8]),.symbol(green));
 tmds_video_lane r(.clk(clk),.rst_n(rst_n),.de(de),.control(2'b00),.din(rgb[23:16]),.symbol(red));
 // Confirmed against the previous mapped netlist before output pin inversion.
 assign clock_word=10'b1111100000;
endmodule

module tmds_video_lane(
 input wire clk,rst_n,de,input wire[1:0] control,input wire[7:0] din,
 output reg[9:0] symbol
);
 reg[8:0] qm_d;
 reg de_d;reg[1:0] control_d;
 reg signed[5:0] balance_d,disparity;
 function[3:0] pop8(input[7:0] d);
  integer k;begin pop8=0;for(k=0;k<8;k=k+1)pop8=pop8+{3'd0,d[k]};end
 endfunction
 function[8:0] transition_word(input[7:0] d);
  reg xn;reg[8:0] q;integer k;
  begin
   xn=(pop8(d)>4)||((pop8(d)==4)&&!d[0]);q[0]=d[0];
   for(k=1;k<8;k=k+1)q[k]=q[k-1]^d[k]^xn;
   q[8]=!xn;transition_word=q;
  end
 endfunction
 wire[8:0] qm=transition_word(din);
 wire[3:0] ones_qm=pop8(qm[7:0]);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin qm_d<=0;balance_d<=0;de_d<=0;control_d<=0;end
  else begin
   qm_d<=qm;balance_d<=$signed({1'b0,ones_qm,1'b0})-6'sd8;
   de_d<=de;control_d<=control;
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin symbol<=10'b1101010100;disparity<=0;end
  else if(!de_d)begin
   disparity<=0;
   case(control_d)
    2'b00:symbol<=10'b1101010100;
    2'b01:symbol<=10'b0010101011;
    2'b10:symbol<=10'b0101010100;
    2'b11:symbol<=10'b1010101011;
   endcase
  end else if((disparity==0)||(balance_d==0))begin
   symbol<={~qm_d[8],qm_d[8],(qm_d[8]?qm_d[7:0]:~qm_d[7:0])};
   disparity<=disparity+(qm_d[8]?balance_d:-balance_d);
  end else if((disparity>0&&balance_d>0)||(disparity<0&&balance_d<0))begin
   symbol<={1'b1,qm_d[8],~qm_d[7:0]};
   disparity<=disparity+(qm_d[8]?6'sd2:6'sd0)-balance_d;
  end else begin
   symbol<={1'b0,qm_d[8],qm_d[7:0]};
   disparity<=disparity+balance_d-(qm_d[8]?6'sd0:6'sd2);
  end
 end
endmodule
