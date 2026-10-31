`timescale 1ns/1ns
// Qualify only weak CURRENT edges using previous-frame 4x4 occupancy.
// No delayed video, no old-edge drawing, and strong edges pass immediately.
// Twelve tiles occupy one 24-bit word: {this-frame OR, previous-frame OR}.
// Storage is supplied by the unused RGB line RAM in full binary views.
module Edge_Temporal_Guard #(
    parameter WIDTH=1280,HEIGHT=720,RAM_DEPTH=6400,
    parameter ADDR_BITS=$clog2(RAM_DEPTH)
)(
    input clk,rst_n,enable_i,epoch_i,vs_i,de_i,edge_i,strong_i,
    input [23:0] ram_data_i,
    output [ADDR_BITS-1:0] ram_read_addr_o,ram_write_addr_o,
    output [23:0] ram_write_data_o,
    output ram_write_o,
    output edge_o,history_valid_o
);
    localparam WORDS_PER_ROW=(WIDTH+47)/48;
    localparam HISTORY_WORDS=WORDS_PER_ROW*((HEIGHT+3)/4);
    localparam X_BITS=$clog2(WIDTH+1),Y_BITS=$clog2(HEIGHT+1);
    reg [X_BITS-1:0] x;
    reg [Y_BITS-1:0] y;
    reg [5:0] position;
    reg [ADDR_BITS-1:0] row_base,word_addr;
    reg [23:0] work_word;
    reg de_d,vs_d,enable_d,epoch_d,active,valid;
    wire config_change=(enable_i!=enable_d)||(epoch_i!=epoch_d);
    wire last_pixel=(x==WIDTH-1);
    wire last_word_pixel=(position==47)||last_pixel;
    wire last_tile_pixel=(position[1:0]==3)||last_pixel;
    wire last_tile_row=(y[1:0]==3)||(y==HEIGHT-1);
    wire [23:0] current_word=(position==0)?ram_data_i:work_word;
    // Rotate by one fixed pair after each tile. Avoid two large variable
    // bit-select/write multiplexers; the stored word layout is unchanged.
    wire previous_hit=current_word[0];
    wire accumulate=((y[1:0]==0)&&(position[1:0]==0)) ?
        edge_i : (current_word[1]||edge_i);
    wire [1:0] next_pair=(last_tile_pixel && last_tile_row) ?
        {1'b0,accumulate} : {accumulate,previous_hit};
    wire [23:0] patched_word={current_word[23:2],next_pair};
    wire [23:0] next_word=last_tile_pixel ?
        {patched_word[1:0],patched_word[23:2]} : patched_word;
    localparam LAST_TILES=((WIDTH%48)+3)/4;
    localparam REMAIN_ROTATE=(LAST_TILES==0)?0:24-2*LAST_TILES;
    wire [23:0] stored_word=(last_pixel && (REMAIN_ROTATE!=0)) ?
        ((next_word>>REMAIN_ROTATE)|(next_word<<(24-REMAIN_ROTATE))) : next_word;
    // Prefetch the next word one clock before its first active pixel.
    assign ram_read_addr_o=(active && de_i && last_word_pixel && !last_pixel) ?
        word_addr+1'b1 : word_addr;
    assign ram_write_addr_o=word_addr;
    assign ram_write_data_o=stored_word;
    assign ram_write_o=enable_i && active && de_i && last_word_pixel && !config_change;
    assign history_valid_o=valid;
    assign edge_o=edge_i && (!enable_i || !valid || !active || strong_i || previous_hit);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x<=0;y<=0;position<=0;row_base<=0;word_addr<=0;work_word<=0;
            de_d<=0;vs_d<=0;enable_d<=0;epoch_d<=0;active<=0;valid<=0;
        end else begin
            de_d<=de_i;vs_d<=vs_i;enable_d<=enable_i;epoch_d<=epoch_i;
            if(!enable_i || config_change) begin
                x<=0;y<=0;position<=0;row_base<=0;word_addr<=0;
                active<=0;valid<=0;
            end else if(vs_i && !vs_d) begin
                x<=0;y<=0;position<=0;row_base<=0;word_addr<=0;active<=1;
            end else if(active) begin
                if(de_i) begin
                    x<=x+1'b1;work_word<=next_word;
                    if(last_word_pixel) begin position<=0;word_addr<=word_addr+1'b1;end
                    else position<=position+1'b1;
                end
                if(de_d && !de_i) begin
                    x<=0;position<=0;
                    if(y==HEIGHT-1) begin active<=0;valid<=1;end
                    else y<=y+1'b1;
                    if(y[1:0]==3) begin
                        row_base<=row_base+WORDS_PER_ROW;
                        word_addr<=row_base+WORDS_PER_ROW;
                    end else word_addr<=row_base;
                end
            end
        end
    end
endmodule
