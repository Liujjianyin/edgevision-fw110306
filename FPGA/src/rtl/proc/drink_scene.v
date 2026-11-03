`timescale 1ns/1ps
// Fixed-camera, one-product cloth demo: capture empty scene over UART,
// locate changes against that reference, classify with a trained int8 CNN.
module drink_scene(input wire clk,rst_n,enable,capture_background,
 input wire measure_de,measure_vs,input wire [23:0] measure_rgb,
 input wire display_de,display_hs,display_vs,input wire [23:0] display_rgb,
 output reg out_de,out_hs,out_vs,output reg[23:0] out_rgb,
 output wire [23:0] model_status,
 input wire debug_capture,debug_clk,input wire [9:0] debug_addr,
 output reg [23:0] debug_rgb,debug_box0,debug_box1,debug_info,
 output reg debug_done=0);
 reg[11:0] mx=0,my=0,dx=0,dy=0;
 reg mvs_d=0,mde_d=0,dvs_d=0,dde_d=0;
 wire frame_start=measure_vs&&!mvs_d;
 always @(posedge clk)begin
  if(!rst_n)begin mx<=0;my<=0;dx<=0;dy<=0;mvs_d<=0;mde_d<=0;dvs_d<=0;dde_d<=0;end
  else begin
   mvs_d<=measure_vs;mde_d<=measure_de;dvs_d<=display_vs;dde_d<=display_de;
   if(frame_start)begin mx<=0;my<=0;end
   else if(measure_de)mx<=mx+1'b1;
   else begin mx<=0;if(mde_d)my<=my+1'b1;end
   if(display_vs&&!dvs_d)begin dx<=0;dy<=0;end
   else if(display_de)dx<=dx+1'b1;
   else begin dx<=0;if(dde_d)dy<=dy+1'b1;end
  end
 end
 // Exact nearest sample positions match exported training preprocessing.
 reg[4:0] nx=0,ny=0;reg[10:0] samples=0;
 wire[11:0] target_x=12'd30+nx*12'd60;
 wire[15:0] yprod=ny*16'd1080+16'd540;
 wire[11:0] target_y=yprod>>5;
 wire nn_we=measure_de&&(mx==target_x)&&(my==target_y)&&(samples<1024);
 // One explicit UART snapshot of the exact 32x32 CNN input. This independent
 // RAM remains unchanged while the host reads it in the core clock domain.
 reg [23:0] debug_pixels[0:1023];
 reg debug_pending=0,debug_writing=0;
 always @(posedge debug_clk)debug_rgb<=debug_pixels[debug_addr];
 always @(posedge clk)begin
  if(!rst_n||frame_start)begin nx<=0;ny<=0;samples<=0;end
  else if(nn_we)begin samples<=samples+1'b1;if(nx==31)begin nx<=0;ny<=ny+1'b1;end else nx<=nx+1'b1;end
 end
 wire cnn_busy,cnn_done;wire[2:0] cnn_class;wire[7:0] cnn_count,cnn_drops;
 drink_cnn_engine cnn(.clk(clk),.rst_n(rst_n),.pixel_we(nn_we),.pixel_addr({ny,nx}),.pixel_rgb(measure_rgb),
 .frame_valid(frame_start&&(samples==1024)&&enable),.busy(cnn_busy),.done(cnn_done),.class_id(cnn_class),.result_count(cnn_count),.drop_count(cnn_drops));
 reg[2:0] class_id=5,previous_class=5;
 always @(posedge clk)begin
  if(!rst_n||!enable)begin class_id<=5;previous_class<=5;end
  else if(cnn_done)begin previous_class<=cnn_class;if(previous_class==cnn_class)class_id<=cnn_class;end
 end
 // 120x68 RGB444 reference. Only sampled pixels touch RAM.
 reg[11:0] reference[0:8159];reg[12:0] ref_addr=0,ref_count=0;
 reg pending=0,calibrating=0,reference_ready=0;reg[4:0] calibration_generation=0;
 wire sample_bg=measure_de&&(mx[3:0]==0)&&(my[3:0]==0);
 wire[11:0] rgb444={measure_rgb[23:20],measure_rgb[15:12],measure_rgb[7:4]};
 reg[11:0] ref_q,pixel_q;reg sample_q=0;reg[11:0] px_q,py_q;
 always @(posedge clk)begin
  if(sample_bg)begin
   ref_q<=reference[ref_addr];pixel_q<=rgb444;px_q<=mx;py_q<=my;
   if(calibrating)reference[ref_addr]<=rgb444;
  end
  sample_q<=sample_bg;
 end
 wire[4:0] dr=pixel_q[11:8]>ref_q[11:8]?pixel_q[11:8]-ref_q[11:8]:ref_q[11:8]-pixel_q[11:8];
 wire[4:0] dg=pixel_q[7:4]>ref_q[7:4]?pixel_q[7:4]-ref_q[7:4]:ref_q[7:4]-pixel_q[7:4];
 wire[4:0] db=pixel_q[3:0]>ref_q[3:0]?pixel_q[3:0]-ref_q[3:0]:ref_q[3:0]-pixel_q[3:0];
 wire[6:0] difference={2'd0,dr}+{2'd0,dg}+{2'd0,db};
 wire foreground=(dr>=4||dg>=4||db>=4||difference>=8);
 // First suppress isolated horizontal noise, then retain only a component
 // that overlaps across at least eight adjacent 16-pixel sample rows. This
 // prevents scattered cloth texture, one-line lighting changes, and border
 // noise from creating a full-screen bounding box.
 reg[7:0] run_length=0;
 reg[11:0] row_y=0,row_min_x=1919,row_max_x=0;
 reg[7:0] row_count=0;
 reg prev_row_good=0;reg[11:0] prev_min_x=0,prev_max_x=0,prev_y=0;
 reg[7:0] vertical_streak=0;
 reg[11:0] component_x0=1919,component_y0=1079,component_x1=0,component_y1=0;
 reg[13:0] component_count=0;
 reg[11:0] best_x0=1919,best_y0=1079,best_x1=0,best_y1=0;
 reg[13:0] best_count=0;
 wire component_good=(vertical_streak>=8)&&(component_count>=40)&&
   (component_x1>=component_x0+64)&&(component_y1>=component_y0+112)&&
   (component_x1-component_x0<=900)&&(component_y1-component_y0<=1000);
 wire row_good=(row_count>=3)&&(row_max_x-row_min_x<=900);
 wire row_contiguous=prev_row_good&&(row_y==prev_y+16)&&
   (row_min_x<=prev_max_x+16)&&(row_max_x+16>=prev_min_x);
 reg[11:0] box_x0=0,box_y0=0,box_x1=0,box_y1=0;
 reg box_valid=0;
 always @(posedge clk)begin
  if(!rst_n)begin
   pending<=0;calibrating<=0;reference_ready<=0;ref_addr<=0;ref_count<=0;calibration_generation<=0;
   run_length<=0;row_y<=0;row_min_x<=1919;row_max_x<=0;row_count<=0;
   prev_row_good<=0;prev_min_x<=0;prev_max_x<=0;prev_y<=0;vertical_streak<=0;
   component_x0<=1919;component_y0<=1079;component_x1<=0;component_y1<=0;component_count<=0;box_valid<=0;
   best_x0<=1919;best_y0<=1079;best_x1<=0;best_y1<=0;best_count<=0;
   box_x0<=0;box_y0<=0;box_x1<=0;box_y1<=0;
  end else begin
   if(frame_start)begin
    ref_addr<=0;ref_count<=0;
    if(calibrating)begin reference_ready<=(ref_count==8160);calibrating<=0;if(ref_count==8160)calibration_generation<=calibration_generation+1'b1;end
    if(pending)begin calibrating<=1;pending<=0;reference_ready<=0;end
    box_valid<=enable&&reference_ready&&!calibrating&&(best_count>=40);
    box_x0<=best_x0>16?best_x0-16:0;box_x1<=best_x1<1903?best_x1+16:1919;
    box_y0<=best_y0>16?best_y0-16:0;box_y1<=best_y1<1063?best_y1+16:1079;
    run_length<=0;row_y<=0;row_min_x<=1919;row_max_x<=0;row_count<=0;
    prev_row_good<=0;vertical_streak<=0;component_count<=0;best_count<=0;
   end else begin
    if(sample_bg)begin if(ref_addr<8159)ref_addr<=ref_addr+1'b1;ref_count<=ref_count+1'b1;end
    if(sample_q&&reference_ready&&!calibrating)begin
     if(py_q!=row_y)begin
      // Complete the previous sample row. Qualify it only if it has at least
      // three adjacent foreground samples, then demand horizontal overlap
      // with the next qualified row to build a tall object component.
      if(row_good)begin
       if(row_contiguous)begin
         if(row_min_x<component_x0)component_x0<=row_min_x;
         if(row_max_x>component_x1)component_x1<=row_max_x;
         component_y1<=row_y;component_count<=component_count+row_count;
         if(vertical_streak!=255)vertical_streak<=vertical_streak+1'b1;
       end else begin
        vertical_streak<=1;component_x0<=row_min_x;component_x1<=row_max_x;
        component_y0<=row_y;component_y1<=row_y;component_count<=row_count;
       end
       prev_row_good<=1;prev_min_x<=row_min_x;prev_max_x<=row_max_x;prev_y<=row_y;
      end else begin vertical_streak<=0;component_count<=0;prev_row_good<=0;end
      row_y<=py_q;row_min_x<=1919;row_max_x<=0;row_count<=0;
      if(foreground)begin run_length<=1;end else run_length<=0;
     end else if(!foreground)run_length<=0;
     else if(px_q==0)run_length<=1;
     else begin
      if(run_length!=255)run_length<=run_length+1'b1;
      if(run_length>=2)begin
       if(row_count!=255)row_count<=row_count+1'b1;
       if(px_q>=32&&px_q-32<row_min_x)row_min_x<=px_q-32;
       if(px_q>row_max_x)row_max_x<=px_q;
      end
     end
    end
    // Preserve the largest completed/ongoing valid component, including when
    // subsequent empty rows end it. Never join separated foreground islands.
    if(component_good&&component_count>best_count)begin
     best_x0<=component_x0;best_y0<=component_y0;best_x1<=component_x1;best_y1<=component_y1;best_count<=component_count;
    end
   end
   if(!enable)box_valid<=0;
   if(capture_background)begin pending<=1;box_valid<=0;end
  end
 end
 // Background output 4 and unknown 5 never draw a product label or box.
 wire visible=enable&&box_valid&&reference_ready&&(class_id<4);
 always @(posedge clk)begin
  if(nn_we&&debug_writing)debug_pixels[{ny,nx}]<=measure_rgb;
  if(!rst_n)begin debug_pending<=0;debug_writing<=0;debug_done<=0;debug_box0<=0;debug_box1<=0;debug_info<=0;end
  else begin
   if(frame_start)begin
    if(debug_writing&&samples==1024)begin
     debug_done<=~debug_done;debug_box0<={box_x0,box_y0};debug_box1<={box_x1,box_y1};
     debug_info<={5'd0,enable,reference_ready,box_valid,2'd0,best_count};
    end
    debug_writing<=debug_pending;debug_pending<=0;
   end
   if(debug_capture&&!debug_writing)debug_pending<=1;
  end
 end
 // 64px glyphs: ROM stores 32px, every pixel is expanded 2x.
 wire[3:0] label_len;wire[4:0] glyph_id;wire[31:0] glyph_bits;
 wire[11:0] label_width=24+(label_len<<6);
 wire[11:0] lx=(box_x0+label_width<1920)?box_x0:(1920-label_width);
 wire[11:0] ly=box_y0>88?box_y0-88:0;
 wire[11:0] glyph_dx=dx-(lx+12),glyph_dy=dy-(ly+8);
 wire[3:0] char_index=glyph_dx>>6;
 drink_label_rom lr(.class_id(class_id),.char_index(char_index),.label_len(label_len),.glyph_id(glyph_id));
 drink_font_rom fr(.glyph_id(glyph_id),.row(glyph_dy[5:1]),.bits(glyph_bits));
 wire label_area=visible&&dx>=lx&&dx<lx+label_width&&dy>=ly&&dy<ly+80;
 wire glyph_area=label_area&&dx>=lx+12&&dx<lx+label_width-12&&dy>=ly+8&&dy<ly+72;
 wire glyph_on=glyph_area&&glyph_bits[31-glyph_dx[5:1]];
 wire border=visible&&dx>=box_x0&&dx<=box_x1&&dy>=box_y0&&dy<=box_y1&&
  (dx<box_x0+6||dx+6>box_x1||dy<box_y0+6||dy+6>box_y1);
 always @(posedge clk)begin
  if(!rst_n)begin out_de<=0;out_hs<=0;out_vs<=0;out_rgb<=0;end
  else begin
   out_de<=display_de;out_hs<=display_hs;out_vs<=display_vs;
   out_rgb<=!display_de?24'd0:(glyph_on?24'hffffff:(border?24'h00ff72:(label_area?24'h082b4a:display_rgb)));
  end
 end
 // Gray result counter crosses to the telemetry clock; decode there.
 assign model_status={4'd0,cnn_busy,visible,calibrating,reference_ready,(cnn_count^(cnn_count>>1)),calibration_generation,class_id};
endmodule
