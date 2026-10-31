`timescale 1ns/1ps
// Complete selected binary frame, 4x4 OR pooling, 320x180 packed bits.
// Buffer remains immutable after done until the CPU's NEXT request.
module Binary_Snapshot #(parameter WIDTH=1280, parameter HEIGHT=720)(
 input sys_clk,sys_rst_n,input [15:0] paddr,input psel,penable,pwrite,
 input [31:0] pwdata,output reg [31:0] prdata,
 input pixel_clk,pixel_rst_n,input vs_i,de_i,edge_i
);
 localparam SW=WIDTH/4, SH=HEIGHT/4, WORDS=SW*SH/32;
 reg [31:0] mem[0:WORDS-1];
 reg request_toggle; reg [11:0] read_addr; reg [31:0] read_data;
 reg done_meta,done_sync,done_seen; reg [31:0] completed; reg busy;
 reg done_toggle;
 always @(posedge sys_clk) read_data <= mem[read_addr];
 always @(posedge sys_clk or negedge sys_rst_n) begin
  if(!sys_rst_n) begin
   request_toggle<=0;read_addr<=0;done_meta<=0;done_sync<=0;done_seen<=0;completed<=0;busy<=0;
  end else begin
   done_meta<=done_toggle;done_sync<=done_meta;
   if(done_sync!=done_seen) begin done_seen<=done_sync;completed<=completed+1'b1;busy<=0;end
   if(psel&&penable&&pwrite) begin
    if(paddr==16'h0180&&pwdata[0]&&!busy) begin request_toggle<=~request_toggle;busy<=1;end
    if(paddr==16'h0188&&pwdata<WORDS) read_addr<=pwdata[11:0];
   end
  end
 end
 always @(*) begin
  case(paddr)
   16'h0180:prdata={31'd0,busy};
   16'h0184:prdata=completed;
   16'h0188:prdata={20'd0,read_addr};
   16'h018c:prdata=read_data;
   16'h0190:prdata=(SH<<16)|SW;
   default:prdata=0;
  endcase
 end
 reg req_meta,req_sync,req_seen,pending,active;
 reg vs_d,de_d;reg [11:0] x,y;reg horizontal;
 // Exactly SW groups arrive left-to-right on every captured row.
 // Rotate one previous-row bit at each group instead of a variable-index
 // read/write mux. After a full row, each column returns to the front.
 // y%4==0 ignores the old state, retaining the original reset semantics.
 reg [SW-1:0] vertical;reg [31:0] packed_word;
 reg write_en;reg [11:0] write_addr;reg [31:0] write_data;
 wire pooled=horizontal|edge_i|((y[1:0]==0)?1'b0:vertical[0]);
 always @(posedge pixel_clk) if(write_en) mem[write_addr]<=write_data;
 always @(posedge pixel_clk or negedge pixel_rst_n) begin
  if(!pixel_rst_n) begin
   req_meta<=0;req_sync<=0;req_seen<=0;pending<=0;active<=0;
   vs_d<=0;de_d<=0;x<=0;y<=0;horizontal<=0;packed_word<=0;
   write_en<=0;write_addr<=0;write_data<=0;done_toggle<=0;
  end else begin
   req_meta<=request_toggle;req_sync<=req_meta;vs_d<=vs_i;de_d<=de_i;write_en<=0;
   if(req_sync!=req_seen) begin req_seen<=req_sync;pending<=1;end
   if(vs_d&&!vs_i) begin
    x<=0;y<=0;horizontal<=0;packed_word<=0;
    if(pending) begin pending<=0;active<=1;end
   end else begin
    if(de_i) x<=x+1'b1;else x<=0;
    if(de_d&&!de_i) y<=y+1'b1;
    if(active&&de_i&&x<WIDTH&&y<HEIGHT) begin
     if(x[1:0]==0) horizontal<=edge_i;else horizontal<=horizontal|edge_i;
     if(x[1:0]==3) begin
      vertical<=(vertical>>1) | ({ {(SW-1){1'b0}},pooled } << (SW-1));horizontal<=0;
      if(y[1:0]==3) begin
       packed_word<={pooled,packed_word[31:1]};
       if(x[6:0]==127) begin
        write_en<=1;write_addr<=(y>>2)*(SW/32)+(x>>7);
        write_data<={pooled,packed_word[31:1]};
       end
      end
     end
     if(x==WIDTH-1&&y==HEIGHT-1) begin active<=0;done_toggle<=~done_toggle;end
    end
   end
  end
 end
endmodule
