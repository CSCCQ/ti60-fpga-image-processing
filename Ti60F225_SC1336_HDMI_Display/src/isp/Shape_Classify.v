`timescale 1ns/1ns
// Shape classification by significant contour corners (3/4/0).
// Streaming run/chain tracking records left/right endpoints in row RAM.
// During frame blanking, one shared Shape_Corner_Count engine simplifies
// each closed contour and counts sharp turns. Unknown contours are rejected.
// ROI affects recognition only; edge_f_o remains the full display edge stream.
module Shape_Classify #(
    parameter           IMG_HDISP  = 1280,
    parameter           IMG_VDISP  = 720,

    //  ---- ???? ----
    parameter   [11:0]  GAPX       = 12'd3,     //  ?????????????
    parameter   [11:0]  GAPY       = 12'd5,     //  ??????5 = ??? 4 ??
    parameter   [11:0]  EXT_MAX    = 12'd32,    //  ???????????????
    parameter integer   RUN_MIN    = 1,         //  ???????????
    parameter   [11:0]  BORDER     = 12'd24,    //  ?????????
    parameter   [11:0]  ROI_X_MIN  = 12'd0,     //  ?? ROI ???????????
    parameter   [11:0]  ROI_X_MAX  = 12'd4095,  //  ?? ROI ???????????
    parameter integer   SPK_MIN    = 1,         //  8 ??????????????
    parameter integer   ENABLE_STRENGTH = 0,
    parameter integer   NBLK       = 8,         //  ???????
    parameter integer   HOLD_MISSES = 0,         //  ??????????????0=?????

    //  ---- ???? ----
    parameter   [15:0]  MIN_PIX    = 16'd250,   //  ???????
    parameter   [31:0]  MIN_AREA   = 32'd4000,  //  ??"????"(????)??
    parameter   [11:0]  MIN_SIZE   = 12'd24,    //  ???????
    parameter   [11:0]  MAX_W      = 12'd1120,  //  ????????7/8 ???
    parameter   [11:0]  MAX_H      = 12'd630,
    parameter   [11:0]  LONG_RUN   = 12'd24,    //  ?????????????????
    parameter   [31:0]  EVICT_AREA = 32'd512,   //  ?????"????"??????

    parameter   [11:0]  QMASK      = 12'h003,   //  ?????? 2 ??? = ? 4 ??????

    parameter integer   DBG        = 0
)(
    input               clk,
    input               rst_n,

    input               vs_i,
    input               de_i,
    input               edge_i,
    input               strong_i,

    //  ---- ?????????NBLK ??????????----
    output reg  [NBLK-1:0]      vld_o,          //  ????????
    output reg  [6*NBLK-1:0]    corners_o,      // diagnostic sharp-corner counts
    output reg  [2*NBLK-1:0]    shape_o,        //  ?? 2bit?0?? 1?? 2? 3??
    output reg  [12*NBLK-1:0]   bx0_o,
    output reg  [12*NBLK-1:0]   by0_o,
    output reg  [12*NBLK-1:0]   bx1_o,
    output reg  [12*NBLK-1:0]   by1_o,

    //  ---- ?????? = edge_i ?? 1 ? + 3 ??----
    output              edge_f_o,
    output              edge_center_o, // unfiltered centre; same timing as edge_f_o
    output              strong_center_o,
    output              sel_o,                  //  ???????????
    output      [1:0]   sel_shape_o,            //  ????????????
    output              vs_f_o,
    output              de_f_o
);

    //==================================================================
    //  0) ????
    //==================================================================
    wire        spk_vs, spk_de;
    localparam SPK_WIDTH=ENABLE_STRENGTH ? 2 : 1;
    wire [SPK_WIDTH-1:0] s11, s12, s13, s21, s22, s23, s31, s32, s33;

    Matrix_Generate_3X3 #(
        .DATA_WIDTH (SPK_WIDTH),
        .IMG_HDISP  (IMG_HDISP),
        .IMG_VDISP  (IMG_VDISP)
    ) u_spk_win (
        .clk                (clk),
        .rst_n              (rst_n),
        .per_frame_vsync    (vs_i),
        .per_frame_href     (de_i),
        .per_frame_hsync    (1'b0),
        .per_img_Y          (ENABLE_STRENGTH ? {strong_i,edge_i} : {1'b0,edge_i}),
        .matrix_frame_vsync (spk_vs),
        .matrix_frame_href  (spk_de),
        .matrix_frame_hsync (),
        .matrix_p11(s11), .matrix_p12(s12), .matrix_p13(s13),
        .matrix_p21(s21), .matrix_p22(s22), .matrix_p23(s23),
        .matrix_p31(s31), .matrix_p32(s32), .matrix_p33(s33)
    );

    wire [3:0] spk_nbr = {3'd0, s11[0]} + {3'd0, s12[0]} + {3'd0, s13[0]} +
                         {3'd0, s21[0]} + {3'd0, s23[0]} +
                         {3'd0, s31[0]} + {3'd0, s32[0]} + {3'd0, s33[0]};

    wire       edge_new = s22[0] && (spk_nbr >= SPK_MIN);
    wire       de_f     = spk_de;
    wire       vs_f     = spk_vs;

    assign     edge_f_o = de_f && edge_new;
    assign     edge_center_o = de_f && s22[0];
    assign     strong_center_o = ENABLE_STRENGTH ? (de_f && s22[SPK_WIDTH-1]) : 1'b0;
    assign     vs_f_o   = vs_f;
    assign     de_f_o   = de_f;

    //==================================================================
    //  1) ????
    //==================================================================
    reg [11:0]  xcnt, ycnt;
    reg         de_d, vs_d;
    reg         row_end_r;

    //  ROI ?????????/???edge_f_o ????????????
    //  ???????????????? ROI ???
    wire roi_x   = (xcnt >= ROI_X_MIN) && (xcnt <= ROI_X_MAX);
    wire in_area = roi_x && (xcnt >= BORDER) && (xcnt < (IMG_HDISP - BORDER)) &&
                   (ycnt >= BORDER) && (ycnt < (IMG_VDISP - BORDER));

    //==================================================================
    //  2) ?????
    //==================================================================
    reg [11:0]  rs, re;
    reg [11:0]  run_len;
    reg [11:0]  run_gap;
    reg         run_on;
    wire        edge_active = de_f && edge_new && in_area;
    // Keep a run open across a very short Canny hole.  The camera's bowed
    // horizontal edge commonly has a one-pixel gap at its midpoint; closing
    // immediately there creates two candidates and exhausts the NBLK slots.
    // A gap longer than GAPX still terminates the run, so separate edges do
    // not get joined.
    wire        run_end = run_on &&
                          ((!de_f) || (de_f && !in_area) ||
                           (!edge_active && (run_gap >= GAPX)));
    wire        long_run = (run_len >= LONG_RUN);

    //==================================================================
    //  3) ?
    //==================================================================
    // Stored coordinates are active-frame coordinates; keep full-width
    // arithmetic below, but do not implement unused high register bits.
    localparam integer X_BITS=(IMG_HDISP>1)?$clog2(IMG_HDISP):1;
    localparam integer Y_BITS=(IMG_VDISP>1)?$clog2(IMG_VDISP):1;
    localparam integer ROW_BITS=$clog2(IMG_HDISP+1);
    reg [X_BITS-1:0] c_x0[0:NBLK-1], c_x1[0:NBLK-1];
    reg [Y_BITS-1:0] c_y0[0:NBLK-1], c_y1[0:NBLK-1];
    // Each pixel/run belongs to one candidate; a candidate's accumulated
    // pixels and row spans cannot exceed the complete active frame area.
    localparam integer STAT_BITS=$clog2(IMG_HDISP*IMG_VDISP+1);
    reg [STAT_BITS-1:0] c_pix[0:NBLK-1], c_sum[0:NBLK-1];
    reg [X_BITS-1:0] pv_min[0:NBLK-1], pv_max[0:NBLK-1];
    reg [Y_BITS-1:0] pv_y[0:NBLK-1];
    reg         pv_v [0:NBLK-1];
    reg [X_BITS-1:0] pd_min[0:NBLK-1], pd_max[0:NBLK-1];
    reg [Y_BITS-1:0] pd_y[0:NBLK-1];
    reg [ROW_BITS-1:0] pd_cnt[0:NBLK-1];
    reg         pd_v [0:NBLK-1];
    reg         v    [0:NBLK-1];
    // ?????????????????????????????
    // ?????????????????
    reg [3:0]   miss_cnt [0:NBLK-1];

    //  ?? 8 ???????pv = ?? + ? 7 ?????
    //  ????????????????????????????
    //  ????????????GAPX ? 3?????????????
    //  ?"???????"??????????????????
    // Exact eight-sample sliding extrema, factored into 2/4/8-sample
    // windows. Seven words still preserve the complete window, while
    // three comparators replace seven per candidate and per extremum.
    // Words: x[-1], min2[-1,-2], min4[-1,-2,-3,-4].
    reg [X_BITS-1:0] hist_min[0:NBLK-1][0:6];
    reg [X_BITS-1:0] hist_max[0:NBLK-1][0:6];

    integer j;

    integer     i, k;
    reg [NBLK-1:0] mhit;
    wire        any_hit;
    //  ????? one-hot ?????????????? pd_*?
    //  ?????????? pd_min/pd_max ??????????
    //  ???????? clk_pixel ????????
    reg [NBLK-1:0]  hit_sel;
    reg [3:0]   slot_i;
    reg         slot_free, slot_found;
    reg [3:0]   smallest_i;
    reg         have_evict;
    reg [3:0]   evict_i_r;
    reg         evict_v_r;
    reg [11:0]  span_now;
    // Balanced minimum tree: the old serial minimum loop cascaded eight
    // area compares/muxes and exceeded the pixel-clock timing budget.
    localparam integer EVICT_LEAVES = 1 << $clog2(NBLK);
    wire [36:0] evict_tree [1:2*EVICT_LEAVES-1];
    function [36:0] smaller;
        input [36:0] a_min, b_min;
        begin
            if(!a_min[36]) smaller=b_min;
            else if(!b_min[36]) smaller=a_min;
            else if(a_min[31:0]<b_min[31:0] ||
                    (a_min[31:0]==b_min[31:0] && a_min[35:32]<b_min[35:32])) smaller=a_min;
            else smaller=b_min;
        end
    endfunction

    // Merge two row-profile samples.  This is used only during the blanking
    // time classifier, so the extra muxing is not on the pixel-clock path.
    // A level rectangle can lose its top/bottom Canny edge and leave the two
    // vertical sides as separate chains.  Their profiles still contain the
    // complete left/right information when read together.
    function [25:0] merge_profile;
        input [25:0] da;
        input [25:0] db;
        reg lv, rv;
        reg [11:0] lx, rx;
        begin
            lv = da[25] | db[25];
            rv = da[24] | db[24];
            if(da[25] && db[25]) lx = (da[23:12] < db[23:12]) ? da[23:12] : db[23:12];
            else if(da[25]) lx = da[23:12];
            else lx = db[23:12];
            if(da[24] && db[24]) rx = (da[11:0] > db[11:0]) ? da[11:0] : db[11:0];
            else if(da[24]) rx = da[11:0];
            else rx = db[11:0];
            merge_profile = {lv,rv,lx,rx};
        end
    endfunction
    genvar et;
    generate for(et=0; et<EVICT_LEAVES; et=et+1) begin : evict_leaves
        if(et<NBLK) begin
            wire eligible = v[et] && (long_run ||
                (!pd_v[et] && !(pv_v[et] && ycnt<=pv_y[et]+GAPY) && c_sum[et]<EVICT_AREA));
            localparam [3:0] INDEX=et;
            assign evict_tree[EVICT_LEAVES+et]={eligible,INDEX,{{(32-STAT_BITS){1'b0}},c_sum[et]}};
        end else assign evict_tree[EVICT_LEAVES+et]=37'd0;
    end
    for(et=1; et<EVICT_LEAVES; et=et+1) begin : evict_nodes
        assign evict_tree[et]=smaller(evict_tree[2*et],evict_tree[2*et+1]);
    end endgenerate

    //  ????????????????????????
    //  ????? ± EXT_MAX ???
    //  ?????????????????? pd ????? pd ???
    //  ??????????????? pd_max -> mhit -> pd_max ??????
    //  ??????????????
    //  EXT_MAX ???????????? 200 ??????????????
    //  ????????????????????????????????
    //  ??????????
    //  ??? ycnt > pv_y ??? ycnt >= pv_y?????????????
    //  ?????????????????"????"??????????
    //  ???? EXT_MAX ??? GAPX ?? ?????????????????
    //  ?? 35°/45° ??????? BORDER ???????????? GAPX
    //  ???????????????????
    // With GAPX>=3, run-end events are at least five clocks apart.
    // Four clocks suffice to test all eight candidates using two lanes.
    // Capture allocation and geometry at the original run-end clock.
    localparam integer SERIAL_MATCH=(GAPX>=3 && BORDER>=8 && NBLK<=8);
    reg match_busy;
    reg [3:0] match_base, match_slot;
    reg match_slot_found;
    reg [NBLK-1:0] match_mask;
    reg [11:0] match_rs,match_re,match_len,match_y;
    wire match_commit=SERIAL_MATCH ? (match_busy && match_base+2>=NBLK) : run_end;
    wire [11:0] submit_rs=SERIAL_MATCH?match_rs:rs;
    wire [11:0] submit_re=SERIAL_MATCH?match_re:re;
    wire [11:0] submit_len=SERIAL_MATCH?match_len:run_len;
    wire [11:0] submit_y=SERIAL_MATCH?match_y:ycnt;
    wire [3:0] submit_slot=SERIAL_MATCH?match_slot:slot_i;
    wire submit_slot_found=SERIAL_MATCH?match_slot_found:slot_found;
    function candidate_match;
        input [3:0] mi;
        input [11:0] s,e,n,y;
        reg [11:0] mn,mx,lo,hi,limit_lo,gap,ext;
        begin
            candidate_match=0;
            mn=0; mx=0; lo=0; hi=0; limit_lo=0; gap=GAPX; ext=EXT_MAX;
            if(mi<NBLK && v[mi] && ((pv_v[mi] && y>=pv_y[mi] && y<=pv_y[mi]+GAPY) ||
                                   (pd_v[mi] && pd_y[mi]==y))) begin
                mn=pv_min[mi]; mx=pv_max[mi];
                if(pd_v[mi] && pd_y[mi]==y) begin
                    if(pd_min[mi]<mn) mn=pd_min[mi];
                    if(pd_max[mi]>mx) mx=pd_max[mi];
                end
                if(pv_y[mi]==y) gap=EXT_MAX;
                if(n>=LONG_RUN && y<=c_y0[mi]+12'd32 && pv_max[mi]-pv_min[mi]<12'd256)
                    ext=(n+EXT_MAX>12'd96)?n+EXT_MAX:12'd96;
                limit_lo=(pv_min[mi]>EXT_MAX)?pv_min[mi]-EXT_MAX:12'd0;
                lo=(mn>limit_lo)?mn:limit_lo;
                hi=(mx<pv_max[mi]+EXT_MAX)?mx:pv_max[mi]+EXT_MAX;
                if(e+gap>=lo && s<=hi+gap && s+ext>=mn && e<=mx+ext)
                    candidate_match=1;
            end
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            match_busy<=0; match_base<=0; match_mask<=0;
            match_rs<=0; match_re<=0; match_len<=0; match_y<=0;
            match_slot<=0; match_slot_found<=0;
        end else if(SERIAL_MATCH) begin
            if(run_end) begin
                match_busy<=1; match_base<=0; match_mask<=0;
                match_rs<=rs; match_re<=re; match_len<=run_len; match_y<=ycnt;
                match_slot<=slot_i; match_slot_found<=slot_found;
            end else if(match_busy) begin
                if(match_commit) match_busy<=0;
                else begin match_base<=match_base+2; match_mask<=mhit; end
            end
        end
    end

    reg [11:0]  w_lo, w_hi, pdmn, pdmx, elo, gap_x, start_ext;
    integer match_i;
    always @(*)
    begin
        if(SERIAL_MATCH) begin
            mhit=match_mask;
            for(match_i=0;match_i<2;match_i=match_i+1)
                if(match_base+match_i<NBLK)
                    mhit[match_base+match_i]=candidate_match(match_base+match_i,match_rs,match_re,match_len,match_y);
        end else begin
        mhit = {NBLK{1'b0}};
        for(match_i = 0; match_i < NBLK; match_i = match_i + 1)
        begin
            pdmn=0; pdmx=0; elo=0;
            w_lo  = 12'd0;
            w_hi  = 12'd0;
            gap_x = GAPX;
            start_ext = EXT_MAX;
            if(v[match_i] && ((pv_v[match_i] &&
               (ycnt >= pv_y[match_i]) && (ycnt <= pv_y[match_i] + GAPY)) ||
               (pd_v[match_i] && (pd_y[match_i] == ycnt))))
            begin
                //  ???????????????????? pd_min/pd_max
                //  ?????????????????????????
                //  ? pd ?????????????????????????
                pdmn = pv_min[match_i];
                pdmx = pv_max[match_i];
                if(pd_v[match_i] && (pd_y[match_i] == ycnt)) begin
                    if(pd_min[match_i] < pdmn) pdmn = pd_min[match_i];
                    if(pd_max[match_i] > pdmx) pdmx = pd_max[match_i];
                end
                //  ???????????? EXT_MAX
                if(pv_y[match_i] == ycnt) gap_x = EXT_MAX;
                // Same-row segments use the already expanded pd envelope;
                // otherwise the old pv limit clips the second half of a
                // bowed horizontal edge back to the first segment.
                if(pd_v[match_i] && (pd_y[match_i] == ycnt)) begin
                    w_lo = (pdmn > gap_x) ? (pdmn-gap_x) : 12'd0;
                    w_hi = (pdmx + gap_x < 12'd4095) ? (pdmx+gap_x) : 12'd4095;
                end
                // A bowed top edge starts at its center, then opens quickly
                // into two horizontal runs. Permit that initial opening,
                // while retaining the normal expansion limit thereafter.
                if(long_run && ycnt<=c_y0[match_i]+12'd32 && pv_max[match_i]-pv_min[match_i]<12'd256)
                    // At the vertex of a bowed top edge the next scanline
                    // can open by roughly half the run length.  Scale the
                    // startup window with that run instead of assuming a
                    // fixed 96-pixel opening.
                    start_ext=(run_len+EXT_MAX > 12'd96) ?
                              (run_len+EXT_MAX) : 12'd96;
                elo  = (pv_min[match_i] > EXT_MAX) ? (pv_min[match_i] - EXT_MAX) : 12'd0;
                w_lo = (pdmn > elo) ? pdmn : elo;
                w_hi = (pdmx < (pv_max[match_i] + EXT_MAX)) ? pdmx : (pv_max[match_i] + EXT_MAX);
                //  ? ??????? = ????? ? ???????????
                //  ? ??????????????????? 200 ?????
                //     ?????? 1 ????????"??"???????
                //     ?????????????????????????
                //     ?/???????????D² ?????????????
                if((re + gap_x >= w_lo) && (rs <= w_hi + gap_x) &&
                   ((rs + start_ext) >= pdmn) && (re <= (pdmx + start_ext)))
                    mhit[match_i] = 1'b1;
            end
        end
        end
    end
    assign any_hit = |mhit;

    //  ????????????????????????? c_sum
    //  ?????????? c_sum ?????????????????
    //  ?? c_sum -> hit_sel -> c_sum ???????????????
    //  ????????????????? c_sum ???????
    integer hit_k;
    always @(*)
    begin
        hit_sel   = {NBLK{1'b0}};
        //  ????????????????????????
        for(hit_k = 0; hit_k < NBLK; hit_k = hit_k + 1)
            if(mhit[hit_k] && (hit_sel == {NBLK{1'b0}}))
            begin
                hit_sel[hit_k] = 1'b1;
            end
    end

    integer slot_k;
    always @(*)
    begin
        slot_i      = 4'd0;
        slot_free   = 1'b0;
        slot_found  = 1'b0;
        smallest_i  = evict_tree[1][35:32];
        have_evict  = evict_tree[1][36];
        for(slot_k = NBLK-1; slot_k >= 0; slot_k = slot_k - 1)
        begin
            if(!v[slot_k] && !slot_free)
            begin
                slot_i     = slot_k[3:0];
                slot_free  = 1'b1;
                slot_found = 1'b1;
            end
            //  ??????????????????????????
            //  ?????????? c_sum ??????? CE?
            //    ??(>=LONG_RUN) : ??????
            //    ???          : ???"????"????????? +
            //                      ???? GAPY ? + ??????
            //  ???"??"?"?????????"??????????????
            //  ?????????????????????????????
        end
        if(!slot_found && evict_v_r)
        begin
            slot_i     = evict_i_r;
            slot_found = 1'b1;
        end
    end

    // One row-profile RAM per candidate; invalid rows overwrite old frames.
    // A newly allocated chain already contains its first run in c_x0/c_x1,
    // so merge that run with pd rather than dropping the initial top edge.
    wire [12*NBLK-1:0] row_left, row_right;
    wire [NBLK-1:0] row_valid;
    wire [11:0] profile_addr;
    wire [25:0] profile_data [0:NBLK-1];



    // Finish row commits before the next in-ROI run can end. Narrow-border
    // parameter configurations retain the original parallel implementation.
    localparam integer SERIAL_ROWS=(BORDER>=2*NBLK+4);
    localparam integer SLOT_BITS=(NBLK>1)?$clog2(NBLK):1;
    reg row_busy, row_phase, frame_pending;
    reg [3:0] row_slot;
    reg [11:0] commit_y;
    reg [1:0] hist_pos[0:NBLK-1];
    reg [2:0] hist_fill[0:NBLK-1];
    reg [2*X_BITS-1:0] hist2_ram[0:2*NBLK-1];
    reg [2*X_BITS-1:0] hist4_ram[0:4*NBLK-1];
    reg [2*X_BITS-1:0] hist2_read, hist4_read;
    wire [SLOT_BITS:0] hist2_addr={row_slot[SLOT_BITS-1:0],hist_pos[row_slot][0]};
    wire [SLOT_BITS+1:0] hist4_addr={row_slot[SLOT_BITS-1:0],hist_pos[row_slot]};
    // Delay the 2-sample extrema by two updates, and the 4-sample extrema
    // by four updates, using two small circular RAMs. Unfilled entries use
    // the chain's initial endpoint, exactly matching the original padding.
    wire [11:0] rc_old2min=(hist_fill[row_slot]>=2)?hist2_read[2*X_BITS-1:X_BITS]:hist_min[row_slot][6];
    wire [11:0] rc_old2max=(hist_fill[row_slot]>=2)?hist2_read[X_BITS-1:0]:hist_max[row_slot][6];
    wire [11:0] rc_old4min=(hist_fill[row_slot]>=4)?hist4_read[2*X_BITS-1:X_BITS]:hist_min[row_slot][6];
    wire [11:0] rc_old4max=(hist_fill[row_slot]>=4)?hist4_read[X_BITS-1:0]:hist_max[row_slot][6];
    wire rc_valid=v[row_slot] && pd_v[row_slot];
    wire rc_first=c_y0[row_slot]==commit_y;
    wire [11:0] rc_left=rc_first ?
        ((pd_v[row_slot] && pd_min[row_slot]<c_x0[row_slot])?pd_min[row_slot]:c_x0[row_slot]):pd_min[row_slot];
    wire [11:0] rc_right=rc_first ?
        ((pd_v[row_slot] && pd_max[row_slot]>c_x1[row_slot])?pd_max[row_slot]:c_x1[row_slot]):pd_max[row_slot];
    wire [12:0] rc_mid=(c_x0[row_slot]+c_x1[row_slot]) >> 1;
    wire [12:0] rc_profile_span=(rc_right>=rc_left)?rc_right-rc_left:13'd0;
    wire rc_profile_valid=v[row_slot] && (rc_first || pd_v[row_slot]);
    wire rc_center=(rc_left<=rc_mid+12'd8) && (rc_right+12'd8>=rc_mid) &&
                   rc_profile_span<=13'd8;
    wire rc_two_sides=rc_profile_span>13'd8 || rc_profile_span>pd_cnt[row_slot];
    wire rc_left_valid=rc_profile_valid && (rc_two_sides || rc_left<=rc_mid || rc_center);
    wire rc_right_valid=rc_profile_valid && (rc_two_sides || rc_right>=rc_mid || rc_center);
    wire [25:0] rc_profile={rc_left_valid,rc_right_valid,rc_left,rc_right};

    genvar g;
    generate for(g=0; g<NBLK; g=g+1) begin : profiles
        wire first_row = v[g] && c_y0[g]==ycnt;
        assign row_valid[g] = v[g] && (first_row || pd_v[g]);
        assign row_left[g*12 +: 12] = first_row ?
            ((pd_v[g] && pd_min[g]<c_x0[g]) ? pd_min[g] : c_x0[g]) : pd_min[g];
        assign row_right[g*12 +: 12] = first_row ?
            ((pd_v[g] && pd_max[g]>c_x1[g]) ? pd_max[g] : c_x1[g]) : pd_max[g];
        reg [25:0] rows [0:IMG_VDISP-1];
        reg [25:0] read_data;
        wire [12:0] row_mid = (c_x0[g]+c_x1[g]) >> 1;
        wire [12:0] row_span = row_right[g*12 +: 12] >= row_left[g*12 +: 12] ?
                                row_right[g*12 +: 12]-row_left[g*12 +: 12] : 13'd0;
        wire row_center = (row_left[g*12 +: 12] <= row_mid + 12'd8) &&
                          (row_right[g*12 +: 12] + 12'd8 >= row_mid) &&
                          (row_span <= 13'd8);
        // Two disjoint runs are left/right sides even when both lie to the
        // right of the global box center near a rotated bottom corner.
        wire two_sides = row_span>13'd8 || row_span>pd_cnt[g];
        wire row_left_v = row_valid[g] &&
                          (two_sides || (row_left[g*12 +: 12] <= row_mid) || row_center);
        wire row_right_v = row_valid[g] &&
                           (two_sides || (row_right[g*12 +: 12] >= row_mid) || row_center);
        if(SERIAL_ROWS) begin : serial_write
            // The row commit already visits every candidate during horizontal
            // blanking. Reuse one endpoint/side calculator before updating the
            // candidate, keeping every row and both side-valid bits intact.
            always @(posedge clk)
                if(row_busy && row_phase && row_slot==g && commit_y<IMG_VDISP)
                    rows[commit_y] <= rc_profile;
        end else begin : parallel_write
            always @(posedge clk)
                if(row_end_r && ycnt<IMG_VDISP)
                    rows[ycnt] <= {row_left_v,row_right_v,row_left[g*12 +: 12],row_right[g*12 +: 12]};
        end
        always @(posedge clk) begin
            if(profile_addr<IMG_VDISP) read_data<=rows[profile_addr];
        end
        assign profile_data[g]=read_data;
    end endgenerate
    wire [11:0] rc_span=rc_right-rc_left+1'b1;
    wire rc_cont=pv_v[row_slot] && (pv_y[row_slot]+12'd1>=commit_y);
    wire [11:0] rc_emn=rc_cont?rc_left:
        ((pd_min[row_slot]<pv_min[row_slot])?pv_min[row_slot]:pd_min[row_slot]);
    wire [11:0] rc_emx=rc_cont?rc_right:
        ((pd_max[row_slot]>pv_max[row_slot])?pv_max[row_slot]:pd_max[row_slot]);
    wire [11:0] rc_mn2=(rc_emn<hist_min[row_slot][0])?rc_emn:hist_min[row_slot][0];
    wire [11:0] rc_mx2=(rc_emx>hist_max[row_slot][0])?rc_emx:hist_max[row_slot][0];
    wire [11:0] rc_mn4=(rc_mn2<rc_old2min)?rc_mn2:rc_old2min;
    wire [11:0] rc_mx4=(rc_mx2>rc_old2max)?rc_mx2:rc_old2max;
    wire [11:0] rc_min=(rc_mn4<rc_old4min)?rc_mn4:rc_old4min;
    wire [11:0] rc_max=(rc_mx4>rc_old4max)?rc_mx4:rc_old4max;
    wire [11:0] rc_x0=(c_pix[row_slot]==0 || pd_min[row_slot]<c_x0[row_slot])?pd_min[row_slot]:c_x0[row_slot];
    wire [11:0] rc_x1=(c_pix[row_slot]==0 || pd_max[row_slot]>c_x1[row_slot])?pd_max[row_slot]:c_x1[row_slot];
    wire [11:0] rc_y0=(c_pix[row_slot]==0)?pd_y[row_slot]:c_y0[row_slot];
    wire [11:0] rc_y1=(c_pix[row_slot]==0 || pd_y[row_slot]>c_y1[row_slot])?pd_y[row_slot]:c_y1[row_slot];
    wire [STAT_BITS-1:0] rc_pix=c_pix[row_slot]+pd_cnt[row_slot];
    wire [STAT_BITS-1:0] rc_sum=rc_first?rc_span:c_sum[row_slot]+rc_span;
    always @(posedge clk) begin
        hist2_read<=hist2_ram[hist2_addr];
        hist4_read<=hist4_ram[hist4_addr];
        if(SERIAL_ROWS && row_busy && row_phase && rc_valid) begin
            hist2_ram[hist2_addr]<={rc_mn2[X_BITS-1:0],rc_mx2[X_BITS-1:0]};
            hist4_ram[hist4_addr]<={rc_mn4[X_BITS-1:0],rc_mx4[X_BITS-1:0]};
        end
    end

    localparam [3:0] ST_IDLE=0, ST_CHECK=1, ST_WAIT=2, ST_FIN=3, ST_CLR=4,
                     ST_PREP=5, ST_PAIR=6, ST_OV_INIT=7, ST_OVERLAP=8;
    reg [3:0] st;
    reg [3:0] compare_idx;
    reg [3:0] ks;
    reg [1:0] result_shape;
    reg [5:0] result_corners;
    // Optional recovery for a contour whose top edge is completely absent:
    // pair two narrow, vertically overlapping side chains only when their
    // horizontal gap is bounded. This avoids combining neighbouring shapes.
    reg pair_found;
    reg [3:0] pair_idx;
    reg [11:0] pair_x0, pair_x1, pair_y0, pair_y1;
    reg [31:0] pair_pix, pair_sum;
    // Reuse one geometric comparison datapath across all eight slots.
    // This runs only during vertical blanking, in the original low-index order.
    wire [11:0] test_x0=(c_x0[ks]<c_x0[compare_idx])?c_x0[ks]:c_x0[compare_idx];
    wire [11:0] test_x1=(c_x1[ks]>c_x1[compare_idx])?c_x1[ks]:c_x1[compare_idx];
    wire [11:0] test_y0=(c_y0[ks]<c_y0[compare_idx])?c_y0[ks]:c_y0[compare_idx];
    wire [11:0] test_y1=(c_y1[ks]>c_y1[compare_idx])?c_y1[ks]:c_y1[compare_idx];
    wire [11:0] pair_span=test_x1-test_x0+1'b1;
    wire [11:0] pair_h=test_y1-test_y0+1'b1;
    wire [11:0] pair_narrow=((c_x1[ks]-c_x0[ks]+1'b1)<(c_x1[compare_idx]-c_x0[compare_idx]+1'b1))?
                            (c_x1[ks]-c_x0[ks]+1'b1):(c_x1[compare_idx]-c_x0[compare_idx]+1'b1);
    wire [11:0] pair_gap=(c_x1[ks]<c_x0[compare_idx])?
        c_x0[compare_idx]-c_x1[ks]-1'b1:c_x0[ks]-c_x1[compare_idx]-1'b1;
    reg [11:0] pair_yov;
    always @(*) begin
        if((c_y1[ks]<c_y0[compare_idx]) || (c_y1[compare_idx]<c_y0[ks])) pair_yov=0;
        else if(c_y0[ks]>c_y0[compare_idx])
            pair_yov=(c_y1[ks]<c_y1[compare_idx])?c_y1[ks]-c_y0[ks]+1'b1:c_y1[compare_idx]-c_y0[ks]+1'b1;
        else pair_yov=(c_y1[ks]<c_y1[compare_idx])?c_y1[ks]-c_y0[compare_idx]+1'b1:c_y1[compare_idx]-c_y0[compare_idx]+1'b1;
    end
    wire pair_ok=(compare_idx!=ks) && v[ks] && v[compare_idx] &&
        ((c_x1[ks]<c_x0[compare_idx]) || (c_x1[compare_idx]<c_x0[ks])) &&
        (pair_yov*4>=pair_h*3) && (pair_yov>=12'd32) &&
        (pair_narrow<=12'd128) && (pair_span>12'd32) &&
        ((pair_narrow<<2)<pair_span) && (pair_gap>=MIN_SIZE) &&
        (pair_gap<=12'd256) && (c_pix[ks]+c_pix[compare_idx]>=MIN_PIX);
    wire [11:0] sel_x0 = pair_found ? pair_x0 : c_x0[ks];
    wire [11:0] sel_x1 = pair_found ? pair_x1 : c_x1[ks];
    wire [11:0] sel_y0 = pair_found ? pair_y0 : c_y0[ks];
    wire [11:0] sel_y1 = pair_found ? pair_y1 : c_y1[ks];
    wire [31:0] sel_pix = pair_found ? pair_pix : c_pix[ks];
    wire [31:0] sel_sum = pair_found ? pair_sum : c_sum[ks];
    wire [11:0] wk = sel_x1-sel_x0+1'b1;
    wire [11:0] hk = sel_y1-sel_y0+1'b1;
    reg prior_overlap;
    wire [11:0] ov_x0=(c_x0[compare_idx]>sel_x0)?c_x0[compare_idx]:sel_x0;
    wire [11:0] ov_x1=(c_x1[compare_idx]<sel_x1)?c_x1[compare_idx]:sel_x1;
    wire [11:0] ov_y0=(c_y0[compare_idx]>sel_y0)?c_y0[compare_idx]:sel_y0;
    wire [11:0] ov_y1=(c_y1[compare_idx]<sel_y1)?c_y1[compare_idx]:sel_y1;
    wire [11:0] ov_w=ov_x1-ov_x0+1'b1, ov_h=ov_y1-ov_y0+1'b1;
    wire overlap_hit=(compare_idx<ks) && v[compare_idx] &&
        (c_x0[compare_idx]<=sel_x1) && (sel_x0<=c_x1[compare_idx]) &&
        (c_y0[compare_idx]<=sel_y1) && (sel_y0<=c_y1[compare_idx]) &&
        (c_sum[compare_idx]>=c_sum[ks]) &&
        (ov_w*2>=((c_x1[compare_idx]-c_x0[compare_idx]+1'b1)<wk ?
                  (c_x1[compare_idx]-c_x0[compare_idx]+1'b1):wk)) &&
        (ov_h*2>=((c_y1[compare_idx]-c_y0[compare_idx]+1'b1)<hk ?
                  (c_y1[compare_idx]-c_y0[compare_idx]+1'b1):hk));
    // A contour touching the tracking border may be only a cropped fragment;
    // never turn that fragment into a triangle or rectangle.
    wire g_ok = v[ks] && sel_x0>ROI_X_MIN && sel_x1<ROI_X_MAX &&
                sel_x0>BORDER && sel_x1<(IMG_HDISP-BORDER) &&
                sel_y0>BORDER && sel_y1<(IMG_VDISP-BORDER) &&
                wk>=MIN_SIZE && hk>=MIN_SIZE &&
                wk<=MAX_W && hk<=MAX_H && sel_pix>=MIN_PIX && sel_sum>=MIN_AREA &&
                !prior_overlap;
    wire [31:0] whk = wk*hk;
    // A smooth contour must also occupy enough of its box and have a
    // reasonable aspect ratio. An open line is not automatically a circle.
    wire circle_ok = (c_sum[ks]*32'd100 >= whk*32'd55) &&
                     ({1'b0,wk}<=({1'b0,hk}<<1)) && ({1'b0,hk}<=({1'b0,wk}<<1));
    wire corner_done, corner_busy;
    wire [1:0] corner_shape;
    wire [5:0] corner_count;
    wire [25:0] corner_row_data = pair_found ?
        merge_profile(profile_data[ks], profile_data[pair_idx]) : profile_data[ks];
    Shape_Corner_Count #(.DBG(DBG)) u_corners (
        .clk(clk), .rst_n(rst_n), .start_i(st==ST_CHECK && g_ok),
        .y0_i(sel_y0), .y1_i(sel_y1), .size_i(wk>hk ? wk : hk),
        .circle_ok_i(circle_ok), .row_addr_o(profile_addr), .row_data_i(corner_row_data),
        .busy_o(corner_busy), .done_o(corner_done), .shape_o(corner_shape), .corners_o(corner_count)
    );

    //  ????????? 2 ??? = ? 4 ??????????? ±??????
    wire [11:0] q_x0 = sel_x0 & ~QMASK;
    wire [11:0] q_y0 = sel_y0 & ~QMASK;
    wire [11:0] q_x1 = sel_x1 |  QMASK;
    wire [11:0] q_y1 = sel_y1 |  QMASK;

    //==================================================================
    //  5) ???
    //==================================================================
    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            xcnt <= 12'd0;  ycnt <= 12'd0;
            de_d <= 1'b0;   vs_d <= 1'b0;
            row_end_r <= 1'b0;
            row_busy<=0; row_phase<=0; row_slot<=0; commit_y<=0; frame_pending<=0;
            rs <= 12'd0; re <= 12'd0; run_len <= 12'd0; run_gap <= 12'd0;
            run_on <= 1'b0;
            st <= ST_IDLE; ks <= 4'd0; compare_idx<=0;
            pair_found<=0; pair_idx<=0; prior_overlap<=0;
            pair_x0<=0; pair_x1<=0; pair_y0<=0; pair_y1<=0;
            pair_pix<=0; pair_sum<=0;
            result_shape<=0; result_corners<=0; corners_o<=0;
            evict_i_r <= 4'd0;  evict_v_r <= 1'b0;
            vld_o <= {NBLK{1'b0}};  shape_o <= {(2*NBLK){1'b0}};
            bx0_o <= {(12*NBLK){1'b0}};  by0_o <= {(12*NBLK){1'b0}};
            bx1_o <= {(12*NBLK){1'b0}};  by1_o <= {(12*NBLK){1'b0}};

            for(i = 0; i < NBLK; i = i + 1)
            begin
                c_x0[i]<=12'd0; c_x1[i]<=12'd0; c_y0[i]<=12'd0; c_y1[i]<=12'd0;
                c_pix[i]<=32'd0; c_sum[i]<=32'd0;
                pv_min[i]<=12'd0; pv_max[i]<=12'd0; pv_y[i]<=12'd0; pv_v[i]<=1'b0;
                pd_min[i]<=12'd0; pd_max[i]<=12'd0; pd_y[i]<=12'd0;
                pd_cnt[i]<=16'd0; pd_v[i]<=1'b0;
                v[i]<=1'b0;
                miss_cnt[i] <= 4'd0;
                hist_pos[i]<=0; hist_fill[i]<=0;
                for(j = 0; j < 7; j = j + 1)
                begin
                    hist_min[i][j] <= 12'd0;
                    hist_max[i][j] <= 12'd0;
                end
            end
        end
        else
        begin
            de_d <= de_f;
            vs_d <= vs_f;
            //  ?????????????? c_sum ??????????
            evict_i_r <= smallest_i;
            evict_v_r <= have_evict;
            //  ??? DE ????????"????????"??????
            //  ??????????
            row_end_r <= de_d && !de_f;

            //==========================================================
            //  ????
            //==========================================================
            if(de_f) xcnt <= xcnt + 1'b1;
            else     xcnt <= 12'd0;

            //==========================================================
            //  ???
            //==========================================================
            if(edge_active)
            begin
                if(!run_on)
                begin
                    run_on  <= 1'b1;
                    rs      <= xcnt;
                    re      <= xcnt;
                    run_len <= 12'd1;
                    run_gap <= 12'd0;
                end
                else
                begin
                    re <= xcnt;
                    if(run_len < 12'd4095)
                        run_len <= run_len + run_gap + 1'b1;
                    run_gap <= 12'd0;
                end
            end
            else if(run_on && de_f && in_area && (run_gap < 12'd4095))
                run_gap <= run_gap + 1'b1;

            //==========================================================
            //  ?????????????
            //==========================================================
            if(run_end) begin
                run_on<=1'b0; run_gap<=0;
            end
            if(match_commit)
            begin
                if(any_hit)
                begin
                    //  ????????? pd_* ???????
                    //  ?????????????????????
                    for(i = 0; i < NBLK; i = i + 1)
                    begin
                        if(hit_sel[i])
                        begin
                            if(pd_v[i] && (pd_y[i] == submit_y))
                            begin
                                //  ????? max/min ?????????
                                //  ?? D ?????????? CE ???
                                pd_min[i] <= (submit_rs < pd_min[i]) ? submit_rs : pd_min[i];
                                pd_max[i] <= (submit_re > pd_max[i]) ? submit_re : pd_max[i];
                                pd_cnt[i] <= pd_cnt[i] + {4'd0, submit_len};
                            end
                            else
                            begin
                                pd_min[i] <= submit_rs;
                                pd_max[i] <= submit_re;
                                pd_y  [i] <= submit_y;
                                pd_cnt[i] <= {4'd0, submit_len};
                                pd_v  [i] <= 1'b1;
                            end
                        end
                    end
                end
                else if(submit_slot_found && (submit_len >= RUN_MIN))
                begin
                    // Explicit per-bank writes avoid a variable-index memory
                    // feedback mux across all eight candidate/history banks.
                    for(i=0;i<NBLK;i=i+1) begin
                        if(submit_slot==i) begin
                    //  ??????????????????????????
                    v     [i] <= 1'b1;
                    hist_pos[i]<=0; hist_fill[i]<=0;
                    c_x0  [i] <= submit_rs;
                    c_x1  [i] <= submit_re;
                    c_y0  [i] <= submit_y;
                    c_y1  [i] <= submit_y;
                    c_pix [i] <= {20'd0, submit_len};
                    c_sum [i] <= {20'd0, (submit_re - submit_rs) + 1'b1};
                    pv_min[i] <= submit_rs;
                    pv_max[i] <= submit_re;
                    pv_y  [i] <= submit_y;
                    pv_v  [i] <= 1'b1;
                    pd_v  [i] <= 1'b0;
                    for(j = 0; j < 7; j = j + 1)
                    begin
                        hist_min[i][j] <= submit_rs;
                        hist_max[i][j] <= submit_re;
                    end
                        end
                    end
                end
            end

            //==========================================================
            //  ??????????????
            //==========================================================
            if(!SERIAL_ROWS && row_end_r)
            begin
                for(i = 0; i < NBLK; i = i + 1)
                begin
                    if(v[i] && pd_v[i])
                    begin
                        span_now = row_right[i*12 +: 12]-row_left[i*12 +: 12]+1'b1;

                        if(c_pix[i] == 32'd0)
                        begin
                            c_x0[i] <= pd_min[i];  c_x1[i] <= pd_max[i];
                            c_y0[i] <= pd_y[i];    c_y1[i] <= pd_y[i];
                        end
                        else
                        begin
                            if(pd_min[i] < c_x0[i]) c_x0[i] <= pd_min[i];
                            if(pd_max[i] > c_x1[i]) c_x1[i] <= pd_max[i];
                            if(pd_y[i]   > c_y1[i]) c_y1[i] <= pd_y[i];
                        end

                        c_pix[i] <= c_pix[i] + {16'd0, pd_cnt[i]};
                        c_sum[i] <= (c_y0[i]==ycnt) ? {20'd0,span_now} : c_sum[i]+{20'd0,span_now};

                        //  ????????????"?????"????????

                        //  ?? = ?? 8 ??????? + ? 7 ???
                        //  ?????????????????????????
                        //  ? ??"???????????"??????????
                        //    ???????????????????????
                        //    ?? GAPX ???????????????????
                        //    ???? ?? ???????????????
                        begin : span_calc
                            reg [11:0] tmn, tmx, emn, emx;
                            reg [11:0] mn2, mx2, mn4, mx4;
                            //  ?????????????"????????"??
                            //  ??? 1 ????????????? (pv_y==ycnt)
                            //  ???? ?? ?????????????????
                            //  ????????????????????????
                            if(pv_v[i] && ((pv_y[i] + 12'd1) >= ycnt))
                            begin
                                emn = row_left[i*12 +: 12]; emx = row_right[i*12 +: 12];
                            end
                            else
                            begin
                                emn = (pd_min[i] < pv_min[i]) ? pv_min[i] : pd_min[i];
                                emx = (pd_max[i] > pv_max[i]) ? pv_max[i] : pd_max[i];
                            end

                            mn2=(emn<hist_min[i][0])?emn:hist_min[i][0];
                            mx2=(emx>hist_max[i][0])?emx:hist_max[i][0];
                            mn4=(mn2<hist_min[i][2])?mn2:hist_min[i][2];
                            mx4=(mx2>hist_max[i][2])?mx2:hist_max[i][2];
                            tmn=(mn4<hist_min[i][6])?mn4:hist_min[i][6];
                            tmx=(mx4>hist_max[i][6])?mx4:hist_max[i][6];
                            pv_min[i] <= tmn;
                            pv_max[i] <= tmx;
                            hist_min[i][0] <= emn;
                            hist_max[i][0] <= emx;
                            hist_min[i][1] <= mn2; hist_max[i][1] <= mx2;
                            hist_min[i][2] <= hist_min[i][1];
                            hist_max[i][2] <= hist_max[i][1];
                            hist_min[i][3] <= mn4; hist_max[i][3] <= mx4;
                            for(j=4;j<7;j=j+1) begin
                                hist_min[i][j] <= hist_min[i][j-1];
                                hist_max[i][j] <= hist_max[i][j-1];
                            end
                        end

                        pv_y  [i] <= pd_y[i];
                        pv_v  [i] <= 1'b1;
                        pd_v  [i] <= 1'b0;

                    end
                end
            end

            if(row_end_r) begin
                ycnt<=ycnt+1'b1;
                if(SERIAL_ROWS) begin
                    row_busy<=1; row_phase<=0; row_slot<=0; commit_y<=ycnt;
                end
            end
            if(SERIAL_ROWS && row_busy) begin
              if(!row_phase) row_phase<=1;
              else begin
                row_phase<=0;
                if(row_slot==NBLK-1) row_busy<=0;
                else row_slot<=row_slot+1'b1;
                for(i=0;i<NBLK;i=i+1) begin
                    if(row_slot==i && rc_valid) begin
                        c_x0[i]<=rc_x0; c_x1[i]<=rc_x1;
                        c_y0[i]<=rc_y0; c_y1[i]<=rc_y1;
                        c_pix[i]<=rc_pix; c_sum[i]<=rc_sum;
                        pv_min[i]<=rc_min; pv_max[i]<=rc_max;
                        pv_y[i]<=pd_y[i]; pv_v[i]<=1; pd_v[i]<=0;
                        hist_min[i][0]<=rc_emn; hist_max[i][0]<=rc_emx;
                        hist_pos[i]<=hist_pos[i]+1'b1;
                        if(hist_fill[i]<4) hist_fill[i]<=hist_fill[i]+1'b1;
                    end
                end
              end
            end

            // At most NBLK*(4800+2*NBLK+8) clocks (38592 for NBLK=8),
            // within the 25*1650=41250 clocks before active 720p video.
            // Results are previous-frame.
            if(vs_d && !vs_f && st==ST_IDLE) frame_pending<=1;
            if(frame_pending && !row_busy && !row_end_r && !match_busy && st==ST_IDLE) begin
                st<=ST_PREP; ks<=0; frame_pending<=0;
            end
            if(st==ST_PREP) begin
                compare_idx<=0; pair_found<=0; pair_idx<=0; prior_overlap<=0;
                pair_x0<=c_x0[ks]; pair_x1<=c_x1[ks];
                pair_y0<=c_y0[ks]; pair_y1<=c_y1[ks];
                pair_pix<=c_pix[ks]; pair_sum<=c_sum[ks];
                st<=ST_PAIR;
            end
            if(st==ST_PAIR) begin
                if(pair_ok) begin
                    pair_found<=1; pair_idx<=compare_idx;
                    pair_x0<=test_x0; pair_x1<=test_x1;
                    pair_y0<=test_y0; pair_y1<=test_y1;
                    pair_pix<=c_pix[ks]+c_pix[compare_idx];
                    pair_sum<=pair_span*pair_h;
                    st<=ST_OV_INIT;
                end else if(compare_idx==NBLK-1) st<=ST_OV_INIT;
                else compare_idx<=compare_idx+1'b1;
            end
            if(st==ST_OV_INIT) begin compare_idx<=0; st<=ST_OVERLAP; end
            if(st==ST_OVERLAP) begin
                if(overlap_hit) prior_overlap<=1;
                if(compare_idx==NBLK-1) st<=ST_CHECK;
                else compare_idx<=compare_idx+1'b1;
            end
            if(st==ST_CHECK) begin
                result_shape<=0; result_corners<=0;
                st<=g_ok ? ST_WAIT : ST_FIN;
            end
            if(st==ST_WAIT && corner_done) begin
                result_shape<=corner_shape; result_corners<=corner_count; st<=ST_FIN;
            end
            if(st==ST_FIN) begin
                // Each result bank has one statically addressed write port.
                // Avoid the variable-part-select read/modify/write crossbar.
                for(i=0;i<NBLK;i=i+1) begin
                  if(ks==i) begin
                if(result_shape != 0) begin
                    vld_o[i] <= 1'b1;
                    miss_cnt[i] <= 4'd0;
                    shape_o[i*2 +: 2] <= result_shape;
                    corners_o[i*6 +: 6] <= result_corners;
                    bx0_o[i*12 +: 12] <= q_x0; by0_o[i*12 +: 12] <= q_y0;
                    bx1_o[i*12 +: 12] <= q_x1; by1_o[i*12 +: 12] <= q_y1;
                end
                else if(vld_o[i] && (HOLD_MISSES != 0) &&
                        (miss_cnt[i] < HOLD_MISSES) && (miss_cnt[i] < 4'd15)) begin
                    // ?????????????????????
                    miss_cnt[i] <= miss_cnt[i] + 1'b1;
                end
                else begin
                    vld_o[i] <= 1'b0;
                    miss_cnt[i] <= 4'd0;
                    shape_o[i*2 +: 2] <= 2'd0;
                    corners_o[i*6 +: 6] <= 6'd0;
                end
                  end
                end
                if(DBG) $display("[shape] k=%0d box=(%0d,%0d)-(%0d,%0d) corners=%0d class=%0d",
                    ks,sel_x0,sel_y0,sel_x1,sel_y1,result_corners,result_shape);
                if(ks==NBLK-1) st<=ST_CLR;
                else begin ks<=ks+1'b1; st<=ST_PREP; end
            end

            if(st == ST_CLR)
            begin
                for(i = 0; i < NBLK; i = i + 1)
                begin
                    v[i]      <= 1'b0;
                    pd_v[i]   <= 1'b0;
                    pd_cnt[i] <= 16'd0;
                    pv_v[i]   <= 1'b0;
                    c_pix[i]  <= 32'd0;
                    c_sum[i]  <= 32'd0;
                end
                ycnt   <= 12'd0;
                xcnt   <= 12'd0;
                run_on <= 1'b0;
                run_gap <= 12'd0;
                st     <= ST_IDLE;
            end
        end
    end

    //  ????????????????????????????????
    reg any_box;
    reg [1:0] any_shape;
    integer box_i;
    always @(*)
    begin
        any_box = 1'b0;
        any_shape = 2'd0;
        for(box_i = 0; box_i < NBLK; box_i = box_i + 1)
            if(vld_o[box_i] &&
               (xcnt >= bx0_o[box_i*12 +: 12]) && (xcnt <= bx1_o[box_i*12 +: 12]) &&
               (ycnt >= by0_o[box_i*12 +: 12]) && (ycnt <= by1_o[box_i*12 +: 12]))
            begin
                any_box = 1'b1;
                if(any_shape == 2'd0) any_shape = shape_o[box_i*2 +: 2];
            end
    end

    assign sel_o = edge_f_o && any_box;
    assign sel_shape_o = (edge_f_o && any_box) ? any_shape : 2'd0;

endmodule

