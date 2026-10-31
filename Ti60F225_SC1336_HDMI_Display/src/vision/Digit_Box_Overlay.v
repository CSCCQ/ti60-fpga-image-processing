`timescale 1ns / 1ps

// Labels and boxes share each CPU result slot. The video path stays one
// clock long. A shared engine prepares each scan line during horizontal
// blanking (MAX_BOXES+3 clocks minimum; production provides 370 clocks).
module Digit_Box_Overlay #(
    parameter integer IMG_HDISP=1280, IMG_VDISP=720,
    parameter integer MAX_BOXES=16, BOX_THICK=3
)(
    input clk, rst_n, vs_i, hs_i, de_i,
    input [23:0] data_i,
    input mode_i,
    input [4:0] box_count_i,
    input [MAX_BOXES*4-1:0] box_labels_i,
    input [MAX_BOXES*16-1:0] box_x0_i,box_y0_i,box_x1_i,box_y1_i,
    output reg vs_o,hs_o,de_o,
    output reg [23:0] data_o
);
    localparam integer TAG_W=24,TAG_H=32,TAG_GAP=2,TAG_INSET=BOX_THICK+1;
    localparam integer TAG_RIGHT=IMG_HDISP-TAG_W,TAG_BOTTOM=IMG_VDISP-TAG_H;
    reg [11:0] x,y;
    reg de_d,vs_d;
    wire frame_start=vs_d&&!vs_i;
    wire [11:0] scan_y=frame_start ? 12'd0 : (de_d&&!de_i) ? y+12'd1 : y;
    wire [31:0] x_low={20'd0,x}-(BOX_THICK-1);
    wire [31:0] x_high={20'd0,x}+(BOX_THICK-1);
    wire [16:0] tag_x_low={5'd0,x}-TAG_W;

    function [34:0] digit_font;input [3:0] n;begin case(n)
      0:digit_font=35'b01110_10001_10011_10101_11001_10001_01110;
      1:digit_font=35'b00100_01100_00100_00100_00100_00100_01110;
      2:digit_font=35'b01110_10001_00001_00010_00100_01000_11111;
      3:digit_font=35'b11110_00001_00001_01110_00001_00001_11110;
      4:digit_font=35'b00010_00110_01010_10010_11111_00010_00010;
      5:digit_font=35'b11111_10000_10000_11110_00001_00001_11110;
      6:digit_font=35'b01110_10000_10000_11110_10001_10001_01110;
      7:digit_font=35'b11111_00001_00010_00100_01000_01000_01000;
      8:digit_font=35'b01110_10001_10001_01110_10001_10001_01110;
      9:digit_font=35'b01110_10001_10001_01111_00001_00001_01110;
      default:digit_font=0;
    endcase end endfunction

    // Flat, asynchronously reset register banks: no additional block RAM.
    reg [MAX_BOXES-1:0] row_valid,row_border,tag_valid;
    reg [MAX_BOXES*12-1:0] tag_left_bank;
    reg [MAX_BOXES*5-1:0] tag_ink_bank;
    reg [4:0] scan_slot,s0_slot,s1_slot;
    reg s0_valid,s1_valid,s0_enabled;
    reg [15:0] s0_x0,s0_y0,s0_x1,s0_y1;
    reg [11:0] s0_y;reg [3:0] s0_label;
    reg s1_row_valid,s1_row_border,s1_tag_valid,s1_ink_valid;
    reg [11:0] s1_left;reg [2:0] s1_glyph_row;reg [3:0] s1_label;
    integer prep_left,prep_top,prep_row;
    reg prep_row_valid,prep_row_border,prep_tag_valid,prep_ink_valid;
    wire [34:0] scan_glyph=digit_font(s1_label);
    wire [4:0] scan_ink=s1_ink_valid ? (scan_glyph>>(30-s1_glyph_row*5)) : 5'd0;
    always @(*) begin
        prep_left={16'd0,s0_x0}+TAG_INSET;
        if(prep_left>TAG_RIGHT)prep_left=TAG_RIGHT;
        if(s0_y0>=TAG_H+TAG_GAP)prep_top={16'd0,s0_y0}-TAG_H-TAG_GAP;
        else begin
            prep_top={16'd0,s0_y0}+TAG_INSET;
            if(prep_top>TAG_BOTTOM)prep_top=TAG_BOTTOM;
        end
        // Reserve the mode/status title and the upper-left FPS/threshold panel. A label that
        // would intersect that panel moves below its box, without making
        // the label jump when freeze/replay status appears.
        // prep_left is clamped to [TAG_INSET, IMG_HDISP-TAG_W],
        // prep_top is nonnegative for the supported dimensions. Remove
        // redundant wide additions/comparisons in this overlap test.
        if(IMG_HDISP>=224 && IMG_VDISP>=120 &&
           ((BOX_THICK>=0 && BOX_THICK<65536) ?
            (((IMG_HDISP<248 || prep_left>IMG_HDISP-248) && prep_top<88) ||
             (IMG_HDISP>=512 && prep_left<264 && prep_top<40)) :
            (((prep_left+TAG_W>IMG_HDISP-224 && prep_left<IMG_HDISP-16) ||
              (IMG_HDISP>=512 && prep_left+TAG_W>24 && prep_left<264 && prep_top<40)) &&
             prep_top<88 && prep_top+TAG_H>8)))begin
            prep_top={16'd0,s0_y1}+TAG_GAP;
            if(prep_top<90)prep_top=90;
            if(prep_top>TAG_BOTTOM)prep_top=TAG_BOTTOM;
        end
        prep_row_valid=s0_enabled && s0_y>=s0_y0 && s0_y<=s0_y1;
        prep_row_border=(s0_y<s0_y0+BOX_THICK)||(s0_y+BOX_THICK>s0_y1);
        prep_tag_valid=s0_enabled && s0_label<10 &&
            s0_x0<IMG_HDISP && s0_y0<IMG_VDISP &&
            s0_x0<=s0_x1 && s0_y0<=s0_y1 &&
            s0_y>=prep_top && s0_y<prep_top+TAG_H;
        prep_ink_valid=s0_y>=prep_top+2 && s0_y<prep_top+30;
        prep_row=(s0_y-prep_top-2)>>2;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            scan_slot<=0;s0_slot<=0;s1_slot<=0;s0_valid<=0;s1_valid<=0;
            s0_enabled<=0;s0_x0<=0;s0_y0<=0;s0_x1<=0;s0_y1<=0;s0_y<=0;s0_label<=0;
            s1_row_valid<=0;s1_row_border<=0;s1_tag_valid<=0;s1_ink_valid<=0;
            s1_left<=0;s1_glyph_row<=0;s1_label<=0;
            row_valid<=0;row_border<=0;tag_valid<=0;tag_left_bank<=0;tag_ink_bank<=0;
        end else if(frame_start)begin
            scan_slot<=0;s0_valid<=0;s1_valid<=0;row_valid<=0;tag_valid<=0;
        end else if(de_i)begin
            // Keep all row attributes fixed throughout active video.
            scan_slot<=0;s0_valid<=0;s1_valid<=0;
        end else begin
            if(s1_valid)begin
                row_valid[s1_slot]<=s1_row_valid;
                row_border[s1_slot]<=s1_row_border;
                tag_valid[s1_slot]<=s1_tag_valid;
                tag_left_bank[s1_slot*12 +:12]<=s1_left;
                tag_ink_bank[s1_slot*5 +:5]<=scan_ink;
            end
            s1_valid<=s0_valid;
            if(s0_valid)begin
                s1_slot<=s0_slot;s1_row_valid<=prep_row_valid;
                s1_row_border<=prep_row_border;s1_tag_valid<=prep_tag_valid;
                s1_ink_valid<=prep_ink_valid;s1_left<=prep_left[11:0];
                s1_glyph_row<=prep_row[2:0];s1_label<=s0_label;
            end
            s0_valid<=1;s0_slot<=scan_slot;s0_enabled<=scan_slot<box_count_i;
            s0_x0<=box_x0_i[scan_slot*16 +:16];s0_y0<=box_y0_i[scan_slot*16 +:16];
            s0_x1<=box_x1_i[scan_slot*16 +:16];s0_y1<=box_y1_i[scan_slot*16 +:16];
            s0_y<=scan_y;s0_label<=box_labels_i[scan_slot*4 +:4];
            if(scan_slot==MAX_BOXES-1)scan_slot<=0;else scan_slot<=scan_slot+1'b1;
        end
    end

    reg panel,text_hit;reg [11:0] left,selected_left,offset_x;
    reg [4:0] ink;integer slot;
    always @(*)begin
        panel=0;text_hit=0;left=0;selected_left=0;ink=0;offset_x=0;
        if(mode_i && de_i)begin
            // Reverse priority mux: lowest result slot owns an overlap.
            for(slot=MAX_BOXES-1;slot>=0;slot=slot-1)begin
                left=tag_left_bank[slot*12 +:12];
                if(tag_valid[slot] && x>=left && (tag_x_low[16]||left>tag_x_low))begin
                    panel=1;selected_left=left;ink=tag_ink_bank[slot*5 +:5];
                end
            end
            if(panel)begin
                offset_x=x-selected_left;
                if(offset_x>=2&&offset_x<22)text_hit=ink[4-((offset_x-2)>>2)];
            end else if(x>=8&&x<16&&y>=8&&y<16)text_hit=1;
        end
    end
    integer i;reg hit;reg [15:0] x0,x1;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            x<=0;y<=0;de_d<=0;vs_d<=0;vs_o<=0;hs_o<=0;de_o<=0;data_o<=0;
        end else begin
            de_d<=de_i;vs_d<=vs_i;
            if(frame_start)begin x<=0;y<=0;end
            else begin
                if(de_i)x<=x+1'b1;else x<=0;
                if(de_d&&!de_i)y<=y+1'b1;
            end
            hit=0;
            if(mode_i&&de_i)begin
                for(i=0;i<MAX_BOXES;i=i+1)begin
                    x0=box_x0_i[i*16 +:16];x1=box_x1_i[i*16 +:16];
                    if(row_valid[i] && x>=x0 && x<=x1 &&
                       (row_border[i] ||
                        ((BOX_THICK>0&&BOX_THICK<=65536) ?
                         (x_low[31]||x0>=x_low||x1<=x_high) :
                         (x<x0+BOX_THICK||x+BOX_THICK>x1))))hit=1;
                end
            end
            vs_o<=vs_i;hs_o<=hs_i;de_o<=de_i;
            data_o<=text_hit ? 24'h00ff00 : panel ? 24'h000000 : hit ? 24'h00ff00 : data_i;
        end
    end
endmodule
