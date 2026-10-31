`timescale 1ns/1ns
//======================================================================
//  Canny_Edge.v  ——  流式 Canny 边缘检测
//
//  按经典 Canny 的 5 个步骤实现：
//      ① 高斯滤波     3x3 [1 2 1; 2 4 2; 1 2 1] / 16
//      ② 梯度幅值和方向  Sobel Gx/Gy，幅值取 |Gx|+|Gy|，方向量化成 4 档
//      ③ 非极大值抑制   沿梯度方向比幅值，只保留局部极大（得到单像素边缘）
//      ④ 双阈值分类      > TH_HIGH 强边缘； > TH_LOW 弱边缘
//      ⑤ 滞后边缘连接   弱边缘只要 3x3 邻域里有强边缘就保留
//
//  流水线（3 级 3x3 窗口）：
//      gray ─[M1 高斯 3x3]─► 平滑图 ─[M2 Sobel 3x3]─► 幅值/方向
//           ─[M3 幅值窗口 3x3]─► NMS + 双阈值 + 滞后 ─► 边缘
//
//  ★ 两个工程近似（流式硬件里必须做的取舍，都在下面注释里标了）：
//    (1) 方向只量化成 4 档（0/45/90/135°），不做插值；
//        比 OpenCV 的精确方向插值略粗，但这是 FPGA 上的标准做法。
//    (2) 滞后连接是"单遍"近似：弱边缘只看 3x3 邻域里**有没有**强边缘，
//        不做真正的连通域传播（那个需要跨行回溯，流式流水线做不了）。
//        好处是不用额外加一级窗口，代价是极少数长弱边缘会被截断。
//
//  阈值：threshold_i 是高阈值，低阈值自动取它的一半 —— 这样原来的
//        k1/k2 两个按键调节一个阈值就能同时带动两个。
//
//  输出格式和 sobel 一致：边缘 = 24'hFFFFFF，非边缘 = 24'h000000。
//======================================================================
module Canny_Edge #(
    parameter           IMG_HDISP = 1280,
    parameter           IMG_VDISP = 720,
    parameter integer   ENABLE_MEDIAN_SOBEL = 0,
    parameter integer   ENABLE_EDGE_GUARD = 0,
    parameter integer   EDGE_MARGIN = 0,
    parameter integer   ENABLE_GRAY_DENOISE = 0
)(
    input               clk_i,
    input               rst_i,              //  低有效

    input       [23:0]  data_i,             //  24bit 灰度（3 字节同值）
    input       [11:0]  threshold_i,        //  高阈值

    input               median_sobel_i, // frame-stable filter select
    input               edge_guard_i,   // frame-stable, binary/split views only
    input               vs_i,
    input               hs_i,
    input               de_i,

    // Tap the existing first-stage filter; no new filter or line memory.
    // Relative to RGB before FrameBoundCrop: one source row + five clocks.
    output      [7:0]   filtered_gray_o,
    output              filtered_vs_o,
    output              filtered_de_o,
    output              edge_strong_o,
    output      [23:0]  data_o,
    output              vs_o,
    output              hs_o,
    output              de_o
);

    //==================================================================
    //  第 1 级：高斯滤波 3x3
    //     g = (p11 + 2*p12 + p13 + 2*p21 + 4*p22 + 2*p23 + p31 + 2*p32 + p33) >> 4
    //==================================================================
    // Spatial, row-local Q8.2 smoothing; no previous-frame luminance.
    // Only low-threshold edge views enable it. Abrupt transitions bypass
    // the recurrence, preserving the location of high-contrast strokes.
    wire gray_denoise=ENABLE_GRAY_DENOISE && edge_guard_i && !median_mode &&
        (threshold_i<12'd50);
    reg [9:0] gray_previous;
    reg gray_previous_valid;
    wire [9:0] gray_current={data_i[7:0],2'b00};
    wire [9:0] gray_delta=(gray_current>=gray_previous) ?
        gray_current-gray_previous : gray_previous-gray_current;
    wire [10:0] gray_average={1'b0,gray_previous}+{1'b0,gray_current}+11'd1;
    wire [9:0] gray_smoothed=(gray_previous_valid && gray_delta<=10'd48) ?
        gray_average[10:1] : gray_current;
    wire [10:0] gray_rounded={1'b0,gray_smoothed}+11'd2;
    wire [7:0] gray_input=gray_denoise ?
        ((gray_rounded>11'd1020)?8'd255:gray_rounded[9:2]) : data_i[7:0];
    always @(posedge clk_i or negedge rst_i) begin
        if(!rst_i) begin gray_previous<=0;gray_previous_valid<=0;end
        else begin
            gray_previous_valid<=de_i;
            if(de_i)gray_previous<=gray_smoothed;
        end
    end

    wire                m1_vs, m1_href, m1_hs;
    wire [7:0]          a11,a12,a13,a21,a22,a23,a31,a32,a33;

    VIP_Matrix_Generate_3X3_8Bit #(
        .IMG_HDISP (IMG_HDISP), .IMG_VDISP (IMG_VDISP)
    ) u_M1_Gauss_Matrix (
        .clk                (clk_i),
        .rst_n              (rst_i),
        .per_frame_vsync    (vs_i),
        .per_frame_href     (de_i),
        .per_frame_hsync    (hs_i),
        .per_img_Y          (gray_input),
        .matrix_frame_vsync (m1_vs),
        .matrix_frame_href  (m1_href),
        .matrix_frame_hsync (m1_hs),
        .matrix_p11(a11), .matrix_p12(a12), .matrix_p13(a13),
        .matrix_p21(a21), .matrix_p22(a22), .matrix_p23(a23),
        .matrix_p31(a31), .matrix_p32(a32), .matrix_p33(a33)
    );

    wire [9:0]  gs_r1 = {2'b0, a11} + {a12, 1'b0} + {2'b0, a13};   //  p11 + 2*p12 + p13
    wire [9:0]  gs_r2 = {2'b0, a21} + {a22, 1'b0} + {2'b0, a23};
    wire [9:0]  gs_r3 = {2'b0, a31} + {a32, 1'b0} + {2'b0, a33};
    wire [11:0] gs_all = {2'b0, gs_r1} + {gs_r2, 1'b0} + {2'b0, gs_r3};   //  最多 4080
    wire [7:0]  gauss_y = gs_all[11:4];                                    //  >>4 -> 8bit


    // Exact 3x3 median: fifth of ALL nine samples, not a separable median.
    // M1/M2 line stores are shared: no extra block RAM or pixel delay.
    function [23:0] sort_three;
        input [7:0] a,b,c;
        reg [7:0] lo_ab,hi_ab,lo_bc,hi_bc;
        begin
            lo_ab=(a<b)?a:b; hi_ab=(a<b)?b:a;
            lo_bc=(hi_ab<c)?hi_ab:c; hi_bc=(hi_ab<c)?c:hi_ab;
            sort_three={hi_bc,((lo_ab<lo_bc)?lo_bc:lo_ab),
                              ((lo_ab<lo_bc)?lo_ab:lo_bc)};
        end
    endfunction
    function [7:0] middle_three;
        input [7:0] a,b,c;
        begin
            middle_three=(a<b) ? ((b<c)?b:((a<c)?c:a))
                               : ((a<c)?a:((b<c)?c:b));
        end
    endfunction
    wire median_mode = ENABLE_MEDIAN_SOBEL ? median_sobel_i : 1'b0;
    wire [7:0] median_y;
    generate if(ENABLE_MEDIAN_SOBEL) begin:g_median
        wire [23:0] r1=sort_three(a11,a12,a13);
        wire [23:0] r2=sort_three(a21,a22,a23);
        wire [23:0] r3=sort_three(a31,a32,a33);
        wire [7:0] max_lo12=(r1[7:0]>r2[7:0])?r1[7:0]:r2[7:0];
        wire [7:0] max_lo=(max_lo12>r3[7:0])?max_lo12:r3[7:0];
        wire [7:0] min_hi12=(r1[23:16]<r2[23:16])?r1[23:16]:r2[23:16];
        wire [7:0] min_hi=(min_hi12<r3[23:16])?min_hi12:r3[23:16];
        wire [7:0] mid_mid=middle_three(r1[15:8],r2[15:8],r3[15:8]);
        assign median_y=middle_three(max_lo,mid_mid,min_hi);
    end else begin:g_gauss_only
        assign median_y=8'd0;
    end endgenerate

    reg  [9:0]  sm_y;
    reg         s1_vs, s1_href, s1_hs;
    always @(posedge clk_i or negedge rst_i)
    begin
        if(!rst_i)
        begin
            sm_y <= 10'd0; s1_vs <= 1'b0; s1_href <= 1'b0; s1_hs <= 1'b0;
        end
        else
        begin
            // Keep two Gaussian fractional bits until AFTER Sobel.
            // Display-only filters and red-edge shape input stay bit-exact.
            sm_y <= median_mode ? {median_y,2'b00} :
                gray_denoise ? gs_all[11:2] : {gauss_y,2'b00};
            s1_vs   <= m1_vs;
            s1_href <= m1_href;
            s1_hs   <= m1_hs;
        end
    end

    //==================================================================
    //  第 2 级：Sobel 梯度（在平滑图上做）
    //      Gx = -p11 + p13 - 2*p21 + 2*p23 - p31 + p33
    //      Gy = -p11 - 2*p12 - p13 + p31 + 2*p32 + p33
    //      mag = |Gx| + |Gy|   （L1 近似，省掉开方）
    //      dir = 4 档方向码：0=水平 1=45° 2=垂直 3=135°
    //==================================================================
    wire                m2_vs, m2_href, m2_hs;
    wire [9:0]          b11,b12,b13,b21,b22,b23,b31,b32,b33;

    Matrix_Generate_3X3 #(
        .DATA_WIDTH(10), .IMG_HDISP (IMG_HDISP), .IMG_VDISP (IMG_VDISP)
    ) u_M2_Sobel_Matrix (
        .clk                (clk_i),
        .rst_n              (rst_i),
        .per_frame_vsync    (s1_vs),
        .per_frame_href     (s1_href),
        .per_frame_hsync    (s1_hs),
        .per_img_Y          (sm_y),
        .matrix_frame_vsync (m2_vs),
        .matrix_frame_href  (m2_href),
        .matrix_frame_hsync (m2_hs),
        .matrix_p11(b11), .matrix_p12(b12), .matrix_p13(b13),
        .matrix_p21(b21), .matrix_p22(b22), .matrix_p23(b23),
        .matrix_p31(b31), .matrix_p32(b32), .matrix_p33(b33)
    );

    // Share diagonal differences between Gx and Gy.
    wire signed [10:0] diagonal_a=$signed({1'b0,b33})-$signed({1'b0,b11});
    wire signed [10:0] diagonal_b=$signed({1'b0,b13})-$signed({1'b0,b31});
    wire signed [10:0] horizontal=$signed({1'b0,b23})-$signed({1'b0,b21});
    wire signed [10:0] vertical=$signed({1'b0,b32})-$signed({1'b0,b12});
    wire signed [12:0] gx=$signed({{2{diagonal_a[10]}},diagonal_a})+
        $signed({{2{diagonal_b[10]}},diagonal_b})+$signed({horizontal[10],horizontal,1'b0});
    wire signed [12:0] gy=$signed({{2{diagonal_a[10]}},diagonal_a})-
        $signed({{2{diagonal_b[10]}},diagonal_b})+$signed({vertical[10],vertical,1'b0});
    wire [11:0] ax=gx[12] ? (-gx[11:0]) : gx[11:0];
    wire [11:0] ay=gy[12] ? (-gy[11:0]) : gy[11:0];
    wire [12:0] mag_fraction={1'b0,ax}+{1'b0,ay};
    wire [10:0] mag=mag_fraction[12:2];

    //  方向量化： |Gy| <= 0.4167*|Gx| -> 水平 ;  |Gy| > 2.4*|Gx| -> 垂直 ;  否则对角
    wire dir_horz = (ay * 12 <= ax * 5);
    wire dir_vert = (ay * 5  >  ax * 12);
    wire dir_same = (gx[12] == gy[12]);              //  同号 -> 走"左上-右下"那条对角线
    wire [1:0] dir = dir_vert ? 2'd2 : (dir_horz ? 2'd0 : (dir_same ? 2'd1 : 2'd3));

    reg  [10:0] mag_r;
    reg  [1:0]  dir_r;
    reg         polarity_r;
    reg         s2_vs, s2_href, s2_hs;
    always @(posedge clk_i or negedge rst_i)
    begin
        if(!rst_i)
        begin
            mag_r <= 11'd0; dir_r <= 2'd0; polarity_r <= 1'b0;
            s2_vs <= 1'b0; s2_href <= 1'b0; s2_hs <= 1'b0;
        end
        else
        begin
            mag_r   <= mag;
            dir_r   <= dir;
            // Full eight-way gradient angle is {polarity,dir}. Retaining
            // polarity prevents opposite sides of a noise spot voting for
            // each other. It is not used by the unchanged edge algorithm.
            polarity_r <= (dir==2'd3) ? !gx[12] :
                          (dir==2'd2) ? gy[12] : gx[12];
            s2_vs   <= m2_vs;
            s2_href <= m2_href;
            s2_hs   <= m2_hs;
        end
    end

    //==================================================================
    //  第 3 级：幅值窗口 3x3（幅值 + 方向一起进窗口，这样方向天然对齐中心）
    //     c11 c12 c13       左上 上   右上
    //     c21 c22 c23       左   中心 右
    //     c31 c32 c33       左下 下   右下
    //==================================================================
    localparam integer MD_WIDTH=ENABLE_EDGE_GUARD ? 14 : 13;
    wire [MD_WIDTH-1:0] md_in = ENABLE_EDGE_GUARD ?
        {polarity_r,mag_r,dir_r} : {mag_r,dir_r};

    wire                m3_vs, m3_href, m3_hs;
    wire [MD_WIDTH-1:0] c11,c12,c13,c21,c22,c23,c31,c32,c33;

    Matrix_Generate_3X3 #(
        .DATA_WIDTH (MD_WIDTH), .IMG_HDISP (IMG_HDISP), .IMG_VDISP (IMG_VDISP)
    ) u_M3_Mag_Matrix (
        .clk                (clk_i),
        .rst_n              (rst_i),
        .per_frame_vsync    (s2_vs),
        .per_frame_href     (s2_href),
        .per_frame_hsync    (s2_hs),
        .per_img_Y          (md_in),
        .matrix_frame_vsync (m3_vs),
        .matrix_frame_href  (m3_href),
        .matrix_frame_hsync (m3_hs),
        .matrix_p11(c11), .matrix_p12(c12), .matrix_p13(c13),
        .matrix_p21(c21), .matrix_p22(c22), .matrix_p23(c23),
        .matrix_p31(c31), .matrix_p32(c32), .matrix_p33(c33)
    );

    wire [10:0] nc  = c22[12:2];                      //  中心幅值
    wire [1:0]  d22 = c22[1:0];                       //  中心方向

    wire [10:0] n11 = c11[12:2], n12 = c12[12:2], n13 = c13[12:2];
    wire [10:0] n21 = c21[12:2], n23 = c23[12:2];
    wire [10:0] n31 = c31[12:2], n32 = c32[12:2], n33 = c33[12:2];

    //------------------------------------------------------------------
    //  非极大值抑制：沿梯度方向取两侧邻居
    //      dir=0 水平   -> 左/右          (n21, n23)
    //      dir=2 垂直   -> 上/下          (n12, n32)
    //      dir=1 对角(同号)   -> 左上/右下 (n11, n33)
    //      dir=3 对角(异号)   -> 右上/左下 (n13, n31)
    //------------------------------------------------------------------
    wire [10:0] nms1 = (d22 == 2'd0) ? n21 : (d22 == 2'd2) ? n12 : (d22 == 2'd1) ? n11 : n13;
    wire [10:0] nms2 = (d22 == 2'd0) ? n23 : (d22 == 2'd2) ? n32 : (d22 == 2'd1) ? n33 : n31;

    //  两侧都用 >= 的话，对称台阶边缘（高斯平滑后必然对称）会保留 2 个像素；
    //  这里用 > / >= 打破平局，保证"单像素边缘"这个 Canny 的核心特性。
    //  平坦区域（三个值相等）不会被误判为边缘。
    wire nms_keep = (nc > nms1) && (nc >= nms2);

    //------------------------------------------------------------------
    //  双阈值 + 滞后连接
    //      strong = nc > TH_HIGH
    //      weak   = nc > TH_LOW
    //      8 邻域里有强边缘吗？（用窗口里未做 NMS 的幅值判断 —— 单遍近似）
    //------------------------------------------------------------------
    wire [11:0] th_hi = threshold_i;
    wire [11:0] th_lo = {1'b0, threshold_i[11:1]};    //  低阈值 = 高阈值的一半

    wire strong_edge = ({1'b0, nc} > th_hi);
    wire weak_edge = ({1'b0, nc} > th_lo);

    wire [7:0] nbr_high={({1'b0,n33}>th_hi),({1'b0,n32}>th_hi),
        ({1'b0,n31}>th_hi),({1'b0,n23}>th_hi),({1'b0,n21}>th_hi),
        ({1'b0,n13}>th_hi),({1'b0,n12}>th_hi),({1'b0,n11}>th_hi)};
    wire nbr_strong=|nbr_high;

    // Low-threshold guard reuses the magnitude window and adds no clocks.
    // Strong gradients and TH>=160 are exactly the original algorithm.
    // Gaussian/Canny accepts three same-angle neighbours OR six neighbours
    // within +/-45 degrees, each above one quarter of the centre magnitude.
    // This second path protects quantized shallow curves and corners.
    // Median/Sobel rejects isolated responses with fewer than two neighbours
    // above the user's threshold; the single-threshold Sobel core is retained.
    wire local_support;
    generate if(ENABLE_EDGE_GUARD) begin:g_edge_guard
        function [1:0] vote;
            input [13:0] sample,centre;
            reg [2:0] angle_delta;
            reg sufficient;
            begin
                angle_delta={sample[13],sample[1:0]}-{centre[13],centre[1:0]};
                sufficient=sample[12:2]>(centre[12:2]>>2);
                vote={sufficient && ((angle_delta<=3'd1)||(angle_delta==3'd7)),
                      sufficient && (angle_delta==3'd0)};
            end
        endfunction
        wire [1:0] q0=vote(c11,c22),q1=vote(c12,c22),q2=vote(c13,c22);
        wire [1:0] q3=vote(c21,c22),q4=vote(c23,c22);
        wire [1:0] q5=vote(c31,c22),q6=vote(c32,c22),q7=vote(c33,c22);
        wire [3:0] same_count={3'd0,q0[0]}+{3'd0,q1[0]}+{3'd0,q2[0]}+
            {3'd0,q3[0]}+{3'd0,q4[0]}+{3'd0,q5[0]}+{3'd0,q6[0]}+{3'd0,q7[0]};
        wire [3:0] near_count={3'd0,q0[1]}+{3'd0,q1[1]}+{3'd0,q2[1]}+
            {3'd0,q3[1]}+{3'd0,q4[1]}+{3'd0,q5[1]}+{3'd0,q6[1]}+{3'd0,q7[1]};
        wire [3:0] high_count={3'd0,nbr_high[0]}+{3'd0,nbr_high[1]}+
            {3'd0,nbr_high[2]}+{3'd0,nbr_high[3]}+{3'd0,nbr_high[4]}+
            {3'd0,nbr_high[5]}+{3'd0,nbr_high[6]}+{3'd0,nbr_high[7]};
        assign local_support=median_mode ? (high_count>=4'd2) :
            ((same_count>=4'd3)||(near_count>=4'd6));
    end else begin:g_no_edge_guard
        assign local_support=1'b1;
    end endgenerate
    wire guard_pass=!(ENABLE_EDGE_GUARD && edge_guard_i) ||
        (threshold_i>=12'd160) || (nc>=11'd160) || local_support;

    // Median/Sobel uses aligned centre magnitude and a single threshold.
    // The M3 centre only equalizes timing; NMS/hysteresis are bypassed.
    wire edge_base = median_mode ? strong_edge :
                    nms_keep && (strong_edge || (weak_edge && nbr_strong));
    // The input crop and incomplete convolution windows are not scene
    // edges. Gate their results, never the RGB/gray image or HDMI timing.
    // M1/M2/M3 retain DE timing but their centre is three source rows old.
    wire edge_window_valid;
    generate if(EDGE_MARGIN>0) begin:g_edge_border
        localparam X_BITS=$clog2(IMG_HDISP+1);
        localparam Y_BITS=$clog2(IMG_VDISP+16);
        reg [X_BITS-1:0] edge_x;
        reg [Y_BITS-1:0] edge_y;
        reg edge_de_d,edge_vs_d;
        always @(posedge clk_i or negedge rst_i) begin
            if(!rst_i) begin edge_x<=0;edge_y<=0;edge_de_d<=0;edge_vs_d<=0;end
            else begin
                edge_de_d<=m3_href;
                edge_vs_d<=m3_vs;
                if(m3_vs && !edge_vs_d) begin edge_x<=0;edge_y<=0;end
                else begin
                    if(m3_href) edge_x<=edge_x+1'b1;else edge_x<=0;
                    if(edge_de_d && !m3_href) edge_y<=edge_y+1'b1;
                end
            end
        end
        assign edge_window_valid=(edge_x>=EDGE_MARGIN) &&
            (edge_x<IMG_HDISP-EDGE_MARGIN) &&
            (edge_y>=EDGE_MARGIN+3) &&
            (edge_y<IMG_VDISP+3-EDGE_MARGIN);
    end else begin:g_edge_no_border
        assign edge_window_valid=1'b1;
    end endgenerate
    wire edge_now = edge_base && guard_pass && edge_window_valid;

    //------------------------------------------------------------------
    //  输出寄存（数据与同步信号一起打一拍，保证同拍）
    //------------------------------------------------------------------
    reg         edge_r,strong_r;
    reg         o_vs, o_href, o_hs;
    always @(posedge clk_i or negedge rst_i)
    begin
        if(!rst_i)
        begin
            edge_r <= 1'b0;
            strong_r <= 1'b0;
            o_vs <= 1'b0; o_href <= 1'b0; o_hs <= 1'b0;
        end
        else
        begin
            edge_r <= edge_now;
            // Keep moderately contrasted moving strokes immediate; only
            // responses below 64 need previous-frame support. This does not
            // change the spatial guard's independent 160-magnitude bypass.
            strong_r <= edge_now && (nc>=11'd64);
            o_vs   <= m3_vs;
            o_href <= m3_href;
            o_hs   <= m3_hs;
        end
    end

    assign filtered_gray_o = sm_y[9:2];
    assign edge_strong_o = strong_r;
    assign filtered_vs_o = s1_vs;
    assign filtered_de_o = s1_href;

    assign data_o = edge_r ? 24'hffffff : 24'h000000;
    assign vs_o   = o_vs;
    assign hs_o   = o_hs;
    assign de_o   = o_href;

endmodule
