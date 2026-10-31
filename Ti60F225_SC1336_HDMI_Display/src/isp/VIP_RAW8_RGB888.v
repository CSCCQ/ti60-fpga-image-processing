/*-----------------------------------------------------------------------
                                 \\\|///
                               \\  - -  //
                                (  @ @  )
+-----------------------------oOOo-(_)-oOOo-----------------------------+
CONFIDENTIAL IN CONFIDENCE
This confidential and proprietary software may be only used as authorized
by a licensing agreement from CrazyBingo (Thereturnofbingo).
In the event of publication, the following notice is applicable:
Copyright (C) 2013-20xx CrazyBingo Corporation
The entire notice above must be reproduced on all authorized copies.
Author              :       CrazyBingo
Technology blogs    :       www.crazyfpga.com
Email Address       :       crazyfpga@vip.qq.com
Filename            :       VIP_YCbCr444_RGB888.v
Date                :       2014-05-03
Description         :       The testbench of VIP_YCbCr444_RGB888.
Modification History    :
Date            By          Version         Change Description
=========================================================================
14/05/03        CrazyBingo  1.0             Original
-------------------------------------------------------------------------
|                                     Oooo                              |
+-------------------------------oooO--(   )-----------------------------+
                               (   )   ) /
                                \ (   (_/
                                 \_)
-----------------------------------------------------------------------*/

