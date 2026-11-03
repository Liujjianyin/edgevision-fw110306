`timescale 1ns/1ps
// Packed scratch image: two bits per pixel {accepted,candidate}. Exact
// bidirectional 8-neighbor sweeps until no change; 64 pixels per word.
// W is a multiple of 64. No RGB data is scanned during repeated sweeps.
module canny_hysteresis_bitmap #(
 parameter W=1920,H=1080,DW=128,AW=32,BURST_BEATS=128
)(
 input wire clk,rst_n,start,input wire [AW-1:0] base_addr,
 output reg busy,done,failed,output reg [31:0] passes,
 output reg [AW-1:0] araddr,output reg [7:0] arlen,output reg arvalid,input wire arready,
 input wire [DW-1:0] rdata,input wire rvalid,rlast,input wire [1:0] rresp,output wire rready,
 output reg [AW-1:0] awaddr,output reg [7:0] awlen,output reg awvalid,input wire awready,
 output reg [DW-1:0] wdata,output wire [DW/8-1:0] wstrb,
 output reg wvalid,wlast,input wire wready,input wire bvalid,input wire [1:0] bresp,output wire bready
);
 localparam LANES=DW/2,ROW_WORDS=W/LANES,MW=DW,LEVELS=$clog2(LANES);
 localparam IX=(ROW_WORDS>1)?$clog2(ROW_WORDS):1;
 localparam S_IDLE=0,S_LOAD=1,S_RADDR=2,S_RDATA=3,S_ZERO=4,
  S_FIRST=5,S_WAIT_L=6,S_LATCH_L=7,S_WAIT_C=8,S_LATCH_C=9,S_WAIT_R=10,S_LATCH_R=11,
  S_CALC=12,S_SHIFT_WAIT=13,S_SHIFT_LOAD=14,S_WRITE=15,S_WADDR=16,
  S_WWAIT=17,S_WLATCH=18,S_WDATA=19,S_BRESP=20,S_NEXT_ROW=21;
 reg [4:0] state;
 reg [AW-1:0] base;
 reg reverse,changed,io_error;
 reg [15:0] row;
 reg [1:0] load_sel;
 reg [IX:0] offset,beat,chunk;
 reg [IX-1:0] word_index,read_addr,out_addr;
 reg [MW-1:0] up_mem[0:ROW_WORDS-1],mid_mem[0:ROW_WORDS-1],down_mem[0:ROW_WORDS-1],out_mem[0:ROW_WORDS-1];
 reg [MW-1:0] uq,mq,dq,oq,ul,uc,ur,ml,mc,mr,dl,dc,dr;
 reg carry;
 wire [MW*3-1:0] ux={ur,uc,ul},mx={mr,mc,ml},dx={dr,dc,dl};
 wire [MW-1:0] calculated;
 wire [LANES-1:0] original,physical_g,physical_p,ordered_g,ordered_p,accepted;
 wire [LANES-1:0] pg[0:LEVELS],pp[0:LEVELS];
 assign pg[0]=ordered_g;assign pp[0]=ordered_p;
 genvar pixel,lev,ix;
 generate for(pixel=0;pixel<LANES;pixel=pixel+1)begin:pixel_logic
  wire left_ok=(word_index!=0)||(pixel!=0);
  wire right_ok=(word_index!=ROW_WORDS-1)||(pixel!=LANES-1);
  wire neighbor=((row!=0)&&(ux[(LANES+pixel)*2+1]||
      (left_ok&&ux[(LANES+pixel-1)*2+1])||(right_ok&&ux[(LANES+pixel+1)*2+1])))||
    ((row!=H-1)&&(dx[(LANES+pixel)*2+1]||
      (left_ok&&dx[(LANES+pixel-1)*2+1])||(right_ok&&dx[(LANES+pixel+1)*2+1])))||
    (left_ok&&mx[(LANES+pixel-1)*2+1])||(right_ok&&mx[(LANES+pixel+1)*2+1]);
  assign original[pixel]=mc[pixel*2+1];
  assign physical_g[pixel]=original[pixel]|(mc[pixel*2]&neighbor);
  assign physical_p[pixel]=mc[pixel*2];
  assign ordered_g[pixel]=reverse?physical_g[LANES-1-pixel]:physical_g[pixel];
  assign ordered_p[pixel]=reverse?physical_p[LANES-1-pixel]:physical_p[pixel];
  assign accepted[pixel]=pg[LEVELS][pixel]|(pp[LEVELS][pixel]&carry);
  assign calculated[pixel*2]=mc[pixel*2];
  assign calculated[pixel*2+1]=reverse?accepted[LANES-1-pixel]:accepted[pixel];
 end
 // Parallel prefix computes the exact sequential horizontal propagation in
 // log2(64) logic levels, including arbitrary-length runs within a DDR beat.
 for(lev=0;lev<LEVELS;lev=lev+1)begin:prefix_level
  for(ix=0;ix<LANES;ix=ix+1)begin:prefix_bit
   if(ix>=(1<<lev))begin
    assign pg[lev+1][ix]=pg[lev][ix]|(pp[lev][ix]&pg[lev][ix-(1<<lev)]);
    assign pp[lev+1][ix]=pp[lev][ix]&pp[lev][ix-(1<<lev)];
   end else begin assign pg[lev+1][ix]=pg[lev][ix];assign pp[lev+1][ix]=pp[lev][ix];end
  end
 end endgenerate
 wire [LANES-1:0] physical_accepted=reverse?reverse_bits(accepted):accepted;
 function [LANES-1:0] reverse_bits(input [LANES-1:0] value);
  integer n;begin for(n=0;n<LANES;n=n+1)reverse_bits[n]=value[LANES-1-n];end
 endfunction
 wire any_change=|(physical_accepted^original);
 wire next_carry=accepted[LANES-1];
 wire [15:0] load_row=(load_sel==0)?row-1'b1:(load_sel==1)?row:row+1'b1;
 wire boundary=((load_sel==0)&&(row==0))||((load_sel==2)&&(row==H-1));
 wire [AW-1:0] transfer_addr=base+((state==S_LOAD)?load_row:row)*ROW_WORDS*(DW/8)+offset*(DW/8);
 wire [8:0] boundary_beats=9'd256-{1'b0,transfer_addr[11:4]};
 wire [IX:0] limited_chunk=((ROW_WORDS-offset)>BURST_BEATS)?BURST_BEATS:(ROW_WORDS-offset);
 wire [IX:0] chunk_size=(limited_chunk>boundary_beats)?boundary_beats:limited_chunk;
 wire last_load=(!reverse && load_sel==2)||(reverse && load_sel==1);
 function [MW-1:0] metadata(input [DW-1:0] v);metadata=v;endfunction
 function [DW-1:0] byte_words(input [MW-1:0] v);byte_words=v;endfunction
 assign wstrb={DW/8{1'b1}};
 assign rready=(state==S_RDATA);
 assign bready=(state==S_BRESP);
 // A single synchronous read port per row RAM, shared by all three fetches.
 always @(posedge clk)begin uq<=up_mem[read_addr];mq<=mid_mem[read_addr];dq<=down_mem[read_addr];oq<=out_mem[out_addr];end
 always @(posedge clk)begin
  if(state==S_RDATA && rvalid)begin
   case(load_sel)
    0:up_mem[offset+beat]<=metadata(rdata);
    1:mid_mem[offset+beat]<=metadata(rdata);
    2:down_mem[offset+beat]<=metadata(rdata);
   endcase
  end
  if(state==S_ZERO)begin
   if(load_sel==0)up_mem[offset]<=0;else down_mem[offset]<=0;
  end
  if(state==S_CALC)out_mem[word_index]<=calculated;
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=S_IDLE;base<=0;busy<=0;done<=0;failed<=0;passes<=0;
   araddr<=0;arlen<=0;arvalid<=0;awaddr<=0;awlen<=0;awvalid<=0;
   wdata<=0;wvalid<=0;wlast<=0;reverse<=0;changed<=0;io_error<=0;
   row<=0;load_sel<=0;offset<=0;beat<=0;chunk<=0;word_index<=0;read_addr<=0;out_addr<=0;carry<=0;
   ul<=0;uc<=0;ur<=0;ml<=0;mc<=0;mr<=0;dl<=0;dc<=0;dr<=0;
  end else begin
   done<=0;failed<=0;
   case(state)
     S_IDLE:if(start)begin base<=base_addr;busy<=1;passes<=0;reverse<=0;changed<=0;io_error<=0;row<=0;load_sel<=0;offset<=0;state<=S_LOAD;end
    S_LOAD:begin
      if(boundary)state<=S_ZERO;
     else begin araddr<=transfer_addr;arlen<=chunk_size-1'b1;chunk<=chunk_size;arvalid<=1;state<=S_RADDR;end
    end
    S_RADDR:if(arready)begin arvalid<=0;beat<=0;state<=S_RDATA;end
    S_RDATA:if(rvalid)begin
     if(rresp!=0 || rlast!=(beat==chunk-1))io_error<=1;
     if(rlast)begin
      if(io_error||rresp!=0||beat!=chunk-1)begin busy<=0;failed<=1;state<=S_IDLE;end
      else if(offset+chunk==ROW_WORDS)begin
       offset<=0;
       if(last_load)state<=S_FIRST;else begin load_sel<=load_sel+1'b1;state<=S_LOAD;end
      end else begin offset<=offset+chunk;state<=S_LOAD;end
     end else beat<=beat+1'b1;
    end
    S_ZERO:begin
      if(offset==ROW_WORDS-1)begin offset<=0;if(last_load)state<=S_FIRST;else begin load_sel<=load_sel+1'b1;state<=S_LOAD;end end
     else offset<=offset+1'b1;
    end
     S_FIRST:begin word_index<=reverse?ROW_WORDS-1:0;read_addr<=(reverse&&ROW_WORDS>1)?ROW_WORDS-2:0;carry<=0;state<=S_WAIT_L;end
    S_WAIT_L:state<=S_LATCH_L;
    S_LATCH_L:begin ul<=uq;ml<=mq;dl<=dq;read_addr<=word_index;state<=S_WAIT_C;end
    S_WAIT_C:state<=S_LATCH_C;
    S_LATCH_C:begin uc<=uq;mc<=mq;dc<=dq;read_addr<=(word_index==ROW_WORDS-1)?word_index:word_index+1'b1;state<=S_WAIT_R;end
    S_WAIT_R:state<=S_LATCH_R;
    S_LATCH_R:begin ur<=uq;mr<=mq;dr<=dq;state<=S_CALC;end
     S_CALC:begin
      changed<=changed|any_change;carry<=next_carry;
      // Reuse the just-calculated row as the vertical neighbor in the next
      // row of the same directional sweep. Boundary guards make stale edge
      // contents harmless; fixed-point iteration remains exact.
      if(!reverse)up_mem[word_index]<=calculated;
      else down_mem[word_index]<=calculated;
     if((!reverse&&word_index==ROW_WORDS-1)||(reverse&&word_index==0))begin offset<=0;state<=S_WRITE;end
     else begin
      if(!reverse)begin ul<=uc;ml<=mc;dl<=dc;uc<=ur;mc<=mr;dc<=dr;word_index<=word_index+1'b1;read_addr<=(word_index>=ROW_WORDS-2)?ROW_WORDS-1:word_index+2;end
      else begin ur<=uc;mr<=mc;dr<=dc;uc<=ul;mc<=ml;dc<=dl;word_index<=word_index-1'b1;read_addr<=(word_index<2)?0:word_index-2;end
      state<=S_SHIFT_WAIT;
     end
    end
    S_SHIFT_WAIT:state<=S_SHIFT_LOAD;
    S_SHIFT_LOAD:begin
     if(!reverse)begin ur<=uq;mr<=mq;dr<=dq;end else begin ul<=uq;ml<=mq;dl<=dq;end
     state<=S_CALC;
    end
    S_WRITE:begin awaddr<=transfer_addr;awlen<=chunk_size-1'b1;chunk<=chunk_size;awvalid<=1;state<=S_WADDR;end
    S_WADDR:if(awready)begin awvalid<=0;beat<=0;out_addr<=offset;state<=S_WWAIT;end
    S_WWAIT:state<=S_WLATCH;
    S_WLATCH:begin wdata<=byte_words(oq);wvalid<=1;wlast<=(beat==chunk-1);state<=S_WDATA;end
    S_WDATA:if(wready)begin
     wvalid<=0;
     if(wlast)state<=S_BRESP;
     else begin beat<=beat+1'b1;out_addr<=offset+beat+1'b1;state<=S_WWAIT;end
    end
    S_BRESP:if(bvalid)begin
     if(bresp!=0)begin busy<=0;failed<=1;state<=S_IDLE;end
     else if(offset+chunk==ROW_WORDS)state<=S_NEXT_ROW;
     else begin offset<=offset+chunk;state<=S_WRITE;end
    end
    S_NEXT_ROW:begin
     if((!reverse&&row==H-1)||(reverse&&row==0))begin
      if(passes!=32'hffffffff)passes<=passes+1'b1;
      if(!changed)begin busy<=0;done<=1;state<=S_IDLE;end
       else begin reverse<=~reverse;changed<=0;load_sel<=0;offset<=0;state<=S_LOAD;end
      end else begin row<=reverse?row-1'b1:row+1'b1;load_sel<=reverse?0:1;offset<=0;state<=S_LOAD;end
    end
    default:begin state<=S_IDLE;busy<=0;failed<=1;end
   endcase
  end
 end
endmodule
