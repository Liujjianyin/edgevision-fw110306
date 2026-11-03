`timescale 1ns/1ps
// Passive 25 MHz observer, independent of video/DDR resets. Counts survive
// transient PLL/global video resets; only board reset clears them. HS/VS are
// sampled directly, so stopped pixel clocks also produce a timeout event.
module hdmi_link_monitor #(
 parameter integer H_MIN=350,H_MAX=390,V_MIN=400000,V_MAX=435000
)(
 input wire ref_clk,rst_n,report_clk,
 input wire rx_locked,frame_stable,tx_rst_n,global_rst_n,tx_locked,cal_done,rx_rst_n,
 input wire tx_hs,tx_vs,
 output wire [23:0] link0,link1,link2,link3
);
 (* async_reg="true" *) reg [6:0] ls1=0,ls2=0;
 (* async_reg="true" *) reg [1:0] hs_sync=0,vs_sync=0;
 reg [6:0] prev=0;
 reg hp=0,vp=0,h_started=0,v_started=0,h_bad=0,v_bad=0;
 reg [19:0] hg=0,vg=0;
 reg [7:0] counts[0:9];
 wire he=hs_sync[1]&&!hp,ve=vs_sync[1]&&!vp;
 reg [79:0] gray_bus=0;
 (* async_reg="true" *) reg [79:0] gray_s1=0,gray_s2=0;
 (* async_reg="true" *) reg [6:0] flags_s1=0,flags_s2=0;
 wire [79:0] binary_bus;
 integer i;
 function [7:0] inc_sat(input [7:0] x);
  inc_sat=(x==255)?x:x+1'b1;
 endfunction
 function [7:0] decode_gray(input [7:0] x);
  integer k;begin decode_gray[7]=x[7];for(k=6;k>=0;k=k-1)decode_gray[k]=decode_gray[k+1]^x[k];end
 endfunction
 genvar g;
 generate for(g=0;g<10;g=g+1)begin: cdc_counts
  always @(posedge ref_clk or negedge rst_n)
   if(!rst_n)gray_bus[g*8+:8]<=0;
   else gray_bus[g*8+:8]<=counts[g]^(counts[g]>>1);
  assign binary_bus[g*8+:8]=decode_gray(gray_s2[g*8+:8]);
 end endgenerate
 always @(posedge ref_clk or negedge rst_n)begin
  if(!rst_n)begin
   ls1<=0;ls2<=0;prev<=0;hs_sync<=0;vs_sync<=0;hp<=0;vp<=0;
   h_started<=0;v_started<=0;h_bad<=0;v_bad<=0;hg<=0;vg<=0;
   for(i=0;i<10;i=i+1)counts[i]<=0;
  end else begin
   ls1<={rx_rst_n,cal_done,tx_locked,global_rst_n,tx_rst_n,frame_stable,rx_locked};
   ls2<=ls1;prev<=ls2;
   hs_sync<={hs_sync[0],tx_hs};vs_sync<={vs_sync[0],tx_vs};
   hp<=hs_sync[1];vp<=vs_sync[1];
   for(i=0;i<7;i=i+1)if(prev[i]&&!ls2[i])counts[i]<=inc_sat(counts[i]);
   if(he)begin
    if(h_started&&hg<H_MIN-1)counts[7]<=inc_sat(counts[7]);
    hg<=0;h_bad<=0;h_started<=1;
   end else if(h_started)begin
    if(hg<H_MAX)hg<=hg+1'b1;
    if(hg==H_MAX-1&&!h_bad)begin h_bad<=1;counts[7]<=inc_sat(counts[7]);end
   end
   if(ve)begin
    if(v_started&&vg<V_MIN-1)counts[8]<=inc_sat(counts[8]);
    vg<=0;v_bad<=0;v_started<=1;counts[9]<=counts[9]+1'b1;
   end else if(v_started)begin
    if(vg<V_MAX)vg<=vg+1'b1;
    if(vg==V_MAX-1&&!v_bad)begin v_bad<=1;counts[8]<=inc_sat(counts[8]);end
   end
  end
 end
 always @(posedge report_clk or negedge rst_n)begin
  if(!rst_n)begin gray_s1<=0;gray_s2<=0;flags_s1<=0;flags_s2<=0;end
  else begin gray_s1<=gray_bus;gray_s2<=gray_s1;flags_s1<=ls2;flags_s2<=flags_s1;end
 end
 assign link0={binary_bus[0+:8],binary_bus[8+:8],binary_bus[16+:8]};
 assign link1={binary_bus[24+:8],binary_bus[32+:8],binary_bus[40+:8]};
 assign link2={binary_bus[56+:8],binary_bus[64+:8],binary_bus[72+:8]};
 assign link3={1'b0,flags_s2,binary_bus[48+:8],8'd0};
endmodule
