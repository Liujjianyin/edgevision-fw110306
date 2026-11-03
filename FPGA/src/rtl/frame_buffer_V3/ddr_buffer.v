

`timescale 1ps/1ps
module ddr_buffer #(
parameter AXI_DATA_WIDTH = 512, //!AXI接口位宽
parameter AXI_ADDR_WIDTH = 33,  //!AXI地址位宽
parameter WR_FIFO_DEPTH	= 1024, //!Write fifo depth   
parameter RD_FIFO_DEPTH = 1024, //!read fifo depth
parameter FB_NUM			= 	3,//2 buffer ,3 buffer   
parameter MAX_VID_WIDTH		=	1920 ,//video width 
parameter MAX_VID_HIGHT		=	1080 ,//wideo height
parameter START_ADDR				=	33'h000201900,
parameter BURST_LEN       = 8'd15,
parameter I_VID_WIDTH = 16,
parameter FULL_CANNY = 0,
parameter AXI_STRB_WIDTH = AXI_DATA_WIDTH/8//!总共的字节数量，= AXI_DATA_WIDTH/8

) (

input 											axi_clk,
input                       wr_clk_rst_n,
input                       axi_clk_rst_n,
input                       rd_clk_rst_n,
input 											rd_start,
input											wr_start, // pulse signal
input                       rd_hold_i,  // 1 = freeze the picture (read bank stops)
input                       wr_hold_i,  // 1 = save: lock the three banks (write side stops)
input                       wr_addr_en, // 1 = use wr_addr_ovr as the write start address
input      [31:0]           wr_addr_ovr,
input                       rd_addr_en, // 1 = use rd_addr_ovr as the read start address
input      [31:0]           rd_addr_ovr,
input                       step_i,     // 1-cycle pulse: advance one bank
input      [1:0]            auto_mode,  // 0 = off, 1 = blink compare, 2 = playback 

// input		[AXI_ADDR_WIDTH-1:0]				start_wr_addr,
// input		[AXI_ADDR_WIDTH-1:0]				start_rd_addr,
input 		[31:0] 								wr_busrt_len,
input 		[31:0] 								rd_burst_len,
output		[7:0] test_cnt ,
output                      wr_frame_done,  // 1-cycle pulse: a frame was fully written
output                      rd_frame_done,  // 1-cycle pulse: a frame was fully read
output wire [15:0]           debug_writer,
output wire capture_busy,
input wire capture_bad,
input wire capture_good,
output wire [31:0] canny_passes,
output reg [7:0] canny_failures=0,
input wire [1:0] bresp,

input                     wr_fifo_rst_p,
input											wr_fifo_wrclk,
input											wr_fifo_wren,
output											wr_fifo_wrfull,
input	 [AXI_DATA_WIDTH-1:0]					wr_fifo_wrdata, 
input											rd_fifo_rdclk,
input                       rd_fifo_rst_p,
output											rd_fifo_rdvalid,
output	 [AXI_DATA_WIDTH-1:0] 					rd_fifo_rddata,
output wire										rd_fifo_rdempty,
input	 wire									rd_fifo_rden,

output 	[5:0] 									awid,
output  [AXI_ADDR_WIDTH-1:0] 					awaddr,
output  [8-1:0] 					awlen,
output  [2:0] 									awsize,
output  [1:0] 									awburst,
output  [3:0] 									awcache,
output [2:0]                    awprot,
output  										awlock,
output  										awvalid,
output  										awcobuf,
output  										awapcmd,
output  										awallstrb,
output  										awqos,
input 											awready,

output [5:0] 									arid,
output  [AXI_ADDR_WIDTH-1:0] 					araddr,
output  [8-1:0] 					arlen,
output  [2:0] 									arsize,
output  [1:0] 									arburst,
output  										arlock,
output  										arvalid,
output  										arapcmd,
output 											arqos,
input 											arready,
output  [3:0] 									arcache,
output [2:0]                    arprot,
output  [AXI_DATA_WIDTH-1:0] 					wdata,  
output	[31:0]									test_wdata,
output	[31:0]									test_rdata,
output  [AXI_STRB_WIDTH-1:0] 					wstrb,
output  										wlast,
output  										wvalid,
input 											wready,

input [5:0] 									rid,
input [AXI_DATA_WIDTH-1:0] 						rdata,
input 											rlast,
input 											rvalid,
output  										rready,
input [1:0] 									rresp,
output[31:0]									wr_fifo_rd_data_test,
input [5:0] 									bid,
input 											bvalid,
output  										bready,

output [7:0] test_BURST_LEN
);
assign test_BURST_LEN = BURST_LEN;

wire [AXI_ADDR_WIDTH-1:0] raw_awaddr,raw_araddr,full_awaddr,full_araddr;
wire [7:0] raw_awlen,raw_arlen,full_awlen,full_arlen;
wire raw_awvalid,raw_awready,raw_wvalid,raw_wlast,raw_wready,raw_bvalid,raw_bready;
wire raw_arvalid,raw_arready,raw_rvalid,raw_rlast,raw_rready;
wire full_awvalid,full_awready,full_wvalid,full_wlast,full_wready,full_bvalid,full_bready;
wire full_arvalid,full_arready,full_rvalid,full_rlast,full_rready;
wire [AXI_DATA_WIDTH-1:0] raw_wdata,full_wdata;
wire [AXI_STRB_WIDTH-1:0] raw_wstrb,full_wstrb;



//=============================================================
//reg define 
//=============================================================   


//=============================================================
//wire define 
//============================================================= 



wire		                        wr_sw_ack           ;
wire		                        wr_sw 		          ;
wire		                        rd_sw			          ;
wire		                        rd_sw_ack           ;
// ---- host-controlled bank hold / step ---------------------------------

// ---- automatic bank advance while frozen -----------------------------
//   auto_mode 1 = blink compare : one bank change every 0.4 s  (find differences)
//   auto_mode 2 = playback      : one bank change every 80 ms  (~12 fps loop
//                                 through the three frames held in DDR3)
localparam integer BLINK_PERIOD = 40_000_000;   // 0.4 s  @ 100 MHz
localparam integer PLAY_PERIOD  =  8_000_000;   // 80 ms  @ 100 MHz

reg [25:0] auto_cnt;
reg        auto_step;

always @(posedge axi_clk or negedge axi_clk_rst_n) begin
    if (!axi_clk_rst_n) begin
        auto_cnt  <= 26'd0;
        auto_step <= 1'b0;
    end else if (!rd_hold_i || (auto_mode == 2'd0)) begin
        auto_cnt  <= 26'd0;
        auto_step <= 1'b0;
    end else if (auto_cnt >= ((auto_mode == 2'd2) ? PLAY_PERIOD : BLINK_PERIOD)) begin
        auto_cnt  <= 26'd0;
        auto_step <= 1'b1;
    end else begin
        auto_cnt  <= auto_cnt + 26'd1;
        auto_step <= 1'b0;
    end
end

wire step_any = step_i | auto_step;

// freeze also locks the WRITE bank: without this the camera keeps
// overwriting the three banks and "playback" would loop a moving window

// Saving is done on a FRAME BOUNDARY: wr_start is the per-frame pulse that kicks
// off a new DDR write sequence. Blocking it lets the frame in flight finish
// normally and then stops writing altogether - no half-written frames, and the
// data path is never starved, so nothing can write garbage.

// address override: a capture / playback just points the existing engines at a
// different DDR region, the data path itself is untouched
wire [AXI_ADDR_WIDTH-1:0] wr_start_addr,rd_start_addr;
wire [1:0] wr_bank,rd_bank;
wire [31:0] wr_start_addr_f = wr_addr_en ? wr_addr_ovr : wr_start_addr;
wire [31:0] rd_start_addr_f = rd_addr_en ? rd_addr_ovr : rd_start_addr;

reg [1:0] wr_mode_sync;
reg processing=0,abort_pending=0,soft_abort=0,capture_error=0;
reg raw_complete=0,capture_valid=0;
wire wr_dma_done,full_done,full_failed,full_busy,dma_idle;
wire wr_start_g=wr_start & ~wr_hold_i & (!FULL_CANNY || !processing);
assign capture_busy=FULL_CANNY && processing;
reg [31:0] processing_base;
wire [31:0] full_passes;
assign canny_passes=full_passes;
wire full_start=processing&&raw_complete&&capture_valid&&!abort_pending&&!capture_bad&&!capture_error;
always @(posedge axi_clk or negedge axi_clk_rst_n)begin
 if(!axi_clk_rst_n)begin processing<=0;abort_pending<=0;soft_abort<=0;processing_base<=0;capture_error<=0;raw_complete<=0;capture_valid<=0;canny_failures<=0;end
 else if(FULL_CANNY)begin
  soft_abort<=0;
  if(wr_start_g)begin processing<=1;capture_error<=0;raw_complete<=0;capture_valid<=0;end
  if(wr_dma_done)raw_complete<=1;
  if(capture_good)capture_valid<=1;
  if(full_start)raw_complete<=0;
  if(wr_mode_sync==2'b01)processing_base<=wr_start_addr_f;
  if(capture_bad)abort_pending<=1;
  if(raw_bvalid&&bresp!=0)begin capture_error<=1;abort_pending<=1;end
  if(abort_pending&&dma_idle&&!full_busy)begin soft_abort<=1;processing<=0;abort_pending<=0;canny_failures<=canny_failures+1'b1;end
  if(full_done||full_failed)processing<=0;
  if(full_failed)canny_failures<=canny_failures+1'b1;
 end
end
assign wr_sw=FULL_CANNY?(full_done&&!abort_pending&&!capture_bad):wr_dma_done;


// the write engine's own frame boundary - capturing on this pulse is
// exact, unlike the camera vsync which is offset from the write path
assign wr_frame_done = wr_sw;
assign rd_frame_done = rd_sw;

// Latch ownership at the same start edge used by each AXI engine.
// A host command may change the override while a complete frame is in flight.

reg [2:0] rd_mode_sync;
reg wr_override_active,rd_override_active;
always @(posedge axi_clk or negedge axi_clk_rst_n) begin
    if(!axi_clk_rst_n) begin
        wr_mode_sync<=0;rd_mode_sync<=0;
        wr_override_active<=0;rd_override_active<=0;
    end else begin
        wr_mode_sync<={wr_mode_sync[0],wr_start_g};
        rd_mode_sync<={rd_mode_sync[1:0],rd_start};
        if(wr_mode_sync==2'b01)wr_override_active<=wr_addr_en;
        if(rd_mode_sync[1:0]==2'b01)rd_override_active<=rd_addr_en;
    end
end
wire wr_sw_step  = (wr_hold_i || wr_override_active) ? 1'b0 : wr_sw;
wire wr_sw_a_buf = wr_sw_ack | wr_hold_i;
wire rd_sw_step  = rd_override_active ? 1'b0 : (rd_hold_i ? step_any : rd_sw);
wire rd_sw_a_buf = rd_sw_ack | rd_hold_i;        // keep the read side running


 

//=============================================================  
//RTL                                                     
//=============================================================  



ddr_wr_buffer # (
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .WR_FIFO_DEPTH(WR_FIFO_DEPTH),
    .BURST_LEN (BURST_LEN        )
  )

  u_ddr_wr_buffer (//_inst
    .debug_writer(debug_writer),
    .idle_o(dma_idle),
    .axi_clk(axi_clk),
    .rst_n(axi_clk_rst_n & ~soft_abort),//(rst_n),
    .wr_start(wr_start_g),
    .start_addr(wr_start_addr_f),//(0),//
    .total_burst_len(wr_busrt_len[24:0]),
/*i*/.bank_sw_ack(wr_sw_a_buf),
/*o*/.bank_sw 		  (wr_dma_done),
    .test_cnt(test_cnt),
    .wr_fifo_rst_p(wr_fifo_rst_p),
    .wr_fifo_wrclk(wr_fifo_wrclk),
    .wr_fifo_wren(wr_fifo_wren),
    .wr_fifo_wrfull(wr_fifo_wrfull),
    .wr_fifo_wrdata(wr_fifo_wrdata),
    .awid(awid),
    .awaddr(raw_awaddr),
    .awlen(raw_awlen),
    .awsize(awsize),
    .awburst(awburst),
    .awcache(awcache),
    .awlock(awlock),
    .awvalid(raw_awvalid),
    .awcobuf(awcobuf),
    .awapcmd(awapcmd),
    .awallstrb(awallstrb),
    .awprot (awprot ),
    .awqos(awqos),
    .awready(raw_awready),
    .wdata(raw_wdata),
    .wstrb(raw_wstrb),
    .wlast(raw_wlast),
    .wvalid(raw_wvalid),
    .wready(raw_wready),
	  .bid	( bid			),
    .bvalid(raw_bvalid),
    .bready(raw_bready)
  );


assign test_wdata = wdata[31:0];
assign test_rdata = rdata[31:0];
//=============================================================================================
// FIFO RD_PROCESSING
//=============================================================================================
ddr_rd_buffer # (
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .RD_FIFO_DEPTH(RD_FIFO_DEPTH),
    .BURST_LEN (BURST_LEN        )
  )
  ddr_rd_buffer_inst (
    .axi_clk(axi_clk),
    .axi_clk_rst_n(axi_clk_rst_n),
    .start(rd_start),
    .start_addr(rd_start_addr_f),//(0),//
    .burst_len(rd_burst_len[24:0]),
    .rd_fifo_rdclk(rd_fifo_rdclk),
    .rd_fifo_rst_p (rd_fifo_rst_p),
    .rd_fifo_rdvalid(rd_fifo_rdvalid),
    .rd_fifo_rddata(rd_fifo_rddata),
    .rd_fifo_rdempty(rd_fifo_rdempty),
    .rd_fifo_rden(rd_fifo_rden),
/*i*/.bank_sw_ack(rd_sw_a_buf),
/*o*/.bank_sw 		  (rd_sw  		 	),
    .arid(arid),
    .araddr(raw_araddr),
    .arlen(raw_arlen),
    .arsize(arsize),
    .arburst(arburst),
    .arlock(arlock),
    .arvalid(raw_arvalid),
    .arapcmd(arapcmd),
    .arqos(arqos),
    .arready(raw_arready),
    .arprot (arprot ),
    .arcache(arcache),
    .rid(rid),
    .rdata(rdata),
    .rlast(raw_rlast),
    .rvalid(raw_rvalid),
    .rready(raw_rready),
    .rresp(rresp),
    .wr_fifo_rd_data_test(wr_fifo_rd_data_test)
  );
//===================================================================================== 
//
//===================================================================================== 
  


bank_switch #(
		.FB_NUM					( FB_NUM),
		.MAX_VID_WIDTH 	( MAX_VID_WIDTH),
		.MAX_VID_HIGHT 	( MAX_VID_HIGHT),
		.START_ADDR			(	START_ADDR 	),
		.VID_DATA_WIDTH	(I_VID_WIDTH	),
		.AXI_DATA_WIDTH (AXI_DATA_WIDTH )
)
  u_bank_sw
(
/*i*/.ddr_clk		(axi_clk	),
/*i*/.rst_n			(axi_clk_rst_n),
              	
/*i*/.wr_sw(wr_sw_step),
/*i*/.rd_sw(rd_sw_step),
                
/*o*/.wr_bank		(wr_bank	),
/*o*/.rd_bank		(rd_bank	),
/*o*/.rd_sw_ack	(rd_sw_ack),
/*o*/.wr_sw_ack (wr_sw_ack),
/*o*/.rd_start_addr(rd_start_addr),
/*o*/.wr_start_addr(wr_start_addr)
);



/*----------------------------------------------------------------------------------*\
                                 The function code
\*----------------------------------------------------------------------------------*/
function integer clogb2;
input [31:0] value;
begin
value = value - 1;
for (clogb2 = 0; value > 0; clogb2 = clogb2 + 1)
value = value >> 1;
end
endfunction

generate if(FULL_CANNY)begin: full_canny
 canny_hysteresis_ddr #(.W(MAX_VID_WIDTH),.H(MAX_VID_HIGHT),.DW(AXI_DATA_WIDTH),.AW(AXI_ADDR_WIDTH)) hysteresis(
 .clk(axi_clk),.rst_n(axi_clk_rst_n),.start(full_start),.base_addr(processing_base),
 .busy(full_busy),.done(full_done),.failed(full_failed),.passes(full_passes),
 .araddr(full_araddr),.arlen(full_arlen),.arvalid(full_arvalid),.arready(full_arready),
 .rdata(rdata),.rvalid(full_rvalid),.rlast(full_rlast),.rresp(rresp),.rready(full_rready),
 .awaddr(full_awaddr),.awlen(full_awlen),.awvalid(full_awvalid),.awready(full_awready),
 .wdata(full_wdata),.wstrb(full_wstrb),.wvalid(full_wvalid),.wlast(full_wlast),.wready(full_wready),
 .bvalid(full_bvalid),.bresp(bresp),.bready(full_bready));
 axi_frame_canny_mux #(.DW(AXI_DATA_WIDTH),.AW(AXI_ADDR_WIDTH)) bus_mux(
 .clk(axi_clk),.rst_n(axi_clk_rst_n),
 .a0(raw_awaddr),.al0(raw_awlen),.av0(raw_awvalid),.ay0(raw_awready),
 .wd0(raw_wdata),.ws0(raw_wstrb),.wv0(raw_wvalid),.wl0(raw_wlast),.wy0(raw_wready),.bv0(raw_bvalid),.by0(raw_bready),
 .r0(raw_araddr),.rl0(raw_arlen),.rv0(raw_arvalid),.ry0(raw_arready),.rdv0(raw_rvalid),.rdl0(raw_rlast),.rdy0(raw_rready),
 .a1(full_awaddr),.al1(full_awlen),.av1(full_awvalid),.ay1(full_awready),
 .wd1(full_wdata),.ws1(full_wstrb),.wv1(full_wvalid),.wl1(full_wlast),.wy1(full_wready),.bv1(full_bvalid),.by1(full_bready),
 .r1(full_araddr),.rl1(full_arlen),.rv1(full_arvalid),.ry1(full_arready),.rdv1(full_rvalid),.rdl1(full_rlast),.rdy1(full_rready),
 .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),
 .wdata(wdata),.wstrb(wstrb),.wvalid(wvalid),.wlast(wlast),.wready(wready),.bvalid(bvalid),.bready(bready),
 .araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),.rvalid(rvalid),.rlast(rlast),.rready(rready));
end else begin: original_path
 assign awaddr=raw_awaddr;assign awlen=raw_awlen;assign awvalid=raw_awvalid;assign raw_awready=awready;
 assign wdata=raw_wdata;assign wstrb=raw_wstrb;assign wlast=raw_wlast;assign wvalid=raw_wvalid;assign raw_wready=wready;
 assign raw_bvalid=bvalid;assign bready=raw_bready;
 assign araddr=raw_araddr;assign arlen=raw_arlen;assign arvalid=raw_arvalid;assign raw_arready=arready;
 assign raw_rvalid=rvalid;assign raw_rlast=rlast;assign rready=raw_rready;
 assign full_done=0;assign full_failed=0;assign full_busy=0;assign full_passes=0;
end endgenerate
endmodule
