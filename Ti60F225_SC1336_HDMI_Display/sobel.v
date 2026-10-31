module sobel
#(
    parameter IMG_HDISP = 1280,
    parameter IMG_VDISP = 720
)
(
input 				clk_i,
input 				rst_i,
input [23:0] data_i,
output [23:0] data_o,
output [23:0] data_gray_o,	//	原始灰度图（3x3 矩阵中心像素），与 data_o 同拍
input [11:0] threshold_i,
	input 				vs_i,
	input 				hs_i,
	input 				de_i,
    output 				vs_o,
	output 			    hs_o,
	output 				de_o
);


wire                matrix_frame_vsync; //Prepared Image data vsync valid signal
wire                matrix_frame_href;  //Prepared Image data href vaild  signal
wire                matrix_frame_hsync; //Prepared Image data href vaild  signal
wire        [7:0]   matrix_p11, matrix_p12, matrix_p13; //3X3 Matrix output
wire        [7:0]   matrix_p21, matrix_p22, matrix_p23;
wire        [7:0]   matrix_p31, matrix_p32, matrix_p33;

VIP_Matrix_Generate_3X3_8Bit    
#(
    .IMG_HDISP  (IMG_HDISP),    //640*480
    .IMG_VDISP  (IMG_VDISP)
)
u_sobel_Matrix_Generate_3X3_8Bit
(
    //global clock
    .clk                    (clk_i),                  //cmos video pixel clock
    .rst_n                  (rst_i),                //global reset

    //Image data prepred to be processd
    .per_frame_vsync        (vs_i),      //Prepared Image data vsync valid signal
    .per_frame_href         (de_i),       //Prepared Image data href vaild  signal
    .per_frame_hsync        (hs_i),      //Prepared Image data href vaild  signal
    .per_img_Y              (data_i[7:0]),          //Prepared Image brightness input

    //Image data has been processd
    .matrix_frame_vsync     (matrix_frame_vsync),   //Processed Image data vsync valid signal
    .matrix_frame_href      (matrix_frame_href),    //Processed Image data href vaild  signal
    .matrix_frame_hsync     (matrix_frame_hsync),   //Processed Image data href vaild  signal
    .matrix_p11(matrix_p11),    .matrix_p12(matrix_p12),    .matrix_p13(matrix_p13),    //3X3 Matrix output
    .matrix_p21(matrix_p21),    .matrix_p22(matrix_p22),    .matrix_p23(matrix_p23),
    .matrix_p31(matrix_p31),    .matrix_p32(matrix_p32),    .matrix_p33(matrix_p33)
);

//	vs/hs/de 打 2 拍（数据侧在文件末尾补了同样的 2 拍，两者必须成对）
reg [1:0]   vs_o_r;
reg [1:0]   de_o_r;
reg [1:0]   hs_o_r;
always @(posedge clk_i or negedge rst_i)
begin
    if(!rst_i)
        begin
        vs_o_r  <=  0;
        de_o_r   <=  0;
        hs_o_r  <=  0;
        end
    else
        begin
        vs_o_r  <=  {vs_o_r[0], matrix_frame_vsync};
        de_o_r   <=  {de_o_r[0],  matrix_frame_href};
        hs_o_r  <=  {hs_o_r[0], matrix_frame_hsync};
        end
end
assign   vs_o   =    vs_o_r  [1];
assign  de_o   =    de_o_r[1];
assign  hs_o  =   hs_o_r[1];


wire signed [31:0]gx,gy;
wire [31:0] abs_gx,abs_gy;
assign gx=-matrix_p11+matrix_p13-2*matrix_p21+2*matrix_p23-matrix_p31+matrix_p33;
assign gy=-matrix_p11-2*matrix_p12-matrix_p13+matrix_p31+2*matrix_p32+matrix_p33;
assign abs_gx=(gx>=0)?gx:-gx;
assign abs_gy=(gy>=0)?gy:-gy;
wire [13:0] edge_value;

assign edge_value = abs_gx + abs_gy;

//------------------------------------------------------------------
//	数据输出级：补 2 拍，与上面 vs_o / hs_o / de_o 的 2 级延迟严格对齐。
//
//	matrix_p* 和 matrix_frame_* 是 3x3 矩阵模块同一级流水的一对信号，
//	本来就是逐列对齐的（已仿真确认：输入第 100 列 <=> matrix_frame_href 第 100 列）。
//	原先只把 vs/hs/de 延了 2 拍、数据没延，于是 de_o 的有效窗口比数据晚 2 拍：
//	    de_o 第 c 列 取到的是图像第 c+2 列  =>  整幅画面左移 2 像素。
//	这里给数据补上同样的 2 拍后：
//	    de_o 第 c 列 <=> 图像第 c 列（无偏移）
//------------------------------------------------------------------
wire [23:0] edge_bin = (edge_value > threshold_i) ? 24'hffffff : 24'h000000;

reg [23:0]  data_o_r1, data_o_r2;
reg [23:0]  gray_o_r1, gray_o_r2;
always @(posedge clk_i or negedge rst_i)
begin
    if(!rst_i)
        begin
        data_o_r1 <= 0;     data_o_r2 <= 0;
        gray_o_r1 <= 0;     gray_o_r2 <= 0;
        end
    else
        begin
        data_o_r1 <= edge_bin;            data_o_r2 <= data_o_r1;
        gray_o_r1 <= {3{matrix_p22}};     gray_o_r2 <= gray_o_r1;
        end
end

assign data_o      = data_o_r2;       //  二值化边缘结果
assign data_gray_o = gray_o_r2;       //  原始灰度图（3x3 矩阵中心像素）

endmodule