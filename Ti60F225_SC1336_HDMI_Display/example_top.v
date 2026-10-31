`timescale 1ns/1ps

//`include "ddr3_controller.vh"


module example_top 
(


	////////////////////////////////////////////////////////////////
	//	key input
	input k1,
	input k2,

	// FPGA user JTAG tap for loading/debugging the RV32 ELF via USB.
	input jtag_inst1_TCK, jtag_inst1_TDI, jtag_inst1_SEL,
	input jtag_inst1_CAPTURE, jtag_inst1_SHIFT, jtag_inst1_UPDATE,
	input jtag_inst1_RESET,
	output jtag_inst1_TDO,

	////////////////////////////////////////////////////////////////
	//	External Clock & Reset
	//input 			nrst, 			//	Button K2
	input 			clk_24m,			//	24MHz Crystal
	input 			clk_25m,			//	25MHz Crystal 
	
	
	////////////////////////////////////////////////////////////////
	//	System Clock
	output 			sys_pll_rstn_o, 		
	
	input 			clk_sys,			//	Sys PLL 96MHz 
	input 			clk_pixel,			//	Sys PLL 74.25MHz
	input 			clk_pixel_2x,		//	Sys PLL 148.5MHz
	input 			clk_pixel_10x,		//	Sys PLL 742.5MHz
	
	input 			sys_pll_lock,		//	Sys PLL Lock
	
	////////////////////////////////////////////////////////////////
	//	MIPI-DSI Clock & Reset
	output 			dsi_pll_rstn_o,
	
	input 			dsi_refclk_i,		//	48MHz Reference Clock (for DSI PLL)
	input 			dsi_byteclk_i,		//	DSI Byte Clock (1X)
	input 			dsi_serclk_i,		//	DSI Serial Clock (4X 45)
	input 			dsi_txcclk_i,		//	DSI Serial Clock (4X 135)
	
	input 			dsi_pll_lock,
	
	////////////////////////////////////////////////////////////////
	//	DDR Clock
	output 			ddr_pll_rstn_o, 
	
	input 			tdqss_clk,			
	input 			core_clk,			//	DDR PLL 200MHz
	input 			tac_clk,			
	input 			twd_clk,			
	
	input 			ddr_pll_lock,		//	DDR PLL Lock
	
	////////////////////////////////////////////////////////////////
	//	DDR PLL Phase Shift Interface
	output 	[2:0] 	shift,
	output 	[4:0] 	shift_sel,
	output 			shift_ena,
	
	
	
	////////////////////////////////////////////////////////////////
	//	LVDS Clock
	output 			lvds_pll_rstn_o, 
	
	input 			clk_lvds_1x, 
	input 			clk_lvds_7x, 
	input 			clk_27m, 			//	RGB 1X Clock (16MHz)
	input 			clk_54m, 			//	RGB 2X Clock (32MHz, for export control)
	
	input 			lvds_pll_lock, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	DDR Interface Ports
	output 	[15:0] 	addr,
	output 	[2:0] 	ba,
	output 			we,
	output 			reset,
	output 			ras,
	output 			cas,
	output 			odt,
	output 			cke,
	output 			cs,
	
	//	DQ I/O
	input 	[15:0] 	i_dq_hi,
	input 	[15:0] 	i_dq_lo,
	
	output 	[15:0] 	o_dq_hi,
	output 	[15:0] 	o_dq_lo,
	output 	[15:0] 	o_dq_oe,
	
	//	DM O
	output 	[1:0] 	o_dm_hi,
	output 	[1:0] 	o_dm_lo,
	
	//	DQS I/O
	input 	[1:0] 	i_dqs_hi,
	input 	[1:0] 	i_dqs_lo,
	
	input 	[1:0] 	i_dqs_n_hi,
	input 	[1:0] 	i_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_hi,
	output 	[1:0] 	o_dqs_lo,
	
	output 	[1:0] 	o_dqs_n_hi,
	output 	[1:0] 	o_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_oe,
	output 	[1:0] 	o_dqs_n_oe,
	
	//	CK
	output 			clk_p_hi, 
	output 			clk_p_lo, 
	output 			clk_n_hi, 
	output 			clk_n_lo, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	MIPI-CSI Ctl / I2C
	output 			csi_ctl0_o,
	output 			csi_ctl0_oe,
	input 			csi_ctl0_i,
	
	output 			csi_ctl1_o,
	output 			csi_ctl1_oe,
	input 			csi_ctl1_i,
	
	output 			csi_scl_o,
	output 			csi_scl_oe,
	input 			csi_scl_i,
	
	output 			csi_sda_o,
	output 			csi_sda_oe,
	input 			csi_sda_i,
	
	//	MIPI-CSI RXC 
	input 			csi_rxc_lp_p_i,
	input 			csi_rxc_lp_n_i,
	output 			csi_rxc_hs_en_o,
	output 			csi_rxc_hs_term_en_o,
	input 			csi_rxc_i,
	
	//	MIPI-CSI RXD0
	output 			csi_rxd0_rst_o,
	output 			csi_rxd0_hs_en_o,
	output 			csi_rxd0_hs_term_en_o,
	
	input 			csi_rxd0_lp_p_i,
	input 			csi_rxd0_lp_n_i,
	input 	[7:0] 	csi_rxd0_hs_i,
	
	//	MIPI-CSI RXD1
	output 			csi_rxd1_rst_o,
	output 			csi_rxd1_hs_en_o,
	output 			csi_rxd1_hs_term_en_o,
	
	input 			csi_rxd1_lp_n_i,
	input 			csi_rxd1_lp_p_i,
	input 	[7:0] 	csi_rxd1_hs_i,
	
	//	MIPI-CSI RXD2
	output 			csi_rxd2_rst_o,
	output 			csi_rxd2_hs_en_o,
	output 			csi_rxd2_hs_term_en_o,
	
	input 			csi_rxd2_lp_p_i,
	input 			csi_rxd2_lp_n_i,
	input 	[7:0] 	csi_rxd2_hs_i,
	
	//	MIPI-CSI RXD3
	output 			csi_rxd3_rst_o,
	output 			csi_rxd3_hs_en_o,
	output 			csi_rxd3_hs_term_en_o,
	
	input 			csi_rxd3_lp_p_i,
	input 			csi_rxd3_lp_n_i,
	input 	[7:0] 	csi_rxd3_hs_i,
	
	//output 			csi_rxd0_fifo_rd_o, 
	//input 			csi_rxd0_fifo_empty_i, 
	//output 			csi_rxd1_fifo_rd_o, 
	//input 			csi_rxd1_fifo_empty_i, 
	//output 			csi_rxd2_fifo_rd_o, 
	//input 			csi_rxd2_fifo_empty_i, 
	//output 			csi_rxd3_fifo_rd_o, 
	//input 			csi_rxd3_fifo_empty_i, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	DSI PWM & Reset Control 
	output 			dsi_pwm_o,			//	MIPI-DSI LCD PWM
	output 			dsi_resetn_o,		//	MIPI-DSI LCD Reset
	
	//	MIPI-DSI TXC / TXD
	output 			dsi_txc_rst_o,
	output 			dsi_txc_lp_p_oe,
	output 			dsi_txc_lp_p_o,
	output 			dsi_txc_lp_n_oe,
	output 			dsi_txc_lp_n_o,
	output 			dsi_txc_hs_oe,
	output 	[7:0] 	dsi_txc_hs_o,
	
	output 			dsi_txd0_rst_o,
	output 			dsi_txd0_hs_oe,
	output 	[7:0] 	dsi_txd0_hs_o,
	output 			dsi_txd0_lp_p_oe,
	output 			dsi_txd0_lp_p_o,
	output 			dsi_txd0_lp_n_oe,
	output 			dsi_txd0_lp_n_o,
	
	output 			dsi_txd1_rst_o,
	output 			dsi_txd1_lp_p_oe,
	output 			dsi_txd1_lp_p_o,
	output 			dsi_txd1_lp_n_oe,
	output 			dsi_txd1_lp_n_o,
	output 			dsi_txd1_hs_oe,
	output 	[7:0] 	dsi_txd1_hs_o,
	
	output 			dsi_txd2_rst_o,
	output 			dsi_txd2_lp_p_oe,
	output 			dsi_txd2_lp_p_o,
	output 			dsi_txd2_lp_n_oe,
	output 			dsi_txd2_lp_n_o,
	output 			dsi_txd2_hs_oe,
	output 	[7:0] 	dsi_txd2_hs_o,
	
	output 			dsi_txd3_rst_o,
	output 			dsi_txd3_lp_p_oe,
	output 			dsi_txd3_lp_p_o,
	output 			dsi_txd3_lp_n_oe,
	output 			dsi_txd3_lp_n_o,
	output 			dsi_txd3_hs_oe,
	output 	[7:0] 	dsi_txd3_hs_o,
	
	input 			dsi_txd0_lp_p_i,
	input 			dsi_txd0_lp_n_i,
	input 			dsi_txd1_lp_p_i,
	input 			dsi_txd1_lp_n_i,
	input 			dsi_txd2_lp_p_i,
	input 			dsi_txd2_lp_n_i,
	input 			dsi_txd3_lp_p_i,
	input 			dsi_txd3_lp_n_i,
	
	
	////////////////////////////////////////////////////////////////
	//	UART Interface
	input 		 	uart_rx_i,			//	Support 460800-8-N-1. 
	output 		 	uart_tx_o, 
	
	
	output 	[5:0] 	led_o,			//	
	
	
	////////////////////////////////////////////////////////////////
	//	CMOS Sensor
	output 			cmos_sclk,
	input 			cmos_sdat_IN,
	output 			cmos_sdat_OUT,
	output 			cmos_sdat_OE,
	
	//	CMOS Interface
	input 			cmos_pclk,
	input 			cmos_vsync,
	input 			cmos_href,
	input 	[7:0] 	cmos_data,
	// input 			cmos_ctl1,
	// output 			cmos_ctl2,
	// output 			cmos_ctl3,
	
	
	////////////////////////////////////////////////////////////////
	//	HDMI Interface
	output 			hdmi_txc_oe,
	output 			hdmi_txd0_oe,
	output 			hdmi_txd1_oe,
	output 			hdmi_txd2_oe,
	
	output 			hdmi_txc_rst_o,
	output 			hdmi_txd0_rst_o,
	output 			hdmi_txd1_rst_o,
	output 			hdmi_txd2_rst_o,
	
	output 	[9:0] 	hdmi_txc_o,
	output 	[9:0] 	hdmi_txd0_o,
	output 	[9:0] 	hdmi_txd1_o,
	output 	[9:0] 	hdmi_txd2_o,
	
	
	////////////////////////////////////////////////////////////////
	//	LVDS Interface
	output 			lvds_txc_oe,
	output 	[6:0] 	lvds_txc_o,
	output 			lvds_txc_rst_o,
	
	output 			lvds_txd0_oe,
	output 	[6:0] 	lvds_txd0_o,
	output 			lvds_txd0_rst_o,
	
	output 			lvds_txd1_oe,
	output 	[6:0] 	lvds_txd1_o,
	output 			lvds_txd1_rst_o,
	
	output 			lvds_txd2_oe,
	output 	[6:0] 	lvds_txd2_o,
	output 			lvds_txd2_rst_o,
	
	output 			lvds_txd3_oe,
	output 	[6:0] 	lvds_txd3_o,
	output 			lvds_txd3_rst_o,
	
	
	////////////////////////////////////////////////////////////////
	//	RGB LCD 5Inch 800x480
	output 			lcd_tp_sda_o,		//	TP SDA
	output 			lcd_tp_sda_oe,
	input 			lcd_tp_sda_i,
	
	output 			lcd_tp_scl_o,		//	TP SCL
	output 			lcd_tp_scl_oe,
	input 			lcd_tp_scl_i,
	
	output 			lcd_tp_int_o,		//	TP INT
	output 			lcd_tp_int_oe,
	input 			lcd_tp_int_i,
	
	output 			lcd_tp_rst_o,		//	TP RST
	
	output 			lcd_pwm_o,			//	Backlight
	output 			lcd_blen_o,
	
	//output 			lcd_pclk_o,			//	PCLK & SCK Mux
	output 			lcd_vs_o,			//	VS & SSN Mux. Fixed to 1. Use DE-Only mode. 
	output 			lcd_hs_o,			//	HS. Fixed to 1. Use DE-Only mode. 
	output 	[7:0] 	lcd_b7_0_o,			//	B7:B0. 
	output 	[7:0] 	lcd_g7_0_o,			//	G7:G0. Must output 8'hFF when access SPI. 
	output 	[7:0] 	lcd_r7_0_o,			//	R7:R0. 
	
	output 	[7:0] 	lcd_b7_0_oe,		//	B7:B0. 
	output 	[7:0] 	lcd_g7_0_oe,		//	G7:G0. Must output 8'hFF when access SPI. 
	output 	[7:0] 	lcd_r7_0_oe,		//	R7:R0. 

	input 	[7:0] 	lcd_b7_0_i,			//	B7:B0. 
	input 	[7:0] 	lcd_g7_0_i,			//	G7:G0. Must output 8'hFF when access SPI. 
	input 	[7:0] 	lcd_r7_0_i,			//	R7:R0. 
	
	//	SPI Pins
	output 			spi_sck_o, 
	output 			spi_ssn_o 			
);
	
	wire 			csi_rxd0_fifo_rd_o; 
	wire 			csi_rxd0_fifo_empty_i = 0;  
	wire 			csi_rxd1_fifo_rd_o;  
	wire 			csi_rxd1_fifo_empty_i = 0;  
	wire 			csi_rxd2_fifo_rd_o;  
	wire 			csi_rxd2_fifo_empty_i = 0;  
	wire 			csi_rxd3_fifo_rd_o;  
	wire 			csi_rxd3_fifo_empty_i = 0;  
	
	
	parameter 	SIM_DATA 	= 0; 
	
	//	Hardware Configuration
	assign clk_p_hi = 1'b0;	//	DDR3 Clock requires 180 degree shifted. 
	assign clk_p_lo = 1'b1;
	assign clk_n_hi = 1'b1;
	assign clk_n_lo = 1'b0; 
	
	//	System Clock Tree Control
	assign sys_pll_rstn_o = 1'b1; 	//	nrst; 	//	Reset whole system when nrst (K2) is pressed. 
	
	assign dsi_pll_rstn_o = sys_pll_lock; 
	assign ddr_pll_rstn_o = sys_pll_lock; 
	assign lvds_pll_rstn_o = sys_pll_lock; 
	
	wire 			w_pll_lock = sys_pll_lock && dsi_pll_lock && ddr_pll_lock && lvds_pll_lock; 
	
	//	Synchronize System Resets. 
	reg 			rstn_sys = 0, rstn_pixel = 0; 
	wire 			rst_sys = ~rstn_sys, rst_pixel = ~rstn_pixel; 
	
	reg 			rstn_dsi_refclk = 0, rstn_dsi_byteclk = 0; 
	wire 			rst_dsi_refclk = ~rstn_dsi_refclk, rst_dsi_byteclk = ~rstn_dsi_byteclk; 
	
	reg 			rstn_lvds_1x = 0; 
	wire 			rst_lvds_1x = ~rstn_lvds_1x; 
	
	reg 			rstn_27m = 0, rstn_54m = 0; 
	wire 			rst_27m = ~rstn_27m, rst_54m = ~rstn_54m; 
	
	//	Clock Gen
	always @(posedge clk_27m or negedge w_pll_lock) begin if(~w_pll_lock) rstn_27m <= 0; else rstn_27m <= 1; end
	always @(posedge clk_54m or negedge w_pll_lock) begin if(~w_pll_lock) rstn_54m <= 0; else rstn_54m <= 1; end
	always @(posedge clk_sys or negedge w_pll_lock) begin if(~w_pll_lock) rstn_sys <= 0; else rstn_sys <= 1; end
	always @(posedge clk_pixel or negedge w_pll_lock) begin if(~w_pll_lock) rstn_pixel <= 0; else rstn_pixel <= 1; end
	always @(posedge dsi_refclk_i or negedge w_pll_lock) begin if(~w_pll_lock) rstn_dsi_refclk <= 0; else rstn_dsi_refclk <= 1; end
	always @(posedge dsi_byteclk_i or negedge w_pll_lock) begin if(~w_pll_lock) rstn_dsi_byteclk <= 0; else rstn_dsi_byteclk <= 1; end
	always @(posedge clk_lvds_1x or negedge w_pll_lock) begin if(~w_pll_lock) rstn_lvds_1x <= 0; else rstn_lvds_1x <= 1; end
	
	
	localparam 	CLOCK_MAIN 	= 96000000; 	//	System clock using 96MHz. 
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	Flash Burner Control
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	wire 			w_ustick, w_mstick; 
	
	wire  [7:0] 	w_dev_index_o;  
	wire  [7:0] 	w_dev_cmd_o;  
	wire  [31:0] 	w_dev_wdata_o;  
	wire  		w_dev_wvalid_o;  
	wire  		w_dev_rvalid_o;  
	wire 	[31:0] 	w_dev_rdata_i;  
	
	wire 			w_spi_ssn_o, w_spi_sck_o; 
	wire 	[3:0] 	w_spi_data_o, w_spi_data_oe; 
	wire 	[3:0] 	w_spi_data_i; 
	
	//	Flash Control
	// Board configuration Flash shares four RGB-LCD pins. Claim them only
	// while SapphireSoC selects the Flash; restore LCD outputs when idle.
	// SPI mode 0: CDI0=MOSI, CDI1=MISO; CDI2/WP and CDI3/HOLD stay high.
	// Match the generated Ti60 devkit's one-cycle output/input pad registers.
	// The SPI controller's late-sampling pipeline requires both stages.
	// Stage only SPI signals so the shared LCD path keeps its original timing.
	// BEGIN FLASH PAD PIPELINE
	reg flash_pad_ss, flash_pad_sclk;
	reg [1:0] flash_pad_data, flash_pad_oe;
	reg [3:0] flash_data_in;
	always @(posedge clk_sys) begin
		flash_pad_ss <= soc_spi_ss[0];
		flash_pad_sclk <= soc_spi_sclk;
		flash_pad_data <= soc_spi_data_write[1:0];
		flash_pad_oe <= soc_spi_data_oe[1:0];
		flash_data_in <= w_spi_data_i;
	end
	// END FLASH PAD PIPELINE
	wire r_flash_en = ~soc_system_reset && ~flash_pad_ss;
	assign w_spi_ssn_o = soc_system_reset ? 1'b1 : flash_pad_ss;
	assign w_spi_sck_o = soc_system_reset ? 1'b0 : flash_pad_sclk;
	assign w_spi_data_o = {2'b11, flash_pad_data};
	assign w_spi_data_oe = {2'b11, flash_pad_oe};
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	LCD Data Mux
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	wire 	[7:0] 	w_lcd_b_o, w_lcd_g_o, w_lcd_r_o; 
	
	assign lcd_b7_0_o = r_flash_en ? {4'b0, w_spi_data_o[3:2], 2'b0} : w_lcd_b_o; 
	assign lcd_g7_0_o = r_flash_en ? {6'h0, w_spi_data_o[1:0]} : w_lcd_g_o; 
	assign lcd_r7_0_o = r_flash_en ? {8'h00} : w_lcd_r_o; 
	assign lcd_b7_0_oe = r_flash_en ? {4'b0, w_spi_data_oe[3:2], 2'b0} : 8'hFF; 
	assign lcd_g7_0_oe = r_flash_en ? {6'h0, w_spi_data_oe[1:0]} : 8'hFF; 
	assign lcd_r7_0_oe = r_flash_en ? {8'h00} : 8'hFF; 
	
	assign spi_sck_o = w_spi_sck_o; 
	assign spi_ssn_o = w_spi_ssn_o; 
	assign w_spi_data_i = {lcd_b7_0_i[3:2], lcd_g7_0_i[1:0]}; 
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	DDR3 Controller
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	wire			w_ddr3_ui_clk = clk_sys;
	wire			w_ddr3_ui_rst = rst_sys;
	wire			w_ddr3_ui_areset = rst_sys;
	wire			w_ddr3_ui_aresetn = rstn_sys;
	

	//	General AXI Interface 
	wire	[7:0] 	w_ddr3_awid;
	wire	[31:0]	w_ddr3_awaddr;
	wire	[7:0]		w_ddr3_awlen;
	wire			w_ddr3_awvalid;
	wire			w_ddr3_awready;
	
	wire 	[7:0]  	w_ddr3_wid;
	wire 	[127:0] 	w_ddr3_wdata;
	wire 	[15:0]	w_ddr3_wstrb;
	wire			w_ddr3_wlast;
	wire			w_ddr3_wvalid;
	wire			w_ddr3_wready;
	
	wire 	[7:0] 	w_ddr3_bid;
	wire 	[1:0] 	w_ddr3_bresp;
	wire			w_ddr3_bvalid;
	wire			w_ddr3_bready;
	
	wire	[7:0] 	w_ddr3_arid;
	wire	[31:0]	w_ddr3_araddr;
	wire	[7:0]		w_ddr3_arlen;
	wire			w_ddr3_arvalid;
	wire			w_ddr3_arready;
	
	wire 	[7:0] 	w_ddr3_rid;
	wire 	[127:0] 	w_ddr3_rdata;
	wire			w_ddr3_rlast;
	wire			w_ddr3_rvalid;
	wire			w_ddr3_rready;
	wire 	[1:0] 	w_ddr3_rresp;
	
	
	//	AXI Interface Request
	wire 	[7:0] 	w_ddr3_aid;
	wire 	[31:0] 	w_ddr3_aaddr;
	wire 	[7:0]  	w_ddr3_alen;
	wire 	[2:0]  	w_ddr3_asize;
	wire 	[1:0]  	w_ddr3_aburst;
	wire 	[1:0]  	w_ddr3_alock;
	wire			w_ddr3_avalid;
	wire			w_ddr3_aready;
	wire			w_ddr3_atype;

	// SapphireSoc32 half-duplex AXI master. It shares DDR with the video
	// frame store through AXI4_DualMasterMux below.
	wire [7:0] soc_ddr_wid;
	wire [127:0] soc_ddr_wdata;
	wire [15:0] soc_ddr_wstrb;
	wire soc_ddr_wlast, soc_ddr_wvalid, soc_ddr_wready;
	wire [1:0] soc_ddr_bresp;
	wire [7:0] soc_ddr_bid;
	wire soc_ddr_bvalid, soc_ddr_bready;
	wire soc_ddr_rvalid, soc_ddr_rready, soc_ddr_rlast;
	wire [127:0] soc_ddr_rdata;
	wire [7:0] soc_ddr_rid;
	wire [1:0] soc_ddr_rresp;
	wire soc_ddr_arw_valid, soc_ddr_arw_ready, soc_ddr_arw_write;
	wire [31:0] soc_ddr_arw_addr;
	wire [7:0] soc_ddr_arw_id, soc_ddr_arw_len;
	wire [2:0] soc_ddr_arw_size, soc_ddr_arw_prot;
	wire [1:0] soc_ddr_arw_burst;
	wire soc_ddr_arw_lock;
	wire [3:0] soc_ddr_arw_cache, soc_ddr_arw_qos, soc_ddr_arw_region;

	// APB and peripheral wires exported by SapphireSoc32.
	wire [15:0] soc_apb0_addr, soc_apb1_addr;
	wire soc_apb0_psel, soc_apb1_psel, soc_apb0_penable, soc_apb1_penable;
	wire soc_apb0_pwrite, soc_apb1_pwrite;
	wire [31:0] soc_apb0_pwdata, soc_apb1_pwdata;
	wire [31:0] soc_apb0_prdata, soc_apb1_prdata;
	wire soc_apb0_pready, soc_apb1_pready, soc_apb0_pslverror, soc_apb1_pslverror;
	wire soc_system_reset, soc_memory_reset;
	wire soc_uart_tx;
	wire soc_custom_cmd_valid, soc_custom_cmd_ready, soc_custom_rsp_valid, soc_custom_rsp_ready;
	wire [9:0] soc_custom_function_id;
	wire [31:0] soc_custom_in0, soc_custom_in1, soc_custom_out0;
	wire [3:0] soc_gpio_we, soc_gpio_write;
	wire soc_spi_sclk;
	wire [3:0] soc_spi_data_write, soc_spi_data_oe;
	wire [0:0] soc_spi_ss;
	assign uart_tx_o = soc_uart_tx;

	// TinyML custom-instruction and full AXI master signals.  The generated
	// RV32 SoC exposes the instruction port directly; the accelerator's AXI
	// master is converted to the same half-duplex shape as the SoC master.
	wire tinyml_cmd_int;
	wire tinyml_awvalid, tinyml_awready;
	wire [31:0] tinyml_awaddr;
	wire [7:0] tinyml_awlen;
	wire [2:0] tinyml_awsize;
	wire [1:0] tinyml_awburst, tinyml_awlock;
	wire [2:0] tinyml_awprot;
	wire [3:0] tinyml_awcache;
	wire [127:0] tinyml_wdata;
	wire [15:0] tinyml_wstrb;
	wire tinyml_wlast, tinyml_wvalid, tinyml_wready;
	wire [1:0] tinyml_bresp;
	wire tinyml_bvalid, tinyml_bready;
	wire tinyml_arvalid, tinyml_arready;
	wire [31:0] tinyml_araddr;
	wire [7:0] tinyml_arlen;
	wire [2:0] tinyml_arsize;
	wire [1:0] tinyml_arburst, tinyml_arlock;
	wire [2:0] tinyml_arprot;
	wire [3:0] tinyml_arcache;
	wire tinyml_rvalid, tinyml_rready, tinyml_rlast;
	wire [127:0] tinyml_rdata;
	wire [1:0] tinyml_rresp;

	wire [7:0] tinyml_ddr_wid, tinyml_ddr_bid, tinyml_ddr_rid;
	wire [127:0] tinyml_ddr_wdata, tinyml_ddr_rdata;
	wire [15:0] tinyml_ddr_wstrb;
	wire tinyml_ddr_wlast, tinyml_ddr_wvalid, tinyml_ddr_wready;
	wire tinyml_ddr_bvalid, tinyml_ddr_bready;
	wire [1:0] tinyml_ddr_bresp;
	wire tinyml_ddr_rvalid, tinyml_ddr_rready, tinyml_ddr_rlast;
	wire [1:0] tinyml_ddr_rresp;
	wire tinyml_ddr_arw_valid, tinyml_ddr_arw_ready, tinyml_ddr_arw_write;
	wire [31:0] tinyml_ddr_arw_addr;
	wire [7:0] tinyml_ddr_arw_id, tinyml_ddr_arw_len;
	wire [2:0] tinyml_ddr_arw_size;
	wire [1:0] tinyml_ddr_arw_burst, tinyml_ddr_arw_lock;

	// First-stage output (video + SoC) becomes the lower-priority input of a
	// second stage that arbitrates TinyML.  This avoids changing the proven
	// video/CPU response routing.
	wire mux0_avalid, mux0_aready, mux0_atype;
	wire [7:0] mux0_aid, mux0_alen;
	wire [31:0] mux0_aaddr;
	wire [2:0] mux0_asize;
	wire [1:0] mux0_aburst;
	wire mux0_alock;
	wire [3:0] mux0_acache, mux0_aqos;
	wire [2:0] mux0_aprot;
	wire mux0_wvalid, mux0_wready, mux0_wlast;
	wire [7:0] mux0_wid;
	wire [127:0] mux0_wdata;
	wire [15:0] mux0_wstrb;
	wire mux0_bvalid, mux0_bready;
	wire [7:0] mux0_bid;
	wire [1:0] mux0_bresp;
	wire mux0_rvalid, mux0_rready, mux0_rlast;
	wire [31:0] ddr_mux0_debug, ddr_mux1_debug;
	wire [351:0] ddr_diagnostics;
	wire [7:0] mux0_rid;
	wire [127:0] mux0_rdata;
	wire [1:0] mux0_rresp;
	
	wire 			w_ddr3_cal_done, w_ddr3_cal_pass; 
	
	//	Do not issue DDR read / write when ~cal_done. 
	reg 			r_ddr_unlock = 0; 
	wire w_ddr3_aready_raw;
	// Both sides of an AXI handshake must see the calibration gate.
	// Otherwise the arbiter can wait forever for an unaccepted command.
	assign w_ddr3_aready = w_ddr3_aready_raw && r_ddr_unlock;
	always @(posedge w_ddr3_ui_clk or negedge w_ddr3_ui_aresetn) begin
		if(~w_ddr3_ui_aresetn)
			r_ddr_unlock <= 0; 
		else
			r_ddr_unlock <= w_ddr3_cal_done; 
	end
	
	DdrCtrl ddr3_ctl_axi (	
		.core_clk		(core_clk),
		.tac_clk		(tac_clk),
		.twd_clk		(twd_clk),	
		.tdqss_clk		(tdqss_clk),
		
		.reset		(reset),
		.cs			(cs),
		.ras			(ras),
		.cas			(cas),
		.we			(we),
		.cke			(cke),    
		.addr			(addr),
		.ba			(ba),
		.odt			(odt),
		
		.o_dm_hi		(o_dm_hi),
		.o_dm_lo		(o_dm_lo),
		
		.i_dq_hi		(i_dq_hi),
		.i_dq_lo		(i_dq_lo),
		.o_dq_hi		(o_dq_hi),
		.o_dq_lo		(o_dq_lo),
		.o_dq_oe		(o_dq_oe),
		
		.i_dqs_hi		(i_dqs_hi),
		.i_dqs_lo		(i_dqs_lo),
		.i_dqs_n_hi		(i_dqs_n_hi),
		.i_dqs_n_lo		(i_dqs_n_lo),
		.o_dqs_hi		(o_dqs_hi),
		.o_dqs_lo		(o_dqs_lo),
		.o_dqs_n_hi		(o_dqs_n_hi),
		.o_dqs_n_lo		(o_dqs_n_lo),
		.o_dqs_oe		(o_dqs_oe),
		.o_dqs_n_oe		(o_dqs_n_oe),
		
		.clk			(w_ddr3_ui_clk),
		.reset_n		(w_ddr3_ui_aresetn),
		
		.axi_avalid		(w_ddr3_avalid && r_ddr_unlock),	//	Enable command only when unlocked. 
		.axi_aready		(w_ddr3_aready_raw),
		.axi_aaddr		(w_ddr3_aaddr),
		.axi_aid		(w_ddr3_aid),
		.axi_alen		(w_ddr3_alen),
		.axi_asize		(w_ddr3_asize),
		.axi_aburst		(w_ddr3_aburst),
		.axi_alock		(w_ddr3_alock),
		.axi_atype		(w_ddr3_atype),
		
		.axi_wid		(w_ddr3_wid),
		.axi_wvalid		(w_ddr3_wvalid),
		.axi_wready		(w_ddr3_wready),
		.axi_wdata		(w_ddr3_wdata),
		.axi_wstrb		(w_ddr3_wstrb),
		.axi_wlast		(w_ddr3_wlast),
		
		.axi_bvalid		(w_ddr3_bvalid),
		.axi_bready		(w_ddr3_bready),
		.axi_bid		(w_ddr3_bid),
		.axi_bresp		(w_ddr3_bresp),
		
		.axi_rvalid		(w_ddr3_rvalid),
		.axi_rready		(w_ddr3_rready),
		.axi_rdata		(w_ddr3_rdata),
		.axi_rid		(w_ddr3_rid),
		.axi_rresp		(w_ddr3_rresp),
		.axi_rlast		(w_ddr3_rlast),
		
		.shift		(shift),
		.shift_sel		(),
		.shift_ena		(shift_ena),
		
		.cal_ena		(1'b1),
		.cal_done		(w_ddr3_cal_done),
		.cal_pass		(w_ddr3_cal_pass)
	);
	
	assign shift_sel = 5'b00100; 		//	ddr_tac_clk always use PLLOUT[2]. 

	// Video-side combined request and response wires for the DDR arbiter.
	wire [7:0] video_aid;
	wire [31:0] video_aaddr;
	wire [7:0] video_alen;
	wire video_avalid, video_aready, video_atype;
	wire video_wvalid, video_wready, video_wlast;
	wire [7:0] video_wid;
	wire [127:0] video_wdata;
	wire [15:0] video_wstrb;
	wire video_bvalid, video_bready;
	wire [7:0] video_bid;
	wire [1:0] video_bresp;
	wire video_rvalid, video_rready, video_rlast;
	wire [7:0] video_rid;
	wire [127:0] video_rdata;
	wire [1:0] video_rresp;
	
	
	AXI4_AWARMux #(.AID_LEN(4), .AADDR_LEN(32)) axi4_awar_mux (
		.aclk_i			(w_ddr3_ui_clk), 
		.arst_i			(w_ddr3_ui_rst), 
		
		.awid_i			(w_ddr3_awid),
		.awaddr_i			(w_ddr3_awaddr),
		.awlen_i			(w_ddr3_awlen),
		.awvalid_i			(w_ddr3_awvalid),
		.awready_o			(w_ddr3_awready),
		
		.arid_i			(w_ddr3_arid),
		.araddr_i			(w_ddr3_araddr),
		.arlen_i			(w_ddr3_arlen),
		.arvalid_i			(w_ddr3_arvalid),
		.arready_o			(w_ddr3_arready),
		
		.aid_o			(video_aid),
		.aaddr_o			(video_aaddr),
		.alen_o			(video_alen),
		.atype_o			(video_atype),
		.avalid_o			(video_avalid),
		.aready_i			(video_aready)
	);

	// CPU and video alternate when both request DDR. The mux holds the
	// selected owner through the complete B/R response, so CPU reads cannot be
	// mistaken for video FIFO reads.
	AXI4_DualMasterMux #(.ID_WIDTH(8), .DATA_WIDTH(128)) u_ddr_master_mux (
		.clk              (w_ddr3_ui_clk),
		.rst              (w_ddr3_ui_rst),
		.v_avalid         (video_avalid),
		.v_aready         (video_aready),
		.v_aid            (video_aid),
		.v_aaddr          (video_aaddr),
		.v_alen           (video_alen),
		.v_atype          (video_atype),
		.v_wvalid         (video_wvalid),
		.v_wready         (video_wready),
		.v_wid            (video_wid),
		.v_wdata          (video_wdata),
		.v_wstrb          (video_wstrb),
		.v_wlast          (video_wlast),
		.v_bvalid         (video_bvalid),
		.v_bready         (video_bready),
		.v_bid            (video_bid),
		.v_bresp          (video_bresp),
		.v_rvalid         (video_rvalid),
		.v_rready         (video_rready),
		.v_rid            (video_rid),
		.v_rdata          (video_rdata),
		.v_rresp          (video_rresp),
		.v_rlast          (video_rlast),
		.s_avalid         (soc_ddr_arw_valid),
		.s_aready         (soc_ddr_arw_ready),
		.s_aid            (soc_ddr_arw_id),
		.s_aaddr          (soc_ddr_arw_addr),
		.s_alen           (soc_ddr_arw_len),
		.s_asize          (soc_ddr_arw_size),
		.s_aburst         (soc_ddr_arw_burst),
		.s_alock          (soc_ddr_arw_lock),
		.s_acache         (soc_ddr_arw_cache),
		.s_aprot          (soc_ddr_arw_prot),
		.s_aqos           (soc_ddr_arw_qos),
		.s_atype          (soc_ddr_arw_write),
		.s_wvalid         (soc_ddr_wvalid),
		.s_wready         (soc_ddr_wready),
		.s_wid            (soc_ddr_wid),
		.s_wdata          (soc_ddr_wdata),
		.s_wstrb          (soc_ddr_wstrb),
		.s_wlast          (soc_ddr_wlast),
		.s_bvalid         (soc_ddr_bvalid),
		.s_bready         (soc_ddr_bready),
		.s_bid            (soc_ddr_bid),
		.s_bresp          (soc_ddr_bresp),
		.s_rvalid         (soc_ddr_rvalid),
		.s_rready         (soc_ddr_rready),
		.s_rid            (soc_ddr_rid),
		.s_rdata          (soc_ddr_rdata),
		.s_rresp          (soc_ddr_rresp),
		.s_rlast          (soc_ddr_rlast),
		.m_avalid         (mux0_avalid),
		.m_aready         (mux0_aready),
		.m_aid            (mux0_aid),
		.m_aaddr          (mux0_aaddr),
		.m_alen           (mux0_alen),
		.m_asize          (mux0_asize),
		.m_aburst         (mux0_aburst),
		.m_alock          (mux0_alock),
		.m_acache         (mux0_acache),
		.m_aprot          (mux0_aprot),
		.m_aqos           (mux0_aqos),
		.m_atype          (mux0_atype),
		.m_wvalid         (mux0_wvalid),
		.m_wready         (mux0_wready),
		.m_wid            (mux0_wid),
		.m_wdata          (mux0_wdata),
		.m_wstrb          (mux0_wstrb),
		.m_wlast          (mux0_wlast),
		.m_bvalid         (mux0_bvalid),
		.m_bready         (mux0_bready),
		.m_bid            (mux0_bid),
		.m_bresp          (mux0_bresp),
		.m_rvalid         (mux0_rvalid),
		.m_rready         (mux0_rready),
		.m_rid            (mux0_rid),
		.m_rdata          (mux0_rdata),
		.m_rresp          (mux0_rresp),
		.m_rlast          (mux0_rlast),
		.debug_state      (ddr_mux0_debug)
	);

	// TinyML and the existing video/CPU aggregate share the physical DDR
	// controller. One complete burst/response owns the port at a time.
	AXI4_DualMasterMux #(.ID_WIDTH(8), .DATA_WIDTH(128)) u_ddr_tinyml_mux (
		.clk              (w_ddr3_ui_clk),
		.rst              (w_ddr3_ui_rst),
		.v_avalid         (tinyml_ddr_arw_valid),
		.v_aready         (tinyml_ddr_arw_ready),
		.v_aid            (tinyml_ddr_arw_id),
		.v_aaddr          (tinyml_ddr_arw_addr),
		.v_alen           (tinyml_ddr_arw_len),
		.v_atype          (tinyml_ddr_arw_write),
		.v_wvalid         (tinyml_ddr_wvalid),
		.v_wready         (tinyml_ddr_wready),
		.v_wid            (tinyml_ddr_wid),
		.v_wdata          (tinyml_ddr_wdata),
		.v_wstrb          (tinyml_ddr_wstrb),
		.v_wlast          (tinyml_ddr_wlast),
		.v_bvalid         (tinyml_ddr_bvalid),
		.v_bready         (tinyml_ddr_bready),
		.v_bid            (tinyml_ddr_bid),
		.v_bresp          (tinyml_ddr_bresp),
		.v_rvalid         (tinyml_ddr_rvalid),
		.v_rready         (tinyml_ddr_rready),
		.v_rid            (tinyml_ddr_rid),
		.v_rdata          (tinyml_ddr_rdata),
		.v_rresp          (tinyml_ddr_rresp),
		.v_rlast          (tinyml_ddr_rlast),
		.s_avalid         (mux0_avalid),
		.s_aready         (mux0_aready),
		.s_aid            (mux0_aid),
		.s_aaddr          (mux0_aaddr),
		.s_alen           (mux0_alen),
		.s_asize          (mux0_asize),
		.s_aburst         (mux0_aburst),
		.s_alock          (mux0_alock),
		.s_acache         (mux0_acache),
		.s_aprot          (mux0_aprot),
		.s_aqos           (mux0_aqos),
		.s_atype          (mux0_atype),
		.s_wvalid         (mux0_wvalid),
		.s_wready         (mux0_wready),
		.s_wid            (mux0_wid),
		.s_wdata          (mux0_wdata),
		.s_wstrb          (mux0_wstrb),
		.s_wlast          (mux0_wlast),
		.s_bvalid         (mux0_bvalid),
		.s_bready         (mux0_bready),
		.s_bid            (mux0_bid),
		.s_bresp          (mux0_bresp),
		.s_rvalid         (mux0_rvalid),
		.s_rready         (mux0_rready),
		.s_rid            (mux0_rid),
		.s_rdata          (mux0_rdata),
		.s_rresp          (mux0_rresp),
		.s_rlast          (mux0_rlast),
		.m_avalid         (w_ddr3_avalid),
		.m_aready         (w_ddr3_aready),
		.m_aid            (w_ddr3_aid),
		.m_aaddr          (w_ddr3_aaddr),
		.m_alen           (w_ddr3_alen),
		.m_asize          (w_ddr3_asize),
		.m_aburst         (w_ddr3_aburst),
		.m_alock          (w_ddr3_alock),
		.m_acache         (),
		.m_aprot          (),
		.m_aqos           (),
		.m_atype          (w_ddr3_atype),
		.m_wvalid         (w_ddr3_wvalid),
		.m_wready         (w_ddr3_wready),
		.m_wid            (w_ddr3_wid),
		.m_wdata          (w_ddr3_wdata),
		.m_wstrb          (w_ddr3_wstrb),
		.m_wlast          (w_ddr3_wlast),
		.m_bvalid         (w_ddr3_bvalid),
		.m_bready         (w_ddr3_bready),
		.m_bid            (w_ddr3_bid),
		.m_bresp          (w_ddr3_bresp),
		.m_rvalid         (w_ddr3_rvalid),
		.m_rready         (w_ddr3_rready),
		.m_rid            (w_ddr3_rid),
		.m_rdata          (w_ddr3_rdata),
		.m_rresp          (w_ddr3_rresp),
		.m_rlast          (w_ddr3_rlast),
		.debug_state      (ddr_mux1_debug)
	);
	Gray_Ddr_Diagnostics u_ddr_diagnostics (
		.clk(clk_sys), .rst_n(rstn_sys),
		.mux0_i(ddr_mux0_debug), .mux1_i(ddr_mux1_debug),
		.address_i(w_ddr3_aaddr),
		.metadata_i({w_ddr3_aid,w_ddr3_alen,w_ddr3_asize,w_ddr3_atype,12'd0}),
		.extra_i({16'd0,soc_custom_cmd_valid,soc_custom_cmd_ready,
			soc_custom_rsp_valid,soc_custom_rsp_ready,tinyml_awvalid,tinyml_arvalid,
			tinyml_wvalid,tinyml_rready,tinyml_bready,tinyml_cmd_int,
			soc_system_reset,soc_memory_reset,r_ddr_unlock,w_ddr3_cal_done,
			w_ddr3_cal_pass,w_pll_lock}), .words_o(ddr_diagnostics)
	);
	
	//assign led_o[1:0] = {w_ddr3_cal_pass, w_ddr3_cal_done}; 
	
	
	
	
	
	
	
	
	
	// ////////////////////////////////////////////////////////////////
	// //	I2C Config (SC130GS)
	
	// //  i2c timing controller module of 16Bit
	// wire            [ 7:0]          sc130_i2c_config_index;
	// wire            [23:0]          sc130_i2c_config_data;
	// wire            [ 7:0]          sc130_i2c_config_size;
	// wire                            sc130_i2c_config_done;
	
	// i2c_timing_ctrl_16bit
	// #(
	//     .CLK_FREQ           (CLOCK_MAIN),                              //  100 MHz
	//     .I2C_FREQ           (50_000    )                               //  10 KHz(<= 400KHz)
	// ) u_i2c_timing_ctrl_16bit (
	//     //  global clock
	//     .clk                (clk_sys                 ),                          //  96MHz
	//     .rst_n              (rstn_sys                ),                          //  system reset

	//     //  i2c interface
	//     .i2c_sclk           (csi_scl_o               ),                          //  i2c clock
	//     .i2c_sdat_IN        (csi_sda_i               ),
	//     .i2c_sdat_OUT       (csi_sda_o               ),
	//     .i2c_sdat_OE        (csi_sda_oe              ),

	//     //  i2c config data
	//     .i2c_config_index   (sc130_i2c_config_index        ),                          //  i2c config reg index, read 2 reg and write xx reg
	//     .i2c_config_data    ({8'h60, sc130_i2c_config_data}),                     //  i2c config data
	//     .i2c_config_size    (sc130_i2c_config_size         ),                          //  i2c config data counte
	//     .i2c_config_done    (sc130_i2c_config_done         )                          //  i2c config timing complete
	// );
	// assign csi_scl_oe = 1; 

	// //  I2C Configure Data of SC130GS
	// I2C_SC130GS_12801024_4Lanes_Config u_I2C_SC130GS_12801024_4Lanes_Config 
	// (
	//     .LUT_INDEX  (sc130_i2c_config_index   ),
	//     .LUT_DATA   (sc130_i2c_config_data    ),
	//     .LUT_SIZE   (sc130_i2c_config_size    )
	// );
	
//wire  i2c_config_done = 1'b1;
//----------------------------------------------
//i2c timing controller module of 16Bit
	wire	[ 7:0]          i2c_config_index;
	wire	[23:0]          i2c_config_data;
	wire	[ 7:0]          i2c_config_size;
	wire	                i2c_config_done;
	wire	[23:0]          sensor_config_data;                     //  {addr,data}
	wire	                sensor_config_data_valid;
	i2c_timing_ctrl_reg16_dat8_wronly
	#(
		.CLK_FREQ       (CLOCK_MAIN ),                                      //  120 MHz
		.I2C_FREQ       (100_000    )                                       //  100 KHz(<= 400KHz)
	)
	u_i2c_timing_ctrl_reg16_dat8_wronly
	(
		//  global clock
		.clk                        (clk_sys                    ),          //  120MHz
		//.rst_n                      (0                 ),          //  system reset
		//.rst_n                      (1                 ),          //  system reset
		.rst_n                      (rstn_sys                 ),          //  system reset
		//.rst_n                      (rst_sys                 ),          //  system reset
	
		//  i2c interface
		.i2c_sclk                   (cmos_sclk                  ),          //  i2c clock
		.i2c_sdat_i                 (cmos_sdat_IN              ),
		.i2c_sdat_o                 (cmos_sdat_OUT              ),
		.i2c_sdat_oe                (cmos_sdat_OE               ),
	
		//  i2c config data
		.i2c_config_index           (i2c_config_index           ),          //  i2c config reg index, read 2 reg and write xx reg
		.i2c_config_data            ({8'h60, i2c_config_data}   ),          //  i2c config data
		.i2c_config_size            (i2c_config_size            ),          //  i2c config data counte
		.i2c_config_done            (i2c_config_done            )           //  i2c config timing complete
	);
	
	
	//----------------------------------
	//I2C Configure Data of SC1336
	I2C_SC1336_1280720_Config    u_I2C_SC1336_1280720_Config   //Auto/Manual Exposure
	(
		.LUT_INDEX  (i2c_config_index   ),
		.LUT_DATA   (i2c_config_data    ),
		.LUT_SIZE   (i2c_config_size    )
	);
	// ////////////////////////////////////////////////////////////////
	// //	I2C Config (AR0135)
	
	// //  i2c timing controller module of 16Bit
	// wire            [ 7:0]          ar0135_i2c_config_index;
	// wire            [31:0]          ar0135_i2c_config_data;
	// wire            [ 7:0]          ar0135_i2c_config_size;
	// wire                            ar0135_i2c_config_done;
	// wire            [15:0]          ar0135_i2c_rdata;                              //  i2c register data

	// i2c_timing_ctrl_reg16_dat16
	// #(
	//     .SIMU_EN            (0              ),
	//     .I2C_READ_EN        (1              ),                              //  Enable I2C Register read
	//     .CLK_FREQ           (CLOCK_MAIN     ),                              //  120 MHz
	//     .I2C_FREQ           (50_000         )                               //  10 KHz(<= 400KHz)
	// )
	// u_i2c_timing_ctrl_16reg_16bit
	// (
	//     //global clock
	//     .clk                (clk_sys                 ),                          //  96MHz
	//     .rst_n              (rstn_sys                ),                          //  system reset

	//     //i2c interface
	//     .i2c_sclk           (cmos_sclk                  ),                  //  i2c clock
	// 	.i2c_sdat_o 	(cmos_sdat_OUT), 
	// 	.i2c_sdat_oe	(cmos_sdat_OE), 
	// 	.i2c_sdat_i 	(cmos_sdat_IN), 
		
	//     //i2c config data
	//     .i2c_config_index   (ar0135_i2c_config_index           ),                  //  i2c config reg index, read 2 reg and write xx reg
	//     .i2c_config_data    ({8'h20, ar0135_i2c_config_data}   ),                  //  i2c config data
	//     .i2c_config_size    (ar0135_i2c_config_size            ),                  //  i2c config data counte
	//     .i2c_config_done    (ar0135_i2c_config_done            ),                  //  i2c config timing complete
	//     .i2c_rdata          (ar0135_i2c_rdata                  )                   //  i2c register data while read i2c slave
	// );
	
	// //----------------------------------------------------------------------
	// //  I2C Configure Data of AR0135
	// I2C_AR0135_1280720_Config u_I2C_AR0135_1280720_Config
	// (
	//     .LUT_INDEX  (ar0135_i2c_config_index   ),
	//     .LUT_DATA   (ar0135_i2c_config_data    ),
	//     .LUT_SIZE   (ar0135_i2c_config_size    )
	// );
	
	
		
	//	CMOS Interface
	//input 			cmos_pclk,
	//input 			cmos_vsync,
	//input 			cmos_href,
	//input 	[7:0] 	cmos_data,
	//input 			cmos_ctl1,
	//output 			cmos_ctl2,
	//output 			cmos_ctl3,

	
	//	Output LED
	reg 	[3:0]		r_cmos_fv_o = 0; 
	reg 	[1:0] 	r_cmos_rx_vsync0_in = 0; 
	always @(posedge cmos_pclk) begin
		r_cmos_rx_vsync0_in <= {r_cmos_rx_vsync0_in, cmos_vsync}; 
		r_cmos_fv_o <= r_cmos_fv_o + ((r_cmos_rx_vsync0_in == 2'b01) ? 1 : 0); 
	end
	assign led_o[5] = r_cmos_fv_o[3]; 
	
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////
	//	System Control. Can be removed for public. 
	
	localparam 	CLK_FREQ 	= 96_000_000; 	//	clk_sys is 96MHz. 
	localparam 	BAUD_RATE 	= 460_800; 		//	Use 460800-8-N-1. 
	
	
	//	SFR I/O Interface
	wire 	[7:0] 	w_sfr_addr_o; 	//	SFR Address (0xFF00 ~ 0xFFFF). 00:Power; 40~5F:Stream0; 60~7F:Stream1. 
	wire 	[7:0] 	w_sfr_wdata_o; 	//	SFR Write Data. 
	wire 			w_sfr_we_o; 		//	SFR WE. 
	reg 	[7:0] 	w_sfr_rdata_i; 	//	Must be valid after sfr_rd_o. 
	wire 			w_sfr_rd_o; 		//	SFR RD. 
	
	
	//	System Control Registers
	reg 			r_dsi_tx_rstn = 0; 	//	DSI TX Reset
	reg 	[7:0] 	r_dsi_pwm = 64; 		//	[6:0]PWM, [7]Pol
	reg 			r_dsi_resetn_o = 0; 	//	DSI Panel Reset
	reg 			r_dsi_data_rstn = 0; 	//	DSI TX Reset
	
	reg 	[3:0] 	r_dsi_lp_p_ovr = 0; 	
	reg 	[3:0] 	r_dsi_lp_n_ovr = 0; 	
	
	
	
	//	AXI-Lite Interface Bridge
	localparam 	CSI_AXILITE_ID 	= 0; 				//	Select DSI_TX when r_axi_sel = DSI_AXILITE_ID. 
	localparam 	DSI_AXILITE_ID 	= 1; 				//	Select DSI_TX when r_axi_sel = DSI_AXILITE_ID. 
	
	reg 	[7:0] 	r_axi_addr = 8'h18; 		//	0xE0 (RW)
	reg 	[31:0] 	r_axi_wdata = 32'h0000000A; 	//	0xE1~0xE4 (RW)
	wire 	[31:0] 	w_axi_rdata; 			//	0xE5~0xE8 (RO)
	reg 	[0:0] 	r_axi_sel = 1; 			//	0xE9[7:2] (RW)
	reg 			r_axi_r1w0 = 0; 			//	0xE9[1] (RW)
	reg 			r_axi_req = 0; 			//	0xE9[0] (WO, Single Cycle)
	reg 			r_axi_req_o = 0; 			//	Delayed of r_axi_req. 
	
	
	//	Buffered AXI Read Data
	reg 	[31:0] 	r_axi_rdata = 0; 		//	Use state machine
	reg 			r_axi_idle = 0; 		//	AXI Idle 
	
	reg 	[3:0] 	rs_axilite = 0; 		//	AXI Access
	wire 	[3:0] 	ws_axilite_idle = 0; 		
	wire 	[3:0] 	ws_axilite_write = 1; 
	wire 	[3:0] 	ws_axilite_read = 2; 
	wire 	[3:0] 	ws_axilite_endread = 3; 
	
	reg 			r_axi_awvalid = 0, r_axi_wvalid = 0, r_axi_arvalid = 0; 
	wire 			w_axi_awready, w_axi_wready, w_axi_arready, w_axi_rvalid; 
	
	
	reg 	[3:0] 	rc_axi_init = 0; 

	always @(posedge clk_sys or posedge rst_sys) begin
		if(rst_sys) begin
			r_dsi_tx_rstn <= 0; 
			r_dsi_pwm <= 64; 
			r_axi_req <= 0; 
			r_dsi_resetn_o <= 0; 
			r_dsi_data_rstn <= 0; 
			
			rs_axilite <= 0; 
			r_axi_awvalid <= 0; 
			r_axi_wvalid <= 0;
			r_axi_arvalid <= 0; 
			
			r_dsi_lp_p_ovr <= 0; 
			r_dsi_lp_n_ovr <= 0; 
			
			rc_axi_init <= 0; 
			r_axi_idle <= 0; 
			
		end else begin
			r_dsi_tx_rstn <= 1; 
			r_dsi_resetn_o <= 1; 
			r_dsi_data_rstn <= 1; 
			
		end
	end
	
	assign dsi_resetn_o = r_dsi_resetn_o; 
	
	assign csi_ctl0_oe = 0; 
	assign csi_ctl1_oe = 0; 
	
	
	PWMLite dsi_pwm (		//	#(.ENABLE_TICK(0), .PWM_BITS(7)) 
		.clk_i			(clk_sys),
		.rst_i			(rst_sys),
		.pwm_i			(r_dsi_pwm[6:0]),
		.pol_i			(r_dsi_pwm[7]), 
		.pwm_o			(dsi_pwm_o)
	);






	////////////////////////////////////////////////////////////////
	//	MIPI CSI RX
	
	//	The CSI RXC shall not be inverted. Data can be inverted with swapped LP data and flipped HS data. 
	localparam 	CSI_RXD_INV 	= 4'b1111; 
	localparam 	CSI_DATA_WIDTH 	= 8; 			
	localparam 	CSI_STRB_WIDTH 	= CSI_DATA_WIDTH / 8; 

	
	////////////////////////////////////////////////////////////////
	//	MIPI-CSI Crop
	
	wire			XYCrop_frame_vsync; 
	wire			XYCrop_frame_href;
	wire			XYCrop_frame_de;
	wire	[63:0]	XYCrop_frame_Gray;

	Sensor_Image_XYCrop
	#(
		.IMAGE_HSIZE_SOURCE (1280 / CSI_STRB_WIDTH),
		.IMAGE_VSIZE_SOURCE (720	 ),
		.IMAGE_HSIZE_TARGET (1280 / CSI_STRB_WIDTH),
		.IMAGE_YSIZE_TARGET (720 	 ),
		.PIXEL_DATA_WIDTH	(CSI_DATA_WIDTH) 		//	32		 )
	)
	u_Sensor_Image_XYCrop
	(
		//	globel clock
		.clk			(cmos_pclk),			//	image pixel clock
		.rst_n		(rstn_sys),			//	system reset
		
		//CMOS Sensor interface
		.image_in_vsync (cmos_vsync		),			//H : Data Valid; L : Frame Sync(Set it by register)
		.image_in_href	(cmos_href		),			//H : Data vaild, L : Line Sync
		.image_in_de	(cmos_href		), 			//H : Data Enable, L : Line Sync
		.image_in_data	(cmos_data),			//8 bits cmos data input
		
		.image_out_vsync(XYCrop_frame_vsync ),			//H : Data Valid; L : Frame Sync(Set it by register)
		.image_out_href (XYCrop_frame_href	),			//H : Data vaild, L : Line Sync
		.image_out_de	(XYCrop_frame_de	), 			//H : Data Enable, L : Line Sync
		.image_out_data (XYCrop_frame_Gray	)			//8 bits cmos data input	
	);

	reg			r_XYCrop_frame_vsync = 0; 
	reg			r_XYCrop_frame_href = 0;
	reg			r_XYCrop_frame_de = 0;
	reg	[63:0]	r_XYCrop_frame_Gray = 0;
	
	always @(posedge cmos_pclk) begin
		r_XYCrop_frame_vsync <= XYCrop_frame_vsync; 
		r_XYCrop_frame_href <= XYCrop_frame_href;
		r_XYCrop_frame_de <= XYCrop_frame_de;
		r_XYCrop_frame_Gray <= XYCrop_frame_Gray;
	end
	
	//	Data Write Assignment
	wire			cmos_frame_vsync = r_XYCrop_frame_vsync;                     //  cmos frame data vsync valid signal
	wire			cmos_frame_href = r_XYCrop_frame_href && r_XYCrop_frame_de;	 //  cmos frame data href vaild  signal
	wire	[63:0]	cmos_frame_Gray = r_XYCrop_frame_Gray; 
	wire 			cmos_vsync_end;

	












	////////////////////////////////////////////////////////////////
	//	DDR R/W Control
	
	// Key gesture state and cross-clock event toggles.  These declarations
	// must precede the DDR instance so Verilog does not create implicit nets.
	wire	[11:0]	edge_threshold_req;
	reg	[11:0]	edge_threshold;
	wire			shape_mode_req;
	reg			shape_mode;
	wire			dbg_mode;
	wire	[2:0]	display_mode_req;
	reg	[2:0]	display_mode;
	reg	[31:0]	view_epoch;
	reg		replay_mode_seen;
	wire			freeze_mode;
	wire			replay_mode;
	wire			save_frame_pulse;
	wire			replay_next_pulse;
	wire			replay_prev_pulse;
	wire	[31:0]		k1_long_sequence;
	wire digit_mode_req;
	reg			save_frame_toggle;
	reg			replay_next_toggle;
	reg			replay_prev_toggle;


	wire                            lcd_de;
	wire                            lcd_hs;      
	wire                            lcd_vs;
	wire 					  lcd_request; 
	wire            [7:0]           lcd_red, lcd_green, lcd_blue;
	wire            [31:0]          lcd_data;


	assign w_ddr3_awid = 0; 
	assign video_wid = 0; 
	assign video_bready = 1'b1;
	
	wire 			w_wframe_vsync; 
	wire 	[7:0] 	w_axi_tp; 
	wire 	[31:0]	w_rgb_frame_base;
	wire 	[31:0]	w_rgb_frame_id;
	wire			cap_rgb_vsync, cap_rgb_href, cap_rgb_hsync;
	wire	[7:0]		cap_rgb_pre_r, cap_rgb_pre_g, cap_rgb_pre_b;
	wire	[7:0]		cap_rgb_r, cap_rgb_g, cap_rgb_b;
	wire	[17:0]	cap_rgb_r_mult = cap_rgb_pre_r * 409;
	wire	[17:0]	cap_rgb_b_mult = cap_rgb_pre_b * 384;
	assign cap_rgb_r = cap_rgb_r_mult[17:16] ? 8'hFF : cap_rgb_r_mult[15:8];
	assign cap_rgb_g = cap_rgb_pre_g;
	assign cap_rgb_b = cap_rgb_b_mult[17:16] ? 8'hFF : cap_rgb_b_mult[15:8];

	// Convert Bayer to RGB once, before DDR. Display, replay and TinyML all
	// consume the same RGBX8888 pixels from the existing frame-slot scheduler.
	// Capture reset: begin
	// The sensor may still be streaming while the FPGA is reconfigured.
	// Ignore that partial frame and all I2C setup traffic. Release only in
	// vertical blanking after configuration has crossed into the camera clock.
	// Keep the original Bayer order; resetting mid-row is not a colour fix.
	reg [1:0] capture_config_sync = 2'b00;
	reg [1:0] capture_reset_sync = 2'b00;
	always @(posedge cmos_pclk or negedge w_pll_lock) begin
		if(!w_pll_lock) begin
			capture_config_sync <= 2'b00;
			capture_reset_sync <= 2'b00;
		end else begin
			capture_config_sync <= {capture_config_sync[0],i2c_config_done};
			if(!capture_config_sync[1])
				capture_reset_sync <= 2'b00;
			else if(!capture_reset_sync[1]) begin
				if(!cmos_frame_vsync && !cmos_frame_href)
					capture_reset_sync <= {capture_reset_sync[0],1'b1};
				else capture_reset_sync <= 2'b00;
			end
		end
	end
	wire rstn_capture = capture_reset_sync[1];
	// Capture reset: end
	VIP_RAW8_RGB888 #(.IMG_HDISP(1280), .IMG_VDISP(720)) capture_bayer2rgb (
		.clk(cmos_pclk), .rst_n(rstn_capture), .mirror(2'b00),
		.per_frame_vsync(cmos_frame_vsync), .per_frame_href(cmos_frame_href),
		.per_frame_hsync(cmos_frame_href), .per_img_RAW(cmos_frame_Gray[7:0]),
		.post_frame_vsync(cap_rgb_vsync), .post_frame_href(cap_rgb_href),
		.post_frame_hsync(cap_rgb_hsync), .post_img_red(cap_rgb_pre_r),
		.post_img_green(cap_rgb_pre_g), .post_img_blue(cap_rgb_pre_b)
	);
	
	// Store the post-Bayer RGB stream as RGBX8888.  Four-byte pixels let the
	// existing W0_FIFO_32 aggregate four pixels into each 128-bit DDR beat.
	// Four megabytes per slot leaves room for the complete 1280x720 frame.
	axi4_ctrl #(.C_BASE_ADDR(32'h02000000), .C_RD_END_ADDR(1280 * 720 * 4),
		.C_BUF_SIZE(22), .C_W_WIDTH(32), .C_R_WIDTH(32), .C_ID_LEN(4)) u_axi4_ctrl (

		.axi_clk        (w_ddr3_ui_clk            ),
		.axi_reset      (w_ddr3_ui_rst            ),

		.axi_awaddr     (w_ddr3_awaddr       ),
		.axi_awlen      (w_ddr3_awlen        ),
		.axi_awvalid    (w_ddr3_awvalid      ),
		.axi_awready    (w_ddr3_awready      ),

		.axi_wdata      (video_wdata         ),
		.axi_wstrb      (video_wstrb         ),
		.axi_wlast      (video_wlast         ),
		.axi_wvalid     (video_wvalid        ),
		.axi_wready     (video_wready        ),

		.axi_bid        (video_bid          ),
		.axi_bresp      (video_bresp        ),
		.axi_bvalid     (video_bvalid       ),

		.axi_arid       (w_ddr3_arid         ),
		.axi_araddr     (w_ddr3_araddr       ),
		.axi_arlen      (w_ddr3_arlen        ),
		.axi_arvalid    (w_ddr3_arvalid      ),
		.axi_arready    (w_ddr3_arready      ),

		.axi_rid        (video_rid            ),
		.axi_rdata      (video_rdata          ),
		.axi_rresp      (video_rresp          ),
		.axi_rlast      (video_rlast          ),
		.axi_rvalid     (video_rvalid         ),
		.axi_rready     (video_rready         ),

		.wframe_pclk    (cmos_pclk          ),
		.wframe_vsync   (cap_rgb_vsync),
		.wframe_data_en (cap_rgb_href),
		// Little-endian DDR bytes become R,G,B,0 in memory.
		.wframe_data    ({8'h00, cap_rgb_b, cap_rgb_g, cap_rgb_r}),
		
		.rframe_pclk    (clk_pixel            ),
		.rframe_vsync   (~lcd_vs             ),		//	Reader VSync. Flush on rising edge. Connect to ~EOF. 
		.rframe_data_en (lcd_request             ),
		.rframe_data    (lcd_data           ),
		.freeze_i       (freeze_mode        ),
		.save_frame_i   (save_frame_toggle  ),
		.replay_mode_i  (replay_mode        ),
		.replay_next_i  (replay_next_toggle ),
		.replay_prev_i  (replay_prev_toggle ),
		.frame_base_o   (w_rgb_frame_base),
		.frame_id_o     (w_rgb_frame_id),
		
		.tp_o 		(w_axi_tp)
	);
	assign led_o[3:0] = w_axi_tp; 
	
	
	
	
	////////////////////////////////////////////////////////////////
	//  LCD Timing Driver
	
	lcd_driver #(.DATA_WIDTH(24)) u_lcd_driver
	(
	    //  global clock
	    .clk        (clk_pixel   ),
	    .rst_n      (rstn_pixel), 
	    
	    //  lcd interface
	    .lcd_dclk   (               ),
	    .lcd_blank  (               ),
	    .lcd_sync   (               ),
	    .lcd_request(lcd_request    ), 	//	Request data 1 cycle ahead. 
	    .lcd_hs     (lcd_hs         ),
	    .lcd_vs     (lcd_vs         ),
	    .lcd_en     (lcd_de         ),
	    .lcd_rgb    ({lcd_red,lcd_green,lcd_blue}),
	    
	    //  user interface
	    .lcd_data   ({lcd_data[7:0],lcd_data[15:8],lcd_data[23:16]})
	);
	
	// =========================================================================================================================================
// bayer 2 rgb
// ========================================================================================================================================= 
	
	// RGBX8888 is already demosaiced and white-balanced before DDR.
	// The FWFT read port presents one complete pixel per display request.
	wire w_rgb_vsync = lcd_vs;
	wire w_rgb_href = lcd_de;
	wire w_rgb_hsync = lcd_hs;
	wire [7:0] w_rgb_r = lcd_red;
	wire [7:0] w_rgb_g = lcd_green;
	wire [7:0] w_rgb_b = lcd_blue;

wire                                    boundcrop_vs               ;
wire                                    boundcrop_hs               ;
wire                                    boundcrop_de               ;
wire                   [  23:0]         boundcrop_data             ;
wire                                    crop_vs                    ;
wire                                    crop_hs                    ;
wire                                    crop_de                    ;
wire                   [  23:0]         crop_data                  ;
// Frame-phase correction: drain all four ISP line delays plus the
// split-view line RAM during blanking. Emit exactly 720 ORIGINAL rows.
wire isp_pipe_de, isp_valid_de, split_valid_de;
wire isp_valid_vs, split_valid_vs, isp_frame_busy;
Video_Frame_Phase #(.WIDTH(1280),.HEIGHT(720),.PAD_LINES(5),
    .ALIGN_LINES(4),.LINE_CLOCKS(1650),.MEASURE_LINE(0)) u_display_phase (
    .clk(clk_pixel),.rst_n(rstn_pixel),
    .vs_i(w_rgb_vsync),.hs_i(w_rgb_hsync),.de_i(w_rgb_href),
    .pipe_de(isp_pipe_de),.aligned_de(isp_valid_de),
    .aligned_next_de(split_valid_de),.aligned_vs(isp_valid_vs),
    .aligned_next_vs(split_valid_vs),.row_index(),.frame_busy(isp_frame_busy));
// FrameBoundCrop(1) + Canny(12) + speckle window(3) = 16 clocks.
reg [15:0] isp_de_phase, isp_vs_phase;
reg [16:0] split_de_phase, split_vs_phase;
always @(posedge clk_pixel or negedge rstn_pixel) begin
    if(!rstn_pixel) begin
        isp_de_phase<=0;isp_vs_phase<=0;split_de_phase<=0;split_vs_phase<=0;
    end else begin
        isp_de_phase<={isp_de_phase[14:0],isp_valid_de};
        isp_vs_phase<={isp_vs_phase[14:0],isp_valid_vs};
        split_de_phase<={split_de_phase[15:0],split_valid_de};
        split_vs_phase<={split_vs_phase[15:0],split_valid_vs};
    end
end

FrameBoundCrop #(.SKIP_ROWS(2),.SKIP_COLS(2),.TOTAL_ROWS(720),.TOTAL_COLS(1280)) inst2_FrameCrop(
    .clk_i                             (clk_pixel                 ),
    .rst_i                             (~rstn_pixel               ),
	
    .vs_i                              (w_rgb_vsync               ),
    .hs_i                              (w_rgb_hsync               ),
    .de_i                              (isp_pipe_de               ),
    .data_i                            ({w_rgb_r, w_rgb_g, w_rgb_b}),
	
    .vs_o                              (crop_vs              ),
    .hs_o                              (crop_hs              ),
    .de_o                              (crop_de              ),
    .data_o                            (crop_data            ) 
);
	////////////////////////////////////////////////////////////////
	//	FrameBoundCrop 输出直接送入 Canny；高斯滤波在 Canny 内部完成
	////////////////////////////////////////////////////////////////
	assign hdmi_txd0_rst_o = rst_pixel; 
	assign hdmi_txd1_rst_o = rst_pixel; 
	assign hdmi_txd2_rst_o = rst_pixel; 
	assign hdmi_txc_rst_o = rst_pixel; 
	
	assign hdmi_txd0_oe = 1'b1; 
	assign hdmi_txd1_oe = 1'b1; 
	assign hdmi_txd2_oe = 1'b1; 
	assign hdmi_txc_oe = 1'b1; 
	

// K1 single: threshold +10; double: freeze/resume; long (~1s):
// colour -> median gray -> median/Sobel -> Gaussian gray -> Canny -> split -> red edges -> colour.
// K2 single: threshold -10; long: digit in binary, shape in edge overlay.
// These controls also process the selected RGB frame while replaying.
// Display changes are committed in vertical blanking to avoid mixed frames.
Key_Ctrl #(
	.LONG_CNT	(27'd74250000)		//	74.25MHz * 1s
) u_Key_Ctrl (
	.clk			(clk_pixel),
	.rst_n			(rstn_pixel),
	.k1				(k1),
	.k2				(k2),
	.threshold_o	(edge_threshold_req),
	.shape_mode_o	(shape_mode_req),
	.dbg_mode_o		(dbg_mode),
	.display_mode_o	(display_mode_req),
	.freeze_o		(freeze_mode),
	.replay_mode_o	(replay_mode),
	.save_frame_o	(save_frame_pulse),
	.replay_next_o	(replay_next_pulse),
	.replay_prev_o	(replay_prev_pulse),
	.k1_press_o		(),
	.k1_long_o		(),
	.k1_long_sequence_o(k1_long_sequence),
	.digit_mode_o(digit_mode_req),
	.k2_press_o		(),
	.k2_short_o		(),
	.k2_long_o		()
);

// Gesture pulses originate in clk_pixel; the DDR scheduler consumes toggles
// so no one-cycle event can be lost at the asynchronous AXI clock.
always @(posedge clk_pixel or negedge rstn_pixel) begin
	if(!rstn_pixel) begin
		save_frame_toggle <= 1'b0;
		replay_next_toggle <= 1'b0;
		replay_prev_toggle <= 1'b0;
	end else begin
		if(save_frame_pulse) save_frame_toggle <= ~save_frame_toggle;
		if(replay_next_pulse) replay_next_toggle <= ~replay_next_toggle;
		if(replay_prev_pulse) replay_prev_toggle <= ~replay_prev_toggle;
	end
end




wire [7:0] filtered_gray;
wire filtered_vs, filtered_de;
wire sobel_strong;
wire filter_gray_mode = (display_mode == 3'd5) || (display_mode == 3'd6);
wire                   [  23:0]         sobel_data             ;	
wire                                    sobel_vs               ;
wire                                    sobel_hs               ;
wire                                    sobel_de               ;
	////////////////////////////////////////////////////////////////
	//	Canny 边缘检测：高斯滤波 → 梯度 → 非极大值抑制 → 双阈值 → 滞后连接
	//	模块本体：src/isp/Canny_Edge.v
	//	为了少改代码，输出仍沿用 sobel_* 这套网络名（其实是 Canny 的结果）
	////////////////////////////////////////////////////////////////
	Canny_Edge #(.ENABLE_MEDIAN_SOBEL(1),.ENABLE_EDGE_GUARD(1),.EDGE_MARGIN(8),.ENABLE_GRAY_DENOISE(1)) u_Canny_Edge
	(
	.clk_i				(clk_pixel),
	.rst_i			(rstn_pixel               ),
	.vs_i                              (crop_vs                ),
    .hs_i                              (crop_hs                 ),
    .de_i                              (crop_de                 ),
	.data_i  							(crop_data),
        .median_sobel_i((display_mode == 3'd4) || (display_mode == 3'd5)),
        // Never alter the accepted red-edge / shape-recognition stream.
        .edge_guard_i((display_mode==3'd1)||(display_mode==3'd2)||(display_mode==3'd4)),
        .filtered_gray_o(filtered_gray),
        .edge_strong_o(sobel_strong),
        .filtered_vs_o(filtered_vs), .filtered_de_o(filtered_de),
	.data_o								(sobel_data),
	.vs_o                              (sobel_vs              ),
    .hs_o                              (sobel_hs              ),
	.threshold_i  						(edge_threshold),
    .de_o   							(sobel_de)
	);




	////////////////////////////////////////////////////////////////
	//	简单图形识别：矩形 / 圆形 / 三角形
	//	模块本体：src/isp/Shape_Classify.v
	//	输出 shape_o 和当前边缘所属类别，识别模式下颜色送给 Edge_Overlay ——
	//	矩形蓝、圆形绿、三角形黄；普通模式始终用红色显示边缘
	//	（按帧更新，比画面晚一帧，肉眼无感）
	////////////////////////////////////////////////////////////////
	//	多图形识别：8 条候选链，每一路都可以给出一个图形
	//	0未知 1矩形 2圆形 3三角形；颜色在画面标注模块里按类别取
	wire	[7:0]	shape_vld;
	wire	[15:0]	shape_id;			//	8 路 x 2bit
	wire	[47:0]	shape_corners;			//	8 路 x 6bit，调试用角点数
	wire	[95:0]	shape_bx0, shape_by0, shape_bx1, shape_by1;	//	8 路 x 12bit
	wire			shape_edge_f;		//	斑点滤除后的边缘（给叠加/诊断视图）
	wire			shape_sel;			//	落在任一识别框内的边缘
	wire	[1:0]	shape_sel_id;			//	当前边缘所在识别框的类别
	wire			shape_vs_f, shape_de_f;
    wire shape_edge_center,shape_strong_center;
    wire binary_display_mode = (display_mode == 3'd1) || (display_mode == 3'd4);
    // Both binary algorithms retain firmware mode 1; view_epoch distinguishes transitions.
    wire [1:0] cpu_display_mode = binary_display_mode ? 2'd1 :
        filter_gray_mode ? 2'd0 : display_mode[1:0];
	// Shape_Classify's 3x3 speckle window delays VS/DE by three clocks.
	reg [2:0] shape_hs_pipe;
	always @(posedge clk_pixel or negedge rstn_pixel) begin
		if(!rstn_pixel) shape_hs_pipe <= 3'd0;
		else shape_hs_pipe <= {shape_hs_pipe[1:0], sobel_hs};
	end
	
	Shape_Classify #(
        .ENABLE_STRENGTH(1),
		.IMG_HDISP	(1280),
		.IMG_VDISP	(720),
		.GAPX		(12'd3),			//	横向连接容差
		.GAPY		(12'd5),			//	行间隔容差（手绘线条会断行）
		.EXT_MAX	(12'd24),			//	一段最多能把链的跨度往外扩多少
		.LONG_RUN	(12'd24),			//	长段可以踢掉噪声链
		.SPK_MIN	(2),				//	斑点滤除：8 邻域至少 2 个邻居
		.MIN_PIX	(16'd250),			//	链的像素数下限
		.MIN_AREA	(32'd4000),			//	链"围住面积"下限（比像素数更能区分图形和背景线）
		.MIN_SIZE	(12'd24),
		.MAX_W		(12'd1120),			//	超过 7/8 画面的一律不算图形
		.MAX_H		(12'd630),
		.BORDER		(12'd24),			//	画面四周这一圈不参与（刷黑边框/纸边）
		.ROI_X_MIN	(12'd100),			//	图形识别 ROI 左边界（含）
		.ROI_X_MAX	(12'd1180),			//	图形识别 ROI 右边界（含）
		.HOLD_MISSES	(2)			//	允许偶发漏判 2 帧，避免识别框闪烁
	) u_Shape_Classify (
		.clk		(clk_pixel),
		.rst_n		(rstn_pixel),
		.vs_i		(sobel_vs),
		.de_i		(sobel_de),
		.edge_i		(|sobel_data),
        .strong_i(sobel_strong),.strong_center_o(shape_strong_center),
		.vld_o		(shape_vld),
		.corners_o	(shape_corners),
		.shape_o	(shape_id),
		.bx0_o		(shape_bx0),
		.by0_o		(shape_by0),
		.bx1_o		(shape_bx1),
		.by1_o		(shape_by1),
		.edge_f_o(shape_edge_f),
        .edge_center_o(shape_edge_center),
		.sel_o		(shape_sel),
		.sel_shape_o	(shape_sel_id),
		.vs_f_o		(shape_vs_f),
		.de_f_o		(shape_de_f)
	);
	
	////////////////////////////////////////////////////////////////
	//	边缘彩色叠加
	//	整屏显示原始彩色图像，边缘像素画成 shape_color（按识别结果变色）
	//	模块本体：src/isp/Edge_Overlay.v
	////////////////////////////////////////////////////////////////
	//	彩色比边缘早 4 行（Canny 三级 3x3 流水 + 斑点窗口 1 行），
	//	叠加模块延迟彩色 4 行后再与边缘对齐。
	wire			overlay_vs, overlay_hs, overlay_de;
	wire	[23:0]	overlay_data;
	wire	[23:0]	overlay_color_data, overlay_gray_data;
	wire			overlay_edge_bit;
	
	//	边缘颜色跟随识别类别：矩形蓝、圆形绿、三角形黄；
	//	尚未落入识别框的普通边缘保持红色。
	wire	[23:0]	edge_draw_color = !shape_mode ? 24'hFF0000 :
								 (shape_sel_id == 2'd1) ? 24'h0000FF :
								 (shape_sel_id == 2'd2) ? 24'h00FF00 :
								 (shape_sel_id == 2'd3) ? 24'hFFFF00 : 24'hFF0000;
	
	Edge_Overlay #(
        .ENABLE_FILTER_VIEW(1),
        .ENABLE_TEMPORAL_GUARD(1),
		.IMG_HDISP		(1280),
		.IMG_VDISP		(720),
		.DELAY_LINES	(4),				//	彩色延迟：Canny 3 行 + 斑点 1 行
		.EDGE_DLY_CLKS    (14)				//	纯寄存器拍数，由 tb_overlay 标定
	) u_Edge_Overlay (
		.clk				(clk_pixel),
		.rst_n				(rstn_pixel),
		
		//	原始彩色（bayer2rgb + 手动 AWB 之后，和 w_rgb_href 同拍）
		.per_frame_vsync	(w_rgb_vsync),
		.per_frame_href		(isp_pipe_de),
		.per_frame_hsync	(w_rgb_hsync),
        .per_img_color        ({w_rgb_r, w_rgb_g, w_rgb_b}),
        .filter_view_i(filter_gray_mode), .filtered_gray_i(filtered_gray),
        .filtered_vs_i(filtered_vs), .filtered_de_i(filtered_de),
		
		//	边缘结果：用**斑点滤除后**的边缘（比原始 Canny 干净，屏幕上噪点少）
		.edge_vsync			(shape_vs_f),
		.edge_href			(shape_de_f),
		.edge_hsync			(shape_hs_pipe[2]),
		.edge_bit(display_mode == 3'd4 ? shape_edge_center : shape_edge_f),
        .edge_strong_i(shape_strong_center),
        .noise_guard_i(binary_display_mode && (edge_threshold<12'd160)),
        .guard_epoch_i(view_epoch[0]),
        .guard_frame_de_i(isp_de_phase[15]),.guard_frame_vs_i(isp_vs_phase[15]),
		.edge_sel			(shape_sel),
		.edge_color_i		(edge_draw_color),
		.edge_enable_i		(display_mode == 2'd3),
		.dbg_i				(1'b0),
		
		//	叠加输出 → 图形标注
		.post_frame_vsync	(overlay_vs),
		.post_frame_href	(overlay_de),
		.post_frame_hsync	(overlay_hs),
		.post_img_data		(overlay_data),
		.post_color_data		(overlay_color_data),
		.post_gray_data		(overlay_gray_data),
		.edge_bit_o			(overlay_edge_bit),
		.edge_sel_o			()
	);
	
	////////////////////////////////////////////////////////////////
	// 灰度/边缘分屏：显示摄像头中心 640 列，左右两侧使用同一源画面。
	////////////////////////////////////////////////////////////////
	wire split_vs, split_hs, split_de;
	wire [23:0] split_data;
	Center_Split #(.IMG_HDISP(1280)) u_Center_Split (
		.clk(clk_pixel), .rst_n(rstn_pixel),
		.vs_i(overlay_vs), .hs_i(overlay_hs), .de_i(overlay_de),
		.gray_i(overlay_gray_data[7:0]), .edge_i(overlay_edge_bit),
		.vs_o(split_vs), .hs_o(split_hs), .de_o(split_de), .data_o(split_data)
	);

	////////////////////////////////////////////////////////////////
	//	图形标注：识别模式下画"框 + 名字"
	//	模块本体：src/isp/Shape_Annotate.v
	//	  普通模式   -> 数据原样透传
	//	  识别模式   -> 围着图形画 2 像素粗的框，旁边用点阵字写
	//	               RECT / CIRCLE / TRIANGLE，左上角有个小方块表示当前模式
	////////////////////////////////////////////////////////////////

    // Share one four-row coordinate offset in the annotation counter,
    // rather than sixteen per-box subtractors.
	wire			annot_vs, annot_hs, annot_de;
	wire	[23:0]	annot_data;
	wire [4:0] bridge_box_count;
	wire [63:0] bridge_box_labels;
	wire [255:0] bridge_box_x0, bridge_box_y0, bridge_box_x1, bridge_box_y1;
	wire digit_vs, digit_hs, digit_de;
	wire [23:0] digit_data;
	
	Shape_Annotate #(
		.IMG_HDISP	(1280),
		.IMG_VDISP	(720),
		.NSHAPE		(8),
		.Y_OFFSET	(4)
	) u_Shape_Annotate (
		.clk			(clk_pixel),
		.rst_n			(rstn_pixel),
		
		.vs_i			(isp_vs_phase[15]),
		.hs_i			(overlay_hs),
		.de_i			(isp_de_phase[15]),
		.data_i			(overlay_data),
		
		.vld_i			(shape_vld),
		.shape_i		(shape_id),
		.bx0_i			(shape_bx0),
		.by0_i			(shape_by0),
		.bx1_i			(shape_bx1),
		.by1_i			(shape_by1),
		.mode_i			(shape_mode && (display_mode == 2'd3)),
		
		.mark_color_i	(24'h00FF00),
		
		.vs_o			(annot_vs),
		.hs_o			(annot_hs),
		.de_o			(annot_de),
		.data_o			(annot_data)
	);

	Digit_Box_Overlay #(
		.IMG_HDISP(1280), .IMG_VDISP(720), .MAX_BOXES(16), .BOX_THICK(3)
	) u_digit_box_overlay (
		.clk(clk_pixel), .rst_n(rstn_pixel),
		.vs_i(isp_vs_phase[15]), .hs_i(overlay_hs), .de_i(isp_de_phase[15]),
		.data_i(binary_display_mode ? {24{overlay_edge_bit}} : overlay_color_data),
		.mode_i(binary_display_mode && digit_mode_req),
		.box_count_i(bridge_box_count), .box_labels_i(bridge_box_labels),
		.box_x0_i(bridge_box_x0), .box_y0_i(bridge_box_y0),
		.box_x1_i(bridge_box_x1), .box_y1_i(bridge_box_y1),
		.vs_o(digit_vs), .hs_o(digit_hs), .de_o(digit_de), .data_o(digit_data)
	);
	
	// Switch only after every path has drained, with common inactive DE
	// and matching HIGH sync levels. VS pulses are now several rows apart,
	// so waiting for overlapping LOW VS pulses would lock mode switching.
    // The selected DDR slot is stable throughout a displayed frame. Sample
    // its four-bit address token through two stages; invalidate digit work
    // after a replay page has actually switched, not just when pressed.
    reg [3:0] replay_slot_meta, replay_slot_sync, replay_slot_seen;
    always @(posedge clk_pixel or negedge rstn_pixel) begin
        if(!rstn_pixel) begin replay_slot_meta<=0;replay_slot_sync<=0;end
        else begin
            replay_slot_meta<=w_rgb_frame_base[25:22];
            replay_slot_sync<=replay_slot_meta;
        end
    end
	wire display_switch_safe = !isp_frame_busy && !w_rgb_href &&
	    !digit_de && !annot_de && !split_de_phase[16] &&
	    lcd_vs && digit_vs && annot_vs && split_vs_phase[16] &&
	    lcd_hs && digit_hs && annot_hs && split_hs &&
	    !render_de && render_vs && render_hs;
	always @(posedge clk_pixel or negedge rstn_pixel) begin
		if(!rstn_pixel) begin
			display_mode <= 2'd0;
			shape_mode <= 1'b0;
			edge_threshold <= 12'd200;
			view_epoch <= 32'd0;
			replay_mode_seen <= 1'b0;
            replay_slot_seen <= 0;
		end else if(display_switch_safe) begin
			if ((display_mode != display_mode_req) ||
			    (replay_mode_seen != replay_mode) ||
                (edge_threshold != edge_threshold_req) ||
                (replay_mode && replay_slot_seen != replay_slot_sync))
				view_epoch <= view_epoch + 1'b1;
			replay_mode_seen <= replay_mode;
            replay_slot_seen <= replay_slot_sync;
			display_mode <= display_mode_req;
			shape_mode <= shape_mode_req && (display_mode_req == 2'd3);
			edge_threshold <= edge_threshold_req;
		end
	end

	// All HDMI modes share one fixed timing: five lines plus 19 clocks.
	// Colour remains RGB888; only its timing is aligned to the split view.
	// Share one line RAM between raw/digit and edge/shape rendering. Both
	// annotations already use the four-line phase, so their coordinates and
	// drawing priority stay unchanged. Padding drains the final complete row.
	reg [1:0] color_pipe_de,color_pipe_vs;
	reg split_vs_d,split_hs_d,split_de_d;
	reg render_vs,render_hs,render_de;
	reg [23:0] split_data_d,split_data_aligned,digit_data_aligned;
	wire [23:0] full_color_aligned;
	always @(posedge clk_pixel or negedge rstn_pixel) begin
	    if(!rstn_pixel) begin
	        color_pipe_de<=0;color_pipe_vs<=0;
	        split_vs_d<=0;split_hs_d<=0;split_de_d<=0;
	        render_vs<=0;render_hs<=0;render_de<=0;
	    end else begin
	        color_pipe_de<={color_pipe_de[0],overlay_de};
	        color_pipe_vs<={color_pipe_vs[0],overlay_vs};
	        split_vs_d<=split_vs_phase[16];split_hs_d<=split_hs;split_de_d<=split_de_phase[16];
	        render_vs<=split_vs_d;render_hs<=split_hs_d;render_de<=split_de_d;
	    end
	end
	always @(posedge clk_pixel) begin
	    // Shape_Annotate has two stages; Digit_Box_Overlay has one.
	    digit_data_aligned<=digit_data;
	    split_data_d<=split_data;split_data_aligned<=split_data_d;
	end
	Display_Line_Delay #(.WIDTH(1280)) u_display_color_line (
	    .clk(clk_pixel),.rst_n(rstn_pixel),
	    .vs_i(color_pipe_vs[1]),.de_i(color_pipe_de[1]),
	    .data_i(display_mode==2'd3 ? annot_data : digit_data_aligned),
	    .data_o(full_color_aligned));
	wire [23:0] render_data = display_mode==2'd2 ? split_data_aligned : full_color_aligned;
	wire labeled_vs,labeled_hs,labeled_de;
	wire [23:0] labeled_data;
	Mode_Label_Overlay #(.IMG_HDISP(1280)) u_mode_label (
	    .clk(clk_pixel),.rst_n(rstn_pixel),
	    .vs_i(render_vs),.hs_i(render_hs),.de_i(render_de),.data_i(render_data),
	    .threshold_i(edge_threshold),.display_mode_i(display_mode),.digit_mode_i(digit_mode_req),
	    .shape_mode_i(shape_mode),.freeze_i(freeze_mode),.replay_i(replay_mode),
	    .vs_o(labeled_vs),.hs_o(labeled_hs),.de_o(labeled_de),.data_o(labeled_data));

    rgb2dvi #(.ENABLE_OSERDES(0)) u_rgb2dvi
    (
    .oe_i                              (1                         ),//	Always enable output
    .bitflip_i                         (4'b0000                   ),//	Reverse clock & data lanes. 
		
    .aRst                              (1'b0                      ),
    .aRst_n                            (1'b1                      ),
		
    .PixelClk                          (clk_pixel                 ),//pixel clk = 74.25M
    .SerialClk                         (                          ),//pixel clk *5 = 371.25M
		
    .vid_pVSync                        (labeled_vs),
    .vid_pHSync                        (labeled_hs),
    .vid_pVDE                          (labeled_de),
    .vid_pData                         (labeled_data),
		
    .txc_o                             (hdmi_txc_o                ),
    .txd0_o                            (hdmi_txd0_o               ),
    .txd1_o                            (hdmi_txd1_o               ),
    .txd2_o                            (hdmi_txd2_o               ) 
    );

	// ------------------------------------------------------------------
	// RV32 SapphireSoC and the video APB bridge.  APB0 is left available
	// for the generated BSP's board peripherals; APB1 is the gray contract.
	// Bootloader polls this read-only status before writing external DDR.
	assign soc_apb0_prdata = {30'd0, w_ddr3_cal_pass, r_ddr_unlock};
	assign soc_apb0_pready = 1'b1;
	assign soc_apb0_pslverror = 1'b0;

	SapphireSoc32 u_sapphiresoc32 (
		.io_systemClk                         (clk_sys),
		.io_ddrA_w_payload_strb               (soc_ddr_wstrb),
		.io_ddrA_w_payload_data               (soc_ddr_wdata),
		.jtagCtrl_enable                      (jtag_inst1_SEL),
		.jtagCtrl_tdi                         (jtag_inst1_TDI),
		.jtagCtrl_capture                     (jtag_inst1_CAPTURE),
		.jtagCtrl_shift                       (jtag_inst1_SHIFT),
		.jtagCtrl_update                      (jtag_inst1_UPDATE),
		.jtagCtrl_reset                       (jtag_inst1_RESET),
		.jtagCtrl_tdo                         (jtag_inst1_TDO),
		.jtagCtrl_tck                         (jtag_inst1_TCK),
		.io_ddrA_w_payload_id                 (soc_ddr_wid),
		.io_ddrA_r_payload_last               (soc_ddr_rlast),
		.io_ddrA_r_payload_resp               (soc_ddr_rresp),
		.io_ddrA_r_payload_id                 (soc_ddr_rid),
		.io_ddrA_r_payload_data               (soc_ddr_rdata),
		.io_ddrA_r_ready                      (soc_ddr_rready),
		.io_ddrA_r_valid                      (soc_ddr_rvalid),
		.io_ddrA_b_payload_resp               (soc_ddr_bresp),
		.io_ddrA_b_payload_id                 (soc_ddr_bid),
		.io_ddrA_b_ready                      (soc_ddr_bready),
		.io_ddrA_b_valid                      (soc_ddr_bvalid),
		.io_ddrA_w_payload_last               (soc_ddr_wlast),
		.io_ddrA_w_ready                      (soc_ddr_wready),
		.io_ddrA_w_valid                      (soc_ddr_wvalid),
		.io_ddrA_arw_payload_write            (soc_ddr_arw_write),
		.io_ddrA_arw_payload_prot             (soc_ddr_arw_prot),
		.io_ddrA_arw_payload_qos              (soc_ddr_arw_qos),
		.io_ddrA_arw_payload_cache            (soc_ddr_arw_cache),
		.io_ddrA_arw_payload_lock             (soc_ddr_arw_lock),
		.io_ddrA_arw_payload_burst            (soc_ddr_arw_burst),
		.io_ddrA_arw_payload_size             (soc_ddr_arw_size),
		.io_ddrA_arw_payload_len              (soc_ddr_arw_len),
		.io_ddrA_arw_payload_region           (soc_ddr_arw_region),
		.io_ddrA_arw_payload_id               (soc_ddr_arw_id),
		.io_ddrA_arw_payload_addr             (soc_ddr_arw_addr),
		.io_ddrA_arw_ready                    (soc_ddr_arw_ready),
		.io_ddrA_arw_valid                    (soc_ddr_arw_valid),
		.system_spi_0_io_data_0_read          (flash_data_in[0]),
		.system_spi_0_io_data_0_write         (soc_spi_data_write[0]),
		.system_spi_0_io_data_0_writeEnable   (soc_spi_data_oe[0]),
		.system_spi_0_io_data_1_read          (flash_data_in[1]),
		.system_spi_0_io_data_1_write         (soc_spi_data_write[1]),
		.system_spi_0_io_data_1_writeEnable   (soc_spi_data_oe[1]),
		.system_spi_0_io_data_2_read          (flash_data_in[2]),
		.system_spi_0_io_data_2_write         (soc_spi_data_write[2]),
		.system_spi_0_io_data_2_writeEnable   (soc_spi_data_oe[2]),
		.system_spi_0_io_data_3_read          (flash_data_in[3]),
		.system_spi_0_io_data_3_write         (soc_spi_data_write[3]),
		.system_spi_0_io_data_3_writeEnable   (soc_spi_data_oe[3]),
		.system_spi_0_io_sclk_write           (soc_spi_sclk),
		.userInterruptB                       (1'b0),
		.userInterruptA                       (tinyml_cmd_int),
		.io_apbSlave_1_PADDR                 (soc_apb1_addr),
		.io_apbSlave_1_PENABLE               (soc_apb1_penable),
		.io_apbSlave_1_PRDATA                (soc_apb1_prdata),
		.io_apbSlave_1_PREADY                (soc_apb1_pready),
		.io_apbSlave_1_PSEL                  (soc_apb1_psel),
		.io_apbSlave_1_PSLVERROR             (soc_apb1_pslverror),
		.io_apbSlave_1_PWDATA                (soc_apb1_pwdata),
		.io_apbSlave_1_PWRITE                (soc_apb1_pwrite),
		.io_apbSlave_0_PADDR                 (soc_apb0_addr),
		.io_apbSlave_0_PENABLE               (soc_apb0_penable),
		.io_apbSlave_0_PRDATA                (soc_apb0_prdata),
		.io_apbSlave_0_PREADY                (soc_apb0_pready),
		.io_apbSlave_0_PSEL                  (soc_apb0_psel),
		.io_apbSlave_0_PSLVERROR             (soc_apb0_pslverror),
		.io_apbSlave_0_PWDATA                (soc_apb0_pwdata),
		.io_apbSlave_0_PWRITE                (soc_apb0_pwrite),
		.io_asyncReset                        (~rstn_sys),
		.io_memoryClk                         (clk_sys),
		.io_systemReset                       (soc_system_reset),
		.system_uart_0_io_txd                (soc_uart_tx),
		.io_memoryReset                       (soc_memory_reset),
		.system_uart_0_io_rxd                (uart_rx_i),
		.system_i2c_0_io_scl_read            (1'b1),
		.system_i2c_0_io_scl_write           (),
		.system_i2c_0_io_sda_read            (1'b1),
		.system_i2c_0_io_sda_write           (),
		.system_gpio_0_io_writeEnable       (soc_gpio_we),
		.system_gpio_0_io_write              (soc_gpio_write),
		.system_gpio_0_io_read               (4'd0),
		.cpu0_customInstruction_cmd_valid    (soc_custom_cmd_valid),
		.cpu0_customInstruction_cmd_ready    (soc_custom_cmd_ready),
		.cpu0_customInstruction_function_id  (soc_custom_function_id),
		.cpu0_customInstruction_inputs_0     (soc_custom_in0),
		.cpu0_customInstruction_inputs_1     (soc_custom_in1),
		.cpu0_customInstruction_rsp_valid    (soc_custom_rsp_valid),
		.cpu0_customInstruction_rsp_ready    (soc_custom_rsp_ready),
		.cpu0_customInstruction_outputs_0    (soc_custom_out0),
		.system_spi_0_io_ss                  (soc_spi_ss)
	);
	// Official TinyML integration: the accelerator consumes the RV32 custom
	// instruction stream and raises its completion interrupt on userInterruptA.
	tinyml_top u_tinyml_top (
		.clk              (clk_sys),
		.reset            (soc_system_reset),
		.cmd_valid        (soc_custom_cmd_valid),
		.cmd_function_id  (soc_custom_function_id),
		.cmd_inputs_0     (soc_custom_in0),
		.cmd_inputs_1     (soc_custom_in1),
		.cmd_ready        (soc_custom_cmd_ready),
		.cmd_int          (tinyml_cmd_int),
		.rsp_valid        (soc_custom_rsp_valid),
		.rsp_outputs_0    (soc_custom_out0),
		.rsp_ready        (soc_custom_rsp_ready),
		.m_axi_clk        (clk_sys),
		.m_axi_rstn       (~soc_system_reset),
		.m_axi_awvalid    (tinyml_awvalid),
		.m_axi_awaddr     (tinyml_awaddr),
		.m_axi_awlen      (tinyml_awlen),
		.m_axi_awsize     (tinyml_awsize),
		.m_axi_awburst    (tinyml_awburst),
		.m_axi_awprot     (tinyml_awprot),
		.m_axi_awlock     (tinyml_awlock),
		.m_axi_awcache    (tinyml_awcache),
		.m_axi_awready    (tinyml_awready),
		.m_axi_wdata      (tinyml_wdata),
		.m_axi_wstrb      (tinyml_wstrb),
		.m_axi_wlast      (tinyml_wlast),
		.m_axi_wvalid     (tinyml_wvalid),
		.m_axi_wready     (tinyml_wready),
		.m_axi_bresp      (tinyml_bresp),
		.m_axi_bvalid     (tinyml_bvalid),
		.m_axi_bready     (tinyml_bready),
		.m_axi_arvalid    (tinyml_arvalid),
		.m_axi_araddr     (tinyml_araddr),
		.m_axi_arlen      (tinyml_arlen),
		.m_axi_arsize     (tinyml_arsize),
		.m_axi_arburst    (tinyml_arburst),
		.m_axi_arprot     (tinyml_arprot),
		.m_axi_arlock     (tinyml_arlock),
		.m_axi_arcache    (tinyml_arcache),
		.m_axi_arready    (tinyml_arready),
		.m_axi_rvalid     (tinyml_rvalid),
		.m_axi_rdata     (tinyml_rdata),
		.m_axi_rlast      (tinyml_rlast),
		.m_axi_rresp      (tinyml_rresp),
		.m_axi_rready     (tinyml_rready)
	);

	AXI4_FullToHalfDuplex_TinyML #(.DATA_WIDTH(128), .ADDR_WIDTH(32), .ID_WIDTH(8))
		u_tinyml_axi_adapter (
		.clk              (w_ddr3_ui_clk),
		.rst              (w_ddr3_ui_rst),
		.h_arw_valid      (tinyml_ddr_arw_valid),
		.h_arw_ready      (tinyml_ddr_arw_ready),
		.h_arw_addr       (tinyml_ddr_arw_addr),
		.h_arw_id         (tinyml_ddr_arw_id),
		.h_arw_len        (tinyml_ddr_arw_len),
		.h_arw_size       (tinyml_ddr_arw_size),
		.h_arw_burst      (tinyml_ddr_arw_burst),
		.h_arw_lock       (tinyml_ddr_arw_lock),
		.h_arw_write      (tinyml_ddr_arw_write),
		.h_w_id           (tinyml_ddr_wid),
		.h_w_valid        (tinyml_ddr_wvalid),
		.h_w_ready        (tinyml_ddr_wready),
		.h_w_data         (tinyml_ddr_wdata),
		.h_w_strb         (tinyml_ddr_wstrb),
		.h_w_last         (tinyml_ddr_wlast),
		.h_b_valid        (tinyml_ddr_bvalid),
		.h_b_ready        (tinyml_ddr_bready),
		.h_b_resp         (tinyml_ddr_bresp),
		.h_r_valid        (tinyml_ddr_rvalid),
		.h_r_ready        (tinyml_ddr_rready),
		.h_r_data         (tinyml_ddr_rdata),
		.h_r_resp         (tinyml_ddr_rresp),
		.h_r_last         (tinyml_ddr_rlast),
		.s_aw_addr        (tinyml_awaddr),
		.s_aw_len         (tinyml_awlen),
		.s_aw_size        (tinyml_awsize),
		.s_aw_burst       (tinyml_awburst),
		.s_aw_lock        (tinyml_awlock),
		.s_aw_cache       (tinyml_awcache),
		.s_aw_prot        (tinyml_awprot),
		.s_aw_valid       (tinyml_awvalid),
		.s_aw_ready       (tinyml_awready),
		.s_w_data         (tinyml_wdata),
		.s_w_strb         (tinyml_wstrb),
		.s_w_last         (tinyml_wlast),
		.s_w_valid        (tinyml_wvalid),
		.s_w_ready        (tinyml_wready),
		.s_b_resp         (tinyml_bresp),
		.s_b_valid        (tinyml_bvalid),
		.s_b_ready        (tinyml_bready),
		.s_ar_addr        (tinyml_araddr),
		.s_ar_len         (tinyml_arlen),
		.s_ar_size        (tinyml_arsize),
		.s_ar_burst       (tinyml_arburst),
		.s_ar_lock        (tinyml_arlock),
		.s_ar_cache       (tinyml_arcache),
		.s_ar_prot        (tinyml_arprot),
		.s_ar_valid       (tinyml_arvalid),
		.s_ar_ready       (tinyml_arready),
		.s_r_data         (tinyml_rdata),
		.s_r_resp         (tinyml_rresp),
		.s_r_last         (tinyml_rlast),
		.s_r_valid        (tinyml_rvalid),
		.s_r_ready        (tinyml_rready)
	);

	Gray_Video_Bridge #(
		.CAPABILITIES(32'h00000076),
		.MAX_BOXES(16)
	) u_gray_video_bridge (
		.sys_clk          (clk_sys),
		.sys_rst_n        (rstn_sys),
		.paddr            (soc_apb1_addr),
		.psel             (soc_apb1_psel),
		.penable          (soc_apb1_penable),
		.pready           (soc_apb1_pready),
		.pwrite           (soc_apb1_pwrite),
		.pwdata           (soc_apb1_pwdata),
		.prdata           (soc_apb1_prdata),
		.pslverror        (soc_apb1_pslverror),
		.pixel_clk        (clk_pixel),
		.pixel_rst_n      (rstn_pixel),
		.display_mode_i   (cpu_display_mode),
		.replay_mode_i    (replay_mode),
        .digit_mode_i    (digit_mode_req),
		.k1_long_sequence_i(k1_long_sequence),
		.view_epoch_i     (view_epoch),
		.frame_base_i     (w_rgb_frame_base),
		.frame_id_i       (w_rgb_frame_id),
		.ddr_diagnostics_i(ddr_diagnostics),
        .binary_vs_i(isp_vs_phase[15]), .binary_de_i(isp_de_phase[15]), .binary_edge_i(overlay_edge_bit),
        .box_labels_o(bridge_box_labels),
		.box_count_o      (bridge_box_count),
		.box_x0_o         (bridge_box_x0),
		.box_y0_o         (bridge_box_y0),
		.box_x1_o         (bridge_box_x1),
		.box_y1_o         (bridge_box_y1)
	);
		
	






	
	
endmodule


