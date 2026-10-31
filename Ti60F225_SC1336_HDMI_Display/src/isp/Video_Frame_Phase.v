`timescale 1ns/1ps
// Drain active-pixel line memories in vertical blanking, and describe the
// REAL source frame at their output. Padding is never sent to the display
// or DDR. No image RAM is cleared or allocated by this module.
module Video_Frame_Phase #(
    parameter integer WIDTH=1280, HEIGHT=720,
    parameter integer PAD_LINES=1, ALIGN_LINES=1,
    parameter integer LINE_CLOCKS=1650, MEASURE_LINE=1
)(
    input clk, rst_n, vs_i, hs_i, de_i,
    output wire pipe_de,
    output wire aligned_de, aligned_next_de,
    output wire aligned_vs, aligned_next_vs,
    output reg [11:0] row_index,
    output reg frame_busy
);
    reg de_d, hs_d, vs_d, hs_seen;
    localparam PHASE_BITS=MEASURE_LINE ? 16 : $clog2(LINE_CLOCKS);
    reg [PHASE_BITS-1:0] phase;
    reg [15:0] hs_ticks, de_ticks, line_clocks;
    reg padding,frame_reset_pending;
    wire de_start=de_i && !de_d;
    wire de_end=!de_i && de_d;
    wire pad_de=padding && phase<WIDTH;
    assign pipe_de=de_i || pad_de;
    assign aligned_de=pipe_de && row_index>=ALIGN_LINES && row_index<HEIGHT+ALIGN_LINES;
    assign aligned_next_de=pipe_de && row_index>=ALIGN_LINES+1 && row_index<HEIGHT+ALIGN_LINES+1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            de_d<=0;hs_d<=0;vs_d<=0;hs_seen<=0;
            phase<=0;hs_ticks<=0;de_ticks<=0;line_clocks<=LINE_CLOCKS;
            row_index<=0;padding<=0;frame_busy<=0;frame_reset_pending<=0;
        end else begin
            de_d<=de_i;hs_d<=hs_i;vs_d<=vs_i;
            if(hs_ticks!=16'hffff) hs_ticks<=hs_ticks+1'b1;
            if(de_ticks!=16'hffff) de_ticks<=de_ticks+1'b1;
            if(hs_i && !hs_d) begin
                hs_ticks<=0;hs_seen<=1;
                if(MEASURE_LINE && hs_seen && hs_ticks>=WIDTH && hs_ticks<16'hfffe)
                    line_clocks<=hs_ticks+1'b1;
            end
            phase <= phase>=line_clocks-1'b1 ? 16'd0 : phase+1'b1;
            if(de_start) begin
                phase<=1;de_ticks<=0;frame_busy<=1;
                // DE also works for CSI, whose HS pin is just line valid.
                // Ignore the long gap between the last and first lines.
                if(MEASURE_LINE && row_index>0 && row_index<HEIGHT && de_ticks>=WIDTH && de_ticks<16'hfffe)
                    line_clocks<=de_ticks+1'b1;
            end
            if(de_end) begin
                row_index<=row_index+1'b1;
                if(row_index==HEIGHT-1) begin
                    padding<=PAD_LINES!=0;
                    if(PAD_LINES==0) frame_busy<=0;
                end
            end
            if(pad_de && phase==WIDTH-1) begin
                row_index<=row_index+1'b1;
                if(row_index==HEIGHT+PAD_LINES-1) begin
                    padding<=0;frame_busy<=0;
                end
            end
            if(frame_reset_pending && !frame_busy) begin
                row_index<=0;frame_reset_pending<=0;
            end
            if(vs_d && !vs_i) begin
                // CSI frame-valid can fall immediately after the last
                // source row. Finish draining before resetting coordinates.
                if(frame_busy) frame_reset_pending<=1;
                else begin row_index<=0;frame_reset_pending<=0;end
            end
        end
    end
    // Delay both VS edges independently: a VS pulse may be shorter than
    // the pipeline. Integer line shifts leave the horizontal phase intact.
    genvar n;
    wire [1:0] delayed_vs;
    generate for(n=0;n<2;n=n+1) begin:g_vs
        localparam integer LINES=ALIGN_LINES+n;
        localparam DELAY_BITS=MEASURE_LINE ? 20 : $clog2(LINE_CLOCKS*(LINES+1)+1);
        reg [DELAY_BITS-1:0] rise_left,fall_left;
        reg rise_pending,fall_pending,value;
        wire [DELAY_BITS-1:0] delay_clocks=line_clocks*LINES;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                rise_left<=0;fall_left<=0;rise_pending<=0;fall_pending<=0;value<=0;
            end else begin
                if(rise_pending) begin
                    if(rise_left==1) begin value<=1;rise_pending<=0;end
                    else rise_left<=rise_left-1'b1;
                end
                if(fall_pending) begin
                    if(fall_left==1) begin value<=0;fall_pending<=0;end
                    else fall_left<=fall_left-1'b1;
                end
                if(vs_i && !vs_d) begin rise_pending<=1;rise_left<=delay_clocks;end
                if(!vs_i && vs_d) begin fall_pending<=1;fall_left<=delay_clocks;end
            end
        end
        assign delayed_vs[n]=LINES==0 ? vs_i : value;
    end endgenerate
    assign aligned_vs=delayed_vs[0];
    assign aligned_next_vs=delayed_vs[1];
endmodule
