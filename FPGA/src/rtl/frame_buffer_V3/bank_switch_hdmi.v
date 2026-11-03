// Three-bank ownership. Writer, reader and spare are always distinct.
// A simultaneous read/write completion must process BOTH events.
module bank_switch #(
 parameter FB_NUM=3,MAX_VID_WIDTH=1920,MAX_VID_HIGHT=1080,
 parameter START_ADDR=0,VID_DATA_WIDTH=32,AXI_DATA_WIDTH=128
)(input wire ddr_clk,rst_n,wr_sw,rd_sw,
 output reg [1:0] wr_bank,rd_bank,
 output reg rd_sw_ack,wr_sw_ack,
 output wire [31:0] rd_start_addr,wr_start_addr);
 localparam FRAME_LEN=((MAX_VID_WIDTH*MAX_VID_HIGHT*VID_DATA_WIDTH/8+2047)/2048)*2048;
 reg [1:0] spare;
 reg available,wr_d,rd_d;
 wire wp=wr_sw&&!wr_d,rp=rd_sw&&!rd_d;
 function [31:0] addr(input [1:0] bank);
  case(bank)
   0:addr=START_ADDR;1:addr=START_ADDR+FRAME_LEN;default:addr=START_ADDR+2*FRAME_LEN;
  endcase
 endfunction
 assign wr_start_addr=addr(wr_bank);
 assign rd_start_addr=addr(rd_bank);
 always @(posedge ddr_clk or negedge rst_n)begin
  if(!rst_n)begin
   wr_bank<=0;rd_bank<=FB_NUM==1?0:1;spare<=2;available<=0;
   wr_d<=0;rd_d<=0;wr_sw_ack<=0;rd_sw_ack<=0;
  end else begin
   wr_d<=wr_sw;rd_d<=rd_sw;wr_sw_ack<=wp;rd_sw_ack<=rp;
   if(FB_NUM==3)begin
    case({wp,rp})
     2'b10:begin spare<=wr_bank;wr_bank<=spare;available<=1;end
     2'b01:if(available)begin rd_bank<=spare;spare<=rd_bank;available<=0;end
     2'b11:begin rd_bank<=wr_bank;wr_bank<=spare;spare<=rd_bank;available<=0;end
     default:;
    endcase
   end else if(FB_NUM==2 && wp && rp)begin wr_bank<=rd_bank;rd_bank<=wr_bank;end
  end
 end
endmodule