`timescale 1ns/1ns
module VIP_RAW8_RGB888
#(
    parameter   [13:0]  IMG_HDISP = 640,    //640*480
    parameter   [13:0]  IMG_VDISP = 480
)
(
    //global clock
    input               clk,                //cmos video pixel clock
    input               rst_n,              //global reset
    
    input       [1:0]   mirror,

    //CMOS YCbCr444 data output
    input               per_frame_vsync,    //Prepared Image data vsync valid signal
    input               per_frame_href,     //Prepared Image data href vaild  signal
    input               per_frame_hsync, 
    input       [7:0]   per_img_RAW,        //Prepared Image data 8 Bit RAW Data

    
    //CMOS RGB888 data output
    output              post_frame_vsync,   //Processed Image data vsync valid signal
    output              post_frame_href,    //Processed Image data href vaild  signal
    output              post_frame_hsync,   //Processed Image data href vaild  signal
    output reg  [7:0]   post_img_red,       //Prepared Image green data to be processed 
    output reg  [7:0]   post_img_green,     //Prepared Image green data to be processed
    output reg  [7:0]   post_img_blue       //Prepared Image blue data to be processed
);

// The 3x3 centre belongs to the PREVIOUS input row. Drain one extra
// row in blanking and move frame-valid/sync together with that centre.
wire capture_pipe_de, capture_valid_de, capture_valid_vs,capture_frame_busy;
// DDR uses frame end rather than an HDMI-style VS porch. Hold capture
// valid until the final interpolated row has actually left the line RAM.
assign capture_valid_vs=per_frame_vsync || capture_frame_busy;
wire [11:0] capture_row;
Video_Frame_Phase #(.WIDTH(IMG_HDISP),.HEIGHT(IMG_VDISP),
    .PAD_LINES(1),.ALIGN_LINES(1)) u_frame_phase (
    .clk(clk),.rst_n(rst_n),.vs_i(per_frame_vsync),
    .hs_i(per_frame_hsync),.de_i(per_frame_href),
    .pipe_de(capture_pipe_de),.aligned_de(capture_valid_de),
    .aligned_vs(),.aligned_next_de(),.aligned_next_vs(),
    .row_index(capture_row),.frame_busy(capture_frame_busy));
reg [2:0] valid_de_pipe,valid_vs_pipe,first_row_pipe,last_row_pipe;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        valid_de_pipe<=0;valid_vs_pipe<=0;first_row_pipe<=0;last_row_pipe<=0;
    end else begin
        valid_de_pipe<={valid_de_pipe[1:0],capture_valid_de};
        valid_vs_pipe<={valid_vs_pipe[1:0],capture_valid_vs};
        first_row_pipe<={first_row_pipe[1:0],capture_row==1};
        last_row_pipe<={last_row_pipe[1:0],capture_row==IMG_VDISP};
    end
end

//----------------------------------------------------
//Generate 8Bit 3X3 Matrix for Video Image Processor.
    //Image data has been processd
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
u_VIP_Matrix_Generate_3X3_8Bit
(
    //global clock
    .clk                    (clk),                  //cmos video pixel clock
    .rst_n                  (rst_n),                //global reset

    //Image data prepred to be processd
    .per_frame_vsync        (per_frame_vsync),      //Prepared Image data vsync valid signal
    .per_frame_href         (capture_pipe_de),       //Prepared Image data href vaild  signal
    .per_frame_hsync        (per_frame_hsync),      //Prepared Image data href vaild  signal
    .per_img_Y              (per_img_RAW),          //Prepared Image brightness input

    //Image data has been processd
    .matrix_frame_vsync     (matrix_frame_vsync),   //Processed Image data vsync valid signal
    .matrix_frame_href      (matrix_frame_href),    //Processed Image data href vaild  signal
    .matrix_frame_hsync     (matrix_frame_hsync),   //Processed Image data href vaild  signal
    .matrix_p11(matrix_p11),    .matrix_p12(matrix_p12),    .matrix_p13(matrix_p13),    //3X3 Matrix output
    .matrix_p21(matrix_p21),    .matrix_p22(matrix_p22),    .matrix_p23(matrix_p23),
    .matrix_p31(matrix_p31),    .matrix_p32(matrix_p32),    .matrix_p33(matrix_p33)
);


//-------------------------------------------------------------
//sync the frame vsync and href signal and generate frame begin & end signal
reg     matrix_frame_href_r;
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        matrix_frame_href_r <= 0;
    else
        matrix_frame_href_r <= matrix_frame_href;
end
wire    matrix_frame_href_end   =   (matrix_frame_href_r & ~matrix_frame_href) ? 1'b1 : 1'b0;   //Line over signal

//----------------------------------------
//Count the frame lines
reg [10:0]  line_cnt;
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        line_cnt <= 0;
    else if(matrix_frame_vsync == 1'b1) //Frame valid
        begin
        if(matrix_frame_href_end)
            line_cnt <= (line_cnt < IMG_VDISP - 1'b1) ? line_cnt + 1'b1 : 11'd0;
        else
            line_cnt <= line_cnt;
        end
    else
        line_cnt <= 0;
end

//----------------------------------------
//Count the pixels
reg [13:0]  point_cnt;
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        point_cnt <= 0;
    else if(matrix_frame_href == 1'b1)  //Line valid
        point_cnt <= (line_cnt < IMG_HDISP - 1'b1) ? point_cnt + 1'b1 : 11'd0;
    else
        point_cnt <= 0;
end

//--------------------------------------
// Reflect the missing outer row. The first/last RGB rows must never
// interpolate with stale previous-frame data or the synthetic drain row.
wire [7:0] bp11=first_row_pipe[2] ? matrix_p31 : matrix_p11;
wire [7:0] bp12=first_row_pipe[2] ? matrix_p32 : matrix_p12;
wire [7:0] bp13=first_row_pipe[2] ? matrix_p33 : matrix_p13;
wire [7:0] bp31=last_row_pipe[2] ? matrix_p11 : matrix_p31;
wire [7:0] bp32=last_row_pipe[2] ? matrix_p12 : matrix_p32;
wire [7:0] bp33=last_row_pipe[2] ? matrix_p13 : matrix_p33;
//Convet RAW 2 RGB888 Format
//
localparam  OddLINE_OddPOINT    =   2'b11;  //odd lines + odd point
localparam  OddLINE_Even_POINT  =   2'b10;  //odd lines + even point
localparam  EvenLINE_OddPOINT   =   2'b01;  //even lines + odd point
localparam  EvenLINE_EvenPOINT  =   2'b00;  //even lines + even point
reg [9:0]   post_img_red_r;
reg [9:0]   post_img_green_r;
reg [9:0]   post_img_blue_r;
reg [9:0]   post_img_red_r_g;
reg [9:0]   post_img_green_r_g;
reg [9:0]   post_img_blue_r_g;
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        post_img_red_r  <=  0;
        post_img_green_r<=  0;
        post_img_blue_r <=  0;
    end
    else
    begin
        case(mirror)
            2'b10 : 
            begin
                case({line_cnt[0], point_cnt[0]})
                    //-------------------------GRGR...GRGR--------------------//
                    OddLINE_OddPOINT:   //odd lines + odd point
                    begin   //Center Red
                        post_img_red_r  <=  matrix_p22;
                        post_img_green_r<=  (bp12 + matrix_p21 + matrix_p23 + bp32)>>2;
                        post_img_blue_r <=  (bp11 + bp13 + bp31 + bp33)>>2;
                    end
                    OddLINE_Even_POINT: //odd lines + even point
                    begin   //Center Green  
                        post_img_red_r  <=  (matrix_p21 + matrix_p23)>>1;
                        post_img_green_r<=  matrix_p22;
                        post_img_blue_r <=  (bp12 + bp32)>>1;
                    end
                    //-------------------------BGBG...BGBG--------------------//
                    EvenLINE_OddPOINT:  //even lines + odd point
                    begin   //Center Green
                        post_img_red_r  <=  (bp12 + bp32)>>1;
                        post_img_green_r<=  matrix_p22;
                        post_img_blue_r <=  (matrix_p21 + matrix_p23)>>1;
                    end
                    EvenLINE_EvenPOINT: //even lines + even point
                    begin   //Center Blue
                        post_img_red_r  <=  (bp11 + bp13 + bp31 + bp33)>>2;
                        post_img_green_r<=  (bp12 + matrix_p21 + matrix_p23 + bp32)>>2;
                        post_img_blue_r <=  matrix_p22;     
                    end
                endcase
            end
            2'b11 : 
            begin
                case({line_cnt[0], point_cnt[0]})
                   //-------------------------GRGR...GRGR--------------------//
                   OddLINE_OddPOINT:   //odd lines + odd point
                   begin   //Center Green  
                       post_img_red_r  <=  (matrix_p21 + matrix_p23)>>1;
                       post_img_green_r<=  matrix_p22;
                       post_img_blue_r <=  (bp12 + bp32)>>1;
                   end
                   OddLINE_Even_POINT: //odd lines + even point
                   begin   //Center Red
                       post_img_red_r  <=  matrix_p22;
                       post_img_green_r<=  (bp12 + matrix_p21 + matrix_p23 + bp32)>>2;
                       post_img_blue_r <=  (bp11 + bp13 + bp31 + bp33)>>2;
                   end
                   //-------------------------BGBG...BGBG--------------------//
                   EvenLINE_OddPOINT:  //even lines + odd point
                   begin   //Center Blue
                       post_img_red_r  <=  (bp11 + bp13 + bp31 + bp33)>>2;
                       post_img_green_r<=  (bp12 + matrix_p21 + matrix_p23 + bp32)>>2;
                       post_img_blue_r <=  matrix_p22;     
                   end
                   EvenLINE_EvenPOINT: //even lines + even point
                   begin   //Center Green
                       post_img_red_r  <=  (bp12 + bp32)>>1;
                       post_img_green_r<=  matrix_p22;
                       post_img_blue_r <=  (matrix_p21 + matrix_p23)>>1;
                   end
                endcase
            end
            2'b00 : 
            begin
                case({line_cnt[0], point_cnt[0]})
                    //-------------------------GBGB...GBGB--------------------//
                    OddLINE_OddPOINT:   //odd lines + odd point
                    begin   //Center Green
                        post_img_red_r  <=  (bp12 + bp32)>>1;
                        post_img_green_r<=  matrix_p22;
                        post_img_blue_r<=  (matrix_p21 + matrix_p23)>>1;
                      //  post_img_red_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                     //   post_img_green_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                       // post_img_blue_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                    end
                    OddLINE_Even_POINT: //odd lines + even point
                    begin   //Center Blue
                        post_img_red_r  <=  (bp11 + bp13 + bp31 + bp33)>>2;
                        post_img_green_r<=  (bp12 + matrix_p21 + matrix_p23 + bp32)>>2;
                        post_img_blue_r <=  matrix_p22;
                    //    post_img_red_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                     //   post_img_green_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                     //   post_img_blue_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                    end
                    //-------------------------RGRG...RGRG--------------------//
                    EvenLINE_OddPOINT:  //even lines + odd point
                    begin   //Center Red
                        post_img_red_r <=  matrix_p22;
                        post_img_green_r<=  (bp12 + matrix_p21 + matrix_p23 + bp32)>>2;
                        post_img_blue_r <=  (bp11 + bp13 + bp31 + bp33)>>2;
                     //   post_img_red_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                     //   post_img_green_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                     //   post_img_blue_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                    end
                    EvenLINE_EvenPOINT: //even lines + even point
                    begin   //Center Green  
                        post_img_red_r  <=  (matrix_p21 + matrix_p23)>>1;
                        post_img_green_r<=  matrix_p22;
                        post_img_blue_r <=  (bp12 + bp32)>>1;
                    //    post_img_red_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                     //   post_img_green_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                     //   post_img_blue_r<=(77*post_img_red_r_g+150*post_img_green_r_g+29*post_img_blue_r_g+128)>>8;
                    end
                endcase
            end
            2'b01 : 
            begin
                case({line_cnt[0], point_cnt[0]})
                    //-------------------------BGBG...BGBG--------------------//
                    OddLINE_OddPOINT:   //odd lines + odd point
                    begin   //Center Blue
                        post_img_red_r  <=  (bp11 + bp13 + bp31 + bp33)>>2;
                        post_img_green_r<=  (bp12 + matrix_p21 + matrix_p23 + bp32)>>2;
                        post_img_blue_r <=  matrix_p22;     
                    end
                    OddLINE_Even_POINT: //odd lines + even point
                    begin   //Center Green
                        post_img_red_r  <=  (bp12 + bp32)>>1;
                        post_img_green_r<=  matrix_p22;
                        post_img_blue_r <=  (matrix_p21 + matrix_p23)>>1;
                    end
                    //-------------------------GRGR...GRGR--------------------//
                    EvenLINE_OddPOINT:  //even lines + odd point
                    begin   //Center Green  
                        post_img_red_r  <=  (matrix_p21 + matrix_p23)>>1;
                        post_img_green_r<=  matrix_p22;
                        post_img_blue_r <=  (bp12 + bp32)>>1;
                    end
                    EvenLINE_EvenPOINT: //even lines + even point
                    begin   //Center Red
                        post_img_red_r  <=  matrix_p22;
                        post_img_green_r<=  (bp12 + matrix_p21 + matrix_p23 + bp32)>>2;
                        post_img_blue_r <=  (bp11 + bp13 + bp31 + bp33)>>2;
                    end
                endcase
            end
        endcase
    end
end



// assign  post_img_red    =   post_img_red_r[7:0];
// assign  post_img_green  =   post_img_green_r[7:0];
// assign  post_img_blue   =   post_img_blue_r[7:0];

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        post_img_red <= 8'b0;
        post_img_green <= 8'b0;
        post_img_blue <= 8'b0;
    end
    else
    begin
        post_img_red <= post_img_red_r[7:0];
        post_img_green <= post_img_green_r[7:0];
        post_img_blue <= post_img_blue_r[7:0];
    end
end

//------------------------------------------
//lag n clocks signal sync      
reg [1:0]   post_frame_vsync_r;
reg [1:0]   post_frame_href_r;
reg [1:0]   post_frame_hsync_r;
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        begin
        post_frame_vsync_r  <=  0;
        post_frame_href_r   <=  0;
        post_frame_hsync_r  <=  0;
        end
    else
        begin
        post_frame_vsync_r  <=  {post_frame_vsync_r[0], valid_vs_pipe[2]};
        post_frame_href_r   <=  {post_frame_href_r[0],  valid_de_pipe[2]};
        post_frame_hsync_r  <=  {post_frame_hsync_r[0], matrix_frame_hsync};
        end
end
assign  post_frame_vsync    =   post_frame_vsync_r[1];
assign  post_frame_href     =   post_frame_href_r[1];
assign  post_frame_hsync    =   post_frame_hsync_r[1];

endmodule
