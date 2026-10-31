`timescale 1ns/1ps
// Repeat the same central half-width ROI on both sides of the screen.
// Read the previous line while writing the current line. The first output
// line of each frame is black so stale/uninitialized RAM is never displayed.
module Center_Split #(
    parameter integer IMG_HDISP = 1280
)(
    input clk, rst_n,
    input vs_i, hs_i, de_i,
    input [7:0] gray_i,
    input edge_i,
    output reg vs_o, hs_o, de_o,
    output [23:0] data_o
);
    localparam integer HALF = IMG_HDISP / 2;
    localparam integer ROI_X0 = (IMG_HDISP - HALF) / 2;
    reg [11:0] x;
    reg de_d, vs_d, bank, line_valid;
    reg [8:0] line_ram [0:IMG_HDISP-1];
    reg [8:0] read_data;
    reg right_d, valid_d;
    wire [11:0] write_index = x - ROI_X0;
    wire [11:0] read_index = x < HALF ? x : x - HALF;
    wire [11:0] write_addr = (bank ? HALF : 0) + write_index;
    wire [11:0] read_addr = (bank ? 0 : HALF) + read_index;
    wire write_en = de_i && x >= ROI_X0 && x < ROI_X0 + HALF;

    // No reset on the RAM port, allowing embedded block RAM inference.
    always @(posedge clk) begin
        if(write_en) line_ram[write_addr] <= {gray_i, edge_i};
        if(de_i) read_data <= line_ram[read_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x <= 0;
            de_d <= 0; vs_d <= 0; bank <= 0; line_valid <= 0;
            vs_o <= 0; hs_o <= 0; de_o <= 0;
            right_d <= 0; valid_d <= 0;
        end else begin
            de_d <= de_i;
            vs_d <= vs_i;
            x <= de_i ? x + 1'b1 : 12'd0;
            if(vs_d && !vs_i) begin
                x <= 0;
                bank <= 0;
                line_valid <= 0;
            end else if(de_d && !de_i) begin
                bank <= ~bank;
                line_valid <= 1;
            end
            vs_o <= vs_i;
            hs_o <= hs_i;
            de_o <= de_i;
            right_d <= x >= HALF;
            valid_d <= line_valid;
        end
    end
    assign data_o = !de_o || !valid_d ? 24'd0 :
                    right_d ? {24{read_data[0]}} : {3{read_data[8:1]}};
endmodule
