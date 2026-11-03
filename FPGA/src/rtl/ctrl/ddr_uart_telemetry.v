`timescale 1ns/1ps
// UART TX lives in the DDR/core clock domain. All multi-bit state is sampled
// atomically here; no independently synchronized status buses are used.
// Six-byte packet: A5 type d0 d1 d2 XOR(all five previous bytes), 115200 8N1.
// 01 ACK: ASCII/op/arg (accepted, NOT save completion); 03 NAK: ASCII/reason/arg.
// 02 DDR: state / {000,video,saved,slots[2:0]} / 5-bit frame progress.
// 04 health: {0000,overflow,frame_stable,rx_locked,cal_done} / wr_count / rd_count.
// 05 identity: 'E' 'V' 02. '?' requests identity + fresh status and health.
module ddr_uart_telemetry #(
 parameter integer CLK_HZ=100000000,BAUD=115200,STATUS_TICKS=25000000,DIAGNOSTICS=0,LINK_MONITOR=0,CANNY_MONITOR=0
)(
 input wire clk,rst_n,cmd_valid,input wire [2:0] cmd_op,input wire [1:0] cmd_arg,
 input wire [3:0] state,input wire [4:0] progress,input wire [2:0] slots,
 input wire video_valid,saved_valid,cal_done,rx_locked,frame_stable,
 input wire [23:0] config_status,model_status,
 input wire debug_ready,input wire [23:0] debug_rgb,debug_box0,debug_box1,debug_info,
 output reg [9:0] debug_addr,
 input wire wr_frame_done,rd_frame_done,
 input wire [23:0] diagnostics,
 input wire [23:0] link0,link1,link2,link3,
 input wire [23:0] canny_info,
 input wire [7:0] canny_errors,
 output reg tx
);
 localparam integer DIV=CLK_HZ/BAUD;
 localparam integer CW=$clog2(STATUS_TICKS+1);
 reg [CW-1:0] timer;
 reg [7:0] wr_count,rd_count;
 reg overflow,status_due,health_due,diag_due,config_due;
 reg [3:0] link_due;
 reg firmware_due,model_due;
 reg debug_seen=0,debug_stream=0;reg [2:0] debug_stage=0;
 reg [23:0] debug_checksum=0;
 reg [1:0] canny_due;
 reg [13:0] last_status;
 wire [13:0] current_status={state,progress,video_valid,saved_valid,slots};
 reg [31:0] fifo[0:15];
 reg [3:0] head,tail;
 reg [4:0] count;
 reg busy;
 reg [31:0] packet;
 reg [2:0] byte_idx;
 reg [3:0] bit_idx;
 reg [15:0] bit_timer;
 reg [7:0] shift;
 wire pop=(!busy)&&(count!=0);
 wire push=cmd_valid&&((count<16)||pop);
 reg [7:0] ascii,reason;
 reg [31:0] reply;
 always @* begin
  ascii=8'h3f;reason=0;
  case(cmd_op)
   0:ascii=8'h46;1:ascii=8'h55;
   2:begin ascii=8'h40+{6'd0,cmd_arg};if(cmd_arg>2)reason=3;else if(slots[cmd_arg])reason=1;end
   3:ascii=8'h56;
   4:begin ascii=8'h50;if(!video_valid)reason=2;end
   5:begin ascii=8'h60+{6'd0,cmd_arg};if(cmd_arg>2)reason=3;else if(!slots[cmd_arg])reason=3;end
   6:ascii=8'h43;
   default:ascii=8'h3f;
  endcase
  if(cmd_op==7)reply={8'h05,8'h45,8'h56,8'h02};
  else if(reason!=0)reply={8'h03,ascii,reason,6'd0,cmd_arg};
  else reply={8'h01,ascii,5'd0,cmd_op,6'd0,cmd_arg};
 end
 function [7:0] packet_byte(input [2:0] n,input [31:0] p);
  begin case(n)
   0:packet_byte=8'ha5;1:packet_byte=p[31:24];2:packet_byte=p[23:16];
   3:packet_byte=p[15:8];4:packet_byte=p[7:0];
   default:packet_byte=8'ha5^p[31:24]^p[23:16]^p[15:8]^p[7:0];
  endcase end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   tx<=1;timer<=0;firmware_due<=1;model_due<=1;debug_seen<=0;debug_stream<=0;debug_stage<=0;debug_addr<=0;debug_checksum<=0;wr_count<=0;rd_count<=0;overflow<=0;
   status_due<=1;health_due<=1;diag_due<=DIAGNOSTICS!=0;config_due<=1;last_status<=14'h3fff;
   link_due<=LINK_MONITOR?4'hf:4'h0;
   canny_due<=CANNY_MONITOR?2'b11:0;
   head<=0;tail<=0;count<=0;busy<=0;packet<=0;
   byte_idx<=0;bit_idx<=0;bit_timer<=0;shift<=0;
  end else begin
   if(debug_ready!=debug_seen&&!debug_stream)begin
    debug_seen<=debug_ready;debug_stream<=1;debug_stage<=0;debug_addr<=0;debug_checksum<=0;
   end
   if(wr_frame_done)wr_count<=wr_count+1'b1;
   if(rd_frame_done)rd_count<=rd_count+1'b1;
   last_status<=current_status;
   if(timer==STATUS_TICKS-1)timer<=0;else timer<=timer+1'b1;
   if(push)begin fifo[tail]<=reply;tail<=tail+1'b1;end
   if(pop)head<=head+1'b1;
   case({push,pop})
    2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;
   endcase
   if(cmd_valid&&!push)overflow<=1;
   if(!busy)begin
    tx<=1;
    if(count!=0||status_due||health_due||config_due||diag_due||(|link_due)||(|canny_due)||firmware_due||model_due||debug_stream)begin
     if(count!=0)packet<=fifo[head];
     else if(status_due)begin
      packet<={8'h02,4'd0,state,3'd0,video_valid,saved_valid,slots,3'd0,progress};
      status_due<=0;
     end else if(health_due)begin
      packet<={8'h04,4'd0,overflow,frame_stable,rx_locked,cal_done,wr_count,rd_count};
      health_due<=0;
     end else if(config_due)begin
      packet<={8'h0d,config_status};config_due<=0;
     end else if(diag_due)begin
      packet<={8'h06,diagnostics};diag_due<=0;
     end else if(link_due[0])begin packet<={8'h07,link0};link_due[0]<=0;
     end else if(link_due[1])begin packet<={8'h08,link1};link_due[1]<=0;
     end else if(link_due[2])begin packet<={8'h09,link2};link_due[2]<=0;
     end else if(link_due[3])begin packet<={8'h0a,link3};link_due[3]<=0;
     end else if(canny_due[0])begin packet<={8'h0b,canny_info};canny_due[0]<=0;
     end else if(canny_due[1])begin packet<={8'h0c,16'd0,canny_errors};canny_due[1]<=0;
     end else if(firmware_due)begin packet<=32'h0e110306;firmware_due<=0;
     end else if(model_due)begin packet<={8'h0f,model_status};model_due<=0;
     end else begin
      case(debug_stage)
       0:begin packet<=32'h19532020;debug_stage<=1;end
       1:begin packet<={8'h16,debug_box0};debug_stage<=2;end
       2:begin packet<={8'h17,debug_box1};debug_stage<=3;end
       3:begin packet<={8'h18,debug_info};debug_stage<=4;end
       4:begin packet<={8'h20,debug_rgb};debug_checksum<=debug_checksum^debug_rgb;
        if(debug_addr==1023)debug_stage<=5;else debug_addr<=debug_addr+1'b1;end
       default:begin packet<={8'h21,debug_checksum};debug_stream<=0;end
      endcase
     end
     tx<=0;shift<=8'ha5;byte_idx<=0;bit_idx<=0;bit_timer<=DIV-1;busy<=1;
    end
   end else if(bit_timer!=0)bit_timer<=bit_timer-1'b1;
   else begin
    bit_timer<=DIV-1;
    if(bit_idx<8)begin tx<=shift[0];shift<={1'b0,shift[7:1]};bit_idx<=bit_idx+1'b1;end
    else if(bit_idx==8)begin tx<=1;bit_idx<=9;end
    else if(byte_idx==5)begin busy<=0;tx<=1;end
    else begin byte_idx<=byte_idx+1'b1;shift<=packet_byte(byte_idx+1'b1,packet);bit_idx<=0;tx<=0;end
   end
   // Requests have priority over clearing a sent notification. A change during
   // serialization schedules a second coherent snapshot instead of being lost.
   if(timer==STATUS_TICKS-1)begin firmware_due<=1;model_due<=1;status_due<=1;health_due<=1;config_due<=1;diag_due<=DIAGNOSTICS!=0;link_due<=LINK_MONITOR?4'hf:4'h0;canny_due<=CANNY_MONITOR?2'b11:0;end
   if(current_status!=last_status)status_due<=1;
   if(cmd_valid)begin firmware_due<=1;model_due<=1;status_due<=1;health_due<=1;config_due<=1;diag_due<=DIAGNOSTICS!=0;link_due<=LINK_MONITOR?4'hf:4'h0;canny_due<=CANNY_MONITOR?2'b11:0;end
  end
 end
endmodule
