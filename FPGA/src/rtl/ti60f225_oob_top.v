// Streaming Sobel / simplified local Canny, four-drink CNN, and DDR controls.
// Input/output: 1920x1080p60, 8-bit RGB, no HDCP or audio passthrough.
`include "ddr3_controller/ddr3_parameter.vh"
module ti60f225_oob_top #(

	parameter                       RANK_RATIO         = 1,       // # of unique CS outputs per rank
	parameter                       ASYN_AXI_CLK       = `ASYN_AXI_CLK, 
	parameter                       RANKS              = `RANKS,
	parameter                       CK_WIDTH           = `CK_WIDTH,       // # of CK/CK# outputs to memory   
	parameter                       CKE_WIDTH          = `CKE_WIDTH,       // # of cke outputs
	parameter                       CS_WIDTH           = `CS_WIDTH,       // # of unique CS outputs
	parameter                       BANK_WIDTH         = `BANK_WIDTH,       // # of bank bits
	parameter                       ROW_WIDTH          = `ROW_WIDTH,       // DRAM address bus width
	parameter                       COL_WIDTH          = `COL_WIDTH,      // column address width
	parameter                       DM_WIDTH           = `DM_WIDTH,       // # of DM (data mask)
	parameter                       DQS_WIDTH          = `DQS_WIDTH,       // # of DQS (strobe)
	parameter                       DQ_WIDTH           = `DQ_WIDTH,      // # of DQ (data)
	parameter                       ODT_WIDTH          = `ODT_WIDTH,
	parameter                       DQ_CNT_WIDTH       = `DQ_CNT_WIDTH,       // = ceil(log2(DQ_WIDTH))
	parameter                       DQS_CNT_WIDTH      = `DQS_CNT_WIDTH,       // = ceil(log2(DQS_WIDTH))  
	parameter                       DRAM_WIDTH         = `DRAM_WIDTH,       // # of DQ per DQS   
	parameter                       DATA_WIDTH         = `DATA_WIDTH,
	parameter                       ADDR_WIDTH         = `ADDR_WIDTH,    
	parameter                       AXI_ID_WIDTH       = `AXI_ID_WIDTH,
	parameter                       AXI_ADDR_WIDTH     = `AXI_ADDR_WIDTH,
	parameter                       AXI_DATA_WIDTH     = `AXI_DATA_WIDTH
)
(

  
input wire i_arstn, CLK_25M, hdmi_tx_slow_clk,
input wire i_pll_locked, pll_locked, user_pll_locked,
output wire pll_inst1_RSTN, USER_PLL_RSTN, DDR3_PLL_RSTN,
// Physical key_i pins remain in the board interface for pin compatibility.
// They are intentionally not consumed: all video, recognition, background,
// and DDR actions are accepted through the UART/PC command path below.
input wire [3:0] key_i,
input wire uart_rx,
output wire [3:0] led,
input 					tx_cal_clk_90edge,
  	input 					rx_cal_clk,
  	input 					tx_cal_clk,
	input                              core_clk,     // CORE CLK @ 100MHz
	input                              sdram_clk,    // SDRAM CK @ 400MHz
	// PLL status flags  
	output [2:0]                       pll_shift,  
	output [4:0]                       pll_shift_sel,
	output                             pll_shift_ena,  
	// memory interface ports
	output                             ddr_ck_hi,
	output                             ddr_ck_lo,
	output                             ddr_reset_n,
	output [CKE_WIDTH-1:0]             ddr_cke,     
	output [ROW_WIDTH-1:0]             ddr_addr,
	output [BANK_WIDTH-1:0]            ddr_ba,
	output                             ddr_cas_n,
 
	output [CS_WIDTH*RANK_RATIO-1:0]   ddr_cs_n,
	output                             ddr_ras_n,
	output                             ddr_we_n,
	
	input  [DQS_WIDTH-1:0]             ddr_dqs_in_hi,
	input  [DQS_WIDTH-1:0]             ddr_dqs_in_lo,
	input  [DQ_WIDTH-1:0]              ddr_dq_in_hi,
	input  [DQ_WIDTH-1:0]              ddr_dq_in_lo,
	
	output [DQS_WIDTH-1:0]             ddr_dqs_oe,
	output [DQS_WIDTH-1:0]             ddr_dqs_oe_n,
	output [DQ_WIDTH-1:0]              ddr_dq_oe,  
	output [DQS_WIDTH-1:0]             ddr_dqs_out_hi,
	output [DQS_WIDTH-1:0]             ddr_dqs_out_lo,
	output [DQ_WIDTH-1:0]              ddr_dq_out_hi,
	output [DQ_WIDTH-1:0]              ddr_dq_out_lo,
	output [DM_WIDTH-1:0]              ddr_dm_hi,
	output [DM_WIDTH-1:0]              ddr_dm_lo,
	output [ODT_WIDTH-1:0]             ddr_odt,

    output tmds_tx_clk_TX_OE,
    output [9:0] tmds_tx_clk_TX_DATA,
    output tmds_tx_clk_TX_RST,
    output tmds_tx_data0_TX_OE,
    output [9:0] tmds_tx_data0_TX_DATA,
    output tmds_tx_data0_TX_RST,
    output tmds_tx_data1_TX_OE,
    output [9:0] tmds_tx_data1_TX_DATA,
    output tmds_tx_data1_TX_RST,
    output tmds_tx_data2_TX_OE,
    output [9:0] tmds_tx_data2_TX_DATA,
    output tmds_tx_data2_TX_RST
,
  input 			hdmi_rx_slow_clk,
  input 			hdmi_rx_clk_RX_DATA,
  input [9:0] 		hdmi_rx_d0_RX_DATA,
  input [9:0] 		hdmi_rx_d1_RX_DATA,
  input [9:0] 		hdmi_rx_d2_RX_DATA,
  output 			hdmi_rx_clk_RX_ENA,
  output 			hdmi_rx_d0_RX_RST,
  output 			hdmi_rx_d0_RX_ENA,
  output 			hdmi_rx_d1_RX_RST,
  output 			hdmi_rx_d1_RX_ENA,
  output 			hdmi_rx_d2_RX_RST,
  output 			hdmi_rx_d2_RX_ENA,   
  output 			hdmi_rx_clk_RX_DLY_INC,
  output 			hdmi_rx_clk_RX_DLY_ENA,
  output 			hdmi_rx_clk_RX_DLY_RST,
  input hdmi_rx_pll_LOCKED ,
  output hdmi_rx_pll_RSTN,
  output 	HPD_N,
  input 	HDMI_5V_N,
  input 	FPGA_HDMI_SCL_IN,
  input 	FPGA_HDMI_SDA_IN,
  output 	FPGA_HDMI_SCL_OUT,
  output 	FPGA_HDMI_SCL_OE,
  output 	FPGA_HDMI_SDA_OUT,
  output 	FPGA_HDMI_SDA_OE
);
wire                              app_sr_active;
wire                              app_ref_ack;
wire                              app_zq_ack;
wire                              cal_done;

// Slave Interface Write Address Ports
wire [AXI_ID_WIDTH-1:0]           s_axi_awid;
wire [AXI_ADDR_WIDTH-1:0]         s_axi_awaddr;
wire [7:0]                        s_axi_awlen;
wire [2:0]                        s_axi_awsize;
wire [1:0]                        s_axi_awburst;
wire [0:0]                        s_axi_awlock;
wire [3:0]                        s_axi_awcache;
wire [2:0]                        s_axi_awprot;
wire                              s_axi_awvalid;
wire                              s_axi_awready;
// Slave Interface Write Data Ports
wire [AXI_DATA_WIDTH-1:0]         s_axi_wdata;
wire [(AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb;
wire                              s_axi_wlast;
wire                              s_axi_wvalid;
wire                              s_axi_wready;
// Slave Interface Write Response Ports
wire                              s_axi_bready;
wire [AXI_ID_WIDTH-1:0]           s_axi_bid;
wire [1:0]                        s_axi_bresp;
wire                              s_axi_bvalid;
// Slave Interface Read Address Ports
wire [AXI_ID_WIDTH-1:0]           s_axi_arid;
wire [AXI_ADDR_WIDTH-1:0]         s_axi_araddr;
wire [7:0]                        s_axi_arlen;
wire [2:0]                        s_axi_arsize;
wire [1:0]                        s_axi_arburst;
wire [0:0]                        s_axi_arlock;
wire [3:0]                        s_axi_arcache;
wire [2:0]                        s_axi_arprot;
wire                              s_axi_arvalid;
wire                              s_axi_arready;
// Slave Interface Read Data Ports
wire                              s_axi_rready;
wire [AXI_ID_WIDTH-1:0]           s_axi_rid;
wire [AXI_DATA_WIDTH-1:0]         s_axi_rdata;
wire [1:0]                        s_axi_rresp;
wire                              s_axi_rlast;
wire                              s_axi_rvalid;





localparam MAX_HRES=1920, MAX_VRES=1080, HFP=88, HSP=44, HBP=148, VFP=4, VSP=5, VBP=36;
assign pll_inst1_RSTN=i_arstn;
assign USER_PLL_RSTN=i_arstn;
assign DDR3_PLL_RSTN=i_arstn;
wire w_arstn=i_arstn & i_pll_locked & pll_locked & user_pll_locked;
wire axi_rst_n, cfg_rst_n, tx_rst_n;
hdmi_reset_sync u_ar(.clk(core_clk),.arst_n(w_arstn),.rst_n(axi_rst_n));
hdmi_reset_sync u_cr(.clk(CLK_25M),.arst_n(w_arstn),.rst_n(cfg_rst_n));
hdmi_reset_sync u_tr(.clk(hdmi_tx_slow_clk),.arst_n(w_arstn & cal_done),.rst_n(tx_rst_n));
wire vid_rst_n=w_arstn & cal_done & hdmi_rx_pll_LOCKED;
reg [25:0] heartbeat=0;
always @(posedge core_clk) heartbeat<=heartbeat+1'b1;
wire rx_hsync,rx_vsync,rx_de;
wire [7:0] rdata_in,gdata_in,bdata_in;
wire [1:0] video_format;
wire pll_rst_n;
reg [22:0] wait_cnt=0,lock_wait_cnt=0;
reg rx_started=0;
wire rx_frame_stalled;
always @(posedge CLK_25M) begin
 if(!cfg_rst_n || HPD_N)rx_started<=0;
 else if(hdmi_rx_pll_LOCKED)rx_started<=1;
 if(!cfg_rst_n || HPD_N) wait_cnt<=0;
 else if(!wait_cnt[22]) wait_cnt<=wait_cnt+1'b1;
 if(!cfg_rst_n || hdmi_rx_pll_LOCKED || lock_wait_cnt[20]) lock_wait_cnt<=0;
 else lock_wait_cnt<=lock_wait_cnt+1'b1;
end
assign hdmi_rx_pll_RSTN=wait_cnt[22] & ~lock_wait_cnt[20] & i_arstn &
                        (pll_rst_n | ~rx_started) & ~rx_frame_stalled;
assign hdmi_rx_clk_RX_ENA=1'b1;
assign hdmi_rx_d0_RX_ENA=1'b1; assign hdmi_rx_d1_RX_ENA=1'b1; assign hdmi_rx_d2_RX_ENA=1'b1;
assign hdmi_rx_d0_RX_RST=1'b0; assign hdmi_rx_d1_RX_RST=1'b0; assign hdmi_rx_d2_RX_RST=1'b0;
hdmi_rx u_hdmi_rx(.cfg_clk(CLK_25M),.rst_n(cfg_rst_n),.hdmi_rx_5v_n(HDMI_5V_N),.hdmi_rx_hpd_n(HPD_N),
 .scl_i(FPGA_HDMI_SCL_IN),.scl_o(FPGA_HDMI_SCL_OUT),.scl_oe(FPGA_HDMI_SCL_OE),
 .sda_i(FPGA_HDMI_SDA_IN),.sda_o(FPGA_HDMI_SDA_OUT),.sda_oe(FPGA_HDMI_SDA_OE));
dvi_decoder u_dvi_decoder(.pclk(hdmi_rx_slow_clk),.bdata(~hdmi_rx_d0_RX_DATA),
 .gdata(~hdmi_rx_d1_RX_DATA),.rdata(~hdmi_rx_d2_RX_DATA),.pll_lock(hdmi_rx_pll_LOCKED),.pll_rst_n(pll_rst_n),
 .hsync(rx_hsync),.vsync(rx_vsync),.de(rx_de),.red(rdata_in),.green(gdata_in),.blue(bdata_in),
 .DLY_INC(hdmi_rx_clk_RX_DLY_INC),.DLY_RST(hdmi_rx_clk_RX_DLY_RST),.DLY_ENA(hdmi_rx_clk_RX_DLY_ENA),
 .avi_infoframe_Y(video_format));
reg [11:0] video_threshold;
reg mode_red,algo_sel,median_enable;
wire detect_enabled,capture_background;
wire [23:0] model_status_tx;
wire [9:0] debug_addr;wire [23:0] debug_rgb,debug_box0,debug_box1,debug_info;wire debug_done;
(* async_reg="true" *) reg [2:0] debug_done_sync=0;
always @(posedge core_clk or negedge axi_rst_n)
 if(!axi_rst_n)debug_done_sync<=0;else debug_done_sync<={debug_done_sync[1:0],debug_done};
wire [11:0] key_thresh;
assign key_thresh=video_threshold;
wire [12:0] filter_rx;
edge_control_cdc u_filter_cdc(.src_clk(hdmi_tx_slow_clk),.src_rst_n(tx_rst_n),
 .src_value({median_enable,key_thresh}),.dst_clk(hdmi_rx_slow_clk),.dst_rst_n(vid_rst_n),.dst_value(filter_rx));
wire classified_de,classified_hs,classified_vs;
wire [31:0] classified_word;
edge_classify u_classify(.clk(hdmi_rx_slow_clk),.rst_n(vid_rst_n),
 .i_de(rx_de),.i_hs(rx_hsync),.i_vs(rx_vsync),.i_rgb({rdata_in,gdata_in,bdata_in}),
 .thresh_i(filter_rx[11:0]),.median_enable_i(filter_rx[12]),
 .o_word(classified_word),.o_de(classified_de),.o_hs(classified_hs),.o_vs(classified_vs));
wire canny_busy;wire [31:0] canny_passes;wire [7:0] canny_failures;
(* async_reg="true" *) reg [2:0] filter_flags_s1=3'b111,filter_flags_s2=3'b111;
(* async_reg="true" *) reg [11:0] filter_thresh_s1=12'd64,filter_thresh_s2=12'd64;
always @(posedge core_clk or negedge axi_rst_n)
 if(!axi_rst_n)begin filter_flags_s1<=3'b111;filter_flags_s2<=3'b111;filter_thresh_s1<=12'd64;filter_thresh_s2<=12'd64;end
 else begin filter_flags_s1<={mode_red,algo_sel,median_enable};filter_flags_s2<=filter_flags_s1;
            filter_thresh_s1<=video_threshold;filter_thresh_s2<=filter_thresh_s1;end
(* async_reg="true" *) reg [1:0] detect_core=0;
(* async_reg="true" *) reg [23:0] model_s1=0,model_s2=0;
always @(posedge core_clk or negedge axi_rst_n)
 if(!axi_rst_n)begin detect_core<=0;model_s1<=0;model_s2<=0;end
 else begin detect_core<={detect_core[0],detect_enabled};model_s1<=model_status_tx;model_s2<=model_s1;end
function [7:0] gray_decode(input [7:0] g);
 integer i;begin gray_decode[7]=g[7];for(i=6;i>=0;i=i-1)gray_decode[i]=gray_decode[i+1]^g[i];end
endfunction
wire [23:0] model_status_core={model_s2[23:16],gray_decode(model_s2[15:8]),model_s2[7:0]};
wire [23:0] video_config_status={8'd0,detect_core[1],filter_flags_s2[2],filter_flags_s2[1],filter_flags_s2[0],filter_thresh_s2};
wire [23:0] canny_info={4'd0,filter_flags_s2,canny_busy,(|canny_passes[31:16])?16'hffff:canny_passes[15:0]};
wire ch0_hs,ch0_vs,ch0_de;
wire [31:0] fb_rgb32;
wire fb_cmd_valid; wire [2:0] fb_cmd_op; wire [1:0] fb_cmd_arg; wire [7:0] fb_last_cmd;
wire fb_video_cmd_valid; wire [3:0] fb_video_cmd;
wire fb_rd_hold,fb_wr_addr_en,fb_rd_addr_en,fb_saved,fb_video_ok,fb_wr_frame_done,fb_rd_frame_done;
wire fb_frame_stable;
wire [15:0] fb_debug_writer;
wire [31:0] fb_wr_addr_ovr,fb_rd_addr_ovr; wire [3:0] fb_state; wire [4:0] fb_prog; wire [2:0] fb_slot_valid;
ddr_ctrl_uart #(.CLK_HZ(25_000_000),.BAUD(115_200)) u_ddr_uart(.clk(CLK_25M),.rst_n(cfg_rst_n),
 .rx(uart_rx),.cmd_valid(fb_cmd_valid),.cmd_op(fb_cmd_op),.cmd_arg(fb_cmd_arg),.last_cmd(fb_last_cmd),
 .video_cmd_valid(fb_video_cmd_valid),.video_cmd(fb_video_cmd));
// UART messages are milliseconds apart. Payload is held stable before toggle crosses.
reg cmd_toggle=0; reg [4:0] cmd_payload=0;
always @(posedge CLK_25M or negedge cfg_rst_n)
 if(!cfg_rst_n) begin cmd_toggle<=0;cmd_payload<=0;end
 else if(fb_cmd_valid) begin cmd_toggle<=~cmd_toggle;cmd_payload<={fb_cmd_op,fb_cmd_arg};end
(* async_reg="true" *) reg [2:0] cmd_sync=0;
reg [4:0] cmd_payload_s1=0,cmd_payload_s2=0;
always @(posedge core_clk or negedge axi_rst_n)
 if(!axi_rst_n) begin cmd_sync<=0;cmd_payload_s1<=0;cmd_payload_s2<=0;end
 else begin cmd_sync<={cmd_sync[1:0],cmd_toggle};cmd_payload_s1<=cmd_payload;cmd_payload_s2<=cmd_payload_s1;end
ddr_save_ctrl #(.FRAME_LEN(8294400),.SLOT_BASE(32'h01800000),.VIDEO_BASE(32'h03000000),
 .NSLOT(3),.NVID(26),.CLK_HZ(100_000_000),.PLAY_FPS(5)) u_save_ctrl(
 .clk(core_clk),.rst_n(axi_rst_n),.vs(fb_wr_frame_done),.rd_done(fb_rd_frame_done),
 .cmd_valid((cmd_sync[2]^cmd_sync[1])&&(cmd_payload_s2[4:2]!=3'd7)),.cmd_op(cmd_payload_s2[4:2]),.cmd_arg(cmd_payload_s2[1:0]),
 .rd_hold(fb_rd_hold),.rd_addr_en(fb_rd_addr_en),.rd_addr_ovr(fb_rd_addr_ovr),
 .wr_addr_en(fb_wr_addr_en),.wr_addr_ovr(fb_wr_addr_ovr),.state(fb_state),.prog(fb_prog),
 .saved_valid(fb_saved),.slot_valid(fb_slot_valid),.video_valid(fb_video_ok));
// Hold payload before request and until acknowledgement. This prevents an
// asynchronously sampled command pulse from applying the previous payload.
wire video_cmd_tx_valid;wire [3:0] video_cmd_tx;
uart_video_command_cdc u_video_command_cdc(
 .src_clk(CLK_25M),.src_rst_n(cfg_rst_n),.src_valid(fb_video_cmd_valid),.src_cmd(fb_video_cmd),
 .dst_clk(hdmi_tx_slow_clk),.dst_rst_n(tx_rst_n),.dst_valid(video_cmd_tx_valid),.dst_cmd(video_cmd_tx));
// All image controls are explicit UART commands; physical keys are ignored.
pc_image_controls u_pc_image_controls(.clk(hdmi_tx_slow_clk),.rst_n(tx_rst_n),
 .cmd_valid(video_cmd_tx_valid),.cmd(video_cmd_tx),
 .detect_enable(detect_enabled),.capture_background(capture_background),
 .threshold(video_threshold),.color_mode(mode_red),.canny_mode(algo_sel),.median_enable(median_enable));
// Board schematic, PDF pages 4/8: FT4232H channel C RX -> GPIOR_28.
// The legacy interface calls this pin led[2]; it is actually FPGA UART TX.
wire uart_tx_status;
(* async_reg="true" *) reg [1:0] uart_rxlock_sync=0,uart_frame_sync=0;
always @(posedge core_clk or negedge axi_rst_n)
 if(!axi_rst_n)begin uart_rxlock_sync<=0;uart_frame_sync<=0;end
 else begin uart_rxlock_sync<={uart_rxlock_sync[0],hdmi_rx_pll_LOCKED};uart_frame_sync<={uart_frame_sync[0],fb_frame_stable};end
// A locked RX PLL and the last valid frame do not prove frames still arrive.
reg rx_vs_prev=0,rx_vs_toggle=0;
always @(posedge hdmi_rx_slow_clk or negedge vid_rst_n)
 if(!vid_rst_n)begin rx_vs_prev<=0;rx_vs_toggle<=0;end
 else begin rx_vs_prev<=rx_vsync;if(rx_vsync&&!rx_vs_prev)rx_vs_toggle<=~rx_vs_toggle;end
(* async_reg="true" *) reg [2:0] rx_vs_sync=0;
reg [7:0] rx_frame_count=0;reg [24:0] rx_frame_gap=25'd20000000;
always @(posedge core_clk or negedge axi_rst_n)
 if(!axi_rst_n)begin rx_vs_sync<=0;rx_frame_count<=0;rx_frame_gap<=25'd20000000;end
 else begin
  rx_vs_sync<={rx_vs_sync[1:0],rx_vs_toggle};
  // Once the RX PLL has locked, a missing frame for 200 ms means the
  // decoder/alignment state is stale (for example after a hot unplug).
  // Clear the timer while the PLL is not locked so initial acquisition is
  // allowed; the stalled condition then forces a fresh RX PLL reset.
  if(!uart_rxlock_sync[1] || !rx_started)begin
   rx_frame_gap<=0;
  end else if(rx_vs_sync[2]^rx_vs_sync[1])begin
   rx_frame_count<=rx_frame_count+1'b1;rx_frame_gap<=0;
  end else if(rx_frame_gap<25'd20000000)rx_frame_gap<=rx_frame_gap+1'b1;
 end
assign rx_frame_stalled=rx_started && rx_frame_gap>=25'd20000000;
wire [23:0] link0,link1,link2,link3;
wire [7:0] pixel_geometry_errors;
ddr_uart_telemetry #(.DIAGNOSTICS(1),.LINK_MONITOR(1),.CANNY_MONITOR(0)) u_uart_telemetry(.clk(core_clk),.rst_n(axi_rst_n),
 .cmd_valid(cmd_sync[2]^cmd_sync[1]),.cmd_op(cmd_payload_s2[4:2]),.cmd_arg(cmd_payload_s2[1:0]),
 .state(fb_state),.progress(fb_prog),.slots(fb_slot_valid),.video_valid(fb_video_ok),.saved_valid(fb_saved),
 .cal_done(cal_done),.rx_locked(uart_rxlock_sync[1]),.frame_stable(uart_frame_sync[1]&&(rx_frame_gap<25'd20000000)),
 .config_status(video_config_status),.model_status(model_status_core),
 .debug_ready(debug_done_sync[2]),.debug_rgb(debug_rgb),.debug_box0(debug_box0),.debug_box1(debug_box1),.debug_info(debug_info),.debug_addr(debug_addr),
 .diagnostics({rx_frame_count,fb_debug_writer[7:0],fb_debug_writer[15:8]}),
 .link0(link0),.link1(link1),.link2(link2),.link3({link3[23:8],pixel_geometry_errors}),
 .canny_info(canny_info),.canny_errors(canny_failures),
 .wr_frame_done(fb_wr_frame_done),.rd_frame_done(fb_rd_frame_done),.tx(uart_tx_status));
frame_buffer #(
.FULL_CANNY(0),
.I_VID_WIDTH         (32),
.O_VID_WIDTH         (32),
.START_ADDR          (32'h00000        ),
.AXI_DATA_WIDTH      ( AXI_DATA_WIDTH	),
.AXI_ADDR_WIDTH      ( AXI_ADDR_WIDTH	),
.WR_FIFO_DEPTH	      ( 1024		),    
.RD_FIFO_DEPTH 	      ( 1024 	),
.BURST_LEN  	       (127),
.FB_NUM	            (3),
.MAX_VID_WIDTH	    (1920) ,
.MAX_VID_HIGHT	    (1080) 


)checker0(
       .axi_clk		(core_clk 	        ),
       .rst_n			(vid_rst_n   ),
/*i*/.i_clk			(hdmi_rx_slow_clk),
/*i*/.i_vs(classified_vs),
/*i*/.wr_frame_done(fb_wr_frame_done),
/*i*/.rd_frame_done(fb_rd_frame_done),
       .debug_frame_stable(fb_frame_stable),
       .debug_writer(fb_debug_writer),
       .bresp(s_axi_bresp),.canny_busy(canny_busy),.canny_passes(canny_passes),.canny_failures(canny_failures),
/*i*/.rd_hold_i		(fb_rd_hold),
/*i*/.wr_addr_en		(fb_wr_addr_en),
/*i*/.wr_addr_ovr	(fb_wr_addr_ovr),
/*i*/.rd_addr_en		(fb_rd_addr_en),
/*i*/.rd_addr_ovr	(fb_rd_addr_ovr),
/*i*/.wr_hold_i		(1'b0),
/*i*/.step_i			(1'b0),
/*i*/.auto_mode		(2'd0),
/*i*/.i_de(classified_de),
/*i*/.vin(classified_word),
                     
/*i*/.o_clk(hdmi_tx_slow_clk),
/*i*/.o_hs    		(ch0_hs		),			
/*i*/.o_vs    		(ch0_vs		),			
/*i*/.o_de    		(ch0_de		),			
/*i*/.vout(fb_rgb32),

/*i*/.H_FRONT_PORCH (HFP  		),//
/*i*/.H_SYNC 	 	    (HSP	 	),///2
/*i*/.H_VALID 	 	  (MAX_HRES     ),//		
/*i*/.H_BACK_PORCH	(HBP		),//		
/*i*/.V_FRONT_PORCH (VFP  		),//		
/*i*/.V_SYNC 	 	    (VSP 	 	),//		
/*i*/.V_VALID 	 	  (MAX_VRES     ),//		
/*i*/.V_BACK_PORCH	(VBP		),//		

       .awid			(s_axi_awid	),      
       .awaddr		(s_axi_awaddr	),
       .awlen			(s_axi_awlen	),
       .awsize		(s_axi_awsize	),
       .awburst		(s_axi_awburst),
       .awprot    (s_axi_awprot ),
       .awcache   (s_axi_awcache),
       .awlock		(s_axi_awlock	),
       .awvalid		(s_axi_awvalid),
       .awready		(s_axi_awready),

       .arid			(s_axi_arid	  ),
       .araddr		(s_axi_araddr	),
       .arlen			(s_axi_arlen	),
       .arsize		(s_axi_arsize	),
       .arburst 	(s_axi_arburst),

       .arprot    (s_axi_arprot ),
       .arcache   (s_axi_arcache),
       .arlock 		(s_axi_arlock	),
       .arvalid		(s_axi_arvalid),
       .arready		(s_axi_arready),

       .wdata			(s_axi_wdata	),
       .wstrb			(s_axi_wstrb	),
       .wlast			(s_axi_wlast	),
       .wvalid		(s_axi_wvalid	),
       .wready		(s_axi_wready	),


       .rid			  (s_axi_rid	),
       .rdata			(s_axi_rdata	),
       .rlast			(s_axi_rlast	),
       .rvalid 		(s_axi_rvalid	),
       .rready		(s_axi_rready	),
       .rresp			(s_axi_rresp	),

       .bid			  (s_axi_bid	),
       .bvalid		(s_axi_bvalid	),
       .bready	  (s_axi_bready	)
);


ddr3_top                 u_ddr3_top
(

.axi_clk                (core_clk            ),
.core_clk               (core_clk            ),
.sdram_clk              (sdram_clk           ),  
.rx_cal_clk             (rx_cal_clk          ),
.tx_cal_clk             (tx_cal_clk          ),
.tx_cal_clk_90edge      (tx_cal_clk_90edge   ),
.rstn                   (w_arstn             ),      
.pll_shift              (pll_shift           ),
.pll_shift_sel          (pll_shift_sel       ),
.pll_shift_ena          (pll_shift_ena       ),       
///////////////DDR BUS
.ddr_ck_hi              (ddr_ck_hi           ),
.ddr_ck_lo              (ddr_ck_lo           ),
.ddr_cke                (ddr_cke             ),    
.ddr_reset_n            (ddr_reset_n         ),
.ddr_cs_n               (ddr_cs_n            ),
.ddr_ras_n              (ddr_ras_n           ),
.ddr_cas_n              (ddr_cas_n           ),
.ddr_we_n               (ddr_we_n            ),     
.ddr_addr               (ddr_addr            ),
.ddr_ba                 (ddr_ba              ),

.ddr_dqs_oe             (ddr_dqs_oe          ),
.ddr_dqs_oe_n           (ddr_dqs_oe_n        ),
.ddr_dq_oe              (ddr_dq_oe           ),
.ddr_dqs_in_hi          (ddr_dqs_in_hi       ),
.ddr_dqs_in_lo          (ddr_dqs_in_lo       ),
.ddr_dq_in_hi           (ddr_dq_in_hi        ),
.ddr_dq_in_lo           (ddr_dq_in_lo        ),

.ddr_dqs_out_hi         (ddr_dqs_out_hi      ),
.ddr_dqs_out_lo         (ddr_dqs_out_lo      ),
.ddr_dq_out_hi          (ddr_dq_out_hi       ),
.ddr_dq_out_lo          (ddr_dq_out_lo       ),

.ddr_dm_hi              (ddr_dm_hi           ),
.ddr_dm_lo              (ddr_dm_lo           ),
.ddr_odt                (ddr_odt             ),

// Application interface ports
.app_sr_req                     (1'b0),
.app_ref_req                    (1'b0),
.app_zq_req                     (1'b0),
.app_sr_active                  (app_sr_active),
.app_ref_ack                    (app_ref_ack),
.app_zq_ack                     (app_zq_ack),

// Slave Interface Write Address Ports
.s_axi_awid                     (s_axi_awid        ),
.s_axi_awaddr                   (s_axi_awaddr      ),
.s_axi_awlen                    (s_axi_awlen       ),
.s_axi_awsize                   (s_axi_awsize      ),
.s_axi_awburst                  (s_axi_awburst     ),
.s_axi_awlock                   (s_axi_awlock      ),
.s_axi_awcache                  (s_axi_awcache     ),
.s_axi_awprot                   (s_axi_awprot      ),
.s_axi_awqos                    (4'h0              ),
.s_axi_awvalid                  (s_axi_awvalid     ),
.s_axi_awready                  (s_axi_awready     ),
// Slave Interface Write Data Ports
.s_axi_wdata                    (s_axi_wdata       ),
.s_axi_wstrb                    (s_axi_wstrb       ),
.s_axi_wlast                    (s_axi_wlast       ),
.s_axi_wvalid                   (s_axi_wvalid      ),
.s_axi_wready                   (s_axi_wready      ),
// Slave Interface Write Response Ports
.s_axi_bid                      (s_axi_bid         ),
.s_axi_bresp                    (s_axi_bresp       ),
.s_axi_bvalid                   (s_axi_bvalid      ),
.s_axi_bready                   (s_axi_bready      ),
// Slave Interface Read Address Ports
.s_axi_arid                     (s_axi_arid        ),
.s_axi_araddr                   (s_axi_araddr      ),
.s_axi_arlen                    (s_axi_arlen       ),
.s_axi_arsize                   (s_axi_arsize      ),
.s_axi_arburst                  (s_axi_arburst     ),
.s_axi_arlock                   (s_axi_arlock      ),
.s_axi_arcache                  (s_axi_arcache     ),
.s_axi_arprot                   (s_axi_arprot      ),
.s_axi_arqos                    (4'h0              ),
.s_axi_arvalid                  (s_axi_arvalid     ),
.s_axi_arready                  (s_axi_arready     ),
// Slave Interface Read Data Ports
.s_axi_rid                      (s_axi_rid         ),
.s_axi_rdata                    (s_axi_rdata       ),
.s_axi_rresp                    (s_axi_rresp       ),
.s_axi_rlast                    (s_axi_rlast       ),
.s_axi_rvalid                   (s_axi_rvalid      ),
.s_axi_rready                   (s_axi_rready      ),
//DEBUG       
.wrlvl_dq_check                 () ,
.rd_level_dqs_check             () ,
.init_cur_state                 () ,
.idelay_ld                      () ,
.mpr_rdlvl_dly                  () ,
.cal_done                       (cal_done          ) 
);

wire [7:0] proc_r,proc_g,proc_b;
wire proc_de,proc_hs,proc_vs;
edge_display u_proc(.clk(hdmi_tx_slow_clk),.rst_n(tx_rst_n),
 .i_de(ch0_de),.i_hs(ch0_hs),.i_vs(ch0_vs),.i_word(fb_rgb32),
 .mode_col_i(mode_red),.algo_canny_i(algo_sel),
 .o_rgb({proc_r,proc_g,proc_b}),.o_de(proc_de),.o_hs(proc_hs),.o_vs(proc_vs));
// Temporary board diagnostics: sticky checkpoints across the video path.
// led[0] RX pixel activity, led[1] valid/stable input frame,
// led[2] nonzero RGB returned from DDR, led[3] >100k processed RGB pixels in a frame.
reg dbg_rx_de_seen=1'b0, dbg_frame_stable_seen=1'b0;
reg dbg_fb_rgb_seen=1'b0, dbg_proc_rgb_dense=1'b0, dbg_proc_vs_d=1'b0;
reg [20:0] dbg_proc_rgb_count=21'd0;
always @(posedge hdmi_rx_slow_clk or negedge vid_rst_n) begin
 if(!vid_rst_n) begin dbg_rx_de_seen<=1'b0;dbg_frame_stable_seen<=1'b0;end
 else begin
  if(rx_de)dbg_rx_de_seen<=1'b1;
  if(fb_frame_stable)dbg_frame_stable_seen<=1'b1;
 end
end
always @(posedge hdmi_tx_slow_clk or negedge tx_rst_n) begin
 if(!tx_rst_n) begin
  dbg_fb_rgb_seen<=1'b0;dbg_proc_rgb_dense<=1'b0;dbg_proc_vs_d<=1'b0;
  dbg_proc_rgb_count<=21'd0;
 end
 else begin
  if(ch0_de && (|fb_rgb32[23:0]))dbg_fb_rgb_seen<=1'b1;
  dbg_proc_vs_d<=proc_vs;
  if(proc_vs && !dbg_proc_vs_d) begin
   if(dbg_proc_rgb_count>=21'd100000)dbg_proc_rgb_dense<=1'b1;
   dbg_proc_rgb_count<=21'd0;
  end else if(proc_de && (|{proc_r,proc_g,proc_b}) && dbg_proc_rgb_count!=21'h1fffff)
   dbg_proc_rgb_count<=dbg_proc_rgb_count+1'b1;
 end
end
(* async_reg="true" *) reg [3:0] dbg_led_sync1=0,dbg_led_sync2=0;
always @(posedge CLK_25M or negedge cfg_rst_n) begin
 if(!cfg_rst_n) begin dbg_led_sync1<=0;dbg_led_sync2<=0;end
 else begin
  dbg_led_sync1<={dbg_proc_rgb_dense,dbg_fb_rgb_seen,dbg_frame_stable_seen,dbg_rx_de_seen};
  dbg_led_sync2<=dbg_led_sync1;
 end
end
assign led={dbg_led_sync2[3],uart_tx_status,dbg_led_sync2[1:0]};
wire [9:0] tmds_clk,tmds_data0,tmds_data1,tmds_data2;
// TX isolation build: keep the DDR-generated output raster and bypass only
// the image-processing RGB path.  This separates TX/physical-link failures
// from processor RGB/sync alignment failures without changing the clocking.
// 0 = processed RGB + processed sync, 1 = raw RGB + raw sync,
// 2 = raw RGB + processed sync, 3 = white RGB + processed sync.
localparam [1:0] TX_TEST_MODE = 2'd0;
wire [7:0] tx_r = (TX_TEST_MODE == 2'd1 || TX_TEST_MODE == 2'd2) ? fb_rgb32[23:16] :
                  (TX_TEST_MODE == 2'd3 ? 8'hff : proc_r);
wire [7:0] tx_g = (TX_TEST_MODE == 2'd1 || TX_TEST_MODE == 2'd2) ? fb_rgb32[15:8]  :
                  (TX_TEST_MODE == 2'd3 ? 8'hff : proc_g);
wire [7:0] tx_b = (TX_TEST_MODE == 2'd1 || TX_TEST_MODE == 2'd2) ? fb_rgb32[7:0]   :
                  (TX_TEST_MODE == 2'd3 ? 8'hff : proc_b);
wire       tx_de = (TX_TEST_MODE == 2'd1) ? ch0_de : proc_de;
wire       tx_hs = (TX_TEST_MODE == 2'd1) ? ch0_hs : proc_hs;
wire       tx_vs = (TX_TEST_MODE == 2'd1) ? ch0_vs : proc_vs;
hdmi_pixel_monitor u_pixel_monitor(.clk(hdmi_tx_slow_clk),.rst_n(i_arstn),
 .de(tx_de),.vs(tx_vs),.report_clk(core_clk),.errors(pixel_geometry_errors));
hdmi_link_monitor u_link_monitor(.ref_clk(CLK_25M),.rst_n(i_arstn),.report_clk(core_clk),
 .rx_locked(hdmi_rx_pll_LOCKED),.frame_stable(fb_frame_stable),.tx_rst_n(tx_rst_n),
 .global_rst_n(w_arstn),.tx_locked(user_pll_locked),.cal_done(cal_done),.rx_rst_n(hdmi_rx_pll_RSTN),
 .tx_hs(tx_hs),.tx_vs(tx_vs),.link0(link0),.link1(link1),.link2(link2),.link3(link3));
// Diagnostic marker is downstream of image processing and independent of RGB.
// A black image with the blinking marker present is distinct from link loss.
wire [23:0] tx_rgb_marked;
hdmi_alive_marker u_tx_alive(.clk(hdmi_tx_slow_clk),.rst_n(tx_rst_n),
 .de(tx_de),.vs(tx_vs),.rgb_in({tx_r,tx_g,tx_b}),.rgb_out(tx_rgb_marked));
// Isolation experiment: change only the symbol encoder, retaining the complete
// processor, raster, PLL, 10:1 serializer and physical I/O settings.
wire scene_de,scene_hs,scene_vs;wire[23:0] scene_rgb;
drink_scene u_drink_scene(.clk(hdmi_tx_slow_clk),.rst_n(tx_rst_n),.enable(detect_enabled),.capture_background(capture_background),
 .measure_de(ch0_de),.measure_vs(ch0_vs),.measure_rgb(fb_rgb32[23:0]),
 .display_de(tx_de),.display_hs(tx_hs),.display_vs(tx_vs),.display_rgb(tx_rgb_marked),
 .out_de(scene_de),.out_hs(scene_hs),.out_vs(scene_vs),.out_rgb(scene_rgb),.model_status(model_status_tx),
 .debug_capture(video_cmd_tx_valid&&(video_cmd_tx==11)),.debug_clk(core_clk),
 .debug_addr(debug_addr),.debug_rgb(debug_rgb),.debug_box0(debug_box0),.debug_box1(debug_box1),.debug_info(debug_info),.debug_done(debug_done));
localparam TX_VIDEO_ONLY=1;
generate if(TX_VIDEO_ONLY)begin: video_only_output
 tmds_video_only u_encoder(.clk(hdmi_tx_slow_clk),.rst_n(tx_rst_n),
  .de(scene_de),.hs(scene_hs),.vs(scene_vs),.rgb(scene_rgb),
  .blue(tmds_data0),.green(tmds_data1),.red(tmds_data2),.clock_word(tmds_clk));
end else begin: original_hdmi_output
dvi_encoder dvi_encoder_m0(.pixelclk(hdmi_tx_slow_clk),.rst_p(~tx_rst_n),
 .i_bdata(tx_rgb_marked[7:0]),.i_gdata(tx_rgb_marked[15:8]),.i_rdata(tx_rgb_marked[23:16]),.i_de(tx_de),.i_hs(tx_hs),.i_vs(tx_vs),
 .video_format(2'd0),.video_VIC(7'd16),.audio_L(24'd0),.audio_R(24'd0),.audio_valid(1'b0),
 .audio_N(20'd6144),.audio_CTS(20'd148500),.audio_sample_frequency(4'd2),.audio_word_length(4'd0),
 .tmds_data0(tmds_data0),.tmds_data1(tmds_data1),.tmds_data2(tmds_data2),.tmds_clk(tmds_clk));
end endgenerate
assign tmds_tx_clk_TX_DATA=~tmds_clk;
assign tmds_tx_data0_TX_DATA=~tmds_data0;assign tmds_tx_data1_TX_DATA=~tmds_data1;assign tmds_tx_data2_TX_DATA=~tmds_data2;
assign tmds_tx_clk_TX_OE=1'b1;assign tmds_tx_data0_TX_OE=1'b1;assign tmds_tx_data1_TX_OE=1'b1;assign tmds_tx_data2_TX_OE=1'b1;
assign tmds_tx_clk_TX_RST=~user_pll_locked;
assign tmds_tx_data0_TX_RST=~user_pll_locked;assign tmds_tx_data1_TX_RST=~user_pll_locked;assign tmds_tx_data2_TX_RST=~user_pll_locked;
endmodule

module hdmi_reset_sync(input wire clk,arst_n,output wire rst_n);
(* async_reg="true" *) reg [2:0] sync=0;
always @(posedge clk or negedge arst_n) if(!arst_n) sync<=0;else sync<={sync[1:0],1'b1};
assign rst_n=sync[2];
endmodule


