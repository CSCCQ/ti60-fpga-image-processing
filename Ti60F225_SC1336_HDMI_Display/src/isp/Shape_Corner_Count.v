`timescale 1ns/1ns
// Shared, bounded frame-blanking contour engine. The caller supplies one
// candidate's synchronous row-profile RAM (one clock read latency).
// 64 left points top->bottom + 64 right points bottom->top form a contour.
// Integer RDP removes small bends; short segments merge rounded corner pixels.
// Count turns above ~60 degrees: 3 triangle, 4 rectangle, 0 + roundness circle.
// No fallback class: missing profiles, overflow and timeout return unknown.
module Shape_Corner_Count #(
    parameter integer MAX_CYCLES = 4800,
    parameter integer DBG = 0
)(
    input clk, rst_n, start_i,
    input [11:0] y0_i, y1_i, size_i,
    input circle_ok_i,
    output reg [11:0] row_addr_o,
    input [25:0] row_data_i, // {left_valid,right_valid,left[11:0],right[11:0]}
    output reg busy_o, done_o,
    output reg [1:0] shape_o,
    output reg [5:0] corners_o
);
    localparam IDLE=0, INIT=1, SAMPLE_BEGIN=2, READ_REQ=3, READ_WAIT=4,
               READ_USE=5, SAMPLE_STORE=6, STACK_INIT=7, POP=8,
               SEG_LOAD=9, SEG_VECTOR=10, SEG_LIMIT=11, SCAN=12,
               SPLIT=13, COMPACT=14, MERGE_BEGIN=15, MERGE_LOAD=16,
               MERGE_CHECK=17, DELETE=18, COUNT_BEGIN=19, COUNT_LOAD=20,
               COUNT_VECTOR=21, COUNT_MUL=22, COUNT_SUM=23,
               COUNT_JUDGE=24, FINISH=25;
    reg [4:0] state;
    reg [12:0] cycles;
    reg [11:0] y0, y1, size, sy, step_y, rem_y, frac_y;
    reg [11:0] eps, min_edge;
    reg circle_ok, sample_valid, contour_ok;
    reg left_seen, right_seen;
    reg [11:0] last_left, last_right;
    reg [5:0] sample_idx;
    reg [2:0] neighbor;
    reg [11:0] sample_left, sample_right;
    // Synchronous dual-port contour RAM; point 128 is the closing duplicate.
    // Preserve all 128 samples and all 12 coordinate bits.
    reg [23:0] points [0:127];
    reg [23:0] close_point, point_qa, point_qb;
    reg point_a_close, point_b_close;
    wire [23:0] point_a_data = point_a_close ? close_point : point_qa;
    wire [23:0] point_b_data = point_b_close ? close_point : point_qb;
    reg [128:0] keep;
    // Two parity banks retain the complete 32-entry RDP stack in block RAM.
    // Consecutive pushes hit different banks; forward the new top for the
    // immediately following POP, preserving the original clock schedule.
    reg [15:0] stack_even [0:15], stack_odd [0:15];
    reg [15:0] stack_even_q, stack_odd_q, stack_forward_data;
    reg stack_read_odd, stack_forward;
    reg [5:0] stack_n, keep_n;
    reg [7:0] a, b, scan_idx, split_idx, compact_idx;
    reg [11:0] ax, ay, bx, by;
    reg signed [12:0] dx, dy;
    reg [26:0] limit, max_dist;
    // RDP stream: point read -> subtract -> multiply -> distance -> compare.
    wire [11:0] point_x=point_a_data[23:12], point_y=point_a_data[11:0];
    reg signed [12:0] vx, vy;
    reg signed [25:0] rdp_p1, rdp_p2;
    wire signed [26:0] rdp_cross = {rdp_p1[25],rdp_p1} - {rdp_p2[25],rdp_p2};
    reg [26:0] distance;
    reg [7:0] pos0, pos1, pos2, pos3;
    reg valid0, valid1, valid2, valid3;
    // Explicit synchronous read replicas share one write port.
    reg [23:0] poly_mem0 [0:31], poly_mem1 [0:31], poly_mem2 [0:31];
    reg [23:0] poly_q0, poly_q1, poly_q2;
    reg [5:0] poly_n, merge_idx, delete_idx, count_idx;
    reg [11:0] cx, cy;
    reg signed [12:0] ux, uy, tx, ty;
    reg signed [25:0] p1, p2, p3, p4;
    reg signed [26:0] turn_cross, dot;
    wire [26:0] abs_cross = turn_cross[26] ? -turn_cross : turn_cross;
    wire [29:0] cross4 = {1'b0, abs_cross, 2'b0};
    wire [29:0] dot7 = ({3'b0,dot} << 3) - {3'b0,dot};
    reg turn_sign, sign_valid, convex;
    reg [5:0] sharp_n;
    wire [12:0] ab_dx = (ax > bx) ? (ax-bx) : (bx-ax);
    wire [12:0] ab_dy = (ay > by) ? (ay-by) : (by-ay);
    wire [13:0] ab_len = {1'b0,ab_dx} + {1'b0,ab_dy};
    wire [12:0] next_frac = {1'b0,frac_y} + {1'b0,rem_y};
    wire signed [13:0] neighbor_y = $signed({2'b0,sy}) + $signed({11'd0,neighbor}) - 14'sd2;

    wire point_write = rst_n && state==SAMPLE_STORE && sample_valid;
    wire [11:0] store_left = (left_seen && sample_left<12'd4095) ? sample_left :
                              ((sample_idx!=0) ? last_left : sample_left);
    wire [11:0] store_right = (right_seen && sample_right!=0) ? sample_right :
                               ((sample_idx!=0) ? last_right : sample_right);
    wire point_read_a = state==SEG_LOAD || state==SCAN ||
                        (state==POP && stack_n==0) || state==COMPACT;
    wire [7:0] point_addr_a = state==SEG_LOAD ? a : state==SCAN ? scan_idx :
                              state==COMPACT ? compact_idx+8'd1 : 8'd0;
    wire [6:0] point_port_a = point_write ? {1'b0,sample_idx} : point_addr_a[6:0];
    wire [6:0] point_port_b = point_write ? (7'd127-{1'b0,sample_idx}) : b[6:0];
    always @(posedge clk) begin
        if(point_write) begin
            points[point_port_a] <= {store_left,sy};
            if(sample_idx==0) close_point <= {sample_left,sy};
        end
        begin // Unconditional RAM read also covers the write enable.
            point_qa <= points[point_port_a];
            point_a_close <= point_addr_a==8'd128;
        end
    end
    always @(posedge clk) begin
        if(point_write) points[point_port_b] <= {store_right,sy};
        begin
            point_qb <= points[point_port_b];
            point_b_close <= b==8'd128;
        end
    end
    wire compact_write = state==COMPACT && keep[compact_idx];
    wire delete_write = state==DELETE && delete_idx+1<poly_n;
    wire poly_write = rst_n && (compact_write || delete_write);
    wire [4:0] poly_waddr = compact_write ? poly_n[4:0] : delete_idx[4:0];
    wire [23:0] poly_wdata = compact_write ? point_a_data : poly_q0;
    reg [4:0] poly_raddr0, poly_raddr1, poly_raddr2;
    always @(*) begin
        poly_raddr0=0; poly_raddr1=0; poly_raddr2=0;
        case(state)
        MERGE_LOAD: begin
            poly_raddr0=merge_idx[4:0];
            poly_raddr1=(merge_idx+1==poly_n) ? 5'd0 : merge_idx[4:0]+5'd1;
        end
        MERGE_CHECK: poly_raddr0=merge_idx[4:0]+5'd2;
        DELETE: poly_raddr0=delete_idx[4:0]+5'd2;
        COUNT_LOAD: begin
            poly_raddr0=(count_idx==0) ? poly_n[4:0]-5'd1 : count_idx[4:0]-5'd1;
            poly_raddr1=count_idx[4:0];
            poly_raddr2=(count_idx+1==poly_n) ? 5'd0 : count_idx[4:0]+5'd1;
        end
        default: begin end
        endcase
    end
    always @(posedge clk) begin
        if(poly_write) begin
            poly_mem0[poly_waddr]<=poly_wdata;
            poly_mem1[poly_waddr]<=poly_wdata;
            poly_mem2[poly_waddr]<=poly_wdata;
        end
        poly_q0<=poly_mem0[poly_raddr0];
        poly_q1<=poly_mem1[poly_raddr1];
        poly_q2<=poly_mem2[poly_raddr2];
    end
    wire [11:0] pax=poly_q0[23:12], pay=poly_q0[11:0];
    wire [11:0] pbx=poly_q1[23:12], pby=poly_q1[11:0];
    wire [11:0] pcx=poly_q2[23:12], pcy=poly_q2[11:0];
    wire [12:0] poly_dx=(pax>pbx)?pax-pbx:pbx-pax;
    wire [12:0] poly_dy=(pay>pby)?pay-pby:pby-pay;
    wire [13:0] poly_len={1'b0,poly_dx}+{1'b0,poly_dy};

    wire stack_push = rst_n && (state==STACK_INIT ||
        (state==SPLIT && max_dist>limit && stack_n<=30 && keep_n<32));
    wire [4:0] stack_first = state==STACK_INIT ? 5'd0 : stack_n[4:0];
    wire [4:0] stack_second = stack_first+5'd1;
    wire [4:0] stack_read = stack_n[4:0]-5'd1;
    wire [15:0] stack_first_data = state==STACK_INIT ? {8'd0,8'd63} : {a,split_idx};
    wire [15:0] stack_second_data = state==STACK_INIT ? {8'd63,8'd128} : {split_idx,b};
    wire [15:0] stack_top = stack_forward ? stack_forward_data :
                            (stack_read_odd ? stack_odd_q : stack_even_q);
    always @(posedge clk) begin
        if(stack_push) begin
            stack_even[stack_first[0] ? stack_second[4:1] : stack_first[4:1]] <=
                stack_first[0] ? stack_second_data : stack_first_data;
            stack_odd[stack_first[0] ? stack_first[4:1] : stack_second[4:1]] <=
                stack_first[0] ? stack_first_data : stack_second_data;
        end
        stack_even_q<=stack_even[stack_read[4:1]];
        stack_odd_q<=stack_odd[stack_read[4:1]];
        stack_read_odd<=stack_read[0];
        stack_forward<=stack_push;
        stack_forward_data<=stack_second_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; busy_o<=0; done_o<=0; shape_o<=0; corners_o<=0;
            row_addr_o<=0; cycles<=0;
            valid0<=0; valid1<=0; valid2<=0; valid3<=0;
        end else begin
            done_o<=0;
            if(busy_o) cycles<=cycles+1'b1;
            case(state)
            IDLE: if(start_i) begin
                y0<=y0_i; y1<=y1_i; size<=size_i;
                circle_ok<=circle_ok_i; cycles<=0; contour_ok<=0;
                left_seen<=0; right_seen<=0; last_left<=0; last_right<=0;
                sharp_n<=0; poly_n<=0; convex<=0;
                busy_o<=1; shape_o<=0; corners_o<=0; state<=INIT;
            end
            INIT: begin
                step_y<=(y1-y0)/63; rem_y<=(y1-y0)%63;
                // Camera bow and a one-pixel Canny staircase create a few
                // extra micro-turns. A slightly wider integer tolerance
                // absorbs those while leaving true corner turns intact.
                eps<=(size<120) ? 12'd3 : size/30;
                // Merge short staircase artifacts near a true corner. The
                // 1/8 scale still preserves edges of the smallest accepted
                // shapes while removing the 20-30 pixel split seen on
                // strongly rotated outlines.
                min_edge<=(size/8 < 8) ? 12'd8 : size/8;
                sy<=y0; frac_y<=0; sample_idx<=0; state<=SAMPLE_BEGIN;
            end
            SAMPLE_BEGIN: begin
                sample_left<=4095; sample_right<=0; sample_valid<=0;
                left_seen<=0; right_seen<=0; neighbor<=0; state<=READ_REQ;
            end
            READ_REQ: begin
                if(neighbor_y < $signed({2'b0,y0}) || neighbor_y > $signed({2'b0,y1})) begin
                    if(neighbor==4) state<=SAMPLE_STORE;
                    else neighbor<=neighbor+1'b1;
                end else begin
                    row_addr_o<=neighbor_y[11:0]; state<=READ_WAIT;
                end
            end
            READ_WAIT: state<=READ_USE;
            READ_USE: begin
                if(row_data_i[25]) begin
                    sample_valid<=1;
                    left_seen<=1;
                    if(row_data_i[23:12]<sample_left) sample_left<=row_data_i[23:12];
                end
                if(row_data_i[24]) begin
                    sample_valid<=1;
                    right_seen<=1;
                    if(row_data_i[11:0]>sample_right) sample_right<=row_data_i[11:0];
                end
                if(neighbor==4) state<=SAMPLE_STORE;
                else begin neighbor<=neighbor+1'b1; state<=READ_REQ; end
            end
            SAMPLE_STORE: begin
                if(DBG && sample_idx<8) $display("  sample %0d y=%0d valid=%0d L=%0d R=%0d",sample_idx,sy,sample_valid,sample_left,sample_right);
                if(!sample_valid) begin shape_o<=0; state<=FINISH; end
                else begin
                    // A broken row can contain only one side. Hold the last
                    // known endpoint for the missing side so it cannot turn
                    // into x=0/4095 outliers in the contour.
                    if(left_seen && sample_left<12'd4095) last_left<=sample_left;
                    if(right_seen && sample_right!=0) last_right<=sample_right;
                    if(sample_idx==63) state<=STACK_INIT;
                    else begin
                        sample_idx<=sample_idx+1'b1;
                        sy<=sy+step_y+((next_frac>=63) ? 12'd1 : 12'd0);
                        frac_y<=(next_frac>=63) ? next_frac-63 : next_frac;
                        state<=SAMPLE_BEGIN;
                    end
                end
            end
            STACK_INIT: begin
                keep<= (129'd1 << 128) | (129'd1 << 63) | 129'd1;
                keep_n<=3; stack_n<=2;
                state<=POP;
            end
            POP: begin
                if(stack_n==0) begin compact_idx<=0; poly_n<=0; state<=COMPACT; end
                else begin
                    a<=stack_top[15:8]; b<=stack_top[7:0];
                    stack_n<=stack_n-1'b1; state<=SEG_LOAD;
                end
            end
            SEG_LOAD: begin
                if(b<=a+1'b1) state<=POP; else state<=SEG_VECTOR;
            end
            SEG_VECTOR: begin
                ax<=point_a_data[23:12]; ay<=point_a_data[11:0];
                bx<=point_b_data[23:12]; by<=point_b_data[11:0];
                dx<=$signed({1'b0,point_b_data[23:12]})-$signed({1'b0,point_a_data[23:12]});
                dy<=$signed({1'b0,point_b_data[11:0]})-$signed({1'b0,point_a_data[11:0]});
                state<=SEG_LIMIT;
            end
            SEG_LIMIT: begin
                limit<=eps*ab_len; max_dist<=0; split_idx<=a+1'b1;
                scan_idx<=a+1'b1; valid0<=0; valid1<=0; valid2<=0; valid3<=0;
                state<=SCAN;
            end
            SCAN: begin
                valid0<=(scan_idx<b); pos0<=scan_idx;
                valid1<=valid0; pos1<=pos0;
                vx<=$signed({1'b0,point_x})-$signed({1'b0,ax});
                vy<=$signed({1'b0,point_y})-$signed({1'b0,ay});
                valid2<=valid1; pos2<=pos1;
                rdp_p1<=dx*vy; rdp_p2<=dy*vx;
                valid3<=valid2; pos3<=pos2;
                distance<=rdp_cross[26] ? -rdp_cross : rdp_cross;
                if(valid3 && distance>max_dist) begin max_dist<=distance; split_idx<=pos3; end
                scan_idx<=scan_idx+1'b1;
                if(scan_idx==b+8'd4) state<=SPLIT;
            end
            SPLIT: begin
                if(max_dist>limit) begin
                    if(stack_n>30 || keep_n>=32) begin shape_o<=0; state<=FINISH; end
                    else begin
                        keep[split_idx]<=1; keep_n<=keep_n+1'b1;
                        stack_n<=stack_n+2; state<=POP;
                    end
                end else state<=POP;
            end
            COMPACT: begin
                if(keep[compact_idx]) begin
                    poly_n<=poly_n+1'b1;
                end
                if(compact_idx==127) state<=MERGE_BEGIN;
                else compact_idx<=compact_idx+1'b1;
            end
            MERGE_BEGIN: begin merge_idx<=0; state<=MERGE_LOAD; end
            MERGE_LOAD: begin
                state<=MERGE_CHECK;
            end
            MERGE_CHECK: begin
                if(poly_n>3 && poly_len<min_edge) begin
                    // Last->first: keep first and remove last.
                    delete_idx<=(merge_idx+1==poly_n) ? merge_idx : merge_idx+1'b1;
                    state<=DELETE;
                end else if(merge_idx+1==poly_n) state<=COUNT_BEGIN;
                else begin merge_idx<=merge_idx+1'b1; state<=MERGE_LOAD; end
            end
            DELETE: begin
                if(delete_idx+1<poly_n) begin
                    delete_idx<=delete_idx+1'b1;
                end else begin poly_n<=poly_n-1'b1; state<=MERGE_BEGIN; end
            end
            COUNT_BEGIN: begin
                sharp_n<=0; count_idx<=0; convex<=1; sign_valid<=0;
                contour_ok<=(poly_n>=3);
                if(poly_n<3) begin shape_o<=0; state<=FINISH; end
                else state<=COUNT_LOAD;
            end
            COUNT_LOAD: begin
                state<=COUNT_VECTOR;
            end
            COUNT_VECTOR: begin
                ux<=$signed({1'b0,pbx})-$signed({1'b0,pax});
                uy<=$signed({1'b0,pby})-$signed({1'b0,pay});
                tx<=$signed({1'b0,pcx})-$signed({1'b0,pbx});
                ty<=$signed({1'b0,pcy})-$signed({1'b0,pby}); state<=COUNT_MUL;
            end
            COUNT_MUL: begin
                p1<=ux*ty; p2<=uy*tx; p3<=ux*tx; p4<=uy*ty; state<=COUNT_SUM;
            end
            COUNT_SUM: begin
                turn_cross<={p1[25],p1}-{p2[25],p2};
                dot<={p3[25],p3}+{p4[25],p4}; state<=COUNT_JUDGE;
            end
            COUNT_JUDGE: begin
                if((ux!=0 || uy!=0) && (tx!=0 || ty!=0) &&
                   (dot<=0 || cross4>dot7)) sharp_n<=sharp_n+1'b1;
                if(turn_cross!=0) begin
                    if(!sign_valid) begin sign_valid<=1; turn_sign<=turn_cross[26]; end
                    else if(turn_sign!=turn_cross[26]) convex<=0;
                end
                if(count_idx+1==poly_n) state<=FINISH;
                else begin count_idx<=count_idx+1'b1; state<=COUNT_LOAD; end
            end
            FINISH: begin
                corners_o<=sharp_n;
                if(contour_ok && convex && sharp_n==3) shape_o<=3;
                else if(contour_ok && convex && sharp_n==4) shape_o<=1;
                else if(contour_ok && convex && sharp_n==0 && poly_n>=6 && circle_ok) shape_o<=2;
                else shape_o<=0;
                if(DBG) begin
                    $display("[corners] vertices=%0d sharp=%0d convex=%0d cycles=%0d",poly_n,sharp_n,convex,cycles);
                    for(scan_idx=0; scan_idx<poly_n; scan_idx=scan_idx+1)
                        $display("  p%0d=(%0d,%0d)",scan_idx,poly_mem0[scan_idx][23:12],poly_mem0[scan_idx][11:0]);
                end
                busy_o<=0; done_o<=1; state<=IDLE;
            end
            default: begin busy_o<=0; state<=IDLE; end
            endcase
            // A malformed/noisy contour must never consume the next active frame.
            if(busy_o && cycles>=MAX_CYCLES-1) begin
                shape_o<=0; corners_o<=0; busy_o<=0; done_o<=1; state<=IDLE;
            end
        end
    end
endmodule
