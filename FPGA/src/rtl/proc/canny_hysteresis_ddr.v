`timescale 1ns/1ps
// Convert frame labels to a compact 2-bit map, converge exactly there, then
// update only the original RGB32 high bytes. Scratch is outside live/slot/video
// regions. One frame owns it until completion. RGB bytes are never rewritten.
module canny_hysteresis_ddr #(
 parameter W=1920,H=1080,DW=128,AW=32,BURST_BEATS=128,
 parameter [AW-1:0] SCRATCH_BASE=32'h0b000000
)(
 input wire clk,rst_n,start,input wire [AW-1:0] base_addr,
 output reg busy,done,failed,output wire [31:0] passes,
 output wire [AW-1:0] araddr,output wire [7:0] arlen,output wire arvalid,input wire arready,
 input wire [DW-1:0] rdata,input wire rvalid,rlast,input wire [1:0] rresp,output wire rready,
 output wire [AW-1:0] awaddr,output wire [7:0] awlen,output wire awvalid,input wire awready,
 output wire [DW-1:0] wdata,output wire [DW/8-1:0] wstrb,
 output wire wvalid,wlast,input wire wready,input wire bvalid,input wire [1:0] bresp,output wire bready
);
 localparam FRAME_WORDS=W*H/4;
 localparam IDLE=0,E_SET=1,E_AR=2,E_READ=3,E_AWSET=4,E_AW=5,E_WRITE=6,E_B=7,
  H_START=8,H_RUN=9,M_SET=10,M_PAR=11,M_PREAD=12,M_ARSET=13,M_AR=14,M_READ=15,
  M_AWSET=16,M_AW=17,M_PREF=18,M_LATCH=19,M_WRITE=20,M_B=21;
 reg [4:0] state=IDLE;
 reg [AW-1:0] base=0,index=0;
 reg [8:0] chunk=0;
 reg [7:0] beat=0;
 reg io_error=0;
 reg [127:0] pack_shift=0,map_buf[0:7];
 reg [31:0] meta_mem[0:127];
 reg [6:0] meta_addr=0;
 reg [31:0] meta_q;
 reg [AW-1:0] xaraddr=0,xawaddr=0;
 reg [7:0] xarlen=0,xawlen=0;
 reg xarvalid=0,xawvalid=0,xwvalid=0,xwlast=0;
 reg [127:0] xwdata=0;
 wire [8:0] remaining_chunk=(FRAME_WORDS-index>128)?9'd128:FRAME_WORDS-index;
 wire [4:0] map_words=chunk>>4;
 function [7:0] labels(input [127:0] v);
  integer n;begin for(n=0;n<4;n=n+1)labels[n*2+:2]=v[n*32+30+:2];end
 endfunction
 function [31:0] merged_meta(input [127:0] v,input [127:0] bits,input [3:0] subword);
  integer n;begin for(n=0;n<4;n=n+1)begin
   merged_meta[n*8+:8]=v[n*32+24+:8];
   merged_meta[n*8+7]=bits[subword*8+n*2+1];
  end end
 endfunction
 function [127:0] byte_words(input [31:0] v);
  integer n;begin byte_words=0;for(n=0;n<4;n=n+1)byte_words[n*32+24+:8]=v[n*8+:8];end
 endfunction
 always @(posedge clk)begin
  meta_q<=meta_mem[meta_addr];
  if(state==M_READ&&rvalid)meta_mem[beat[6:0]]<=merged_meta(rdata,map_buf[beat[6:4]],beat[3:0]);
 end
 wire use_h=(state==H_START)||(state==H_RUN);
 wire hbusy,hdone,hfailed,harvalid,hawvalid,hwvalid,hwlast,hrready,hbready;
 wire [AW-1:0] haraddr,hawaddr;wire [7:0] harlen,hawlen;
 wire [DW-1:0] hwdata;wire [DW/8-1:0] hwstrb;
 canny_hysteresis_bitmap #(.W(W),.H(H),.DW(DW),.AW(AW)) bitmap(
  .clk(clk),.rst_n(rst_n),.start(state==H_START),.base_addr(SCRATCH_BASE),
  .busy(hbusy),.done(hdone),.failed(hfailed),.passes(passes),
  .araddr(haraddr),.arlen(harlen),.arvalid(harvalid),.arready(arready&&use_h),
  .rdata(rdata),.rvalid(rvalid&&use_h),.rlast(rlast),.rresp(rresp),.rready(hrready),
  .awaddr(hawaddr),.awlen(hawlen),.awvalid(hawvalid),.awready(awready&&use_h),
  .wdata(hwdata),.wstrb(hwstrb),.wvalid(hwvalid),.wlast(hwlast),.wready(wready&&use_h),
  .bvalid(bvalid&&use_h),.bresp(bresp),.bready(hbready));
 assign araddr=use_h?haraddr:xaraddr;assign arlen=use_h?harlen:xarlen;assign arvalid=use_h?harvalid:xarvalid;
 assign awaddr=use_h?hawaddr:xawaddr;assign awlen=use_h?hawlen:xawlen;assign awvalid=use_h?hawvalid:xawvalid;
 assign wdata=use_h?hwdata:xwdata;assign wvalid=use_h?hwvalid:xwvalid;assign wlast=use_h?hwlast:xwlast;
 assign wstrb=use_h?hwstrb:((state==E_WRITE)?16'hffff:16'h8888);
 assign rready=use_h?hrready:((state==E_READ)||(state==M_PREAD)||(state==M_READ));
 assign bready=use_h?hbready:((state==E_B)||(state==M_B));
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;base<=0;index<=0;chunk<=0;beat<=0;io_error<=0;
   busy<=0;done<=0;failed<=0;pack_shift<=0;meta_addr<=0;
   xaraddr<=0;xawaddr<=0;xarlen<=0;xawlen<=0;xarvalid<=0;xawvalid<=0;xwvalid<=0;xwlast<=0;xwdata<=0;
  end else begin
   done<=0;failed<=0;
   case(state)
    IDLE:if(start)begin base<=base_addr;index<=0;busy<=1;io_error<=0;state<=E_SET;end
    E_SET:begin chunk<=remaining_chunk;xaraddr<=base+index*16;xarlen<=remaining_chunk-1'b1;xarvalid<=1;state<=E_AR;end
    E_AR:if(arready)begin xarvalid<=0;beat<=0;pack_shift<=0;state<=E_READ;end
    E_READ:if(rvalid)begin
     pack_shift<={labels(rdata),pack_shift[127:8]};
     if(beat[3:0]==15)map_buf[beat[6:4]]<={labels(rdata),pack_shift[127:8]};
     if(rresp!=0||rlast!=(beat==chunk-1))io_error<=1;
     if(rlast)begin
      if(io_error||rresp!=0||beat!=chunk-1)begin failed<=1;busy<=0;state<=IDLE;end
      else state<=E_AWSET;
     end else beat<=beat+1'b1;
    end
    E_AWSET:begin xawaddr<=SCRATCH_BASE+index;xawlen<=map_words-1'b1;xawvalid<=1;state<=E_AW;end
    E_AW:if(awready)begin xawvalid<=0;beat<=0;xwdata<=map_buf[0];xwvalid<=1;xwlast<=(map_words==1);state<=E_WRITE;end
    E_WRITE:if(wready)begin
     if(xwlast)begin xwvalid<=0;state<=E_B;end
     else begin beat<=beat+1'b1;xwdata<=map_buf[beat+1'b1];xwlast<=(beat+1'b1==map_words-1);end
    end
    E_B:if(bvalid)begin
     if(bresp!=0)begin failed<=1;busy<=0;state<=IDLE;end
     else if(index+chunk==FRAME_WORDS)state<=H_START;
     else begin index<=index+chunk;state<=E_SET;end
    end
    H_START:state<=H_RUN;
    H_RUN:begin
     if(hfailed)begin failed<=1;busy<=0;state<=IDLE;end
     else if(hdone)begin index<=0;state<=M_SET;end
    end
    M_SET:begin chunk<=remaining_chunk;xaraddr<=SCRATCH_BASE+index;xarlen<=(remaining_chunk>>4)-1'b1;xarvalid<=1;state<=M_PAR;end
    M_PAR:if(arready)begin xarvalid<=0;beat<=0;state<=M_PREAD;end
    M_PREAD:if(rvalid)begin
     map_buf[beat]<=rdata;
     if(rresp!=0||rlast!=(beat==map_words-1))io_error<=1;
     if(rlast)begin
      if(io_error||rresp!=0||beat!=map_words-1)begin failed<=1;busy<=0;state<=IDLE;end
      else state<=M_ARSET;
     end else beat<=beat+1'b1;
    end
    M_ARSET:begin xaraddr<=base+index*16;xarlen<=chunk-1'b1;xarvalid<=1;state<=M_AR;end
    M_AR:if(arready)begin xarvalid<=0;beat<=0;state<=M_READ;end
    M_READ:if(rvalid)begin
     if(rresp!=0||rlast!=(beat==chunk-1))io_error<=1;
     if(rlast)begin
      if(io_error||rresp!=0||beat!=chunk-1)begin failed<=1;busy<=0;state<=IDLE;end
      else state<=M_AWSET;
     end else beat<=beat+1'b1;
    end
    M_AWSET:begin xawaddr<=base+index*16;xawlen<=chunk-1'b1;xawvalid<=1;state<=M_AW;end
    M_AW:if(awready)begin xawvalid<=0;beat<=0;meta_addr<=0;state<=M_PREF;end
    M_PREF:state<=M_LATCH;
    M_LATCH:begin xwdata<=byte_words(meta_q);xwvalid<=1;xwlast<=(beat==chunk-1);state<=M_WRITE;end
    M_WRITE:if(wready)begin
     xwvalid<=0;
     if(xwlast)state<=M_B;
     else begin beat<=beat+1'b1;meta_addr<=beat+1'b1;state<=M_PREF;end
    end
    M_B:if(bvalid)begin
     if(bresp!=0)begin failed<=1;busy<=0;state<=IDLE;end
     else if(index+chunk==FRAME_WORDS)begin done<=1;busy<=0;state<=IDLE;end
     else begin index<=index+chunk;state<=M_SET;end
    end
    default:begin failed<=1;busy<=0;state<=IDLE;end
   endcase
  end
 end
endmodule
