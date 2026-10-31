`timescale 1ns / 1ps

// Small AXI4 arbiter used by the gray design.  SapphireSoc exposes a
// half-duplex request channel (ARW), while the video frame store uses the
// split AW/AR signals.  Only one transaction is allowed in flight; this is
// sufficient for the frame store and keeps response routing deterministic.
module AXI4_DualMasterMux #(
    parameter integer ID_WIDTH = 8,
    parameter integer DATA_WIDTH = 128
)(
    input                       clk,
    input                       rst,

    input                       v_avalid,
    output                      v_aready,
    input  [ID_WIDTH-1:0]       v_aid,
    input  [31:0]               v_aaddr,
    input  [7:0]                v_alen,
    input                       v_atype,
    input                       v_wvalid,
    output                      v_wready,
    input  [ID_WIDTH-1:0]       v_wid,
    input  [DATA_WIDTH-1:0]     v_wdata,
    input  [DATA_WIDTH/8-1:0]   v_wstrb,
    input                       v_wlast,
    output                      v_bvalid,
    input                       v_bready,
    output [ID_WIDTH-1:0]       v_bid,
    output [1:0]                v_bresp,
    output                      v_rvalid,
    input                       v_rready,
    output [ID_WIDTH-1:0]       v_rid,
    output [DATA_WIDTH-1:0]     v_rdata,
    output [1:0]                v_rresp,
    output                      v_rlast,

    input                       s_avalid,
    output                      s_aready,
    input  [ID_WIDTH-1:0]       s_aid,
    input  [31:0]               s_aaddr,
    input  [7:0]                s_alen,
    input  [2:0]                s_asize,
    input  [1:0]                s_aburst,
    input                       s_alock,
    input  [3:0]                s_acache,
    input  [2:0]                s_aprot,
    input  [3:0]                s_aqos,
    input                       s_atype,
    input                       s_wvalid,
    output                      s_wready,
    input  [ID_WIDTH-1:0]       s_wid,
    input  [DATA_WIDTH-1:0]     s_wdata,
    input  [DATA_WIDTH/8-1:0]   s_wstrb,
    input                       s_wlast,
    output                      s_bvalid,
    input                       s_bready,
    output [ID_WIDTH-1:0]       s_bid,
    output [1:0]                s_bresp,
    output                      s_rvalid,
    input                       s_rready,
    output [ID_WIDTH-1:0]       s_rid,
    output [DATA_WIDTH-1:0]     s_rdata,
    output [1:0]                s_rresp,
    output                      s_rlast,

    output                      m_avalid,
    input                       m_aready,
    output [ID_WIDTH-1:0]       m_aid,
    output [31:0]               m_aaddr,
    output [7:0]                m_alen,
    output [2:0]                m_asize,
    output [1:0]                m_aburst,
    output                      m_alock,
    output [3:0]                m_acache,
    output [2:0]                m_aprot,
    output [3:0]                m_aqos,
    output                      m_atype,
    output                      m_wvalid,
    input                       m_wready,
    output [ID_WIDTH-1:0]       m_wid,
    output [DATA_WIDTH-1:0]     m_wdata,
    output [DATA_WIDTH/8-1:0]   m_wstrb,
    output                      m_wlast,
    input                       m_bvalid,
    output                      m_bready,
    input  [ID_WIDTH-1:0]       m_bid,
    input  [1:0]                m_bresp,
    input                       m_rvalid,
    output                      m_rready,
    input  [ID_WIDTH-1:0]       m_rid,
    input  [DATA_WIDTH-1:0]     m_rdata,
    input  [1:0]                m_rresp,
    input                       m_rlast,
    output [31:0]               debug_state
);
    localparam [1:0] OWNER_IDLE = 2'd0;
    localparam [1:0] OWNER_VIDEO = 2'd1;
    localparam [1:0] OWNER_SOC = 2'd2;

    reg [1:0] owner;
    reg owner_write;
    reg write_data_done;
    reg address_pending, address_soc, prefer_soc;
    wire select_soc = address_pending ? address_soc :
                      (s_avalid && (!v_avalid || prefer_soc));
    wire request_fire = m_avalid && m_aready;
    // Read-only observation; no feedback into arbitration or handshakes.
    assign debug_state = {v_aready, s_aready, m_rlast, m_rready,
        m_rvalid, m_bready, m_bvalid, m_wlast, m_wready, m_wvalid,
        m_aready, m_avalid, v_rready, v_bready, v_wlast, v_wvalid,
        v_atype, v_avalid, s_rready, s_bready, s_wlast, s_wvalid,
        s_atype, s_avalid, prefer_soc, address_soc, address_pending,
        write_data_done, owner_write, owner, (owner != OWNER_IDLE)};

    assign m_avalid = (owner == OWNER_IDLE) && (s_avalid || v_avalid);
    assign m_aid = select_soc ? s_aid : v_aid;
    assign m_aaddr = select_soc ? s_aaddr : v_aaddr;
    assign m_alen = select_soc ? s_alen : v_alen;
    assign m_asize = select_soc ? s_asize : 3'd4;
    assign m_aburst = select_soc ? s_aburst : 2'b01;
    assign m_alock = select_soc ? s_alock : 1'b0;
    assign m_acache = select_soc ? s_acache : 4'd0;
    assign m_aprot = select_soc ? s_aprot : 3'd0;
    assign m_aqos = select_soc ? s_aqos : 4'd0;
    assign m_atype = select_soc ? s_atype : v_atype;
    assign s_aready = m_avalid && select_soc && m_aready;
    assign v_aready = m_avalid && !select_soc && m_aready;

    // Once the address has been accepted, the owner remains selected until
    // its B or final R response is consumed.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            owner <= OWNER_IDLE;
            owner_write <= 1'b0;
            write_data_done <= 1'b0;
            address_pending <= 1'b0;
            address_soc <= 1'b0;
            prefer_soc <= 1'b1;
        end else begin
            // Hold the chosen source while DDR stalls an offered address.
            // Alternate contenders so CPU traffic cannot starve the video.
            if (m_avalid && !m_aready) begin
                address_pending <= 1'b1;
                address_soc <= select_soc;
            end
            if (request_fire) begin
                address_pending <= 1'b0;
                prefer_soc <= !select_soc;
                owner_write <= m_atype;
                write_data_done <= 1'b0;
            end
            if (m_wvalid && m_wready && m_wlast)
                write_data_done <= 1'b1;
            case (owner)
                OWNER_IDLE: begin
                    if (request_fire)
                        owner <= select_soc ? OWNER_SOC : OWNER_VIDEO;
                end
                OWNER_VIDEO: begin
                    if ((v_bvalid && v_bready) || (v_rvalid && v_rready && v_rlast))
                        owner <= OWNER_IDLE;
                end
                OWNER_SOC: begin
                    if ((s_bvalid && s_bready) || (s_rvalid && s_rready && s_rlast))
                        owner <= OWNER_IDLE;
                end
                default: owner <= OWNER_IDLE;
            endcase
        end
    end

    // A source may already offer data for its next write while its current
    // read owns the port. Never forward that data under the read grant.
    // W and B are independent channels. After WLAST, a pipelined master may
    // already offer its next write while this transaction waits for B. That
    // next address has not won arbitration: another master may win it first.
    // Never let those extra data beats enter the shared DDR write FIFO.
    assign m_wvalid = owner_write && !write_data_done && ((owner == OWNER_SOC) ? s_wvalid :
                      (owner == OWNER_VIDEO) ? v_wvalid : 1'b0);
    assign m_wid = (owner == OWNER_SOC) ? s_wid : v_wid;
    assign m_wdata = (owner == OWNER_SOC) ? s_wdata : v_wdata;
    assign m_wstrb = (owner == OWNER_SOC) ? s_wstrb : v_wstrb;
    assign m_wlast = (owner == OWNER_SOC) ? s_wlast : v_wlast;
    assign s_wready = owner_write && !write_data_done && (owner == OWNER_SOC) && m_wready;
    assign v_wready = owner_write && !write_data_done && (owner == OWNER_VIDEO) && m_wready;

    assign m_bready = (owner == OWNER_SOC) ? s_bready :
                      (owner == OWNER_VIDEO) ? v_bready : 1'b0;
    assign m_rready = (owner == OWNER_SOC) ? s_rready :
                      (owner == OWNER_VIDEO) ? v_rready : 1'b0;

    assign s_bvalid = (owner == OWNER_SOC) && m_bvalid;
    assign s_bid = m_bid;
    assign s_bresp = m_bresp;
    assign v_bvalid = (owner == OWNER_VIDEO) && m_bvalid;
    assign v_bid = m_bid;
    assign v_bresp = m_bresp;

    assign s_rvalid = (owner == OWNER_SOC) && m_rvalid;
    assign s_rid = m_rid;
    assign s_rdata = m_rdata;
    assign s_rresp = m_rresp;
    assign s_rlast = m_rlast;
    assign v_rvalid = (owner == OWNER_VIDEO) && m_rvalid;
    assign v_rid = m_rid;
    assign v_rdata = m_rdata;
    assign v_rresp = m_rresp;
    assign v_rlast = m_rlast;
endmodule
