`timescale 1ns / 1ps
// Final, common HDMI stage: Chinese mode name plus freeze/replay status.
// Small combinational font tables use logic, not another line/frame RAM.
// Both pixel data and HS/VS/DE are delayed by exactly two clocks.
module Mode_Label_Overlay #(parameter integer IMG_HDISP=1280,
    parameter integer PIXEL_HZ=74250000)(
    input clk, input rst_n,
    input vs_i, input hs_i, input de_i, input [23:0] data_i,
    input [2:0] display_mode_i,
    input [11:0] threshold_i, // Actual threshold used by the selected edge detector, not the pending key request.
    input digit_mode_i, input shape_mode_i, input freeze_i, input replay_i,
    output reg vs_o, output reg hs_o, output reg de_o,
    output reg [23:0] data_o
);
    localparam integer PANEL_LEFT=IMG_HDISP-224;
    localparam integer PANEL_RIGHT=IMG_HDISP-16;
    localparam integer TEXT_LEFT=IMG_HDISP-216;
    reg [11:0] x,y;
    reg de_prev,vs_prev;
    reg [3:0] title_mode;
    reg [1:0] status_mode;
    wire [11:0] tx=x-TEXT_LEFT;
    wire status_line=(y>=12'd48);
    wire [11:0] ty=status_line ? y-12'd52 : y-12'd12;
    wire [2:0] slot=tx[7:5];
    wire [3:0] glyph_x=tx[4:1];
    wire [3:0] glyph_y=ty[4:1];
    wire panel=IMG_HDISP>=224 && de_i &&
        x>=PANEL_LEFT && x<PANEL_RIGHT && y>=8 &&
        (y<48 || (status_mode!=0 && y<88));
    wire text_area=panel && x>=TEXT_LEFT && x<TEXT_LEFT+192 &&
        ((!status_line && y>=12 && y<44) ||
         (status_line && y>=52 && y<84));
    reg [5:0] glyph_id;
    // Count actual non-empty HDMI frames in a one-second pixel-clock
    // window. This is display FPS (including repeated frozen/replay frames),
    // not camera capture FPS or neural-network inference FPS.
    localparam integer SECOND_TICKS=(PIXEL_HZ<1)?1:PIXEL_HZ;
    localparam integer SECOND_BITS=(SECOND_TICKS<2)?1:$clog2(SECOND_TICKS);
    reg [SECOND_BITS-1:0] second_count;
    reg frame_has_pixels;
    reg [7:0] frame_bcd, measured_bcd, shown_bcd;
    reg fps_valid, shown_valid;
    wire frame_done=vs_prev && !vs_i && frame_has_pixels;
    wire [7:0] next_frame_bcd = !frame_done || frame_bcd==8'h99 ? frame_bcd :
        frame_bcd[3:0]==9 ? {frame_bcd[7:4]+4'd1,4'd0} : frame_bcd+8'd1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            second_count<=0;frame_has_pixels<=0;frame_bcd<=0;
            measured_bcd<=0;shown_bcd<=0;fps_valid<=0;shown_valid<=0;
        end else begin
            if(vs_prev && !vs_i) frame_has_pixels<=0;
            else if(de_i) frame_has_pixels<=1;
            if(second_count==SECOND_TICKS-1) begin
                second_count<=0;measured_bcd<=next_frame_bcd;
                frame_bcd<=0;fps_valid<=1;
            end else begin
                second_count<=second_count+1'b1;
                frame_bcd<=next_frame_bcd;
            end
            // Keep both digits stable throughout the visible frame.
            if(!vs_i) begin shown_bcd<=measured_bcd;shown_valid<=fps_valid;end
        end
    end
    // Convert the applied threshold during vertical blanking with a small
    // serial double-dabble converter. No divider, multiplier or RAM.
    // The display register never changes during visible video.
    reg [27:0] threshold_work;
    reg [15:0] threshold_shown;
    reg [3:0] threshold_steps;
    reg [27:0] threshold_adjusted;
    integer decimal_digit;
    always @(*) begin
        threshold_adjusted=threshold_work;
        for(decimal_digit=0;decimal_digit<4;decimal_digit=decimal_digit+1)
            if(threshold_work[12+decimal_digit*4 +: 4]>=5)
                threshold_adjusted[12+decimal_digit*4 +: 4]=
                    threshold_work[12+decimal_digit*4 +: 4]+4'd3;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            threshold_work<=0;threshold_shown<=0;threshold_steps<=0;
        end else if(vs_i) begin
            threshold_steps<=0;
        end else if(threshold_steps==0) begin
            threshold_work<={16'd0,threshold_i};threshold_steps<=12;
        end else begin
            threshold_work<={threshold_adjusted[26:0],1'b0};
            threshold_steps<=threshold_steps-1'b1;
            if(threshold_steps==1) threshold_shown<=threshold_adjusted[26:11];
        end
    end
    // 5x7 font at 2x scale, sharing the title's existing two-stage pipeline.
    // Tiny simulation widths omit this panel to avoid the right-hand title.
    wire fps_panel=(IMG_HDISP>=512) && de_i && x>=24 && x<264 && y>=8 && y<40;
    wire fps_text=fps_panel && x>=32 && x<256 && y>=16 && y<30 && x[3:1]<5;
    wire [3:0] fps_slot=x[7:4]-4'd2;
    reg [4:0] fps_character;
    always @(*) begin
        case(fps_slot)
            0:fps_character=10; // F
            1:fps_character=11; // P
            2:fps_character=12; // S
            3:fps_character=13; // :
            4:fps_character=shown_valid ? shown_bcd[7:4] : 4'd14;
            5:fps_character=shown_valid ? shown_bcd[3:0] : 4'd14;
            7:fps_character=16; // T
            8:fps_character=17; // H
            9:fps_character=13; // :
            10:fps_character=threshold_shown[15:12]!=0 ? {1'b0,threshold_shown[15:12]} : 5'd15;
            11:fps_character=threshold_shown[15:8]!=0 ? {1'b0,threshold_shown[11:8]} : 5'd15;
            12:fps_character=threshold_shown[15:4]!=0 ? {1'b0,threshold_shown[7:4]} : 5'd15;
            13:fps_character={1'b0,threshold_shown[3:0]};
            default:fps_character=15;
        endcase
    end
    function [4:0] fps_font_row;
        input [4:0] character;
        input [2:0] row;
        reg [34:0] pixels;
        begin
            case(character)
                0:pixels=35'b01110_10001_10011_10101_11001_10001_01110;
                1:pixels=35'b00100_01100_00100_00100_00100_00100_01110;
                2:pixels=35'b01110_10001_00001_00010_00100_01000_11111;
                3:pixels=35'b11110_00001_00001_01110_00001_00001_11110;
                4:pixels=35'b00010_00110_01010_10010_11111_00010_00010;
                5:pixels=35'b11111_10000_10000_11110_00001_00001_11110;
                6:pixels=35'b01110_10000_10000_11110_10001_10001_01110;
                7:pixels=35'b11111_00001_00010_00100_01000_01000_01000;
                8:pixels=35'b01110_10001_10001_01110_10001_10001_01110;
                9:pixels=35'b01110_10001_10001_01111_00001_00001_01110;
                10:pixels=35'b11111_10000_10000_11110_10000_10000_10000;
                11:pixels=35'b11110_10001_10001_11110_10000_10000_10000;
                12:pixels=35'b01111_10000_10000_01110_00001_00001_11110;
                13:pixels=35'b00000_00100_00100_00000_00100_00100_00000;
                14:pixels=35'b00000_00000_00000_01110_00000_00000_00000;
                16:pixels=35'b11111_00100_00100_00100_00100_00100_00100;
                17:pixels=35'b10001_10001_10001_11111_10001_10001_10001;
                default:pixels=0;
            endcase
            case(row)
                0:fps_font_row=pixels[34:30];1:fps_font_row=pixels[29:25];
                2:fps_font_row=pixels[24:20];3:fps_font_row=pixels[19:15];
                4:fps_font_row=pixels[14:10];5:fps_font_row=pixels[9:5];
                6:fps_font_row=pixels[4:0];default:fps_font_row=0;
            endcase
        end
    endfunction
    // BEGIN GENERATED FONT
    always @(*) begin
        glyph_id=0;
        if(status_line) begin
            case({status_mode,slot})
                5'd12:glyph_id=6'd31;
                5'd13:glyph_id=6'd32;
                5'd20:glyph_id=6'd33;
                5'd21:glyph_id=6'd34;
                default:glyph_id=0;
            endcase
        end else begin
            case({title_mode,slot})
                7'd2:glyph_id=6'd1;
                7'd3:glyph_id=6'd2;
                7'd4:glyph_id=6'd3;
                7'd5:glyph_id=6'd4;
                7'd9:glyph_id=6'd5;
                7'd10:glyph_id=6'd6;
                7'd11:glyph_id=6'd7;
                7'd12:glyph_id=6'd8;
                7'd13:glyph_id=6'd9;
                7'd16:glyph_id=6'd10;
                7'd17:glyph_id=6'd11;
                7'd18:glyph_id=6'd12;
                7'd19:glyph_id=6'd13;
                7'd20:glyph_id=6'd14;
                7'd21:glyph_id=6'd15;
                7'd26:glyph_id=6'd16;
                7'd27:glyph_id=6'd17;
                7'd28:glyph_id=6'd18;
                7'd29:glyph_id=6'd19;
                7'd32:glyph_id=6'd5;
                7'd33:glyph_id=6'd6;
                7'd34:glyph_id=6'd20;
                7'd35:glyph_id=6'd21;
                7'd36:glyph_id=6'd22;
                7'd37:glyph_id=6'd23;
                7'd42:glyph_id=6'd4;
                7'd43:glyph_id=6'd24;
                7'd44:glyph_id=6'd22;
                7'd45:glyph_id=6'd23;
                7'd49:glyph_id=6'd25;
                7'd50:glyph_id=6'd13;
                7'd51:glyph_id=6'd26;
                7'd52:glyph_id=6'd27;
                7'd53:glyph_id=6'd28;
                7'd56:glyph_id=6'd25;
                7'd57:glyph_id=6'd13;
                7'd58:glyph_id=6'd20;
                7'd59:glyph_id=6'd21;
                7'd60:glyph_id=6'd22;
                7'd61:glyph_id=6'd23;
                7'd66:glyph_id=6'd25;
                7'd67:glyph_id=6'd13;
                7'd68:glyph_id=6'd29;
                7'd69:glyph_id=6'd30;
                7'd74:glyph_id=6'd5;
                7'd75:glyph_id=6'd6;
                7'd76:glyph_id=6'd29;
                7'd77:glyph_id=6'd30;
                default:glyph_id=0;
            endcase
        end
    end
    function [15:0] font_row;
        input [5:0] character;input [3:0] row;
        begin case(character)
            6'd1:begin case(row)
                4'd0:font_row=16'h0100;
                4'd1:font_row=16'h0784;
                4'd2:font_row=16'h7804;
                4'd3:font_row=16'h0888;
                4'd4:font_row=16'h4490;
                4'd5:font_row=16'h2522;
                4'd6:font_row=16'h2002;
                4'd7:font_row=16'h0404;
                4'd8:font_row=16'h7f88;
                4'd9:font_row=16'h0c10;
                4'd10:font_row=16'h1622;
                4'd11:font_row=16'h1502;
                4'd12:font_row=16'h2484;
                4'd13:font_row=16'h4408;
                4'd14:font_row=16'h8410;
                4'd15:font_row=16'h0460;
                default:font_row=0;endcase end
            6'd2:begin case(row)
                4'd0:font_row=16'h0800;
                4'd1:font_row=16'h0800;
                4'd2:font_row=16'h1fe0;
                4'd3:font_row=16'h2020;
                4'd4:font_row=16'h4040;
                4'd5:font_row=16'hbff8;
                4'd6:font_row=16'h2108;
                4'd7:font_row=16'h2108;
                4'd8:font_row=16'h2108;
                4'd9:font_row=16'h3ff8;
                4'd10:font_row=16'h2000;
                4'd11:font_row=16'h2002;
                4'd12:font_row=16'h2002;
                4'd13:font_row=16'h2002;
                4'd14:font_row=16'h1ffe;
                default:font_row=0;endcase end
            6'd3:begin case(row)
                4'd0:font_row=16'h3ffe;
                4'd1:font_row=16'h2080;
                4'd2:font_row=16'h2100;
                4'd3:font_row=16'h27f0;
                4'd4:font_row=16'h2410;
                4'd5:font_row=16'h2410;
                4'd6:font_row=16'h27f0;
                4'd7:font_row=16'h2410;
                4'd8:font_row=16'h2410;
                4'd9:font_row=16'h27f0;
                4'd10:font_row=16'h2080;
                4'd11:font_row=16'h2490;
                4'd12:font_row=16'h4888;
                4'd13:font_row=16'h5284;
                4'd14:font_row=16'h8100;
                default:font_row=0;endcase end
            6'd4:begin case(row)
                4'd0:font_row=16'h7ffc;
                4'd1:font_row=16'h4204;
                4'd2:font_row=16'h4204;
                4'd3:font_row=16'h47e4;
                4'd4:font_row=16'h4c44;
                4'd5:font_row=16'h5284;
                4'd6:font_row=16'h4104;
                4'd7:font_row=16'h46c4;
                4'd8:font_row=16'h783c;
                4'd9:font_row=16'h4304;
                4'd10:font_row=16'h4084;
                4'd11:font_row=16'h4604;
                4'd12:font_row=16'h4184;
                4'd13:font_row=16'h7ffc;
                4'd14:font_row=16'h4004;
                default:font_row=0;endcase end
            6'd5:begin case(row)
                4'd0:font_row=16'h0200;
                4'd1:font_row=16'h0100;
                4'd2:font_row=16'hfffe;
                4'd4:font_row=16'h0fe0;
                4'd5:font_row=16'h0820;
                4'd6:font_row=16'h0820;
                4'd7:font_row=16'h0fe0;
                4'd9:font_row=16'h7ffc;
                4'd10:font_row=16'h4004;
                4'd11:font_row=16'h4fe4;
                4'd12:font_row=16'h4824;
                4'd13:font_row=16'h4824;
                4'd14:font_row=16'h4fe4;
                4'd15:font_row=16'h400c;
                default:font_row=0;endcase end
            6'd6:begin case(row)
                4'd0:font_row=16'h2200;
                4'd1:font_row=16'h2204;
                4'd2:font_row=16'h7f78;
                4'd3:font_row=16'h2240;
                4'd4:font_row=16'h2240;
                4'd5:font_row=16'h3e40;
                4'd6:font_row=16'h227e;
                4'd7:font_row=16'h2248;
                4'd8:font_row=16'h3e48;
                4'd9:font_row=16'h2248;
                4'd10:font_row=16'h2248;
                4'd11:font_row=16'hff48;
                4'd12:font_row=16'h0448;
                4'd13:font_row=16'h2288;
                4'd14:font_row=16'h4188;
                4'd15:font_row=16'h8108;
                default:font_row=0;endcase end
            6'd7:begin case(row)
                4'd7:font_row=16'h1c38;
                4'd8:font_row=16'h2244;
                4'd9:font_row=16'h4004;
                4'd10:font_row=16'h403c;
                4'd11:font_row=16'h4044;
                4'd12:font_row=16'h2246;
                4'd13:font_row=16'h3c36;
                default:font_row=0;endcase end
            6'd8:begin case(row)
                4'd7:font_row=16'hdcdc;
                4'd8:font_row=16'h6262;
                4'd9:font_row=16'h4242;
                4'd10:font_row=16'h4242;
                4'd11:font_row=16'h4242;
                4'd12:font_row=16'h4242;
                4'd13:font_row=16'he7e7;
                default:font_row=0;endcase end
            6'd9:begin case(row)
                4'd7:font_row=16'h6600;
                4'd8:font_row=16'h2400;
                4'd9:font_row=16'h2400;
                4'd11:font_row=16'h1800;
                4'd12:font_row=16'h0800;
                4'd14:font_row=16'h1000;
                4'd15:font_row=16'h6000;
                default:font_row=0;endcase end
            6'd10:begin case(row)
                4'd0:font_row=16'h0400;
                4'd1:font_row=16'h0400;
                4'd2:font_row=16'h0400;
                4'd3:font_row=16'hfffe;
                4'd4:font_row=16'h0800;
                4'd5:font_row=16'h0880;
                4'd6:font_row=16'h0884;
                4'd7:font_row=16'h1284;
                4'd8:font_row=16'h1288;
                4'd9:font_row=16'h2490;
                4'd10:font_row=16'h2940;
                4'd11:font_row=16'h4140;
                4'd12:font_row=16'h8220;
                4'd13:font_row=16'h0410;
                4'd14:font_row=16'h1808;
                4'd15:font_row=16'h6006;
                default:font_row=0;endcase end
            6'd11:begin case(row)
                4'd0:font_row=16'h0100;
                4'd1:font_row=16'h0080;
                4'd2:font_row=16'h3ffe;
                4'd3:font_row=16'h2220;
                4'd4:font_row=16'h2220;
                4'd5:font_row=16'h3ffc;
                4'd6:font_row=16'h2220;
                4'd7:font_row=16'h2220;
                4'd8:font_row=16'h23e0;
                4'd9:font_row=16'h2000;
                4'd10:font_row=16'h2ff0;
                4'd11:font_row=16'h2410;
                4'd12:font_row=16'h4220;
                4'd13:font_row=16'h41c0;
                4'd14:font_row=16'h8630;
                4'd15:font_row=16'h380e;
                default:font_row=0;endcase end
            6'd12:begin case(row)
                4'd2:font_row=16'h3ff8;
                4'd11:font_row=16'hfffe;
                default:font_row=0;endcase end
            6'd13:begin case(row)
                4'd0:font_row=16'h0840;
                4'd1:font_row=16'h0840;
                4'd2:font_row=16'h0ffc;
                4'd3:font_row=16'h1040;
                4'd4:font_row=16'h1040;
                4'd5:font_row=16'h33f8;
                4'd6:font_row=16'h3208;
                4'd7:font_row=16'h53f8;
                4'd8:font_row=16'h9208;
                4'd9:font_row=16'h13f8;
                4'd10:font_row=16'h1208;
                4'd11:font_row=16'h13f8;
                4'd12:font_row=16'h1208;
                4'd13:font_row=16'h1208;
                4'd14:font_row=16'h1ffe;
                4'd15:font_row=16'h1000;
                default:font_row=0;endcase end
            6'd14:begin case(row)
                4'd0:font_row=16'h0040;
                4'd1:font_row=16'h0440;
                4'd2:font_row=16'h0420;
                4'd3:font_row=16'h0820;
                4'd4:font_row=16'h1010;
                4'd5:font_row=16'h2008;
                4'd6:font_row=16'h4004;
                4'd7:font_row=16'h9fe2;
                4'd8:font_row=16'h0420;
                4'd9:font_row=16'h0420;
                4'd10:font_row=16'h0420;
                4'd11:font_row=16'h0820;
                4'd12:font_row=16'h0820;
                4'd13:font_row=16'h1020;
                4'd14:font_row=16'h2140;
                4'd15:font_row=16'h4080;
                default:font_row=0;endcase end
            6'd15:begin case(row)
                4'd0:font_row=16'h3ff8;
                4'd1:font_row=16'h2008;
                4'd2:font_row=16'h2008;
                4'd3:font_row=16'h3ff8;
                4'd4:font_row=16'h2410;
                4'd5:font_row=16'h2220;
                4'd6:font_row=16'h2ff8;
                4'd7:font_row=16'h2220;
                4'd8:font_row=16'h2220;
                4'd9:font_row=16'h3ffc;
                4'd10:font_row=16'h2220;
                4'd11:font_row=16'h4220;
                4'd12:font_row=16'h4420;
                4'd13:font_row=16'h8420;
                4'd14:font_row=16'h0820;
                default:font_row=0;endcase end
            6'd16:begin case(row)
                4'd0:font_row=16'h1000;
                4'd1:font_row=16'h1000;
                4'd2:font_row=16'h21fc;
                4'd3:font_row=16'h2420;
                4'd4:font_row=16'h4420;
                4'd5:font_row=16'hf820;
                4'd6:font_row=16'h1020;
                4'd7:font_row=16'h2020;
                4'd8:font_row=16'h4020;
                4'd9:font_row=16'hfc20;
                4'd10:font_row=16'h4020;
                4'd11:font_row=16'h0020;
                4'd12:font_row=16'h1c20;
                4'd13:font_row=16'he020;
                4'd14:font_row=16'h43fe;
                default:font_row=0;endcase end
            6'd17:begin case(row)
                4'd0:font_row=16'h0040;
                4'd1:font_row=16'h2040;
                4'd2:font_row=16'h1040;
                4'd3:font_row=16'h13fc;
                4'd4:font_row=16'h0044;
                4'd5:font_row=16'h0044;
                4'd6:font_row=16'hf044;
                4'd7:font_row=16'h1084;
                4'd8:font_row=16'h1084;
                4'd9:font_row=16'h1104;
                4'd10:font_row=16'h1104;
                4'd11:font_row=16'h1228;
                4'd12:font_row=16'h1410;
                4'd13:font_row=16'h2800;
                4'd14:font_row=16'h47fe;
                default:font_row=0;endcase end
            6'd18:begin case(row)
                4'd0:font_row=16'h1fe0;
                4'd1:font_row=16'h0440;
                4'd2:font_row=16'h0380;
                4'd3:font_row=16'h0c40;
                4'd4:font_row=16'h7efc;
                4'd5:font_row=16'h2244;
                4'd6:font_row=16'h1c38;
                4'd7:font_row=16'h6244;
                4'd9:font_row=16'hfffe;
                4'd10:font_row=16'h9012;
                4'd11:font_row=16'h1ff0;
                4'd12:font_row=16'h1010;
                4'd13:font_row=16'h1ff0;
                4'd14:font_row=16'h1010;
                4'd15:font_row=16'hfffe;
                default:font_row=0;endcase end
            6'd19:begin case(row)
                4'd0:font_row=16'h1000;
                4'd1:font_row=16'h1000;
                4'd2:font_row=16'h1000;
                4'd3:font_row=16'h107c;
                4'd4:font_row=16'hfe44;
                4'd5:font_row=16'h1244;
                4'd6:font_row=16'h1244;
                4'd7:font_row=16'h1244;
                4'd8:font_row=16'h1244;
                4'd9:font_row=16'h1244;
                4'd10:font_row=16'h1244;
                4'd11:font_row=16'h1244;
                4'd12:font_row=16'h2244;
                4'd13:font_row=16'h227c;
                4'd14:font_row=16'h4a44;
                4'd15:font_row=16'h8400;
                default:font_row=0;endcase end
            6'd20:begin case(row)
                4'd0:font_row=16'h0820;
                4'd1:font_row=16'h4920;
                4'd2:font_row=16'h2a20;
                4'd3:font_row=16'h083e;
                4'd4:font_row=16'hff44;
                4'd5:font_row=16'h2a44;
                4'd6:font_row=16'h4944;
                4'd7:font_row=16'h88a4;
                4'd8:font_row=16'h1028;
                4'd9:font_row=16'hfe28;
                4'd10:font_row=16'h2210;
                4'd11:font_row=16'h4210;
                4'd12:font_row=16'h6428;
                4'd13:font_row=16'h1828;
                4'd14:font_row=16'h3444;
                4'd15:font_row=16'hc282;
                default:font_row=0;endcase end
            6'd21:begin case(row)
                4'd0:font_row=16'h0200;
                4'd1:font_row=16'h0100;
                4'd2:font_row=16'h7ffe;
                4'd3:font_row=16'h4002;
                4'd4:font_row=16'h8004;
                4'd5:font_row=16'h1fe0;
                4'd6:font_row=16'h0040;
                4'd7:font_row=16'h0080;
                4'd8:font_row=16'h0100;
                4'd9:font_row=16'hfffe;
                4'd10:font_row=16'h0100;
                4'd11:font_row=16'h0100;
                4'd12:font_row=16'h0100;
                4'd13:font_row=16'h0100;
                4'd14:font_row=16'h0500;
                4'd15:font_row=16'h0200;
                default:font_row=0;endcase end
            6'd22:begin case(row)
                4'd0:font_row=16'h2000;
                4'd1:font_row=16'h11fc;
                4'd2:font_row=16'h1104;
                4'd3:font_row=16'h0104;
                4'd4:font_row=16'h0104;
                4'd5:font_row=16'hf104;
                4'd6:font_row=16'h1104;
                4'd7:font_row=16'h11fc;
                4'd8:font_row=16'h1104;
                4'd9:font_row=16'h1000;
                4'd10:font_row=16'h1490;
                4'd11:font_row=16'h1888;
                4'd12:font_row=16'h1104;
                4'd13:font_row=16'h0202;
                4'd14:font_row=16'h0402;
                default:font_row=0;endcase end
            6'd23:begin case(row)
                4'd0:font_row=16'h0004;
                4'd1:font_row=16'h7f04;
                4'd2:font_row=16'h4104;
                4'd3:font_row=16'h4124;
                4'd4:font_row=16'h4124;
                4'd5:font_row=16'h7f24;
                4'd6:font_row=16'h1024;
                4'd7:font_row=16'h1024;
                4'd8:font_row=16'hff24;
                4'd9:font_row=16'h1124;
                4'd10:font_row=16'h1124;
                4'd11:font_row=16'h1124;
                4'd12:font_row=16'h2104;
                4'd13:font_row=16'h2104;
                4'd14:font_row=16'h4a14;
                4'd15:font_row=16'h8408;
                default:font_row=0;endcase end
            6'd24:begin case(row)
                4'd0:font_row=16'h7f84;
                4'd1:font_row=16'h1204;
                4'd2:font_row=16'h1208;
                4'd3:font_row=16'h1210;
                4'd4:font_row=16'h1222;
                4'd5:font_row=16'h1202;
                4'd6:font_row=16'hffc4;
                4'd7:font_row=16'h1208;
                4'd8:font_row=16'h1210;
                4'd9:font_row=16'h1222;
                4'd10:font_row=16'h1202;
                4'd11:font_row=16'h2204;
                4'd12:font_row=16'h2208;
                4'd13:font_row=16'h4210;
                4'd14:font_row=16'h8260;
                default:font_row=0;endcase end
            6'd25:begin case(row)
                4'd0:font_row=16'h0100;
                4'd1:font_row=16'h0100;
                4'd2:font_row=16'h0100;
                4'd3:font_row=16'h0100;
                4'd4:font_row=16'h3ff8;
                4'd5:font_row=16'h2108;
                4'd6:font_row=16'h2108;
                4'd7:font_row=16'h2108;
                4'd8:font_row=16'h2108;
                4'd9:font_row=16'h2108;
                4'd10:font_row=16'h3ff8;
                4'd11:font_row=16'h2108;
                4'd12:font_row=16'h0100;
                4'd13:font_row=16'h0100;
                4'd14:font_row=16'h0100;
                4'd15:font_row=16'h0100;
                default:font_row=0;endcase end
            6'd26:begin case(row)
                4'd7:font_row=16'h3e3c;
                4'd8:font_row=16'h4224;
                4'd9:font_row=16'h4042;
                4'd10:font_row=16'h1c42;
                4'd11:font_row=16'h0242;
                4'd12:font_row=16'h4224;
                4'd13:font_row=16'h7c38;
                default:font_row=0;endcase end
            6'd27:begin case(row)
                4'd3:font_row=16'h4000;
                4'd4:font_row=16'hc000;
                4'd5:font_row=16'h4000;
                4'd6:font_row=16'h4000;
                4'd7:font_row=16'h5c1c;
                4'd8:font_row=16'h6626;
                4'd9:font_row=16'h4242;
                4'd10:font_row=16'h427e;
                4'd11:font_row=16'h4240;
                4'd12:font_row=16'h4422;
                4'd13:font_row=16'h5c1c;
                default:font_row=0;endcase end
            6'd28:begin case(row)
                4'd3:font_row=16'h1800;
                4'd4:font_row=16'h3800;
                4'd5:font_row=16'h0800;
                4'd6:font_row=16'h0800;
                4'd7:font_row=16'h0800;
                4'd8:font_row=16'h0800;
                4'd9:font_row=16'h0800;
                4'd10:font_row=16'h0800;
                4'd11:font_row=16'h0800;
                4'd12:font_row=16'h0800;
                4'd13:font_row=16'h3e00;
                default:font_row=0;endcase end
            6'd29:begin case(row)
                4'd0:font_row=16'h0040;
                4'd1:font_row=16'h207c;
                4'd2:font_row=16'h1040;
                4'd3:font_row=16'h17fe;
                4'd4:font_row=16'h8442;
                4'd5:font_row=16'h4470;
                4'd6:font_row=16'h47c4;
                4'd7:font_row=16'h1444;
                4'd8:font_row=16'h143c;
                4'd9:font_row=16'h2420;
                4'd10:font_row=16'he410;
                4'd11:font_row=16'h2454;
                4'd12:font_row=16'h2542;
                4'd13:font_row=16'h2942;
                4'd14:font_row=16'h294a;
                4'd15:font_row=16'h1238;
                default:font_row=0;endcase end
            6'd30:begin case(row)
                4'd0:font_row=16'h0020;
                4'd1:font_row=16'h2020;
                4'd2:font_row=16'h1020;
                4'd3:font_row=16'h13fe;
                4'd4:font_row=16'h8222;
                4'd5:font_row=16'h4224;
                4'd6:font_row=16'h4a20;
                4'd7:font_row=16'h0bfc;
                4'd8:font_row=16'h1284;
                4'd9:font_row=16'h1288;
                4'd10:font_row=16'he248;
                4'd11:font_row=16'h2250;
                4'd12:font_row=16'h2220;
                4'd13:font_row=16'h2450;
                4'd14:font_row=16'h2488;
                4'd15:font_row=16'h0906;
                default:font_row=0;endcase end
            6'd31:begin case(row)
                4'd0:font_row=16'h0040;
                4'd1:font_row=16'h4040;
                4'd2:font_row=16'h2040;
                4'd3:font_row=16'h27fe;
                4'd4:font_row=16'h0080;
                4'd5:font_row=16'h0920;
                4'd6:font_row=16'h0920;
                4'd7:font_row=16'h1220;
                4'd8:font_row=16'h13fc;
                4'd9:font_row=16'he020;
                4'd10:font_row=16'h2128;
                4'd11:font_row=16'h2124;
                4'd12:font_row=16'h2222;
                4'd13:font_row=16'h2422;
                4'd14:font_row=16'h20a0;
                4'd15:font_row=16'h0040;
                default:font_row=0;endcase end
            6'd32:begin case(row)
                4'd0:font_row=16'h1020;
                4'd1:font_row=16'h1020;
                4'd2:font_row=16'h2020;
                4'd3:font_row=16'h27fe;
                4'd4:font_row=16'h4420;
                4'd5:font_row=16'hf820;
                4'd6:font_row=16'h11fc;
                4'd7:font_row=16'h2000;
                4'd8:font_row=16'h4000;
                4'd9:font_row=16'hfdfc;
                4'd10:font_row=16'h4104;
                4'd11:font_row=16'h0104;
                4'd12:font_row=16'h1d04;
                4'd13:font_row=16'he104;
                4'd14:font_row=16'h41fc;
                4'd15:font_row=16'h0104;
                default:font_row=0;endcase end
            6'd33:begin case(row)
                4'd1:font_row=16'h3ff8;
                4'd2:font_row=16'h2008;
                4'd3:font_row=16'h2008;
                4'd4:font_row=16'h27c8;
                4'd5:font_row=16'h2448;
                4'd6:font_row=16'h2448;
                4'd7:font_row=16'h2448;
                4'd8:font_row=16'h2448;
                4'd9:font_row=16'h2448;
                4'd10:font_row=16'h27c8;
                4'd11:font_row=16'h2008;
                4'd12:font_row=16'h2008;
                4'd13:font_row=16'h3ff8;
                4'd14:font_row=16'h2008;
                default:font_row=0;endcase end
            6'd34:begin case(row)
                4'd0:font_row=16'h2040;
                4'd1:font_row=16'h1040;
                4'd2:font_row=16'h0040;
                4'd3:font_row=16'hfe80;
                4'd4:font_row=16'h20fe;
                4'd5:font_row=16'h2108;
                4'd6:font_row=16'h3e88;
                4'd7:font_row=16'h2488;
                4'd8:font_row=16'h2488;
                4'd9:font_row=16'h2450;
                4'd10:font_row=16'h2450;
                4'd11:font_row=16'h2420;
                4'd12:font_row=16'h4450;
                4'd13:font_row=16'h5488;
                4'd14:font_row=16'h8904;
                4'd15:font_row=16'h0202;
                default:font_row=0;endcase end
            default:font_row=0;
        endcase end
    endfunction
    // END GENERATED FONT
    reg vs_d,hs_d,de_d,panel_d,text_d;
    reg [23:0] data_d,ink_d;
    reg [15:0] row_d;
    reg [3:0] column_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x<=0;y<=0;de_prev<=0;vs_prev<=0;title_mode<=0;status_mode<=0;
            vs_d<=0;hs_d<=0;de_d<=0;panel_d<=0;text_d<=0;
            data_d<=0;ink_d<=0;row_d<=0;column_d<=0;
            vs_o<=0;hs_o<=0;de_o<=0;data_o<=0;
        end else begin
            de_prev<=de_i;vs_prev<=vs_i;
            if(vs_prev && !vs_i) begin x<=0;y<=0;end
            else begin
                if(de_i) x<=x+1'b1;else x<=0;
                if(de_prev && !de_i) y<=y+1'b1;
            end
            // Latch during vertical sync, keeping each frame's title intact.
            if(!vs_i) begin
                if(display_mode_i==5) title_mode<=4'd8;
                else if(display_mode_i==6) title_mode<=4'd9;
                else if(display_mode_i==4) title_mode<=digit_mode_i ? 4'd7 : 4'd6;
                else if(display_mode_i==1 && digit_mode_i) title_mode<=4;
                else if(display_mode_i==3 && shape_mode_i) title_mode<=5;
                else title_mode<=display_mode_i;
                status_mode<=replay_i ? 2'd2 : freeze_i ? 2'd1 : 2'd0;
            end
            vs_d<=vs_i;hs_d<=hs_i;de_d<=de_i;data_d<=data_i;
            panel_d<=panel || fps_panel;text_d<=text_area || fps_text;
            column_d<=fps_panel ? {1'b0,x[3:1]} : glyph_x;
            row_d<=fps_panel ? {fps_font_row(fps_character,y[3:1]),11'b0} : font_row(glyph_id,glyph_y);
            ink_d<=fps_panel || !status_line ? 24'hFFFFFF :
                   status_mode==1 ? 24'hFFD166 : 24'h5AD9FF;
            vs_o<=vs_d;hs_o<=hs_d;de_o<=de_d;
            data_o<=panel_d ? ((text_d && row_d[15-column_d]) ? ink_d : 24'h152435) : data_d;
        end
    end
endmodule
