//2026.8.17：V3: 
//（1）使用了通用串并转换模块，理论上可以支持任意位宽的串并，并串转换。

`timescale 1ps/1ps
module frame_buffer #(
parameter FULL_CANNY = 0,
parameter I_VID_WIDTH = 16,
parameter O_VID_WIDTH = 16,
parameter AXI_DATA_WIDTH	= 512,
parameter AXI_ADDR_WIDTH 	= 33,
parameter	WR_FIFO_DEPTH		= 1024,    
parameter	RD_FIFO_DEPTH 	= 1024,
parameter START_ADDR			=	33'h000201900,
parameter BURST_LEN       = 8'd15,
parameter FB_NUM			    = 	3,//2 buffer ,3 buffer 
parameter MAX_VID_WIDTH		=	1920 ,//video width 
parameter MAX_VID_HIGHT		=	1080 ,//wideo height
parameter AXI_STRB_WIDTH 	= AXI_DATA_WIDTH/8
) (

input 												axi_clk,
input 												rst_n,

input	wire								i_clk	,
input	wire								i_vs, //active hgih
input	wire								i_de, //active high
input	wire	[I_VID_WIDTH-1:0] 			vin ,

input	wire								  o_clk	,
output	wire								o_hs , //active high
output	wire								o_vs , //active hgih
output	wire								o_de , //active high
output	wire	[O_VID_WIDTH-1:0] 			vout ,
  output wire wr_frame_done,
  output wire rd_frame_done,
  output wire debug_frame_stable,
  output wire [15:0] debug_writer,
  input wire [1:0] bresp,
  output wire canny_busy,
  output wire [31:0] canny_passes,
  output wire [7:0] canny_failures,
  input wire rd_hold_i,
  input wire wr_hold_i,
  input wire step_i   ,
  input wire [1:0] auto_mode,
  input wire        wr_addr_en,
  input wire [31:0] wr_addr_ovr,
  input wire        rd_addr_en,
  input wire [31:0] rd_addr_ovr,

input	wire 	[12:0]									H_FRONT_PORCH 	,
input	wire 	[12:0]									H_SYNC 			,
input	wire 	[12:0]									H_VALID 		,
input	wire 	[12:0]									H_BACK_PORCH 	,
input	wire 	[12:0]									V_FRONT_PORCH 	,
input	wire 	[12:0]									V_SYNC 			,
input	wire 	[12:0]									V_VALID 		,
input	wire 	[12:0]									V_BACK_PORCH 	,


output 	[5:0] 								awid,
output  [AXI_ADDR_WIDTH-1:0] 	awaddr,
output  [7:0] 								awlen,
output  [2:0] 								awsize,
output  [1:0] 								awburst,
output  [3:0] 								awcache,
output [2:0]                    awprot,
output  									    awlock,
output  									    awvalid,
output  									    awcobuf,
output  									    awapcmd,
output  									    awallstrb,
output  									    awqos,
input 										    awready,

output [5:0] 									arid,
output  [AXI_ADDR_WIDTH-1:0] 	                araddr,
output  [7:0] 								    arlen,
output  [2:0] 								    arsize,
output  [1:0] 								    arburst,
output  									    arlock,
output  									    arvalid,
output  									    arapcmd,
output 										    arqos,
input 										    arready,
output  [3:0] 									arcache,
output [2:0]                    arprot,

output  [AXI_DATA_WIDTH-1:0] 	wdata,  
output  [AXI_STRB_WIDTH-1:0] 	wstrb,
output  											wlast,
output  											wvalid,
input 												wready,

input [5:0] 									    rid,
input [AXI_DATA_WIDTH-1:0] 		rdata,
input 												rlast,
input 												rvalid,
output  											rready,
input [1:0] 									    rresp,

input [5:0] 									    bid,
input 												bvalid,
output  											bready,
output			[31:0]								test_rd_fifo_rddata,   
output	[31:0]								        test_wdata,
output	[31:0]								        test_rdata,
output [7:0] test_BURST_LEN
);
assign test_BURST_LEN = BURST_LEN;
//=============================================================
//parameter define                                                  
//============================================================= 
wire [31:0]               ddr_frame_len ;
// The output raster is fixed. A malformed input frame must not change its
// DDR read length while the last complete bank is being displayed.
localparam [31:0] RD_FRAME_WORDS =
    (MAX_VID_WIDTH*MAX_VID_HIGHT*I_VID_WIDTH+AXI_DATA_WIDTH-1)/AXI_DATA_WIDTH;
wire [7:0] test_cnt;
wire [AXI_DATA_WIDTH-1:0] wr_fifo_wrdata;

wire                      rd_fifo_rdvalid	;
wire [AXI_DATA_WIDTH-1:0] rd_fifo_rddata	 ; 
wire                      rd_fifo_rdempty	;
wire                      rd_fifo_rden     ;

wire                      fifo_rd_period;

reg [12:0] h_front_porch  = 13'd100; 
reg [12:0] h_sync 	 		= 13'd100; 
reg [12:0] h_valid 	 	 	= 13'd100; 
reg [12:0] h_back_porch = 13'd100; 
reg [12:0] v_front_porch  = 13'd100; 
reg [12:0] v_sync 	 		= 13'd100; 
reg [12:0] v_valid 	 	  = 13'd100; 
reg [12:0] v_back_porch = 13'd100; 

wire		wr_sw_ack ;
wire		wr_sw 		;
wire		rd_sw			;
wire		rd_sw_ack ;

//=============================================================  
//RTL                                                     
//=============================================================  
wire wr_clk_rst_n;
wire axi_clk_rst_n;
wire rd_clk_rst_n;
rst_n_piple #(                       
	.DLY ( 3 )                        
)	u_i_clk_rst_pip(                                          
/*i*/.clk			(i_clk),                        
/*i*/.rst_n_i	(rst_n),                    
/*o*/.rst_n_o (wr_clk_rst_n)            
);

  rst_n_piple #(                       
	.DLY ( 3 )                        
)	u_axi_rst_pip(                                          
/*i*/.clk			(axi_clk),                        
/*i*/.rst_n_i	(rst_n),                    
/*o*/.rst_n_o (axi_clk_rst_n)            
);

  rst_n_piple #(                       
	.DLY ( 3 )                        
)	u_o_clk_rst_pip(                                          
/*i*/.clk			(o_clk),                        
/*i*/.rst_n_i	(rst_n),                    
/*o*/.rst_n_o (rd_clk_rst_n)            
);


wire                      wr_fifo_wren;
wire                      wr_fifo_wrfull;
wire                      frame_start;
wire                      frame_stable;
assign debug_frame_stable = frame_stable;



vid_rx_align_v1 #(
	.I_VID_WIDTH   (I_VID_WIDTH		),
	.EXPECTED_PIXELS(MAX_VID_WIDTH*MAX_VID_HIGHT),
	.AXI_DDR_WIDTH (AXI_DATA_WIDTH )
)u_vid_rx_align(
/*i*/.clk			    (i_clk			),  
/*i*/.rst_n			  (wr_clk_rst_n	),
/*i*/.i_vs			  (i_vs			), //active hgih
/*i*/.i_de			  (i_de			), //active high
/*i*/.vin			    (vin			),
/*o*/.fifo_wr_en	  (wr_fifo_wren		),
/*o*/.fifo_wr_data	(wr_fifo_wrdata	),
/*o*/.frame_start	  (frame_start	),
/*O*/.fifo_rst_p		  (fifo_rst		  ),
/*O*/.frame_stable  (frame_stable ),
/*O*/.ddr_frame_len (ddr_frame_len)
);


reg fifo_rd_period_r0 = 'd0;
reg fifo_rd_period_r1 = 'd0;
reg fifo_rd_period_r2 = 'd0;
always @( posedge axi_clk)
begin
  fifo_rd_period_r0 <= fifo_rd_period;
  fifo_rd_period_r1 <= fifo_rd_period_r0;
  fifo_rd_period_r2 <= fifo_rd_period_r1; 
end
wire neg_rd_period = {fifo_rd_period_r2,fifo_rd_period_r1} == 2'b10;
// RX is now 148.5 MHz, faster than AXI. A one-pixel VS pulse can be
// missed at 100 MHz; a toggle preserves every qualified frame start.

// Admit a whole RX frame only while the writer/connection engine is free.
// Qualification still observes every input frame, including skipped ones.
wire capture_busy;
assign canny_busy=capture_busy;
(* async_reg="true" *) reg [1:0] busy_rx=0;
reg admit_frame=0,cap_vs_d=0,bad_toggle=0,good_toggle=0,cap_overflow=0;
reg [23:0] cap_pixels=0;
always @(posedge i_clk or negedge wr_clk_rst_n)begin
 if(!wr_clk_rst_n)begin busy_rx<=0;admit_frame<=0;cap_vs_d<=0;bad_toggle<=0;good_toggle<=0;cap_pixels<=0;cap_overflow<=0;end
 else begin
  busy_rx<={busy_rx[0],capture_busy};cap_vs_d<=i_vs;
  if(frame_start)begin admit_frame<=!busy_rx[1]&&frame_stable;cap_pixels<=0;cap_overflow<=0;end
  else if(i_de&&admit_frame)cap_pixels<=cap_pixels+1'b1;
  if(wr_fifo_wren&&wr_fifo_wrfull&&admit_frame)cap_overflow<=1;
  if(i_vs&&!cap_vs_d&&admit_frame)begin
   admit_frame<=0;
   if(cap_pixels!=MAX_VID_WIDTH*MAX_VID_HIGHT||cap_overflow)bad_toggle<=~bad_toggle;
   else good_toggle<=~good_toggle;
  end
 end
end
(* async_reg="true" *) reg [2:0] bad_sync=0;
(* async_reg="true" *) reg [2:0] good_sync=0;
always @(posedge axi_clk or negedge axi_clk_rst_n)
 if(!axi_clk_rst_n)begin bad_sync<=0;good_sync<=0;end
 else begin bad_sync<={bad_sync[1:0],bad_toggle};good_sync<={good_sync[1:0],good_toggle};end
wire capture_bad=bad_sync[2]^bad_sync[1];
wire capture_good=good_sync[2]^good_sync[1];
wire accepted_start=frame_start&&frame_stable&&(!FULL_CANNY||!busy_rx[1]);

reg wr_frame_toggle=0;
always @(posedge i_clk or negedge wr_clk_rst_n)
 if(!wr_clk_rst_n)wr_frame_toggle<=0;
 else if(accepted_start)wr_frame_toggle<=~wr_frame_toggle;
(* async_reg="true" *) reg [2:0] wr_frame_sync=0;
always @(posedge axi_clk or negedge axi_clk_rst_n)
 if(!axi_clk_rst_n)wr_frame_sync<=0;
 else wr_frame_sync<={wr_frame_sync[1:0],wr_frame_toggle};
wire wr_start_axi=wr_frame_sync[2]^wr_frame_sync[1];
ddr_buffer #(
.FULL_CANNY(FULL_CANNY),
.AXI_DATA_WIDTH ( AXI_DATA_WIDTH	),
.AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH	),
.WR_FIFO_DEPTH	( WR_FIFO_DEPTH		),    
.RD_FIFO_DEPTH 	( RD_FIFO_DEPTH 	),
.START_ADDR			( START_ADDR      ),
.I_VID_WIDTH    ( I_VID_WIDTH     ),
.FB_NUM         ( FB_NUM          ),
.MAX_VID_WIDTH  ( MAX_VID_WIDTH   ),
.MAX_VID_HIGHT  ( MAX_VID_HIGHT   ),
.BURST_LEN      (BURST_LEN        )
)u_ddr_buffer(
    .debug_writer(debug_writer),
    .capture_busy(capture_busy),.capture_bad(capture_bad),.capture_good(capture_good),.bresp(bresp),
    .canny_passes(canny_passes),.canny_failures(canny_failures),
    .wr_frame_done(wr_frame_done),
    .rd_frame_done(rd_frame_done),
    .rd_hold_i  (rd_hold_i),
    .wr_hold_i  (wr_hold_i),
    .step_i     (step_i),
    .auto_mode  (auto_mode),
    .wr_addr_en (wr_addr_en),
    .wr_addr_ovr(wr_addr_ovr),
    .rd_addr_en (rd_addr_en),
    .rd_addr_ovr(rd_addr_ovr),
    .axi_clk		    (axi_clk	),
    .wr_clk_rst_n (wr_clk_rst_n),
    .axi_clk_rst_n(axi_clk_rst_n),
    .rd_clk_rst_n (rd_clk_rst_n),
    
/*i*/.rd_start	      (fifo_rd_period),
/*i*/.wr_start	      (wr_start_axi),
    .wr_busrt_len     (FULL_CANNY?RD_FRAME_WORDS:ddr_frame_len ),
    .rd_burst_len     (RD_FRAME_WORDS ),

	   .test_cnt				(test_cnt),
/*i*/.wr_fifo_wrclk		(i_clk					),
/*i*/.wr_fifo_rst_p   ( fifo_rst && (!FULL_CANNY || admit_frame) ),
// Packing still runs for unqualified frames. Never feed those pixels into a
// previous incomplete DDR frame while its writer is waiting for a full burst.
/*i*/.wr_fifo_wren		(wr_fifo_wren && frame_stable && (!FULL_CANNY || admit_frame)),
/*o*/.wr_fifo_wrfull	(wr_fifo_wrfull	  ),
/*i*/.wr_fifo_wrdata	(wr_fifo_wrdata	  ), 

/*i*/.rd_fifo_rdclk		(o_clk					  ),
/*i*/.rd_fifo_rst_p   (neg_rd_period    ),
/*o*/.rd_fifo_rdvalid	(rd_fifo_rdvalid	),
/*o*/.rd_fifo_rddata	(rd_fifo_rddata	  ),
/*o*/.rd_fifo_rdempty	(rd_fifo_rdempty	),
/*i*/.rd_fifo_rden		(rd_fifo_rden     ),

/*o*/.test_wdata(test_wdata ),
/*o*/.test_rdata(test_rdata ),    
    .awid			  ( awid			),
    .awaddr			( awaddr		),
    .awlen			( awlen			),
    .awsize			( awsize		),
    .awburst		( awburst		),
    .awvalid		( awvalid		),
    .awready		( awready		),
    .awqos			( awqos			),
    .awcache    ( awcache   ),
    .awprot     ( awprot    ),

    .arid			  ( arid			),
    .araddr			( araddr		),
    .arlen			( arlen			),
    .arsize			( arsize		),
    .arburst		( arburst		),
    .arlock			( arlock		),
    .arvalid		( arvalid		),
    .arapcmd		( arapcmd		),
    .arready		( arready		),
    .arqos			( arqos			),
    .arprot     (arprot     ),
    .arcache    (arcache    ),
    //
    .wdata			( wdata			),
    .wstrb			( wstrb			),
    .wlast			( wlast			),
    .wvalid			( wvalid		),
    .wready			( wready		),
    //
    .rid			  ( rid			  ),
    .rdata			( rdata			),
    .rlast			( rlast			),
    .rvalid			( rvalid		),
    .rready			( rready		),
    .rresp			( rresp			),
    .bid			  ( bid			  ),
    .bvalid			( bvalid		),
    .bready			( bready		));

//===================================================================================
//
//===================================================================================


wire tx_valid;
wire [O_VID_WIDTH-1:0] tx_vin;
    par2ser_parse#(
      .VID_WIDTH 				( O_VID_WIDTH  ),
      .AXI_DATA_WIDTH   (AXI_DATA_WIDTH)
      
    )u_par2ser_parse(
    /*i*/.clk               (o_clk),
    /*i*/.rst_n             (rd_clk_rst_n),
    /*i*/.frame_period      (	fifo_rd_period),
    /*i*/.ddr_frame_len     (RD_FRAME_WORDS),
    /*i*/.rd_fifo_rdvalid   (rd_fifo_rdvalid  ),
    /*i*/.rd_fifo_rddata    (rd_fifo_rddata		),
    /*i*/.rd_fifo_rdempty   (rd_fifo_rdempty ),
    /*o*/.rd_fifo_rden      (rd_fifo_rden     ),

    /*o*/.tx_fifo_wrdata     (tx_vin),
    /*o*/.tx_fifo_valid    (tx_valid),
    /*I*/.tx_fifo_full    (tx_almost_full)

);

    



always @( posedge o_clk )
begin
    h_front_porch   <=  H_FRONT_PORCH ;
    h_sync 	 		    <=  H_SYNC 			  ;
    h_valid 	 	    <=  H_VALID 		  ;
    h_back_porch    <=  H_BACK_PORCH 	;
    v_front_porch   <=  V_FRONT_PORCH ;
    v_sync 	 		    <=  V_SYNC 			  ;
    v_valid 	 	    <=  V_VALID 		  ;
    v_back_porch    <=  V_BACK_PORCH 	;
end

reg rd_frame_en_r0 = 'd0;
reg rd_frame_en_r1 = 'd0;
always @( posedge o_clk or negedge rd_clk_rst_n )
begin
    if( !rd_clk_rst_n ) begin
      rd_frame_en_r0 <= 1'b0;
      rd_frame_en_r1 <= 1'b0;
    end else begin
      rd_frame_en_r0 <= frame_stable;
      rd_frame_en_r1 <= rd_frame_en_r0;
    end
end

data_tx #(
	.VID_WIDTH 				( O_VID_WIDTH  ),
	.FIFO_DIPTH  			( 1024 				 ),
	.FIFO_ALMOST_FULL	( 960          )
	
	
	)u_data_tx(
	/*i*/.clk					  (o_clk				),
	/*i*/.rst_n				  (rd_clk_rst_n	),
	/*i*/.H_FRONT_PORCH (h_front_porch),//( 50 			),
	/*i*/.H_SYNC 	 		  (h_sync 	 		),//( 50 			),
	/*i*/.H_VALID 	 	  (h_valid 	 	  ),//( 48 			),
	/*i*/.H_BACK_PORCH  (h_back_porch ),//( 50 			),
	/*i*/.V_FRONT_PORCH (v_front_porch),//( 5 			),
	/*i*/.V_SYNC 	 		  (v_sync 	 		),//( 5 			),
	/*i*/.V_VALID 	 	  (v_valid 	 	  ),//( 20 			),
	/*i*/.V_BACK_PORCH  (v_back_porch ),//( 5 			),
	/*i*/.frame_en		  (rd_frame_en_r1),//(  	frame_stable		),//(tx_frame_en	),
	/*i*/.fifo_wr_data  (tx_vin				),
	/*i*/.fifo_wr_en	  (tx_valid			),
	/*o*/.fifo_wr_almost_full	(tx_almost_full	),
	/*o*/.fifo_rd_period(fifo_rd_period),
	/*o*/.vout		(vout		),
	/*o*/.o_hs		(o_hs		),
	/*o*/.o_vs		(o_vs		),
	/*o*/.o_de		(o_de		)
	
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


endmodule
