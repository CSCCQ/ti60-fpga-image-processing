`timescale 1ns / 1ps

// Adapts the full AXI master emitted by tinyml_top to the Sapphire/DDR
// half-duplex request channel used by the gray design.  TinyML does not
// expose AXI IDs, QoS, or region signals, so the adapter supplies the fixed
// values required by the shared DDR arbiter.
module AXI4_FullToHalfDuplex_TinyML #(
    parameter integer DATA_WIDTH = 128,
    parameter integer ADDR_WIDTH = 32,
    parameter integer ID_WIDTH = 8
)(
    input clk,
    input rst,

    output reg h_arw_valid,
    input h_arw_ready,
    output reg [ADDR_WIDTH-1:0] h_arw_addr,
    output reg [ID_WIDTH-1:0] h_arw_id,
    output reg [7:0] h_arw_len,
    output reg [2:0] h_arw_size,
    output reg [1:0] h_arw_burst,
    output reg [1:0] h_arw_lock,
    output reg h_arw_write,

    output [ID_WIDTH-1:0] h_w_id,
    output h_w_valid,
    input h_w_ready,
    output [DATA_WIDTH-1:0] h_w_data,
    output [DATA_WIDTH/8-1:0] h_w_strb,
    output h_w_last,
    input h_b_valid,
    output h_b_ready,
    input [1:0] h_b_resp,
    input h_r_valid,
    output h_r_ready,
    input [DATA_WIDTH-1:0] h_r_data,
    input [1:0] h_r_resp,
    input h_r_last,

    input [ADDR_WIDTH-1:0] s_aw_addr,
    input [7:0] s_aw_len,
    input [2:0] s_aw_size,
    input [1:0] s_aw_burst,
    input [1:0] s_aw_lock,
    input [3:0] s_aw_cache,
    input [2:0] s_aw_prot,
    input s_aw_valid,
    output s_aw_ready,
    input [DATA_WIDTH-1:0] s_w_data,
    input [DATA_WIDTH/8-1:0] s_w_strb,
    input s_w_last,
    input s_w_valid,
    output s_w_ready,
    output [1:0] s_b_resp,
    output s_b_valid,
    input s_b_ready,
    input [ADDR_WIDTH-1:0] s_ar_addr,
    input [7:0] s_ar_len,
    input [2:0] s_ar_size,
    input [1:0] s_ar_burst,
    input [1:0] s_ar_lock,
    input [3:0] s_ar_cache,
    input [2:0] s_ar_prot,
    input s_ar_valid,
    output s_ar_ready,
    output [DATA_WIDTH-1:0] s_r_data,
    output [1:0] s_r_resp,
    output s_r_last,
    output s_r_valid,
    input s_r_ready
);
    localparam [1:0] REQ_IDLE = 2'd0;
    localparam [1:0] REQ_WRITE = 2'd1;
    localparam [1:0] REQ_READ = 2'd2;
    reg [1:0] req_state;

    wire write_fire = (req_state == REQ_WRITE) && h_arw_ready;
    wire read_fire = (req_state == REQ_READ) && h_arw_ready;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            req_state <= REQ_IDLE;
        end else begin
            case (req_state)
                REQ_IDLE: begin
                    if (s_aw_valid) req_state <= REQ_WRITE;
                    else if (s_ar_valid) req_state <= REQ_READ;
                end
                REQ_WRITE: if (write_fire) req_state <= REQ_IDLE;
                REQ_READ: if (read_fire) req_state <= REQ_IDLE;
                default: req_state <= REQ_IDLE;
            endcase
        end
    end

    assign s_aw_ready = (req_state == REQ_WRITE) && h_arw_ready;
    assign s_ar_ready = (req_state == REQ_READ) && h_arw_ready;
    assign h_w_id = {ID_WIDTH{1'b0}};
    assign h_w_valid = s_w_valid;
    assign s_w_ready = h_w_ready;
    assign h_w_data = s_w_data;
    assign h_w_strb = s_w_strb;
    assign h_w_last = s_w_last;

    assign s_b_valid = h_b_valid;
    assign s_b_resp = h_b_resp;
    assign h_b_ready = s_b_ready;
    assign s_r_valid = h_r_valid;
    assign s_r_data = h_r_data;
    assign s_r_resp = h_r_resp;
    assign s_r_last = h_r_last;
    assign h_r_ready = s_r_ready;

    always @(*) begin
        h_arw_valid = 1'b0;
        h_arw_addr = {ADDR_WIDTH{1'b0}};
        h_arw_id = {ID_WIDTH{1'b0}};
        h_arw_len = 8'd0;
        h_arw_size = 3'd0;
        h_arw_burst = 2'd0;
        h_arw_lock = 2'd0;
        h_arw_write = 1'b0;
        if (req_state == REQ_WRITE) begin
            h_arw_valid = s_aw_valid;
            h_arw_addr = s_aw_addr;
            h_arw_len = s_aw_len;
            h_arw_size = s_aw_size;
            h_arw_burst = s_aw_burst;
            h_arw_lock = s_aw_lock;
            h_arw_write = 1'b1;
        end else if (req_state == REQ_READ) begin
            h_arw_valid = s_ar_valid;
            h_arw_addr = s_ar_addr;
            h_arw_len = s_ar_len;
            h_arw_size = s_ar_size;
            h_arw_burst = s_ar_burst;
            h_arw_lock = s_ar_lock;
        end
    end

    // These inputs are present only to keep the port contract explicit when
    // wiring generated TinyML variants; the current top has no AXI IDs.
    wire unused = &{1'b0, s_aw_cache, s_aw_prot, s_ar_cache, s_ar_prot};
endmodule
