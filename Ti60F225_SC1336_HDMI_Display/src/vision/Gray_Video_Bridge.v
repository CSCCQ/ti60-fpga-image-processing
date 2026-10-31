`timescale 1ns/1ps

// APB3 register bridge between SapphireSoC and the gray video pipeline.
//
// The bridge deliberately separates the CPU/APB clock from the pixel clock:
// state is sampled through synchronizers, while box coordinates are written
// into a staging bank and become visible only after the commit toggle crosses
// into the pixel domain.  A mode/replay transition immediately gates the
// active box count, so an old detector result cannot remain on a new view.
module Gray_Video_Bridge #(
    parameter [31:0] CAPABILITIES = 32'd0,
    parameter integer MAX_BOXES = 16
)(
    input                   sys_clk,
    input                   sys_rst_n,
    input  [15:0]           paddr,
    input                   psel,
    input                   penable,
    output                  pready,
    input                   pwrite,
    input  [31:0]           pwdata,
    output reg [31:0]       prdata,
    output                  pslverror,

    input binary_vs_i, binary_de_i, binary_edge_i,
    output reg [MAX_BOXES*4-1:0] box_labels_o,
    input                   pixel_clk,
    input                   pixel_rst_n,
    input  [1:0]             display_mode_i,
    input                   replay_mode_i,
    input                   digit_mode_i,
    input  [31:0]            k1_long_sequence_i,
    input  [31:0]            view_epoch_i,
    input  [31:0]            frame_base_i,
    input  [31:0]            frame_id_i,
    input  [351:0]           ddr_diagnostics_i,

    output reg [4:0]         box_count_o,
    output reg [MAX_BOXES*16-1:0] box_x0_o,
    output reg [MAX_BOXES*16-1:0] box_y0_o,
    output reg [MAX_BOXES*16-1:0] box_x1_o,
    output reg [MAX_BOXES*16-1:0] box_y1_o
);
    localparam [31:0] ID_VALUE = 32'h47525931; // "GRY1"
    localparam [4:0] MAX_BOXES_U5 = MAX_BOXES;

    assign pready = 1'b1;
    assign pslverror = 1'b0;

    wire apb_write = psel && penable && pwrite;

    // CPU-domain staging bank.  Coordinates are 16-bit because the display
    // is 1280x720; each is returned in the low half of a 32-bit APB word.
    reg [MAX_BOXES*4-1:0] labels_stage, active_labels;
    reg [4:0] box_count_stage;
    reg [MAX_BOXES*16-1:0] box_x0_stage;
    reg [MAX_BOXES*16-1:0] box_y0_stage;
    reg [MAX_BOXES*16-1:0] box_x1_stage;
    reg [MAX_BOXES*16-1:0] box_y1_stage;
    reg box_commit_toggle;
    reg [31:0] result_sequence,result_epoch;

    integer wi;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            box_count_stage <= 5'd0; labels_stage<=0;
            box_x0_stage <= {MAX_BOXES*16{1'b0}};
            box_y0_stage <= {MAX_BOXES*16{1'b0}};
            box_x1_stage <= {MAX_BOXES*16{1'b0}};
            box_y1_stage <= {MAX_BOXES*16{1'b0}};
            box_commit_toggle <= 1'b0;
            result_sequence<=0;result_epoch<=0;
        end else if (apb_write) begin
            if (paddr[11:0] == 12'h01c) begin
                box_count_stage <= (pwdata[4:0] > MAX_BOXES_U5) ? MAX_BOXES_U5 : pwdata[4:0];
            end else if (paddr[11:0] == 12'h124) begin
                result_sequence<=pwdata;
            end else if (paddr[11:0] == 12'h128) begin
                result_epoch<=pwdata;
            end else if (paddr[11:0] == 12'h120) begin
                if (pwdata[0]) box_commit_toggle <= ~box_commit_toggle;
            end else if ((paddr[11:0] >= 12'h020) &&
                         (paddr[11:0] < (12'h020 + MAX_BOXES*16))) begin
                for(wi=0;wi<MAX_BOXES;wi=wi+1) begin
                    if(paddr[11:4]==wi+2) begin
                        case (paddr[3:2])
                            2'd0: begin box_x0_stage[wi*16 +: 16] <= pwdata[15:0]; labels_stage[wi*4 +: 4]<=pwdata[19:16]; end
                            2'd1: box_y0_stage[wi*16 +: 16] <= pwdata[15:0];
                            2'd2: box_x1_stage[wi*16 +: 16] <= pwdata[15:0];
                            2'd3: box_y1_stage[wi*16 +: 16] <= pwdata[15:0];
                        endcase
                    end
                end
            end
        end
    end

    // Pixel-domain state synchronizers.
    reg [1:0] mode_meta, mode_sync;
    reg replay_meta, replay_sync;
    reg digit_meta, digit_sync;
    reg [31:0] sequence_meta, sequence_sync;
    reg [31:0] epoch_meta, epoch_sync;
    reg commit_meta, commit_sync, commit_seen;
    reg [4:0] active_count;
    reg [MAX_BOXES*16-1:0] active_x0, active_y0, active_x1, active_y1;

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            mode_meta <= 2'd0;
            mode_sync <= 2'd0;
            replay_meta <= 1'b0;
            replay_sync <= 1'b0;
            digit_meta<=1'b0; digit_sync<=1'b0;
            sequence_meta <= 32'd0;
            sequence_sync <= 32'd0;
            epoch_meta <= 32'd0;
            epoch_sync <= 32'd0;
            commit_meta <= 1'b0;
            commit_sync <= 1'b0;
            commit_seen <= 1'b0;
            active_count <= 5'd0; active_labels<=0;
            active_x0 <= {MAX_BOXES*16{1'b0}};
            active_y0 <= {MAX_BOXES*16{1'b0}};
            active_x1 <= {MAX_BOXES*16{1'b0}};
            active_y1 <= {MAX_BOXES*16{1'b0}};
        end else begin
            mode_meta <= display_mode_i;
            mode_sync <= mode_meta;
            replay_meta <= replay_mode_i;
            replay_sync <= replay_meta;
            digit_meta<=digit_mode_i; digit_sync<=digit_meta;
            sequence_meta <= k1_long_sequence_i;
            sequence_sync <= sequence_meta;
            epoch_meta <= view_epoch_i;
            epoch_sync <= epoch_meta;
            commit_meta <= box_commit_toggle;
            commit_sync <= commit_meta;

            // A new view invalidates all previous detections immediately.
            if (mode_sync != 2'd1 || replay_sync != replay_mode_i || !digit_sync ||
                sequence_sync!=k1_long_sequence_i || epoch_sync!=view_epoch_i) begin
                active_count <= 5'd0;
                commit_seen <= commit_sync;
            end else if (commit_sync != commit_seen && !binary_vs_i) begin
                // The staging bank has been stable for two pixel clocks by
                // the time the toggle is observed.
                commit_seen <= commit_sync;
                active_count <= ((result_sequence==k1_long_sequence_i && result_epoch==view_epoch_i) || box_count_stage==0) ? box_count_stage : 0;
                active_labels<=labels_stage;
                active_x0 <= box_x0_stage;
                active_y0 <= box_y0_stage;
                active_x1 <= box_x1_stage;
                active_y1 <= box_y1_stage;
            end
        end
    end

    // CPU-domain synchronized copies of the pixel state for APB reads.
    reg [1:0] rd_mode_meta, rd_mode_sync;
    reg rd_replay_meta, rd_replay_sync;
    reg rd_digit_meta, rd_digit_sync;
    reg [31:0] rd_sequence_meta, rd_sequence_sync;
    reg [31:0] rd_epoch_meta, rd_epoch_sync;
    reg [31:0] rd_frame_base_meta, rd_frame_base_sync;
    reg [31:0] rd_frame_id_meta, rd_frame_id_sync;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rd_mode_meta <= 2'd0; rd_mode_sync <= 2'd0;
            rd_replay_meta <= 1'b0; rd_replay_sync <= 1'b0;
            rd_digit_meta <= 1'b0; rd_digit_sync <= 1'b0;
            rd_sequence_meta <= 32'd0; rd_sequence_sync <= 32'd0;
            rd_epoch_meta <= 32'd0; rd_epoch_sync <= 32'd0;
            rd_frame_base_meta <= 32'd0; rd_frame_base_sync <= 32'd0;
            rd_frame_id_meta <= 32'd0; rd_frame_id_sync <= 32'd0;
        end else begin
            rd_mode_meta <= display_mode_i; rd_mode_sync <= rd_mode_meta;
            rd_replay_meta <= replay_mode_i; rd_replay_sync <= rd_replay_meta;
            rd_digit_meta <= digit_mode_i; rd_digit_sync <= rd_digit_meta;
            rd_sequence_meta <= k1_long_sequence_i; rd_sequence_sync <= rd_sequence_meta;
            rd_epoch_meta <= view_epoch_i; rd_epoch_sync <= rd_epoch_meta;
            rd_frame_base_meta <= frame_base_i; rd_frame_base_sync <= rd_frame_base_meta;
            rd_frame_id_meta <= frame_id_i; rd_frame_id_sync <= rd_frame_id_meta;
        end
    end

    wire [31:0] snapshot_data;
    Binary_Snapshot u_binary_snapshot(
      .sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.paddr(paddr),.psel(psel),.penable(penable),.pwrite(pwrite),
      .pwdata(pwdata),.prdata(snapshot_data),.pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),
      .vs_i(binary_vs_i),.de_i(binary_de_i),.edge_i(binary_edge_i));
    integer ri;
    always @(*) begin
        prdata = 32'd0;
        ri = 0;
        if (paddr >= 16'h0180 && paddr <= 16'h0190) prdata = snapshot_data;
        else if (paddr[11:0] == 12'h000) prdata = ID_VALUE;
        else if (paddr[11:0] == 12'h004) prdata = CAPABILITIES;
        else if (paddr[11:0] == 12'h008)
            prdata = {28'd0, rd_digit_sync, rd_replay_sync, rd_mode_sync};
        else if (paddr[11:0] == 12'h00c) prdata = rd_sequence_sync;
        else if (paddr[11:0] == 12'h010) prdata = rd_epoch_sync;
        else if (paddr[11:0] == 12'h014) prdata = rd_frame_base_sync;
        else if (paddr[11:0] == 12'h018) prdata = rd_frame_id_sync;
        else if (paddr[11:0] == 12'h01c) prdata = {27'd0, box_count_stage};
        else if (paddr[11:0] >= 12'h130 && paddr[11:0] <= 12'h158)
            prdata = ddr_diagnostics_i[((paddr[11:0]-12'h130)>>2)*32 +: 32];
        else if ((paddr[11:0] >= 12'h020) &&
                 (paddr[11:0] < (12'h020 + MAX_BOXES*16))) begin
            ri = (paddr[11:0] - 12'h020) >> 4;
            case (paddr[3:2])
                2'd0: prdata = {16'd0, box_x0_stage[ri*16 +: 16]};
                2'd1: prdata = {16'd0, box_y0_stage[ri*16 +: 16]};
                2'd2: prdata = {16'd0, box_x1_stage[ri*16 +: 16]};
                2'd3: prdata = {16'd0, box_y1_stage[ri*16 +: 16]};
            endcase
        end
    end

    // Gate the output as well as the active bank.  This keeps the overlay
    // off during the synchronizer latency of a mode switch.
    always @(*) begin
        if (display_mode_i == 2'd1 && digit_mode_i &&
            mode_sync == 2'd1 && replay_sync == replay_mode_i && digit_sync &&
            sequence_sync == k1_long_sequence_i && epoch_sync == view_epoch_i) begin
            box_count_o = active_count; box_labels_o=active_labels;
            box_x0_o = active_x0;
            box_y0_o = active_y0;
            box_x1_o = active_x1;
            box_y1_o = active_y1;
        end else begin
            box_count_o = 5'd0; box_labels_o=0;
            box_x0_o = {MAX_BOXES*16{1'b0}};
            box_y0_o = {MAX_BOXES*16{1'b0}};
            box_x1_o = {MAX_BOXES*16{1'b0}};
            box_y1_o = {MAX_BOXES*16{1'b0}};
        end
    end
endmodule
