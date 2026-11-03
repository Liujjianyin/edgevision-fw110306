`timescale 1ns/1ps
// Complements the independent HS/VS watchdog with exact active-video geometry.
// One saturating event per malformed output frame, after the first observed VS.
module hdmi_pixel_monitor #(parameter WIDTH=1920,HEIGHT=1080)(
 input wire clk,rst_n,de,vs,report_clk,output wire[7:0] errors
);
 reg dp=0,vp=0,started=0,bad_line=0;
 reg[12:0] line_pixels=0,lines=0;
 reg[23:0] pixels=0;
 reg[7:0] count=0,gray=0;
 (* async_reg="true" *) reg[7:0] g1=0,g2=0;
 reg[7:0] decoded;integer k;
 always @* begin decoded[7]=g2[7];for(k=6;k>=0;k=k-1)decoded[k]=decoded[k+1]^g2[k];end
 assign errors=decoded;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin dp<=0;vp<=0;started<=0;bad_line<=0;line_pixels<=0;lines<=0;pixels<=0;count<=0;gray<=0;end
  else begin
   dp<=de;vp<=vs;gray<=count^(count>>1);
   if(vs&&!vp)begin
    if(started&&(bad_line||pixels!=WIDTH*HEIGHT||lines!=HEIGHT||de)&&count!=255)count<=count+1'b1;
    started<=1;bad_line<=0;line_pixels<=0;lines<=0;pixels<=0;
   end else if(de)begin
    if(line_pixels!=8191)line_pixels<=line_pixels+1'b1;
    if(pixels!=24'hffffff)pixels<=pixels+1'b1;
   end else if(dp)begin
    if(line_pixels!=WIDTH)bad_line<=1;
    if(lines!=8191)lines<=lines+1'b1;
    line_pixels<=0;
   end
  end
 end
 always @(posedge report_clk or negedge rst_n)
  if(!rst_n)begin g1<=0;g2<=0;end
  else begin g1<=gray;g2<=g1;end
endmodule
