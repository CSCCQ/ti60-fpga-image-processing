`timescale 1ns/1ns
//======================================================================
//  Shape_Annotate.v  ——  给**每个**识别到的图形画框 + 写名字（多图形版）
//
//  接在 Edge_Overlay 之后、rgb2dvi 之前：
//      正常模式(mode_i=0)：数据原样透传（屏幕上只有描边）
//      识别模式(mode_i=1)：对 8 路识别结果里每一路有效的，都画
//          ① 贴着包围盒的矩形框（2 像素粗，颜色 = 该图形的代表色）
//          ② 框旁边的图形名字（5x7 点阵字库 ×2 倍）
//          ③ 左上角一个小方块表示"当前处于识别模式"
//
//  8 路输入压平成一维向量（Verilog-2001 不好用多维端口），
//  内部用 `[k*12 +: 12]` 这种带变量基址的部分选择取用。
//
//  字库：RECT / CIRCLE / TRIANGLE，只做了用到的 9 个字母 + 空格。
//
//  ★ 包围盒是上一帧算出来的常数，本帧整帧不变，所以这里对时序不敏感。
//======================================================================
module Shape_Annotate #(
    parameter           IMG_HDISP  = 1280,
    parameter           IMG_VDISP  = 720,
    parameter integer   NSHAPE    = 8,      //  最多几路（要和 Shape_Classify 的 NBLK 一致）
    parameter integer   CELL      = 16,     //  每个字符占的宽度(px)，必须 2 的幂
    parameter integer   SCALE     = 2,      //  字号放大倍数
    parameter integer   BOX_THICK = 2,      //  框线宽度
    parameter integer   LABEL_H   = 16,     //  7 行 x SCALE，向上取 16
    parameter integer   Y_OFFSET  = 0       // Classifier window's source-row phase
)(
    input               clk,
    input               rst_n,

    input               vs_i,
    input               hs_i,
    input               de_i,
    input   [23:0]      data_i,             //  Edge_Overlay 的输出

    //  多路识别结果（上一帧结果，本帧不变）
    input   [NSHAPE-1:0]        vld_i,
    input   [2*NSHAPE-1:0]      shape_i,
    input   [12*NSHAPE-1:0]     bx0_i,
    input   [12*NSHAPE-1:0]     by0_i,
    input   [12*NSHAPE-1:0]     bx1_i,
    input   [12*NSHAPE-1:0]     by1_i,
    input               mode_i,             //  1 = 识别模式

    input   [23:0]      mark_color_i,       //  模式指示块颜色

    output reg          vs_o,
    output reg          hs_o,
    output reg          de_o,
    output reg [23:0]   data_o
);

    localparam integer LABEL_MAXW = 8*CELL;

    //==================================================================
    //  1) 输出流的行列计数
    //==================================================================
    reg [$clog2(IMG_HDISP+1)-1:0] xc;
    reg [$clog2(IMG_VDISP+Y_OFFSET+1)-1:0] yc;
    reg         de_d, vs_d;

    wire vs_neg = vs_d && !vs_i;

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            xc <= 12'd0;  yc <= Y_OFFSET;
            de_d <= 1'b0; vs_d <= 1'b0;
        end
        else
        begin
            de_d <= de_i;
            vs_d <= vs_i;

            if(vs_neg)
            begin
                xc <= 12'd0;
                yc <= Y_OFFSET;
            end
            else
            begin
                if(de_i) xc <= xc + 1'b1;
                else     xc <= 12'd0;
                if(de_d && !de_i) yc <= yc + 1'b1;
            end
        end
    end

    //==================================================================
    //  2) 逐路判断：这个像素落在哪几路的框线 / 名字上
    //==================================================================
    // Compute common pixel bounds once, rather than 8 independent box
    // additions. Unsigned-underflow flags preserve border behaviour.
    wire [31:0] x_low={20'd0,xc}-(BOX_THICK-1);
    wire [31:0] x_high={20'd0,xc}+(BOX_THICK-1);
    wire [31:0] y_low={20'd0,yc}-(BOX_THICK-1);
    wire [31:0] y_high={20'd0,yc}+(BOX_THICK-1);
    integer k;
    reg [11:0] kx0, ky0, kx1, ky1;
    reg [11:0] klx, kly;
    reg        k_box, k_lbl;
    reg [11:0] klx_sel, kly_sel;
    reg [2:0]  sel_k;               //  命中名字的那一路（取编号最小的）
    reg        any_box, any_lbl;
    reg [1:0]  box_shape, lbl_shape;

    //  名字：**每一路只要有图形就一定写**（以前框小就直接不写，屏幕上
    //  就成了"有框没类别"）。
    //    框够大（宽>=140 高>=28）-> 写在框内左上角，压不到任何描边
    //    框不够大              -> 写在框外：优先上方，其次下方
    //  （框外的位置取在包围盒之外，所以也不会压到自己这个图形的边）
    //  颜色用该图形的类别色（不是白色），不会和"边缘变白"混起来。
    always @(*)
    begin
        any_box   = 1'b0;
        any_lbl   = 1'b0;
        box_shape = 2'd0;
        lbl_shape = 2'd0;
        sel_k     = 3'd0;
        klx_sel   = 12'd0;
        kly_sel   = 12'd0;

        for(k = 0; k < NSHAPE; k = k + 1)
        begin
            kx0 = bx0_i[k*12 +: 12];
            ky0 = by0_i[k*12 +: 12];
            kx1 = bx1_i[k*12 +: 12];
            ky1 = by1_i[k*12 +: 12];

            //  框：只有在包围盒范围内、且贴着四条边 2 像素才算
            k_box = vld_i[k] && mode_i &&
                    (xc >= kx0) && (xc <= kx1) && (yc >= ky0) && (yc <= ky1) &&
                    ((BOX_THICK>0 && BOX_THICK<=65536) ?
                     (y_low[31] || ky0>=y_low || ky1<=y_high ||
                      x_low[31] || kx0>=x_low || kx1<=x_high) :
                     ((yc <= ky0 + (BOX_THICK-1)) || (yc + (BOX_THICK-1) >= ky1) ||
                      (xc <= kx0 + (BOX_THICK-1)) || (xc + (BOX_THICK-1) >= kx1)));

            if((kx1 >= kx0 + 12'd140) && (ky1 >= ky0 + 12'd28))
            begin
                klx = kx0 + 12'd4;                     //  框内左上角
                kly = ky0 + 12'd4;
            end
            else if(ky0 >= 20+Y_OFFSET)
            begin
                klx = (kx1 + 12'd144 <= IMG_HDISP) ? (kx1 + 12'd8) :
                      ((kx0 >= 12'd144) ? (kx0 - 12'd144) : 12'd4);
                kly = ky0 - 12'd20;                    //  框外上方
            end
            else
            begin
                klx = (kx1 + 12'd144 <= IMG_HDISP) ? (kx1 + 12'd8) :
                      ((kx0 >= 12'd144) ? (kx0 - 12'd144) : 12'd4);
                kly = (ky1 + 12'd20 + LABEL_H < IMG_VDISP+Y_OFFSET) ? (ky1 + 12'd4) : 4+Y_OFFSET;
            end

            k_lbl = vld_i[k] && mode_i &&
                    (xc >= klx) && (xc < klx + LABEL_MAXW) &&
                    (yc >= kly) && (yc < kly + LABEL_H);

            if(k_box && !any_box)
            begin
                any_box   = 1'b1;
                box_shape = shape_i[k*2 +: 2];
            end
            if(k_lbl && !any_lbl)
            begin
                any_lbl   = 1'b1;
                sel_k     = k[2:0];
                klx_sel   = klx;
                kly_sel   = kly;
                lbl_shape = shape_i[k*2 +: 2];
            end
        end
    end

    //  名字取字：算出这一路的名字区域里的字符位置
    wire [11:0] llx = xc - klx_sel;
    wire [11:0] lly = yc - kly_sel;

    wire [2:0]  lci   = llx[6:4];          //  CELL = 16
    wire [2:0]  lgcol = llx[3:1];          //  SCALE = 2
    wire [2:0]  lgrow = lly[3:1];

    wire [1:0]  lbl_shape2 = shape_i[sel_k*2 +: 2];
    wire [7:0]  lch  = label_chr(lbl_shape2, lci);
    wire [4:0]  lrow = font_5x7(lch, lgrow);

    //  索引钳到 0..4，lgcol>=5 的部分本来就被 (lgcol<5) 挡掉
    wire [2:0]  lbi = (lgcol < 3'd5) ? (3'd4 - lgcol) : 3'd0;
    wire label_pix = any_lbl && (lgcol < 3'd5) && lrow[lbi];

    //==================================================================
    //  3) 模式指示块（左上角 12x12）
    //==================================================================
    wire mark_pix = mode_i && (xc >= 12'd8) && (xc < 12'd20) &&
                              (yc >= 8+Y_OFFSET) && (yc < 20+Y_OFFSET);

    //==================================================================
    //  4) 颜色
    //==================================================================
    reg [23:0] box_color;
    always @(*)
    begin
        case(box_shape)
            2'd1:    box_color = 24'h0000FF;   //  矩形 -> 蓝
            2'd2:    box_color = 24'h00FF00;   //  圆形 -> 绿
            2'd3:    box_color = 24'hFFFF00;   //  三角 -> 黄
            default: box_color = 24'hC0C0C0;   //  未知 -> 灰
        endcase
    end

    reg [23:0] lbl_color;
    always @(*)
    begin
        case(lbl_shape)
            2'd1:    lbl_color = 24'h0000FF;
            2'd2:    lbl_color = 24'h00FF00;
            2'd3:    lbl_color = 24'hFFFF00;
            default: lbl_color = 24'hC0C0C0;
        endcase
    end

    //==================================================================
    //  5) 两级流水
    //==================================================================
    reg         s1_vs, s1_hs, s1_de;
    reg         s1_box, s1_label, s1_mark;
    reg  [23:0] s1_data, s1_col;

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            s1_vs <= 1'b0; s1_hs <= 1'b0; s1_de <= 1'b0;
            s1_box <= 1'b0; s1_label <= 1'b0; s1_mark <= 1'b0;
            s1_data <= 24'd0; s1_col <= 24'd0;
        end
        else
        begin
            s1_vs <= vs_i;
            s1_hs <= hs_i;
            s1_de <= de_i;
            s1_data <= data_i;

            //  Keep the overlay causes separate so the final mux has an
            // explicit frame-over-edge priority.  Labels remain above the
            // frame at the top-left corner; the frame always beats data_i.
            s1_label <= de_i && label_pix;
            s1_box   <= de_i && any_box;
            s1_mark  <= de_i && mark_pix;
            if(label_pix)      s1_col <= lbl_color;     //  字 -> 该图形的类别色
            else if(any_box)   s1_col <= box_color;     //  框 -> 该图形代表色
            else               s1_col <= mark_color_i;  //  模式块 -> 绿
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            vs_o <= 1'b0; hs_o <= 1'b0; de_o <= 1'b0; data_o <= 24'd0;
        end
        else
        begin
            vs_o <= s1_vs;
            hs_o <= s1_hs;
            de_o <= s1_de;
            //  A recognized frame is applied after Edge_Overlay, so it
            // cannot be replaced by red/blue/green edge pixels in data_i.
            if(s1_label || s1_box || s1_mark)
                data_o <= s1_col;
            else
                data_o <= s1_data;
        end
    end

    //==================================================================
    //  6) 名字查表
    //==================================================================
    function [7:0] label_chr;
        input [1:0] shp;
        input [2:0] idx;
        begin
            case(shp)
                2'd1:  //  RECT
                    case(idx)
                        3'd0: label_chr = 8'h52;   //  R
                        3'd1: label_chr = 8'h45;   //  E
                        3'd2: label_chr = 8'h43;   //  C
                        3'd3: label_chr = 8'h54;   //  T
                        default: label_chr = 8'h20;
                    endcase
                2'd2:  //  CIRCLE
                    case(idx)
                        3'd0: label_chr = 8'h43;   //  C
                        3'd1: label_chr = 8'h49;   //  I
                        3'd2: label_chr = 8'h52;   //  R
                        3'd3: label_chr = 8'h43;   //  C
                        3'd4: label_chr = 8'h4C;   //  L
                        3'd5: label_chr = 8'h45;   //  E
                        default: label_chr = 8'h20;
                    endcase
                2'd3:  //  TRIANGLE
                    case(idx)
                        3'd0: label_chr = 8'h54;   //  T
                        3'd1: label_chr = 8'h52;   //  R
                        3'd2: label_chr = 8'h49;   //  I
                        3'd3: label_chr = 8'h41;   //  A
                        3'd4: label_chr = 8'h4E;   //  N
                        3'd5: label_chr = 8'h47;   //  G
                        3'd6: label_chr = 8'h4C;   //  L
                        3'd7: label_chr = 8'h45;   //  E
                    endcase
                default: label_chr = 8'h20;
            endcase
        end
    endfunction

    //==================================================================
    //  7) 5x7 点阵字库（bit4 最左）
    //==================================================================
    function [4:0] font_5x7;
        input [7:0] ch;
        input [2:0] row;
        begin
            case(ch)
                8'h41:  //  A
                    case(row)
                        3'd0: font_5x7 = 5'b01110;
                        3'd1: font_5x7 = 5'b10001;
                        3'd2: font_5x7 = 5'b10001;
                        3'd3: font_5x7 = 5'b11111;
                        3'd4: font_5x7 = 5'b10001;
                        3'd5: font_5x7 = 5'b10001;
                        3'd6: font_5x7 = 5'b10001;
                        default: font_5x7 = 5'b00000;
                    endcase
                8'h43:  //  C
                    case(row)
                        3'd0: font_5x7 = 5'b01110;
                        3'd1: font_5x7 = 5'b10001;
                        3'd2: font_5x7 = 5'b10000;
                        3'd3: font_5x7 = 5'b10000;
                        3'd4: font_5x7 = 5'b10000;
                        3'd5: font_5x7 = 5'b10001;
                        3'd6: font_5x7 = 5'b01110;
                        default: font_5x7 = 5'b00000;
                    endcase
                8'h45:  //  E
                    case(row)
                        3'd0: font_5x7 = 5'b11111;
                        3'd1: font_5x7 = 5'b10000;
                        3'd2: font_5x7 = 5'b10000;
                        3'd3: font_5x7 = 5'b11110;
                        3'd4: font_5x7 = 5'b10000;
                        3'd5: font_5x7 = 5'b10000;
                        3'd6: font_5x7 = 5'b11111;
                        default: font_5x7 = 5'b00000;
                    endcase
                8'h47:  //  G
                    case(row)
                        3'd0: font_5x7 = 5'b01110;
                        3'd1: font_5x7 = 5'b10001;
                        3'd2: font_5x7 = 5'b10000;
                        3'd3: font_5x7 = 5'b10111;
                        3'd4: font_5x7 = 5'b10001;
                        3'd5: font_5x7 = 5'b10001;
                        3'd6: font_5x7 = 5'b01111;
                        default: font_5x7 = 5'b00000;
                    endcase
                8'h49:  //  I
                    case(row)
                        3'd0: font_5x7 = 5'b11111;
                        3'd1: font_5x7 = 5'b00100;
                        3'd2: font_5x7 = 5'b00100;
                        3'd3: font_5x7 = 5'b00100;
                        3'd4: font_5x7 = 5'b00100;
                        3'd5: font_5x7 = 5'b00100;
                        3'd6: font_5x7 = 5'b11111;
                        default: font_5x7 = 5'b00000;
                    endcase
                8'h4C:  //  L
                    case(row)
                        3'd0: font_5x7 = 5'b10000;
                        3'd1: font_5x7 = 5'b10000;
                        3'd2: font_5x7 = 5'b10000;
                        3'd3: font_5x7 = 5'b10000;
                        3'd4: font_5x7 = 5'b10000;
                        3'd5: font_5x7 = 5'b10000;
                        3'd6: font_5x7 = 5'b11111;
                        default: font_5x7 = 5'b00000;
                    endcase
                8'h4E:  //  N
                    case(row)
                        3'd0: font_5x7 = 5'b10001;
                        3'd1: font_5x7 = 5'b11001;
                        3'd2: font_5x7 = 5'b10101;
                        3'd3: font_5x7 = 5'b10011;
                        3'd4: font_5x7 = 5'b10001;
                        3'd5: font_5x7 = 5'b10001;
                        3'd6: font_5x7 = 5'b10001;
                        default: font_5x7 = 5'b00000;
                    endcase
                8'h52:  //  R
                    case(row)
                        3'd0: font_5x7 = 5'b11110;
                        3'd1: font_5x7 = 5'b10001;
                        3'd2: font_5x7 = 5'b10001;
                        3'd3: font_5x7 = 5'b11110;
                        3'd4: font_5x7 = 5'b10100;
                        3'd5: font_5x7 = 5'b10010;
                        3'd6: font_5x7 = 5'b10001;
                        default: font_5x7 = 5'b00000;
                    endcase
                8'h54:  //  T
                    case(row)
                        3'd0: font_5x7 = 5'b11111;
                        3'd1: font_5x7 = 5'b00100;
                        3'd2: font_5x7 = 5'b00100;
                        3'd3: font_5x7 = 5'b00100;
                        3'd4: font_5x7 = 5'b00100;
                        3'd5: font_5x7 = 5'b00100;
                        3'd6: font_5x7 = 5'b00100;
                        default: font_5x7 = 5'b00000;
                    endcase
                default: font_5x7 = 5'b00000;
            endcase
        end
    endfunction

endmodule
