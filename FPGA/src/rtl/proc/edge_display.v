`timescale 1ns/1ps
// Overlay only completed same-frame RGB and edges; no temporal edge/RGB mix.
module edge_display #(
 parameter PIP_W=320,PIP_H=180,PIP_X=1560,PIP_Y=40,PIP_SCALE=6
)(input wire clk,rst_n,i_de,i_hs,i_vs,input wire [31:0] i_word,
 input wire mode_col_i,algo_canny_i,
 output reg [23:0] o_rgb,output reg o_de,o_hs,o_vs);
 wire [23:0] rgb_f=i_word[23:0];
 wire de_f=i_de,hs_f=i_hs,vs_f=i_vs;
 reg mode_col_f=1,algo_canny_f=1;
 wire edge_f=algo_canny_f?i_word[31]:i_word[29];
 reg de_d=0,vs_d=0;
 always @(posedge clk)begin
  if(!rst_n)begin mode_col_f<=1;algo_canny_f<=1;end
  else if(vs_f&&!vs_d)begin mode_col_f<=mode_col_i;algo_canny_f<=algo_canny_i;end
 end
 // Count only active lines. HS also occurs in vertical blanking and cannot be Y.
 reg [11:0] x=0,y=0;
 reg [3:0] xm=0,ym=0;
 always @(posedge clk) begin
  de_d<=de_f;vs_d<=vs_f;
  if(!rst_n || (vs_f&&!vs_d))begin x<=0;y<=0;xm<=0;ym<=0;end
  else begin
   if(de_f)begin x<=x+1'b1;xm<=(xm==PIP_SCALE-1)?0:xm+1'b1;end
   else begin x<=0;xm<=0;end
   if(de_d&&!de_f)begin y<=y+1'b1;ym<=(ym==PIP_SCALE-1)?0:ym+1'b1;end
  end
 end
 // Double-buffered thumbnail. Read a completed previous frame, never partial RAM.
 localparam PIP_SIZE=PIP_W*PIP_H;
 reg [16:0] waddr=0;reg wbank=0,pip_valid=0;
 wire pip_we=de_f&&(xm==0)&&(ym==0)&&(waddr<PIP_SIZE);
 always @(posedge clk)begin
  if(!rst_n)begin waddr<=0;wbank<=0;pip_valid<=0;end
  else if(vs_f&&!vs_d)begin
   if(waddr==PIP_SIZE)begin wbank<=~wbank;pip_valid<=1;end
   waddr<=0;
  end else if(pip_we)waddr<=waddr+1'b1;
 end
 wire pip_inside=de_f&&(x>=PIP_X)&&(x<PIP_X+PIP_W)&&(y>=PIP_Y)&&(y<PIP_Y+PIP_H);
 wire border=pip_inside&&((x<PIP_X+2)||(x>=PIP_X+PIP_W-2)||(y<PIP_Y+2)||(y>=PIP_Y+PIP_H-2));
 wire [15:0] pip_sum=77*{8'd0,rgb_f[23:16]}+150*{8'd0,rgb_f[15:8]}+29*{8'd0,rgb_f[7:0]};
 // Pack five 8-bit samples into 40 bits to fill RAM10 lanes efficiently.
 // This keeps two full-precision frames within the Ti60's 256 RAM blocks.
 reg [31:0] pack4=0;
 reg [2:0] wbyte=0,rbyte=0,rbyte_d=0;
 reg [13:0] wword=0,rword=0;
 always @(posedge clk)begin
  if(!rst_n || (vs_f&&!vs_d))begin wbyte<=0;rbyte<=0;wword<=0;rword<=0;end
  else begin
   if(pip_we)begin
    case(wbyte)
     0:pack4[7:0]<=pip_sum[15:8];1:pack4[15:8]<=pip_sum[15:8];
     2:pack4[23:16]<=pip_sum[15:8];3:pack4[31:24]<=pip_sum[15:8];default:;
    endcase
    if(wbyte==4)begin wbyte<=0;wword<=wword+1'b1;end else wbyte<=wbyte+1'b1;
   end
   if(pip_inside)begin
    if(rbyte==4)begin rbyte<=0;rword<=rword+1'b1;end else rbyte<=rbyte+1'b1;
   end
  end
  rbyte_d<=rbyte;
 end
 wire [39:0] pq0,pq1;
 wire [13:0] raddr=pip_inside?rword:14'd0;
 edge_pip_ram40 #(.WORDS(PIP_SIZE/5)) pp0(.clk(clk),.we(pip_we&&!wbank&&(wbyte==4)),.din({pip_sum[15:8],pack4}),.waddr(wword),.raddr(raddr),.dout(pq0));
 edge_pip_ram40 #(.WORDS(PIP_SIZE/5)) pp1(.clk(clk),.we(pip_we&&wbank&&(wbyte==4)),.din({pip_sum[15:8],pack4}),.waddr(wword),.raddr(raddr),.dout(pq1));
 reg inside_d,border_d,valid_d,bank_d;reg [23:0] base_d;reg [2:0] sync_d;
 wire [39:0] pq=bank_d?pq0:pq1;
 wire [7:0] pg=pq >> (rbyte_d*8);
 always @(posedge clk) begin
  if(!rst_n)begin
   inside_d<=0;border_d<=0;valid_d<=0;bank_d<=0;base_d<=0;sync_d<=0;
   o_rgb<=0;o_de<=0;o_hs<=0;o_vs<=0;
  end else begin
   inside_d<=pip_inside;border_d<=border;valid_d<=pip_valid;bank_d<=wbank;
   base_d<=mode_col_f?(edge_f?24'hFF0000:rgb_f):(edge_f?24'hFFFFFF:24'd0);
   sync_d<={vs_f,hs_f,de_f};
   // Use the completed thumbnail when available.  Before the first complete
   // thumbnail frame, fall back to the main image instead of blacking the PiP.
   o_rgb<=!sync_d[0]?24'd0:
          (inside_d?(border_d?24'hFFFFFF:(valid_d?{pg,pg,pg}:base_d)):base_d);
   {o_vs,o_hs,o_de}<=sync_d;
  end
 end
endmodule

module edge_pip_ram40 #(parameter WORDS=11520)(input wire clk,we,
 input wire [39:0] din,input wire [13:0] waddr,raddr,output reg [39:0] dout);
 reg [39:0] mem[0:WORDS-1];
 always @(posedge clk)begin
  if(we)mem[waddr]<=din;
  dout<=mem[raddr];
 end
endmodule

