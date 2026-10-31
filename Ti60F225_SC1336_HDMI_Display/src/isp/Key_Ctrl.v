`timescale 1ns/1ns
//======================================================================
// Active-low buttons, synchronized and debounced on both transitions.
// K1 short release: wait DOUBLE_CNT clocks before deciding whether this is
// a single, double, or triple click.  Delaying double-click confirmation is
// required so the first two clicks of a triple click do not freeze first.
// K1 long: cycle raw -> median gray -> median/Sobel -> Gaussian gray -> Canny -> split -> red edge -> raw.
// K2 long in binary: toggle digit detection (legacy sequence ABI).
// K2 single: threshold down in live AND replay. Replay waits for the
// double-click window; two releases navigate without changing threshold.
// K2 long: toggle shape recognition only in color/red-edge mode.
// Simultaneous long events give K1 priority and clear shape recognition.
//======================================================================
module Key_Ctrl #(
    parameter [26:0] LONG_CNT     = 27'd74250000,
    parameter [11:0] TH_DEF       = 12'd200,
    parameter [11:0] TH_STEP      = 12'd10,
    parameter [11:0] TH_MAX       = 12'd2040,
    parameter [11:0] TH_MIN       = 12'd20,
    parameter [26:0] DOUBLE_CNT   = 27'd37125000,
    parameter [26:0] DEBOUNCE_CNT = 27'd1485000
)(
    input               clk,
    input               rst_n,
    input               k1,
    input               k2,
    output reg [11:0]    threshold_o,
    output reg          shape_mode_o,
    output reg          dbg_mode_o,       // Compatibility output; held low.
    output reg [2:0]    display_mode_o,   // 0=color, 5=median gray, 4=Sobel, 6=Gaussian gray, 1=Canny, 2=split, 3=red edge.
    output reg          freeze_o,
    output reg          replay_mode_o,
    output reg          save_frame_o,
    output reg          replay_next_o,
    output reg          replay_prev_o,
    output reg          k1_press_o,
    output reg          k1_long_o,
    output reg [31:0]   k1_long_sequence_o,
    output reg          digit_mode_o,
    output reg          k2_press_o,
    output reg          k2_short_o,
    output reg          k2_long_o
);
    // Treat a zero simulation parameter as one clock rather than underflow.
    localparam [26:0] DEBOUNCE_TICKS = (DEBOUNCE_CNT == 0) ? 27'd1 : DEBOUNCE_CNT;
    localparam [26:0] LONG_TICKS = (LONG_CNT == 0) ? 27'd1 : LONG_CNT;
    localparam [26:0] DOUBLE_TICKS = (DOUBLE_CNT == 0) ? 27'd1 : DOUBLE_CNT;
    localparam integer DEBOUNCE_BITS = (DEBOUNCE_TICKS <= 1) ? 1 : $clog2(DEBOUNCE_TICKS);
    localparam integer HOLD_BITS = (LONG_TICKS <= 1) ? 1 : $clog2({1'b0,LONG_TICKS}+1);
    localparam integer CLICK_BITS = (DOUBLE_TICKS <= 1) ? 1 : $clog2({1'b0,DOUBLE_TICKS}+1);

    reg [1:0] k1_sync, k2_sync;
    reg       k1_db, k2_db;
    reg       k1_last, k2_last;
    reg [DEBOUNCE_BITS-1:0] debounce1, debounce2;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            k1_sync <= 2'b11;
            k2_sync <= 2'b11;
            k1_db <= 1'b1;
            k2_db <= 1'b1;
            k1_last <= 1'b1;
            k2_last <= 1'b1;
            debounce1 <= 27'd0;
            debounce2 <= 27'd0;
        end else begin
            k1_sync <= {k1_sync[0], k1};
            k2_sync <= {k2_sync[0], k2};
            k1_last <= k1_db;
            k2_last <= k2_db;

            if(k1_sync[1] == k1_db)
                debounce1 <= 27'd0;
            else if(debounce1 == DEBOUNCE_TICKS - 1'b1) begin
                k1_db <= k1_sync[1];
                debounce1 <= 27'd0;
            end else
                debounce1 <= debounce1 + 1'b1;

            if(k2_sync[1] == k2_db)
                debounce2 <= 27'd0;
            else if(debounce2 == DEBOUNCE_TICKS - 1'b1) begin
                k2_db <= k2_sync[1];
                debounce2 <= 27'd0;
            end else
                debounce2 <= debounce2 + 1'b1;
        end
    end

    wire k1_press = k1_last && !k1_db;
    wire k2_press = k2_last && !k2_db;
    wire k1_release = !k1_last && k1_db;
    wire k2_release = !k2_last && k2_db;

    reg [HOLD_BITS-1:0] hold1, hold2;
    reg long1_done, long2_done;
    reg [CLICK_BITS-1:0] k1_click_timer, k2_click_timer;
    reg [1:0]  k1_click_count, k2_click_count;

    wire k1_long = !k1_db && !long1_done && (hold1 == LONG_TICKS - 1'b1);
    wire k2_long = !k2_db && !long2_done && (hold2 == LONG_TICKS - 1'b1);
    wire k1_short = k1_release && !long1_done && (hold1 != 0);
    wire k2_short = k2_release && !long2_done && (hold2 != 0);
    wire k1_click_timeout = (k1_click_count != 0) && k1_db &&
                            (k1_click_timer <= 1);
    wire k2_click_timeout = (k2_click_count != 0) && k2_db &&
                            (k2_click_timer <= 1);

    // Resolve thresholds once, so simultaneous +/- gestures cancel even
    // at the limits. A replay double-click must never change the threshold.
    wire k1_triple = k1_short && (k1_click_count == 2'd2);
    wire threshold_up = !k1_triple && (k1_click_count == 2'd1) &&
                        ((k1_click_timeout && !k1_short) || k1_long);
    wire threshold_down = !k1_triple &&
        ((!replay_mode_o && k2_short) ||
         (replay_mode_o && k2_click_count == 2'd1 &&
          ((k2_click_timeout && !k2_short) || (k2_long && !k1_long))));

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            hold1 <= 27'd0;
            hold2 <= 27'd0;
            long1_done <= 1'b0;
            long2_done <= 1'b0;
            k1_click_timer <= 27'd0;
            k2_click_timer <= 27'd0;
            k1_click_count <= 2'd0;
            k2_click_count <= 2'd0;
            threshold_o <= TH_DEF;
            shape_mode_o <= 1'b0;
            dbg_mode_o <= 1'b0;
            display_mode_o <= 3'd0;
            freeze_o <= 1'b0;
            replay_mode_o <= 1'b0;
            save_frame_o <= 1'b0;
            replay_next_o <= 1'b0;
            replay_prev_o <= 1'b0;
            k1_press_o <= 1'b0;
            k1_long_o <= 1'b0;
            k1_long_sequence_o <= 32'd0;
            digit_mode_o <= 1'b0;
            k2_press_o <= 1'b0;
            k2_short_o <= 1'b0;
            k2_long_o <= 1'b0;
        end else begin
            k1_press_o <= k1_press;
            k1_long_o <= k1_long;
            k2_press_o <= k2_press;
            k2_short_o <= k2_short;
            k2_long_o <= k2_long;
            save_frame_o <= 1'b0;
            replay_next_o <= 1'b0;
            replay_prev_o <= 1'b0;

            if(!k1_db) begin
                if(hold1 < LONG_TICKS)
                    hold1 <= hold1 + 1'b1;
                if(k1_long)
                    long1_done <= 1'b1;
            end else begin
                hold1 <= 27'd0;
                long1_done <= 1'b0;
            end
            if(!k2_db) begin
                if(hold2 < LONG_TICKS)
                    hold2 <= hold2 + 1'b1;
                if(k2_long)
                    long2_done <= 1'b1;
            end else begin
                hold2 <= 27'd0;
                long2_done <= 1'b0;
            end

            // K1 gesture classifier. A count of two is deliberately held
            // until the window expires, leaving room for the third click.
            if(k1_long) begin//长按
                k1_click_count <= 2'd0;//记录点击数
                k1_click_timer <= 27'd0;//点击间隔窗口
                begin // Cycle the same seven views in both live and replay.
                    digit_mode_o <= 1'b0;//关闭数字识别
                    case(display_mode_o)
                        3'd0: display_mode_o <= 3'd5;
                        3'd5: display_mode_o <= 3'd4;
                        3'd4: display_mode_o <= 3'd6;
                        3'd6: display_mode_o <= 3'd1;
                        3'd1: display_mode_o <= 3'd2;
                        3'd2: display_mode_o <= 3'd3;
                        default: display_mode_o <= 3'd0;
                    endcase
                    shape_mode_o <= 1'b0;
                end
            end else if(k1_short) begin
                if(k1_click_count == 2'd0) begin
                    k1_click_count <= 2'd1;
                    k1_click_timer <= DOUBLE_TICKS;
                end else if(k1_click_count == 2'd1) begin
                    k1_click_count <= 2'd2;
                    k1_click_timer <= DOUBLE_TICKS;
                end else begin
                    // Third short release is the replay mode toggle.
                    replay_mode_o <= ~replay_mode_o;
                    digit_mode_o <= 1'b0;
                    k1_click_count <= 2'd0;
                    k1_click_timer <= 27'd0;
                    k2_click_count <= 2'd0;
                    k2_click_timer <= 27'd0;
                end
            end else if(k1_click_timeout) begin
                if(k1_click_count == 2'd1) begin
                    // Applied by the shared threshold arbitration below.
                end else if(k1_click_count == 2'd2) begin
                    if(replay_mode_o)
                        replay_next_o <= 1'b1;
                    else begin
                        if(!freeze_o) save_frame_o <= 1'b1;
                        freeze_o <= ~freeze_o;
                    end
                end
                k1_click_count <= 2'd0;
                k1_click_timer <= 27'd0;
            end else if(k1_click_count != 0 && k1_db) begin
                k1_click_timer <= k1_click_timer - 1'b1;
            end

            // Live K2 single remains immediate. In replay, a lone click
            // adjusts the threshold only after ruling out a double-click.
            // A simultaneous K1 long press owns the mode transition.  Do not
            // let K2 restore shape recognition after K1 clears it.
            if(k2_long && !k1_long) begin
                k2_click_count <= 2'd0;
                k2_click_timer <= 27'd0;
                begin
                    if(display_mode_o == 3'd1 || display_mode_o == 3'd4) begin
                        // Legacy signal name retained for the CPU/bridge ABI.
                        // Digit mode is now toggled by K2 in the binary view.
                        k1_long_sequence_o <= k1_long_sequence_o + 1'b1;
                        digit_mode_o <= ~digit_mode_o;
                        shape_mode_o <= 1'b0;
                    end else if(display_mode_o == 2'd3)
                        shape_mode_o <= ~shape_mode_o;
                    else begin
                        // Raw, split and filtered-gray views never enter recognition.
                        digit_mode_o <= 1'b0;
                        shape_mode_o <= 1'b0;
                    end
                end
            end else if(k2_short) begin
                if(replay_mode_o) begin
                    if(k2_click_count == 2'd0) begin
                        k2_click_count <= 2'd1;
                        k2_click_timer <= DOUBLE_TICKS;
                    end else if(k2_click_count == 2'd1) begin
                        k2_click_count <= 2'd2;
                        k2_click_timer <= DOUBLE_TICKS;
                    end
                end else begin
                    // Applied by the shared threshold arbitration below.
                end
            end else if(k2_click_timeout) begin
                if(replay_mode_o && k2_click_count == 2'd2)
                    replay_prev_o <= 1'b1;
                k2_click_count <= 2'd0;
                k2_click_timer <= 27'd0;
            end else if(k2_click_count != 0 && k2_db) begin
                k2_click_timer <= k2_click_timer - 1'b1;
            end
            if(threshold_up && !threshold_down) begin
                if({1'b0, threshold_o}+{1'b0, TH_STEP} >= {1'b0, TH_MAX})
                    threshold_o <= TH_MAX;
                else threshold_o <= threshold_o + TH_STEP;
            end else if(threshold_down && !threshold_up) begin
                if({1'b0, threshold_o} <= {1'b0, TH_MIN}+{1'b0, TH_STEP})
                    threshold_o <= TH_MIN;
                else threshold_o <= threshold_o - TH_STEP;
            end
            // The replay toggle owns simultaneous K2 events as well.
            if(k1_triple) begin
                digit_mode_o <= 1'b0;
                k2_click_count <= 0;
                k2_click_timer <= 0;
                replay_prev_o <= 1'b0;
            end
        end
    end
endmodule
