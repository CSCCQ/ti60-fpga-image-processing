`timescale 1ns/1ps
// Capture the first long transaction stall. CPU debug reset does not clear
// this observer, so APB remains readable after a pipeline hang.
module Gray_Ddr_Diagnostics #(parameter STALL_BITS=20)(
    input clk, input rst_n,
    input [31:0] mux0_i, mux1_i, address_i, metadata_i, extra_i,
    output [351:0] words_o
);
    reg [STALL_BITS-1:0] age;
    reg captured;
    reg [31:0] last_address, last_metadata;
    reg [31:0] snap0, snap1, snap_address, snap_metadata, snap_extra;
    wire address_fire=mux1_i[20] && mux1_i[21];
    wire progress=address_fire || (mux1_i[22] && mux1_i[23]) ||
        (mux1_i[25] && mux1_i[26]) || (mux1_i[27] && mux1_i[28]);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            age<=0; captured<=0; last_address<=0; last_metadata<=0;
            snap0<=0; snap1<=0; snap_address<=0; snap_metadata<=0; snap_extra<=0;
        end else begin
            if(address_fire) begin last_address<=address_i; last_metadata<=metadata_i; end
            if(!(mux1_i[0] || mux1_i[20]) || progress) age<=0;
            else if(!(&age)) age<=age+1'b1;
            if((&age) && !captured && (mux1_i[0] || mux1_i[20]) && !progress) begin
                captured<=1; snap0<=mux0_i; snap1<=mux1_i;
                snap_address<=last_address; snap_metadata<=last_metadata; snap_extra<=extra_i;
            end
        end
    end
    assign words_o={extra_i,snap_extra,snap_metadata,snap_address,snap1,snap0,
        last_address,mux1_i,mux0_i,{captured,11'd0,{{(20-STALL_BITS){1'b0}},age}},32'h44445231};
endmodule
