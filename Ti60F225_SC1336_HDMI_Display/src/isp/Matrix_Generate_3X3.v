`timescale 1ns/1ns
//======================================================================
//  Matrix_Generate_3X3.v  ——  位宽可参数化的 3x3 窗口生成
//
//  和 VIP_Matrix_Generate_3X3_8Bit 是同一套逻辑（同样的行缓存、同样的
//  pixel_cnt 边界处理、同样的 href 同步），只是把数据位宽做成了参数，
//  这样 Canny 里"幅值+方向"这种超过 8bit 的数据也能用同一套窗口。
//
//    p11 p12 p13      上 左 / 上 中 / 上 右
//    p21 p22 p23      中 左 / 中 中 / 中 右
//    p31 p32 p33      下 左 / 下 中 / 下 右
//
//  ★ 时序约定（和 VIP 那个完全一致，已由仿真确认）：
//      matrix_p* 与 matrix_frame_href 是同一级流水的一对信号 ——
//      在 matrix_frame_href 的第 C 列，matrix_p22 恰好是输入的第 C 列、
//      且比输入行号早 1 行（也就是窗口中心在"1 行前"）。
//======================================================================
module Matrix_Generate_3X3 #(
    parameter               DATA_WIDTH  = 8,
    parameter               IMG_HDISP   = 1280,
    parameter               IMG_VDISP   = 720
)(
    input                   clk,
    input                   rst_n,

    input                   per_frame_vsync,
    input                   per_frame_href,
    input                   per_frame_hsync,
    input   [DATA_WIDTH-1:0] per_img_Y,

    output                  matrix_frame_vsync,
    output                  matrix_frame_href,
    output                  matrix_frame_hsync,

    output reg [DATA_WIDTH-1:0] matrix_p11, matrix_p12, matrix_p13,
    output reg [DATA_WIDTH-1:0] matrix_p21, matrix_p22, matrix_p23,
    output reg [DATA_WIDTH-1:0] matrix_p31, matrix_p32, matrix_p33
);

    //------------------------------------------------------------------
    //  三行数据：row3 = 当前行，row2 = 1 行前，row1 = 2 行前
    //------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] row1_data;
    wire [DATA_WIDTH-1:0] row2_data;
    reg  [DATA_WIDTH-1:0] row3_data;

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
            row3_data <= 0;
        else if(per_frame_href)
            row3_data <= per_img_Y;
        else
            row3_data <= row3_data;
    end

    Line_Shift_RAM_8Bit #(
        .DATA_WIDTH (DATA_WIDTH), .ADDR_WIDTH (11),
        .DATA_DEPTH (IMG_HDISP ), .DELAY_NUM  (0)
    ) u0_Line_Shift_RAM (
        .clk(clk), .rst_n(rst_n), .clken(per_frame_href),
        .din(per_img_Y), .dout(row2_data)
    );

    Line_Shift_RAM_8Bit #(
        .DATA_WIDTH (DATA_WIDTH), .ADDR_WIDTH (11),
        .DATA_DEPTH (IMG_HDISP ), .DELAY_NUM  (1)
    ) u1_Line_Shift_RAM (
        .clk(clk), .rst_n(rst_n), .clken(per_frame_href),
        .din(row2_data), .dout(row1_data)
    );

    //------------------------------------------------------------------
    //  href / vsync / hsync 延迟 3 拍，和窗口数据对齐
    //------------------------------------------------------------------
    reg [2:0] per_frame_vsync_r;
    reg [2:0] per_frame_href_r;
    reg [2:0] per_frame_hsync_r;

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            per_frame_vsync_r <= 0;
            per_frame_href_r  <= 0;
            per_frame_hsync_r <= 0;
        end
        else
        begin
            per_frame_vsync_r <= {per_frame_vsync_r[1:0], per_frame_vsync};
            per_frame_href_r  <= {per_frame_href_r [1:0], per_frame_href };
            per_frame_hsync_r <= {per_frame_hsync_r[1:0], per_frame_hsync};
        end
    end

    wire read_frame_href = per_frame_href_r[0] | per_frame_href_r[1];

    assign matrix_frame_vsync = per_frame_vsync_r[2];
    assign matrix_frame_href  = per_frame_href_r[2];
    assign matrix_frame_hsync = per_frame_hsync_r[2];

    //------------------------------------------------------------------
    //  拼 3x3 窗口
    //  和 VIP 版本一样：第 0 列、第 1 列、最后一列做特殊处理（重复/补 0）
    //------------------------------------------------------------------
    reg [13:0] pixel_cnt;
    reg [DATA_WIDTH-1:0] r1d0, r1d1, r2d0, r2d1, r3d0, r3d1;

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            pixel_cnt <= 0;
            r1d0 <= 0; r1d1 <= 0;
            r2d0 <= 0; r2d1 <= 0;
            r3d0 <= 0; r3d1 <= 0;
            {matrix_p11, matrix_p12, matrix_p13} <= 0;
            {matrix_p21, matrix_p22, matrix_p23} <= 0;
            {matrix_p31, matrix_p32, matrix_p33} <= 0;
        end
        else if(read_frame_href)
        begin
            pixel_cnt <= (pixel_cnt < IMG_HDISP) ? pixel_cnt + 1'b1 : 14'd0;
            {r1d1, r1d0} <= {r1d0, row1_data};
            {r2d1, r2d0} <= {r2d0, row2_data};
            {r3d1, r3d0} <= {r3d0, row3_data};
            if(pixel_cnt == 0)
            begin
                {matrix_p11, matrix_p12, matrix_p13} <= 0;
                {matrix_p21, matrix_p22, matrix_p23} <= 0;
                {matrix_p31, matrix_p32, matrix_p33} <= 0;
            end
            else if(pixel_cnt == 1)
            begin
                {matrix_p11, matrix_p12, matrix_p13} <= {row1_data, r1d0, row1_data};
                {matrix_p21, matrix_p22, matrix_p23} <= {row2_data, r2d0, row2_data};
                {matrix_p31, matrix_p32, matrix_p33} <= {row3_data, r3d0, row3_data};
            end
            else if(pixel_cnt == IMG_HDISP)
            begin
                {matrix_p11, matrix_p12, matrix_p13} <= {r1d1, row1_data, r1d1};
                {matrix_p21, matrix_p22, matrix_p23} <= {r2d1, row2_data, r2d1};
                {matrix_p31, matrix_p32, matrix_p33} <= {r3d1, row3_data, r3d1};
            end
            else
            begin
                {matrix_p11, matrix_p12, matrix_p13} <= {r1d1, r1d0, row1_data};
                {matrix_p21, matrix_p22, matrix_p23} <= {r2d1, r2d0, row2_data};
                {matrix_p31, matrix_p32, matrix_p33} <= {r3d1, r3d0, row3_data};
            end
        end
        else
        begin
            pixel_cnt <= 0;
            {matrix_p11, matrix_p12, matrix_p13} <= 0;
            {matrix_p21, matrix_p22, matrix_p23} <= 0;
            {matrix_p31, matrix_p32, matrix_p33} <= 0;
        end
    end

endmodule
