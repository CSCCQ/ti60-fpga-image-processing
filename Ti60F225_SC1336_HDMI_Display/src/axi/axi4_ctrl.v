//  by CrazyBird
module axi4_ctrl #(
	parameter 	C_ID_LEN      = 8, 
			C_DATA_LEN    = 128, //总线宽度
			C_DATA_SIZE   = 4, 	//	C_DATA_LEN=8:0, 16:1, 32:2, 64:3, 128:4, 256:5, 512:6, 1024:7，
			
			C_BURST_LEN   = 128,//一个突发有多少个beat
			
			C_STRB_LEN    = C_DATA_LEN / 8, //每个beat包含的字节数
			C_ADDR_INC    = C_BURST_LEN * C_STRB_LEN,
			
			C_BASE_ADDR   = 32'h00000000, 	//	Start at 0x00000000 by default
			C_BUF_SIZE    = 22, 			//	Allocate 2^22 bytes (4MB) by default. The module takes 4*4MB by default. 
			C_RD_END_ADDR = 1280 * 720,
			
			C_W_WIDTH     = 64, 
			C_R_WIDTH     = 8
)(
    input  wire                 axi_clk         ,
    input  wire                 axi_reset       ,
    
    output       [C_ID_LEN-1:0]      axi_awid        ,
    output       [31:0]      axi_awaddr      ,
    output       [ 7:0]      axi_awlen       ,
    output       [ 2:0]      axi_awsize      ,
    output       [ 1:0]      axi_awburst     ,
    output                   axi_awlock      ,
    output       [ 3:0]      axi_awcache     ,
    output       [ 2:0]      axi_awprot      ,
    output       [ 3:0]      axi_awqos       ,
    output reg                  axi_awvalid     ,
    input  wire                 axi_awready     ,
    
    output       [C_DATA_LEN-1:0]      axi_wdata       ,
    output       [C_STRB_LEN-1:0]      axi_wstrb       ,
    output                   axi_wlast       ,
    output reg                  axi_wvalid      ,
    input  wire                 axi_wready      ,
    
    input  wire     [C_ID_LEN-1:0]      axi_bid         ,
    input  wire     [ 1:0]      axi_bresp       ,
    input  wire                 axi_bvalid      ,
    output                   axi_bready      ,
    
    output       [C_ID_LEN-1:0]      axi_arid        ,
    output       [31:0]      axi_araddr      ,
    output       [ 7:0]      axi_arlen       ,
    output       [ 2:0]      axi_arsize      ,
    output       [ 1:0]      axi_arburst     ,
    output                   axi_arlock      ,
    output       [ 3:0]      axi_arcache     ,
    output       [ 2:0]      axi_arprot      ,
    output       [ 3:0]      axi_arqos       ,
    output reg                  axi_arvalid     ,
    input  wire                 axi_arready     ,
    
    input  wire     [C_ID_LEN-1:0]      axi_rid         ,
    input  wire     [C_DATA_LEN-1:0]      axi_rdata       ,
    input  wire     [ 1:0]      axi_rresp       ,
    input  wire                 axi_rlast       ,
    input  wire                 axi_rvalid      ,
    output                   axi_rready      ,
    
    input  wire                 wframe_pclk     ,
    input  wire                 wframe_vsync    ,		//	Writter VSync. Flush on falling edge. Connect to EOF. 
    input  wire                 wframe_data_en  ,
    input  wire     [C_W_WIDTH-1:0]      wframe_data     ,
    
    input  wire                 rframe_pclk     ,
    input  wire                 rframe_vsync    ,		//	Reader VSync. Flush on falling edge. Connect to ~EOF. 
    input  wire                 rframe_data_en  ,
    input  wire                 freeze_i        ,
    input  wire                 save_frame_i    ,
    input  wire                 replay_mode_i   ,
    input  wire                 replay_next_i   ,
    input  wire                 replay_prev_i   ,
    output wire     [C_R_WIDTH-1:0]      rframe_data     ,
    output wire     [31:0]      frame_base_o,
    output wire     [31:0]      frame_id_o,
    
    output 		[31:0] 	tp_o
);
	
	initial begin
		axi_awvalid <= 0; 
		axi_wvalid <= 0; 
		axi_arvalid <= 0; 
	end

	assign axi_awid    = {C_ID_LEN{1'b0}};
	assign axi_awlen   = C_BURST_LEN - 1'b1;
	assign axi_awsize  = C_DATA_SIZE;
	assign axi_awburst = 2'b01;	//	INCR
	assign axi_awlock  = 1'b0;
	assign axi_awcache = 0;
	assign axi_awprot  = 3'b0;
	assign axi_awqos   = 4'b0;
	assign axi_wstrb   = 32'hFFFFFFFF;
	assign axi_bready  = 1; 
	    
	assign axi_arid    = {C_ID_LEN{1'b0}};
	assign axi_arlen   = C_BURST_LEN - 1'b1;
	assign axi_arsize  = C_DATA_SIZE;
	assign axi_arburst = 2'b01;	//	INCR
	assign axi_arlock  = 1'b0;
	assign axi_arcache = 0;
	assign axi_arprot  = 3'b0;
	assign axi_arqos   = 4'b0;
	assign axi_rready  = 1; 
	
	
	
	
	////////////////////////////////////////////////////////////////
	//	R/W Schedule
	localparam integer FRAME_SLOTS = 16;
	localparam integer HISTORY_SLOTS = 10;
	reg	[3:0] 	rc_wframe_index;
	reg	[3:0] 	rc_rframe_index;

    // K1's freeze toggle originates in the display pixel clock domain.
    // Synchronize it before deciding which DDR frame the reader owns.
    reg freeze_axi_meta;
    reg freeze_axi;
    reg replay_axi_meta;
    reg replay_axi;
    reg replay_axi_d;
    reg save_toggle_meta, save_toggle_axi, save_toggle_seen;
    reg next_toggle_meta, next_toggle_axi, next_toggle_seen;
    reg prev_toggle_meta, prev_toggle_axi, prev_toggle_seen;
    always @(posedge axi_clk or posedge axi_reset) begin
        if (axi_reset) begin
            freeze_axi_meta <= 1'b0;
            freeze_axi <= 1'b0;
            replay_axi_meta <= 1'b0;
            replay_axi <= 1'b0;
            save_toggle_meta <= 1'b0;
            save_toggle_axi <= 1'b0;
            next_toggle_meta <= 1'b0;
            next_toggle_axi <= 1'b0;
            prev_toggle_meta <= 1'b0;
            prev_toggle_axi <= 1'b0;
        end else begin
            freeze_axi_meta <= freeze_i;
            freeze_axi <= freeze_axi_meta;
            replay_axi_meta <= replay_mode_i;
            replay_axi <= replay_axi_meta;
            save_toggle_meta <= save_frame_i;
            save_toggle_axi <= save_toggle_meta;
            next_toggle_meta <= replay_next_i;
            next_toggle_axi <= next_toggle_meta;
            prev_toggle_meta <= replay_prev_i;
            prev_toggle_axi <= prev_toggle_meta;
        end
    end

    // Sixteen 1MiB slots provide ten saved snapshots plus live reader and
    // writer space. The history bitmap prevents the camera from overwriting
    // a saved frame; the oldest slot is released only when snapshot eleven
    // is committed.
    reg [3:0] history_slot [0:HISTORY_SLOTS-1];
    reg [15:0] history_saved;
    reg [3:0] history_head;
    reg [3:0] history_count;
    reg [3:0] replay_pos;
    reg replay_pending;
    reg replay_active;
    reg replay_exit_pending;
    reg [3:0] replay_resume_bank;
    reg [3:0] replay_slot_selected;
    reg [3:0] r_wframe_index_last = 0;
    reg r_wframe_inc = 0, r_rframe_inc = 0;
    reg [31:0] frame_id_slots [0:FRAME_SLOTS-1];
    reg [31:0] frame_sequence;

    integer wi;
    reg [3:0] w_candidate;
    reg [3:0] w_wframe_index_next;
    reg w_candidate_found;
    always @(*) begin
        w_wframe_index_next = rc_wframe_index;
        w_candidate_found = 1'b0;
        w_candidate = rc_wframe_index;
        for(wi = 1; wi <= FRAME_SLOTS; wi = wi + 1) begin
            w_candidate = rc_wframe_index + wi;
            if(!w_candidate_found && (w_candidate != rc_rframe_index) &&
               !history_saved[w_candidate]) begin
                w_wframe_index_next = w_candidate;
                w_candidate_found = 1'b1;
            end
        end
    end

    integer hi;
    reg [4:0] history_lookup;
    reg [4:0] history_tail;
    always @(*) begin
        history_lookup = {1'b0, history_head} + {1'b0, replay_pos};
        if(history_lookup >= HISTORY_SLOTS)
            history_lookup = history_lookup - HISTORY_SLOTS;
        history_tail = {1'b0, history_head} + {1'b0, history_count};
        if(history_tail >= HISTORY_SLOTS)
            history_tail = history_tail - HISTORY_SLOTS;
        if(history_count != 0)
            replay_slot_selected = history_slot[history_lookup];
        else
            replay_slot_selected = rc_rframe_index;
    end

    function [3:0] history_inc;
        input [3:0] value;
        begin
            history_inc = (value == HISTORY_SLOTS-1) ? 4'd0 : value + 1'b1;
        end
    endfunction

    always @(posedge axi_clk) begin
        if (axi_reset) begin
            rc_wframe_index <= 4'd0;
            rc_rframe_index <= 4'd2;
            r_wframe_index_last <= 4'd0;
            history_saved <= 16'd0;
            history_head <= 4'd0;
            history_count <= 4'd0;
            replay_pos <= 4'd0;
            replay_pending <= 1'b0;
            replay_active <= 1'b0;
            replay_exit_pending <= 1'b0;
            replay_resume_bank <= 4'd2;
            frame_sequence <= 32'd0;
            for(hi = 0; hi < FRAME_SLOTS; hi = hi + 1)
                frame_id_slots[hi] <= 32'd0;
            replay_axi_d <= 1'b0;
            save_toggle_seen <= 1'b0;
            next_toggle_seen <= 1'b0;
            prev_toggle_seen <= 1'b0;
            for(hi = 0; hi < HISTORY_SLOTS; hi = hi + 1)
                history_slot[hi] <= 4'd0;
        end else begin
            replay_axi_d <= replay_axi;
            // Record every completed frame, including simultaneous reader
            // and writer events, so unfreezing selects the newest frame.
            if (r_wframe_inc) begin
                frame_sequence <= frame_sequence + 1'b1;
                frame_id_slots[rc_wframe_index] <= frame_sequence + 1'b1;
                rc_wframe_index <= w_wframe_index_next;
                r_wframe_index_last <= rc_wframe_index;
            end

            // A save toggle is generated only when a double-click changes
            // freeze from off to on. Store the currently displayed complete
            // slot in the chronological ten-entry ring.
            if(save_toggle_axi != save_toggle_seen) begin
                save_toggle_seen <= save_toggle_axi;
                if(!history_saved[rc_rframe_index]) begin
                    if(history_count == HISTORY_SLOTS) begin
                        history_saved[history_slot[history_head]] <= 1'b0;
                        history_slot[history_head] <= rc_rframe_index;
                        history_saved[rc_rframe_index] <= 1'b1;
                        history_head <= history_inc(history_head);
                    end else begin
                        history_slot[history_tail] <= rc_rframe_index;
                        history_saved[rc_rframe_index] <= 1'b1;
                        history_count <= history_count + 1'b1;
                    end
                end
            end

            // Navigation changes only the logical history position here.
            // The physical reader bank changes below at a display-frame
            // boundary, so an image is never mixed with another frame.
            if(next_toggle_axi != next_toggle_seen) begin
                next_toggle_seen <= next_toggle_axi;
                if(replay_active) begin
                    if(history_count != 0)
                        replay_pos <= (replay_pos == history_count - 1'b1) ?
                                      4'd0 : replay_pos + 1'b1;
                    replay_pending <= 1'b1;
                end
            end
            if(prev_toggle_axi != prev_toggle_seen) begin
                prev_toggle_seen <= prev_toggle_axi;
                if(replay_active) begin
                    if(history_count != 0)
                        replay_pos <= (replay_pos == 0) ?
                                      history_count - 1'b1 : replay_pos - 1'b1;
                    replay_pending <= 1'b1;
                end
            end

            if(replay_axi && !replay_axi_d) begin
                replay_resume_bank <= rc_rframe_index;
                replay_exit_pending <= 1'b0;
                replay_pos <= (history_count == 0) ? 4'd0 : history_count - 1'b1;
                replay_active <= (history_count != 0);
                replay_pending <= (history_count != 0);
            end else if(!replay_axi && replay_axi_d) begin
                replay_active <= 1'b0;
                replay_pending <= 1'b0;
                replay_exit_pending <= 1'b1;
            end

            // Read FIFO reset/restart still occurs on every display frame.
            // Only its frame index is held; no mid-frame address changes.
            if(r_rframe_inc && !replay_axi && replay_exit_pending) begin
                rc_rframe_index <= replay_resume_bank;
                replay_exit_pending <= 1'b0;
            end else if(r_rframe_inc && replay_active && replay_pending) begin
                rc_rframe_index <= replay_slot_selected;
                replay_pending <= 1'b0;
            end else if(r_rframe_inc && !replay_active && !freeze_axi)
                rc_rframe_index <= r_wframe_inc ?
                    rc_wframe_index : r_wframe_index_last;
        end
    end
    

	////////////////////////////////////////////////////////////////
	//	AXI Writter

	wire 				w_wfifo_pempty, w_wfifo_empty; 
	wire 				w_wfifo_ren; 
	wire 	[C_DATA_LEN-1:0] 	w_wfifo_rdata; 

	//	On EOF when ~empty, flush the last data then reset FIFO. 
	reg 	[3:0] 	rs_w = 0; 
	wire 	[3:0] 	ws_w_idle = 0; 
	wire 	[3:0] 	ws_w_wdata = 1; 
	wire 	[3:0] 	ws_w_winc = 2; 
	wire 	[3:0] 	ws_w_eof = 3; 

	//	Write Pointer. Burst bytes is always C_ADDR_INC. 
	reg 	[C_BUF_SIZE-1:0] 	rc_w_ptr = 0; 
	reg 	[0:0] 		rc_w_eof = 0; 
	reg 				r_w_rst = 1; 
	
	//	Burst Control
	reg 	[7:0] 	rc_burst = 0; 	//	Compare to C_BURST_LEN - 1. 突发计数器
	
	//	EOF Monitor. 
	reg 	[1:0] 	r_wframe_sync = 0; 	
	reg 			r_weof_pending = 0; 

	always @(posedge axi_clk or posedge axi_reset) begin
		if(axi_reset) begin
			rs_w <= 0; 
			rc_w_ptr <= 0; 
			rc_w_eof <= 0; 
			r_w_rst <= 1; 
			axi_awvalid <= 0; 
			axi_wvalid <= 0; 
			r_wframe_sync <= 0; 
			r_weof_pending <= 0; 
			r_wframe_inc <= 0; 
			
		end else begin
			rc_w_eof <= 0; 
			r_wframe_inc <= 0; 
			
			//	Raise EOF on falling edge of VSYNC. 
			r_wframe_sync <= {r_wframe_sync, wframe_vsync}; 
			if(r_wframe_sync == 2'b10) begin
				r_weof_pending <= 1; 
			end else begin
			end
			
			if(axi_awready) begin
				axi_awvalid <= 0; 
			end else begin
			end
			
			case (rs_w)
				ws_w_idle: begin
						rc_burst <= 0; 
						r_w_rst <= 0; 
						
						if(~w_wfifo_pempty) begin
							axi_awvalid <= 1; 
							axi_wvalid <= 1; 
							rs_w <= ws_w_wdata; 
						
						end else if(r_weof_pending && (~w_wfifo_empty)) begin
							//	There's some data in the FIFO. write last. 
							axi_awvalid <= 1; 
							axi_wvalid <= 1; 
							rs_w <= ws_w_wdata; 
							
						end else if(r_weof_pending) begin
							//	EOF. Reset FIFO. Increment write pointer. 
							r_w_rst <= 1; 
							r_wframe_inc <= 1; 
							rs_w <= ws_w_eof; 
							
						end else begin
						end
					end
					
				ws_w_eof: begin
						//	Wait for some cycles to release reset. 
						r_weof_pending <= 0; 
						rc_w_ptr <= 0; 
						
						rc_w_eof <= rc_w_eof + 1; 
						if(&rc_w_eof)
							rs_w <= ws_w_idle; 
						else begin
						end
					end
					
				ws_w_wdata: begin
						rc_burst <= rc_burst + axi_wready; 
						
						//	On last transaction terminate write. 
						if(axi_wlast && axi_wready) begin
							axi_wvalid <= 0; 
							rs_w <= ws_w_winc; 
						end else begin
						end
					end
					
				ws_w_winc: begin
						rc_w_ptr <= rc_w_ptr + C_ADDR_INC; 
						rs_w <= ws_w_idle; 
					end
			endcase
		end
	end
	assign axi_awaddr = C_BASE_ADDR + {rc_wframe_index, rc_w_ptr}; 
	assign axi_wdata = w_wfifo_rdata; 
	assign axi_wlast = (rc_burst >= C_BURST_LEN - 1); 
	assign frame_base_o = C_BASE_ADDR + (rc_rframe_index << C_BUF_SIZE);
	assign frame_id_o = frame_id_slots[rc_rframe_index];
	
	assign w_wfifo_ren = axi_wvalid && axi_wready; 
	
	
	assign tp_o[1:0] = {rs_w[1:0]}; 
	assign tp_o[2] = axi_wvalid; 
	assign tp_o[3] = wframe_data_en; 
	
	
	generate
		if(C_W_WIDTH == 64) begin: Gen_FIFO_W64
			W0_FIFO_64 u_W0_FIFO_64 
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end else if(C_W_WIDTH == 32) begin: Gen_FIFO_W32
			W0_FIFO_32 u_W0_FIFO_32
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end else if(C_W_WIDTH == 8) begin: Gen_FIFO_W8
			W0_FIFO_8 u_W0_FIFO_8 
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end
	endgenerate




















reg                             rframe_vsync_dly;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rframe_vsync_dly <= 1'b0;
    else
        rframe_vsync_dly <= rframe_vsync;
end

wire                            rframe_vsync_neg;
assign rframe_vsync_neg =  rframe_vsync_dly & ~rframe_vsync;

reg             [4:0]           rfifo_cnt;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rfifo_cnt <= 5'h1f;//0-31
    else
    begin
        if(rframe_vsync_neg == 1'b1)
            rfifo_cnt <= 5'h1f;
        else if(rfifo_cnt > 5'd0)
            rfifo_cnt <= rfifo_cnt - 1'b1;
        else
            rfifo_cnt <= 5'b0;
    end
end

reg                             rfifo_rst;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rfifo_rst <= 1'b1;
    else
    begin
        if(rfifo_cnt == 5'b0)
            rfifo_rst <= 1'b0;
        else
            rfifo_rst <= 1'b1;
    end
end


wire 			w_rfifo_rst = axi_reset || rfifo_rst; 

reg                             rfifo_wenb;
reg             [C_DATA_LEN-1:0]          rfifo_wdata;
wire            [ 9:0]          rfifo_wcnt;
wire 					  rfifo_wfull; 
wire                            rfifo_wr_rst_busy;
wire 					w_rfifo_aempty; 
wire 					w_rfifo_empty; 


generate
	if(C_R_WIDTH == 8) begin: Gen_RFIFO_8
		R0_FIFO_8 u_R0_FIFO_8
		(
			.wr_clk_i		(axi_clk),
			.wr_en_i		(rfifo_wenb),
			.wdata			(rfifo_wdata),
			.a_rst_i		(w_rfifo_rst), 
			.prog_full_o		(rfifo_wfull),
			
			.rd_clk_i		(rframe_pclk),
			.rd_en_i		(rframe_data_en),
			.rdata			(rframe_data),
			.empty_o		(w_rfifo_empty),
			.almost_empty_o	(w_rfifo_aempty)
		);
	end else if(C_R_WIDTH == 16) begin: Gen_RFIFO_16	
		R0_FIFO_16 u_R0_FIFO_16
		(
			.wr_clk_i		(axi_clk),
			.wr_en_i		(rfifo_wenb),
			.wdata			(rfifo_wdata),
			.a_rst_i		(w_rfifo_rst), 
			.prog_full_o		(rfifo_wfull),
			
			.rd_clk_i		(rframe_pclk),
			.rd_en_i		(rframe_data_en),
			.rdata			(rframe_data),
			.empty_o		(w_rfifo_empty),
			.almost_empty_o	(w_rfifo_aempty)
		);
	end else if(C_R_WIDTH == 32) begin: Gen_RFIFO_32	
		R0_FIFO_32 u_R0_FIFO_32
		(
			.wr_clk_i		(axi_clk),
			.wr_en_i		(rfifo_wenb),
			.wdata			(rfifo_wdata),
			.a_rst_i		(w_rfifo_rst), 
			.prog_full_o		(rfifo_wfull),
			
			.rd_clk_i		(rframe_pclk),
			.rd_en_i		(rframe_data_en),
			.rdata			(rframe_data),
			.empty_o		(w_rfifo_empty),
			.almost_empty_o	(w_rfifo_aempty)
		);
	end
endgenerate
		
reg r_rfifo_rst = 0; 
always @(posedge axi_clk)
begin
	r_rfifo_rst <= w_rfifo_rst; 
end

//assign tp_o[7:0] = {w_rfifo_empty, rfifo_wfull, rframe_data_en, rfifo_wenb, rfifo_rst, axi_reset, rframe_pclk, axi_clk}; 

reg             [15:0]               rfifo_wr_rst_busy_dly = 2'b0;

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        rfifo_wr_rst_busy_dly <= 0;
    else
        rfifo_wr_rst_busy_dly <= {rfifo_wr_rst_busy_dly,1'b1};
end

wire                                rfifo_wr_rst_busy_neg;
assign rfifo_wr_rst_busy_neg = (rfifo_wr_rst_busy_dly[1:0] == 2'b01) ? 1'b1 : 1'b0;

reg             [4:0]               read_ddr_delay_cnt;

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        read_ddr_delay_cnt <= 5'b0;
    else
    begin
        if(rfifo_wr_rst_busy_neg == 1'b1)
            read_ddr_delay_cnt <= 5'd31;
        else if(read_ddr_delay_cnt > 5'b0)
            read_ddr_delay_cnt <= read_ddr_delay_cnt - 1'b1;
        else
            read_ddr_delay_cnt <= 5'b0;
    end
end

always @(posedge axi_clk or posedge axi_reset) begin
	if(axi_reset)
		r_rframe_inc <= 0; 
	else
		r_rframe_inc <= rfifo_wr_rst_busy_neg; 
end


wire                                read_ddr_init_flag;
assign read_ddr_init_flag = (read_ddr_delay_cnt == 5'd1) ? 1'b1 : 1'b0;

//----------------------------------------------------------------------




//----------------------------------------------------------------------
localparam S_READ_IDLE = 2'd0;
localparam S_READ_ADDR = 2'd1;
localparam S_READ_DATA = 2'd2;

reg             [ 1:0]          rd_state;
reg             [ 8:0]          rdata_cnt;
reg             [C_BUF_SIZE-1:0]          araddr;
reg 					r_rd_pend = 0; 


always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst) begin
        rd_state <= S_READ_IDLE;
	  axi_arvalid <= 0; 
	  r_rd_pend <= 0; 
    end else
    begin
	
	
	
	if(axi_arready) begin
		axi_arvalid <= 0; 
	end else begin
	end
	if(axi_rvalid && axi_rlast) begin
		 r_rd_pend <= 0; 
	end else begin
	end
	
        case(rd_state)
            S_READ_IDLE : 
            begin
			//	Continue if RFIFO ~Full. 
                if(rfifo_wr_rst_busy_dly[15] && (araddr < C_RD_END_ADDR)&&(~rfifo_wfull)) begin	//	rfifo_wcnt < 10'd256))
                    rd_state <= S_READ_ADDR;
                end else
                    rd_state <= S_READ_IDLE;
            end
		
            S_READ_ADDR : 
            begin
				axi_arvalid <= 1; 
				r_rd_pend <= 1; 
                rd_state <= S_READ_DATA;
            end
            S_READ_DATA : 
            begin
			//	Return when ~arvalid && ~rd_pend. 
			if((~axi_arvalid) && (~r_rd_pend))
                //if((axi_rvalid == 1'b1)&&(axi_rready == 1'b1)&&(rdata_cnt == C_BURST_LEN))
                    rd_state <= S_READ_IDLE;
                else
                    rd_state <= S_READ_DATA;
            end
            default : 
            begin
                rd_state <= S_READ_IDLE;
            end
        endcase
    end
end

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        araddr <= 0;
    else
    begin
        if((axi_arvalid == 1'b1)&&(axi_arready == 1'b1))
            araddr <= araddr + C_ADDR_INC;
        else
            araddr <= araddr;
    end
end

assign axi_araddr = C_BASE_ADDR + {rc_rframe_index, araddr};


reg             [8:0]           rdata_cnt_dly;

always @(posedge axi_clk)
begin
    rdata_cnt_dly <= rdata_cnt;
end

always @(*)
begin
    if(rd_state == S_READ_DATA)
        begin
        if((axi_rvalid == 1'b1)&&(axi_rready == 1'b1))
            rdata_cnt = rdata_cnt_dly + 1'b1;
        else
            rdata_cnt = rdata_cnt_dly;
        end
    else
        rdata_cnt = 9'b0;
end

assign axi_rready = 1; 

always @(posedge axi_clk)
begin
    if(axi_reset == 1'b1)
        rfifo_wenb <= 1'b0;
    else
    begin
        if((axi_rvalid == 1'b1)&&(axi_rready == 1'b1))
            rfifo_wenb <= 1'b1;
        else
            rfifo_wenb <= 1'b0;
    end
end

always @(posedge axi_clk)
begin
    rfifo_wdata <= axi_rdata;
end

endmodule
