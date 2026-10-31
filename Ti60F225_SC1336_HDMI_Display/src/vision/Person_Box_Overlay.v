`timescale 1ns / 1ps

// Draws CPU-provided person boxes after the edge/shape renderer.  Keeping
// this as the final video stage guarantees a detection rectangle covers a
// red edge pixel underneath it.
module Person_Box_Overlay #(
    parameter integer IMG_HDISP = 1280,
    parameter integer IMG_VDISP = 720,
    parameter integer MAX_BOXES = 16,
    parameter integer BOX_THICK = 3
)(
    input clk,
    input rst_n,
    input vs_i,
    input hs_i,
    input de_i,
    input [23:0] data_i,
    input mode_i,
    input [4:0] box_count_i,
    input [MAX_BOXES*16-1:0] box_x0_i,
    input [MAX_BOXES*16-1:0] box_y0_i,
    input [MAX_BOXES*16-1:0] box_x1_i,
    input [MAX_BOXES*16-1:0] box_y1_i,
    output reg vs_o,
    output reg hs_o,
    output reg de_o,
    output reg [23:0] data_o
);
    reg [11:0] x, y;
    reg de_d, vs_d;
    integer i;
    reg hit;
    // Box coordinates are 16-bit on the APB contract.  Keep the full width
    // here and compare it against the 12-bit raster counters after zero
    // extension; truncating the box bus caused Efinity warnings and could
    // wrap coordinates at the right/bottom edge.
    reg [15:0] x0, y0, x1, y1;
    // Move constant border offsets to the raster side of the comparisons.
    // These four add/subtract results are shared by all sixteen boxes.
    // Bit 31 detects a negative lower bound; keep all 16 APB coordinate bits.
    wire [31:0] x_low={20'd0,x}-(BOX_THICK-1);
    wire [31:0] y_low={20'd0,y}-(BOX_THICK-1);
    wire [31:0] x_high={20'd0,x}+(BOX_THICK-1);
    wire [31:0] y_high={20'd0,y}+(BOX_THICK-1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 12'd0;
            y <= 12'd0;
            de_d <= 1'b0;
            vs_d <= 1'b0;
            vs_o <= 1'b0;
            hs_o <= 1'b0;
            de_o <= 1'b0;
            data_o <= 24'd0;
        end else begin
            de_d <= de_i;
            vs_d <= vs_i;
            if (vs_d && !vs_i) begin
                x <= 12'd0;
                y <= 12'd0;
            end else begin
                if (de_i) x <= x + 1'b1;
                else x <= 12'd0;
                if (de_d && !de_i) y <= y + 1'b1;
            end

            hit = 1'b0;
            if (mode_i && de_i) begin
                for (i = 0; i < MAX_BOXES; i = i + 1) begin
                    if (i < box_count_i) begin
                        x0 = box_x0_i[i*16 +: 16];
                        y0 = box_y0_i[i*16 +: 16];
                        x1 = box_x1_i[i*16 +: 16];
                        y1 = box_y1_i[i*16 +: 16];
                        if ((x >= x0) && (x <= x1) && (y >= y0) && (y <= y1) &&
                            ((BOX_THICK>0 && BOX_THICK<=65536) ?
                             (y_low[31] || y0>=y_low || y1<=y_high ||
                              x_low[31] || x0>=x_low || x1<=x_high) :
                             ((y < y0 + BOX_THICK) || (y + BOX_THICK > y1) ||
                              (x < x0 + BOX_THICK) || (x + BOX_THICK > x1))))
                            hit = 1'b1;
                    end
                end
            end

            vs_o <= vs_i;
            hs_o <= hs_i;
            de_o <= de_i;
            data_o <= hit ? 24'h00FF00 : data_i;
        end
    end
endmodule
