`timescale 1ns/1ps
// One outstanding burst per direction. Display reads have priority; ownership
// remains fixed through RLAST / write response, including all backpressure.
module axi_frame_canny_mux #(parameter DW=128,AW=32)(
 input wire clk,rst_n,
 input wire [AW-1:0] a0,input wire [7:0] al0,input wire av0,output wire ay0,
 input wire [DW-1:0] wd0,input wire [DW/8-1:0] ws0,input wire wv0,wl0,output wire wy0,
 output wire bv0,input wire by0,
 input wire [AW-1:0] r0,input wire [7:0] rl0,input wire rv0,output wire ry0,
 output wire rdv0,rdl0,input wire rdy0,
 input wire [AW-1:0] a1,input wire [7:0] al1,input wire av1,output wire ay1,
 input wire [DW-1:0] wd1,input wire [DW/8-1:0] ws1,input wire wv1,wl1,output wire wy1,
 output wire bv1,input wire by1,
 input wire [AW-1:0] r1,input wire [7:0] rl1,input wire rv1,output wire ry1,
 output wire rdv1,rdl1,input wire rdy1,
 output wire [AW-1:0] awaddr,output wire [7:0] awlen,output wire awvalid,input wire awready,
 output wire [DW-1:0] wdata,output wire [DW/8-1:0] wstrb,output wire wvalid,wlast,input wire wready,
 input wire bvalid,output wire bready,
 output wire [AW-1:0] araddr,output wire [7:0] arlen,output wire arvalid,input wire arready,
 input wire rvalid,rlast,output wire rready
);
 reg ra=0,ro=0,wa=0,wo=0;
 // Latch the grant even before ready, so a newly arriving higher-priority
 // request cannot change an address already presented while stalled.
 reg rg=0,rsel=0,wg=0,wsel=0;
 always @(posedge clk)begin
  if(!rst_n)begin ra<=0;ro<=0;wa<=0;wo<=0;rg<=0;rsel<=0;wg<=0;wsel<=0;end
  else begin
   if(!ra&&!rg&&(rv0||rv1))begin rg<=1;rsel<=!rv0;end
   if(arvalid&&arready)begin ra<=1;ro<=rsel;rg<=0;end
   if(ra&&rvalid&&rready&&rlast)ra<=0;
   if(!wa&&!wg&&(av0||av1))begin wg<=1;wsel<=!av0;end
   if(awvalid&&awready)begin wa<=1;wo<=wsel;wg<=0;end
   if(wa&&bvalid&&bready)wa<=0;
  end
 end
 assign araddr=rsel?r1:r0;assign arlen=rsel?rl1:rl0;
 assign arvalid=rg&&!ra&&(rsel?rv1:rv0);
 assign ry0=rg&&!ra&&!rsel&&arready;assign ry1=rg&&!ra&&rsel&&arready;
 assign rdv0=ra&&!ro&&rvalid;assign rdv1=ra&&ro&&rvalid;
 assign rdl0=rlast;assign rdl1=rlast;assign rready=ra&&(ro?rdy1:rdy0);
 assign awaddr=wsel?a1:a0;assign awlen=wsel?al1:al0;
 assign awvalid=wg&&!wa&&(wsel?av1:av0);
 assign ay0=wg&&!wa&&!wsel&&awready;assign ay1=wg&&!wa&&wsel&&awready;
 assign wdata=wo?wd1:wd0;assign wstrb=wo?ws1:ws0;
 assign wvalid=wa&&(wo?wv1:wv0);assign wlast=wo?wl1:wl0;
 assign wy0=wa&&!wo&&wready;assign wy1=wa&&wo&&wready;
 assign bv0=wa&&!wo&&bvalid;assign bv1=wa&&wo&&bvalid;
 assign bready=wa&&(wo?by1:by0);
endmodule
