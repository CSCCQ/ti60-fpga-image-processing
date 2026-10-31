`timescale 1ns/1ns
//======================================================================
//  Edge_Overlay.v  ——  边缘彩色叠加
//
//  整屏显示原始彩色图像，把边缘检测到的像素画成醒目颜色（默认纯红）。
//
//  ★ 难点是"对齐"：
//      彩色数据走在前面（bayer2rgb/AWB 的输出，此时还没灰度化），
//      边缘数据走在后面，二者的行差由 DELAY_LINES 指定。
//      所以这里要先把彩色延迟同样多行，才能和边缘在同一拍、指向同一个源像素。
//
//    彩色使用循环行缓存，保留每行全部像素；额外一行使读写地址分离。
//    输出有效区由顶层 Video_Frame_Phase 对齐，包含原图首尾全部行。
//
//    行缓存之外还差的纯寄存器拍数由 EDGE_DLY_CLKS 给出（这个数由仿真标定）。
//
//  接口约定：
//      per_frame_*  : 原始彩色的时序（bayer2rgb / AWB 之后、灰度化之前）
//      edge_*       : 边缘结果的时序（比 per_frame_* 晚 DELAY_LINES 行 + EDGE_DLY_CLKS 拍）
//      post_frame_* : 叠加输出，时序 = edge_*（叠加发生在边缘那一拍）
//======================================================================
module Edge_Overlay #(
    parameter           IMG_HDISP     = 1280,
    parameter           IMG_VDISP     = 720,
    parameter           DELAY_LINES   = 4,              //  彩色要延迟几行
    parameter integer   ENABLE_FILTER_VIEW = 0,
    parameter integer   ENABLE_TEMPORAL_GUARD = 0,
    parameter           EDGE_DLY_CLKS = 6               //  行缓存之外还要补的拍数
)(
    input               clk,
    input               rst_n,

    //  原始彩色（时序 per_frame_*）
    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input       [23:0]  per_img_color,

    // Filtered grayscale is one row and five clocks later than RGB.
    // Share the existing RGB ring RAM, shortening its delay in these views.
    input               filter_view_i,
    input       [7:0]   filtered_gray_i,
    input               filtered_vs_i,
    input               filtered_de_i,

    //  边缘结果（时序 edge_*）
    input               edge_vsync,
    input               edge_href,
    input               edge_hsync,
    input               edge_bit,               //  1 = 这里是边缘
    input               edge_strong_i,noise_guard_i,guard_epoch_i,
    input               guard_frame_de_i,guard_frame_vs_i,
    input               edge_sel,               //  1 = 这个边缘属于识别选中的那个图形
    input       [23:0]  edge_color_i,           //  边缘画成什么颜色（由图形识别模块给）
    input               edge_enable_i,         //  1 = 叠加边缘，0 = 只显示彩色原图

    //  诊断模式：背景刷黑、只显示边缘，选中的图形边缘画成亮绿
    input               dbg_i,

    //  叠加输出（时序 = edge_*）
    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output      [23:0]  post_img_data,
    output      [23:0]  post_color_data,
    output      [23:0]  post_gray_data,

    //  和 post_img_data 同拍的边缘/选中标志（给诊断视图用）
    output              edge_bit_o,
    output              edge_sel_o
);

    //------------------------------------------------------------------
    //  1) 彩色延迟 DELAY_LINES 行
    //     循环缓存保持完整的行内像素位置
    //------------------------------------------------------------------
    // Keep exact source columns, including the final two pixels. Chained
    // legacy matrix FIFOs advance their read pointers in blanking and used
    // to replace those pixels with the following row. An extra bank keeps
    // simultaneous read/write addresses distinct (no RAM collision mode).
    wire filter_view = ENABLE_FILTER_VIEW ? filter_view_i : 1'b0;
    wire source_vs = filter_view ? filtered_vs_i : per_frame_vsync;
    wire source_de = filter_view ? filtered_de_i : per_frame_href;
    wire [23:0] source_data = filter_view ? {3{filtered_gray_i}} : per_img_color;
    localparam FILTER_TAP=(EDGE_DLY_CLKS>=5) ? EDGE_DLY_CLKS-5 : 0;
    localparam COLOR_DEPTH=(DELAY_LINES+1)*IMG_HDISP;
    localparam ADDR_BITS=$clog2(COLOR_DEPTH);
    reg [23:0] color_ram [0:COLOR_DEPTH-1];
    reg [ADDR_BITS-1:0] write_addr,read_addr;
    reg [23:0] line_color;
    wire history_enable=ENABLE_TEMPORAL_GUARD ? noise_guard_i : 1'b0;
    wire [ADDR_BITS-1:0] history_read_addr,history_write_addr;
    wire [23:0] history_write_data;
    wire history_write,qualified_edge;
    generate if(ENABLE_TEMPORAL_GUARD) begin:g_history
        Edge_Temporal_Guard #(.WIDTH(IMG_HDISP),.HEIGHT(IMG_VDISP),
            .RAM_DEPTH(COLOR_DEPTH),.ADDR_BITS(ADDR_BITS)) u_guard(
            .clk(clk),.rst_n(rst_n),.enable_i(history_enable),.epoch_i(guard_epoch_i),
            .vs_i(guard_frame_vs_i),.de_i(guard_frame_de_i),
            .edge_i(edge_bit),.strong_i(edge_strong_i),.ram_data_i(line_color),
            .ram_read_addr_o(history_read_addr),.ram_write_addr_o(history_write_addr),
            .ram_write_data_o(history_write_data),.ram_write_o(history_write),
            .edge_o(qualified_edge),.history_valid_o());
    end else begin:g_no_history
        assign history_read_addr=0;assign history_write_addr=0;
        assign history_write_data=0;assign history_write=0;
        assign qualified_edge=edge_bit;
    end endgenerate
    reg vs_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin write_addr<=0;read_addr<=IMG_HDISP;vs_d<=0;end
        else begin
            vs_d<=source_vs;
            if(vs_d && !source_vs) begin
                write_addr<=0;
                // Five banks remain allocated. Reading two banks ahead
                // gives three rows rather than the RGB path's four rows.
                read_addr<=filter_view ? 2*IMG_HDISP : IMG_HDISP;
            end
            else if(source_de) begin
                write_addr<=write_addr==COLOR_DEPTH-1 ? 0 : write_addr+1'b1;
                read_addr<=read_addr==COLOR_DEPTH-1 ? 0 : read_addr+1'b1;
            end
        end
    end
    // Binary views use this same RAM for history; other views keep RGB.
    // RGB refills during the existing four-row mode-switch warm-up.
    // Keep exactly one synchronous read and one write in the RAM template.
    // Select addresses outside the memory processes so synthesis retains BRAM.
    wire shared_write_en=history_enable ? history_write : source_de;
    wire shared_read_en=history_enable || source_de;
    wire [ADDR_BITS-1:0] shared_write_addr=history_enable ? history_write_addr : write_addr;
    wire [ADDR_BITS-1:0] shared_read_addr=history_enable ? history_read_addr : read_addr;
    wire [23:0] shared_write_data=history_enable ? history_write_data : source_data;
    always @(posedge clk) if(shared_write_en)
        color_ram[shared_write_addr]<=shared_write_data;
    always @(posedge clk) if(shared_read_en)
        line_color<=color_ram[shared_read_addr];

    //------------------------------------------------------------------
    //  2) 再补 EDGE_DLY_CLKS 拍纯寄存器延迟，和边缘通路对齐
    //------------------------------------------------------------------
    // One RAM-read clock plus this register chain preserves the existing
    // EDGE_DLY_CLKS+2 timing contract (16 clocks in the production pipeline).
    reg [23:0] color_d [0:EDGE_DLY_CLKS];
    integer i;
    // Payload only: no reset is needed because the line RAM itself is
    // uninitialized until filled. The top-level valid window starts after
    // DELAY_LINES complete rows, well beyond this short pipeline warm-up.
    // Omitting data reset allows inference of compact SRL8 shift registers.
    always @(posedge clk)
    begin
        color_d[0] <= line_color;
        for(i = 1; i <= EDGE_DLY_CLKS; i = i + 1) begin
            color_d[i] <= color_d[i-1];
        end
    end

    // Both taps represent the same original pixel at the same clock.
    wire [23:0] color_aligned = filter_view ? color_d[FILTER_TAP] : color_d[EDGE_DLY_CLKS];
    // Convert after colour alignment, sharing its line buffers. Match the
    // rounded luma conversion in FrameBoundCrop feeding the Canny pipeline.
    wire [15:0] gray_sum = color_aligned[23:16] * 16'd77 +
                           color_aligned[15:8] * 16'd150 +
                           color_aligned[7:0] * 16'd29 + 16'd128;
    wire [23:0] gray_aligned = {3{gray_sum[15:8]}};

    //------------------------------------------------------------------
    //  3) 叠加：是边缘就画成醒目颜色，否则输出原始彩色
    //     诊断模式(dbg_i=1)：背景刷黑，普通边缘暗红，选中图形的边缘亮绿，
    //     这样一眼就能看出"识别到底选中了哪一片"，不用猜。
    //------------------------------------------------------------------
    assign post_frame_vsync = edge_vsync;
    assign post_frame_href  = edge_href;
    assign post_frame_hsync = edge_hsync;

    assign edge_bit_o       = qualified_edge;
    assign edge_sel_o       = edge_sel;
    assign post_color_data  = color_aligned;
    assign post_gray_data   = gray_aligned;

    wire [23:0] dbg_pix = edge_sel  ? 24'h00FF00 :
                          qualified_edge ? 24'h802000 : 24'h000000;

    wire edge_draw = edge_enable_i && qualified_edge;
    assign post_img_data    = dbg_i ? dbg_pix :
                              (edge_draw ? edge_color_i : color_aligned);

endmodule
