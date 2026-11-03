`timescale 1ns/1ps
// Exact median of nine; five registered stages, one window per clock.
// Comparator/multiplexer network; no serial sorter or divider.
module median3x3(
 input wire clk,rst_n,de_i,
 input wire [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22,
 output reg de_o,output reg [7:0] med_o,min_o,max_o
);
 function [7:0] mn(input [7:0] a,b);mn=(a<b)?a:b;endfunction
 function [7:0] mx(input [7:0] a,b);mx=(a>b)?a:b;endfunction
 function [7:0] mid(input [7:0] a,b,c);mid=mx(mn(a,b),mn(mx(a,b),c));endfunction
 reg [7:0] al[0:2],ah[0:2],ac[0:2];
 reg [7:0] lo[0:2],mi[0:2],hi[0:2];
 reg [7:0] a3,b3,c3,mn3,mx3,lo4,hi4,c4,mn4,mx4;
 reg [3:0] valid;
 integer j;
 always @(posedge clk)begin
  if(!rst_n)begin
   for(j=0;j<3;j=j+1)begin al[j]<=0;ah[j]<=0;ac[j]<=0;lo[j]<=0;mi[j]<=0;hi[j]<=0;end
   a3<=0;b3<=0;c3<=0;mn3<=0;mx3<=0;
   lo4<=0;hi4<=0;c4<=0;mn4<=0;mx4<=0;
   valid<=0;de_o<=0;med_o<=0;min_o<=0;max_o<=0;
  end else begin
   valid<={valid[2:0],de_i};de_o<=valid[3];
   al[0]<=mn(p00,p01);ah[0]<=mx(p00,p01);ac[0]<=p02;
   al[1]<=mn(p10,p11);ah[1]<=mx(p10,p11);ac[1]<=p12;
   al[2]<=mn(p20,p21);ah[2]<=mx(p20,p21);ac[2]<=p22;
   for(j=0;j<3;j=j+1)begin
    lo[j]<=mn(al[j],ac[j]);hi[j]<=mx(ah[j],ac[j]);
    mi[j]<=mx(al[j],mn(ah[j],ac[j]));
   end
   a3<=mx(mx(lo[0],lo[1]),lo[2]);b3<=mid(mi[0],mi[1],mi[2]);c3<=mn(mn(hi[0],hi[1]),hi[2]);
   mn3<=mn(mn(lo[0],lo[1]),lo[2]);mx3<=mx(mx(hi[0],hi[1]),hi[2]);
   lo4<=mn(a3,b3);hi4<=mx(a3,b3);c4<=c3;mn4<=mn3;mx4<=mx3;
   med_o<=mx(lo4,mn(hi4,c4));min_o<=mn4;max_o<=mx4;
  end
 end
endmodule