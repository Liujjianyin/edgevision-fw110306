`timescale 1ns/1ps
// FW110303: 0 Wusu, 1 Coke, 2 Lime, 3 Pepsi, 4 background, 5 unknown.
// Sequential, exact signed-int8 CNN. Video capture is double-buffered and
// inference never controls HDMI/DDR admission or video sync.
module drink_cnn_engine #(
 parameter C1=8,C2=16,C3=24,
 parameter S1=7,S2=6,S3=5,
 parameter WEIGHT_FILE="drink_cnn_weights.hex",BIAS_FILE="drink_cnn_bias.hex"
)(input wire clk,rst_n,
 input wire pixel_we,input wire [9:0] pixel_addr,input wire [23:0] pixel_rgb,
 input wire frame_valid,output reg busy,done,output reg [2:0] class_id,
 output reg [7:0] result_count,drop_count);
 localparam W1=0,W2=C1*27,W3=C1*27+C2*C1*9,WF=C1*27+C2*C1*9+C3*C2*9;
 localparam NW=WF+5*C3,NB=C1+C2+C3+5;
 reg [23:0] input0[0:1023],input1[0:1023];
 localparam NA=(C1*256>C3*16)?C1*256:C3*16,NB_ACT=C2*64;
 reg signed [7:0] a[0:NA-1],b[0:NB_ACT-1],weights[0:NW-1];
 reg signed [31:0] biases[0:NB-1];
 initial begin $readmemh(WEIGHT_FILE,weights);$readmemh(BIAS_FILE,biases);end
 reg write_bank=0,read_bank=0;
 reg [2:0] state=0;
 localparam IDLE=0,INIT=1,BIAS=2,ADDR=3,MUL=4,ACC=5,STORE=6;
 reg [1:0] layer=0;
 reg [5:0] oc=0,ic=0;
 reg [4:0] ox=0,oy=0;
 reg [1:0] kx=0,ky=0;
 reg [3:0] fcpos=0;
 reg [12:0] read_addr,write_addr;
 reg [13:0] weight_addr;
 reg [6:0] bias_addr;
 reg [5:0] inch,outch,iw,ow;
 reg [3:0] qshift;
 reg signed [6:0] sx,sy;
 reg pad;
 always_comb begin
  inch=3;outch=C1;iw=32;ow=16;qshift=S1;
  sx=$signed({1'b0,ox,1'b0})+$signed({5'd0,kx})-7'sd1;
  sy=$signed({1'b0,oy,1'b0})+$signed({5'd0,ky})-7'sd1;
  read_addr=0;write_addr=0;weight_addr=0;bias_addr=0;
  case(layer)
   0:begin
    read_addr={3'd0,sy[4:0],sx[4:0]};write_addr=(oc<<8)+(oy<<4)+ox;
    weight_addr=oc*27+ic*9+ky*3+kx;bias_addr=oc;
   end
   1:begin
    inch=C1;outch=C2;iw=16;ow=8;qshift=S2;
    read_addr=(ic<<8)+({9'd0,sy[3:0]}<<4)+sx[3:0];write_addr=(oc<<6)+(oy<<3)+ox;
    weight_addr=W2+oc*(C1*9)+ic*9+ky*3+kx;bias_addr=C1+oc;
   end
   2:begin
    inch=C2;outch=C3;iw=8;ow=4;qshift=S3;
    read_addr=(ic<<6)+({10'd0,sy[2:0]}<<3)+sx[2:0];write_addr=(oc<<4)+(oy<<2)+ox;
    weight_addr=W3+oc*(C2*9)+ic*9+ky*3+kx;bias_addr=C1+C2+oc;
   end
   3:begin
    inch=C3;outch=5;iw=4;ow=1;qshift=0;
    read_addr=(ic<<4)+fcpos;
    weight_addr=WF+oc*C3+ic;bias_addr=C1+C2+C3+oc;
   end
  endcase
  pad=layer!=3&&(sx<0||sy<0||sx>=$signed({1'b0,iw})||sy>=$signed({1'b0,iw}));
 end
 reg [23:0] rgb0_q,rgb1_q;
 wire [23:0] rgb_q=read_bank?rgb1_q:rgb0_q;
 reg signed [7:0] act_a_q,act_b_q,weight_q;
 wire signed [7:0] act_q=layer==2?act_b_q:act_a_q;
 reg signed [31:0] bias_q;
 reg pad_q;
 reg signed [7:0] operand;
 always_comb begin
  if(layer==0)begin
   case(ic)
    0:operand=$signed(rgb_q[23:16]^8'h80);
    1:operand=$signed(rgb_q[15:8]^8'h80);
    default:operand=$signed(rgb_q[7:0]^8'h80);
   endcase
  end else operand=act_q;
  if(pad_q)operand=0;
 end
 reg signed [15:0] product;
 reg signed [31:0] acc;
 wire signed [31:0] shifted=acc >>> qshift;
 wire [7:0] clamped=shifted<0?8'd0:(shifted>127?8'd127:shifted[7:0]);
 reg signed [31:0] scores[0:4];
 reg signed [31:0] best_score;
 reg [2:0] best_class;
 // Native synchronous RAM/ROM ports; no reset loops over memories.
 always @(posedge clk)begin
  if(pixel_we)begin if(write_bank)input1[pixel_addr]<=pixel_rgb;else input0[pixel_addr]<=pixel_rgb;end
  rgb0_q<=input0[read_addr[9:0]];rgb1_q<=input1[read_addr[9:0]];
  act_a_q<=a[read_addr[11:0]];act_b_q<=b[read_addr[11:0]];
  weight_q<=weights[weight_addr];bias_q<=biases[bias_addr];
  if(state==STORE&&layer!=3)begin
   if(layer==1)b[write_addr[11:0]]<=clamped;else a[write_addr[11:0]]<=clamped;
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;busy<=0;done<=0;class_id<=5;result_count<=0;drop_count<=0;
   write_bank<=0;read_bank<=0;layer<=0;oc<=0;ic<=0;ox<=0;oy<=0;kx<=0;ky<=0;fcpos<=0;
   acc<=0;product<=0;pad_q<=0;best_score<=-32'sd2147483647;best_class<=0;
  end else begin
   done<=0;
   if(frame_valid&&busy&&drop_count!=255)drop_count<=drop_count+1'b1;
   case(state)
    IDLE:if(frame_valid)begin
     read_bank<=write_bank;write_bank<=~write_bank;busy<=1;layer<=0;oc<=0;ic<=0;
     ox<=0;oy<=0;kx<=0;ky<=0;fcpos<=0;best_score<=-32'sd2147483647;best_class<=0;state<=INIT;
    end
    INIT:state<=BIAS;
    BIAS:begin acc<=bias_q;state<=ADDR;end
    ADDR:begin pad_q<=pad;state<=MUL;end
    MUL:begin product<=operand*weight_q;state<=ACC;end
    ACC:begin
     acc<=acc+{{16{product[15]}},product};
     if(layer==3)begin
      if(fcpos==15)begin fcpos<=0;if(ic==inch-1)begin ic<=0;state<=STORE;end else begin ic<=ic+1'b1;state<=ADDR;end end
      else begin fcpos<=fcpos+1'b1;state<=ADDR;end
     end else if(kx==2)begin
      kx<=0;
      if(ky==2)begin ky<=0;if(ic==inch-1)begin ic<=0;state<=STORE;end else begin ic<=ic+1'b1;state<=ADDR;end end
      else begin ky<=ky+1'b1;state<=ADDR;end
     end else begin kx<=kx+1'b1;state<=ADDR;end
    end
    STORE:begin
     if(layer==3)begin
      scores[oc]<=acc;
      if(acc>best_score)begin best_score<=acc;best_class<=oc[2:0];end
      if(oc==4)begin class_id<=(acc>best_score)?oc[2:0]:best_class;result_count<=result_count+1'b1;done<=1;busy<=0;state<=IDLE;end
      else begin oc<=oc+1'b1;state<=INIT;end
     end else begin
      state<=INIT;
      if(ox==ow-1)begin
       ox<=0;
       if(oy==ow-1)begin oy<=0;if(oc==outch-1)begin oc<=0;layer<=layer+1'b1;end else oc<=oc+1'b1;end
       else oy<=oy+1'b1;
      end else ox<=ox+1'b1;
     end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
