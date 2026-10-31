`timescale 1ns/1ps
// Delay one complete active-pixel line, plus the synchronous RAM-read clock.
// The extra word separates read and write addresses: no read-during-write
// behaviour is assumed. The caller suppresses the initial warm-up line.
module Display_Line_Delay #(parameter integer WIDTH=1280)(
    input clk,rst_n,vs_i,de_i,
    input [23:0] data_i,
    output reg [23:0] data_o
);
    localparam integer ADDR_BITS=$clog2(WIDTH+1);
    (* syn_ramstyle = "block_ram" *) reg [23:0] line_ram [0:WIDTH];
    reg [ADDR_BITS-1:0] write_addr,read_addr;
    reg vs_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin write_addr<=0;read_addr<=1;vs_d<=0;end
        else begin
            vs_d<=vs_i;
            if(vs_d && !vs_i) begin write_addr<=0;read_addr<=1;end
            else if(de_i) begin
                write_addr<=write_addr==WIDTH ? 0 : write_addr+1'b1;
                read_addr<=read_addr==WIDTH ? 0 : read_addr+1'b1;
            end
        end
    end
    always @(posedge clk) if(de_i) begin
        line_ram[write_addr]<=data_i;
        data_o<=line_ram[read_addr];
    end
endmodule
