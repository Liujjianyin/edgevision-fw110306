`timescale 1ns/1ps
// Legacy key decoder retained for isolated historical simulation only. It is
// not instantiated by the production top; physical board keys are ignored.
// Production controls use pc_image_controls and the UART CDC below. key_n is
// already debounced. KEY3 commits a short click on release;
// a one-second hold toggles median exactly once and suppresses that click.
module edge_controls #(parameter LONG_TICKS=148500000)(
 input wire clk,rst_n,input wire [3:0] key_n,
 output reg [11:0] threshold,output reg color_mode,canny_mode,median_enable);
 localparam CW=$clog2(LONG_TICKS+1);
 reg [3:0] previous;
 reg [CW-1:0] held;
 reg long_fired;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   previous<=4'hf;held<=0;long_fired<=0;
   threshold<=64;color_mode<=1;canny_mode<=1;median_enable<=1;
  end else begin
   previous<=key_n;
   if(previous[0]&&!key_n[0])color_mode<=~color_mode;
   if(previous[1]&&!key_n[1])threshold<=(threshold<=251)?threshold+4:255;
   else if(previous[2]&&!key_n[2])threshold<=(threshold>=20)?threshold-4:16;
   if(!key_n[3])begin
    if(!long_fired)begin
     if(held==LONG_TICKS-1)begin median_enable<=~median_enable;long_fired<=1;end
     else held<=held+1'b1;
    end
   end else begin
    if(!previous[3]&&!long_fired)canny_mode<=~canny_mode;
    held<=0;long_fired<=0;
   end
  end
 end
endmodule

// UART command payload crosses from 25 MHz to 148.5 MHz. The source makes
// payload stable one full source clock BEFORE toggling request, and holds it
// until the destination acknowledges receipt. UART bytes are at least 86 us
// apart; this handshake finishes within a few hundred ns.
module uart_video_command_cdc(
 input wire src_clk,src_rst_n,src_valid,input wire[3:0] src_cmd,
 input wire dst_clk,dst_rst_n,output reg dst_valid,output reg[3:0] dst_cmd);
 reg[3:0] payload=0;
 reg request=0,launch_pending=0,ack=0;
 (* async_reg="true" *) reg[1:0] ack_sync=0;
 (* async_reg="true" *) reg[2:0] req_sync=0;
 reg[3:0] data_s1=0,data_s2=0;
 always @(posedge src_clk or negedge src_rst_n)begin
  if(!src_rst_n)begin payload<=0;request<=0;launch_pending<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(launch_pending)begin request<=~request;launch_pending<=0;end
   else if(src_valid&&(request==ack_sync[1]))begin payload<=src_cmd;launch_pending<=1;end
  end
 end
 always @(posedge dst_clk or negedge dst_rst_n)begin
  if(!dst_rst_n)begin req_sync<=0;data_s1<=0;data_s2<=0;ack<=0;dst_valid<=0;dst_cmd<=0;end
  else begin
   req_sync<={req_sync[1:0],request};data_s1<=payload;data_s2<=data_s1;
   dst_valid<=0;
   if(req_sync[2]!=ack)begin dst_cmd<=data_s2;dst_valid<=1;ack<=req_sync[2];end
  end
 end
endmodule

// Host command map: 0 color, 1 edges, 2 threshold+, 3 threshold-,
// 4 Sobel, 5 Canny, 6 median on, 7 median off.
module pc_image_controls(
 input wire clk,rst_n,input wire cmd_valid,input wire [3:0] cmd,
 output reg detect_enable,capture_background,output reg [11:0] threshold,output reg color_mode,canny_mode,median_enable);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin threshold<=12'd64;color_mode<=1'b1;canny_mode<=1'b0;median_enable<=1'b1;detect_enable<=0;capture_background<=0;end
  else begin
   capture_background<=0;
   if(cmd_valid)begin
   case(cmd)
    4'd0:color_mode<=1'b1;
    4'd1:color_mode<=1'b0;
    4'd2:threshold<=(threshold<12'd246)?threshold+12'd4:12'd255;
    4'd3:threshold<=(threshold>12'd19)?threshold-12'd4:12'd16;
    4'd4:canny_mode<=1'b0;
    4'd5:canny_mode<=1'b1; // Streaming local Canny; not iterative full-frame hysteresis.
    4'd6:median_enable<=1'b1;
    4'd7:median_enable<=1'b0;
    4'd8:detect_enable<=1'b1;
    4'd9:detect_enable<=1'b0;
    4'd10:capture_background<=1'b1;
    default:;
   endcase
   end
  end
 end
endmodule

// Bundled-data handshake: payload stays fixed until the receiving domain
// acknowledges it. Intermediate button changes are coalesced, never torn.
module edge_control_cdc(
 input wire src_clk,src_rst_n,input wire [12:0] src_value,
 input wire dst_clk,dst_rst_n,output reg [12:0] dst_value);
 reg [12:0] payload=13'h1040;
 reg request=0,ack=0;
 (* async_reg="true" *) reg [1:0] ack_sync=0;
 (* async_reg="true" *) reg [2:0] req_sync=0;
 reg [12:0] data_s1=13'h1040,data_s2=13'h1040;
 always @(posedge src_clk or negedge src_rst_n)begin
  if(!src_rst_n)begin request<=0;payload<=13'h1040;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(ack_sync[1]==request && payload!=src_value)begin payload<=src_value;request<=~request;end
  end
 end
 always @(posedge dst_clk or negedge dst_rst_n)begin
  if(!dst_rst_n)begin req_sync<=0;ack<=0;data_s1<=13'h1040;data_s2<=13'h1040;dst_value<=13'h1040;end
  else begin
   req_sync<={req_sync[1:0],request};data_s1<=payload;data_s2<=data_s1;
   // Also refresh stable payload after an independent destination reset.
   if(req_sync[2]==req_sync[1])begin dst_value<=data_s2;ack<=req_sync[2];end
  end
 end
endmodule
