// gap_fc_head_streaming.sv
// Consumes pooled pixels in raster order, accumulates their sum (GAP),
// optionally scales by a fixed-point reciprocal 'gap_scale' to form an average,
// then computes K class logits:  logit_k = w[k] * feat + b[k].
// Emits K scores as a stream with ready/valid.
//
// Notes:
// - If you don't want the divide, set gap_scale = 1<<SCALE_Q and treat 'feat' == sum.
//   (Or pre-scale weights offline to absorb 1/NPIX.)
// - For MNIST-like single-channel pipeline, C=1 (this module handles that case).
module gap_fc_head_streaming #(
    parameter int DATA_W  = 32,
    parameter int K       = 10,
    parameter int SCALE_Q = 16  // Q-format for gap_scale
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Control for one image inference
    input  logic                  start,        // pulse to start a new image
    input  logic [31:0]           npix,         // number of pooled pixels (e.g., (W/2)*(H/2))

    // Pooled feature-map stream (single-channel)
    input  logic [DATA_W-1:0]     in_data,
    input  logic                  valid_in,
    output logic                  ready_out,    // back-pressure to MaxPool

    // CSR programming (write weights/biases/scale before 'start')
    input  logic                  w_we,
    input  logic[$clog2(K)-1:0]   w_waddr,
    input  logic [DATA_W-1:0]     w_wdata,     // FC weights W[k]
    input  logic                  b_we,
    input  logic[$clog2(K)-1:0]   b_waddr,
    input  logic [DATA_W-1:0]     b_wdata,     // FC biases B[k]
    input  logic                  scale_we,
    input  logic [DATA_W-1:0]     scale_wdata, // fixed-point reciprocal (≈ (1/NPIX) in Q(SCALE_Q))

    // Score stream (one score per cycle)
    output logic [DATA_W-1:0]     score_out,
    output logic                  score_valid,
    input  logic                  score_ready,

    // Done pulse after last score is accepted
    output logic                  done
);
    typedef enum logic [1:0] {IDLE, ACCUM, EMIT} state_e;
    state_e state_q, state_d;

    // Registers
    logic [DATA_W-1:0]  fc_w   [0:K-1];
    logic [DATA_W-1:0]  fc_b   [0:K-1];
    logic [DATA_W-1:0]  gap_scale_q;

    // Sum needs headroom: add ~16 bits to be safe for up to a few hundred pixels
    localparam int SUM_W = DATA_W + 16;
    logic signed [SUM_W-1:0] sum_q, sum_d;

    logic [31:0] pix_cnt_q, pix_cnt_d;

    // Feature (scaled sum -> average), keep wide during multiply
    logic signed [SUM_W-1:0] feat_q;
    logic                    feat_valid_q;

    // FC emission
    logic [$clog2(K)-1:0] k_idx_q, k_idx_d;
    logic                  score_hold_valid;
    logic [DATA_W-1:0]     score_hold;

    // -------------------------------
    // CSR programming
    // -------------------------------
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < K; i++) begin
                fc_w[i] <= '0;
                fc_b[i] <= '0;
            end
            gap_scale_q <= (1 << SCALE_Q); // default no-op scale
        end else begin
            if (w_we) fc_w[w_waddr] <= w_wdata;
            if (b_we) fc_b[b_waddr] <= b_wdata;
            if (scale_we) gap_scale_q <= scale_wdata;
        end
    end

    // -------------------------------
    // Next-state / counters
    // -------------------------------
    wire accept = (state_q == ACCUM) && valid_in && ready_out;

    always_comb begin
        state_d      = state_q;
        pix_cnt_d    = pix_cnt_q;
        sum_d        = sum_q;
        k_idx_d      = k_idx_q;

        case (state_q)
            IDLE: begin
                if (start) begin
                    state_d   = ACCUM;
                    pix_cnt_d = 32'd0;
                    sum_d     = '0;
                end
            end

            ACCUM: begin
                if (accept) begin
                    sum_d     = sum_q + $signed(in_data);
                    pix_cnt_d = pix_cnt_q + 1;
                    if (pix_cnt_q + 1 == npix) begin
                        state_d = EMIT; // accumulate last pixel this cycle
                        k_idx_d = '0;
                    end
                end
            end

            EMIT: begin
                // k_idx advances when current score is accepted
                if (score_hold_valid && score_ready) begin
                    if (k_idx_q == K-1) begin
                        state_d = IDLE;
                    end else begin
                        k_idx_d = k_idx_q + 1;
                    end
                end
            end
        endcase
    end

    // -------------------------------
    // State / accum regs
    // -------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q       <= IDLE;
            pix_cnt_q     <= '0;
            sum_q         <= '0;
            feat_q        <= '0;
            feat_valid_q  <= 1'b0;
            k_idx_q       <= '0;
        end else begin
            state_q   <= state_d;
            pix_cnt_q <= pix_cnt_d;
            sum_q     <= sum_d;
            k_idx_q   <= k_idx_d;

            // Latch feature (scaled sum) when entering EMIT
            if (state_q == ACCUM && state_d == EMIT) begin
                // feat = (sum_q * gap_scale_q) >>> SCALE_Q
                // (sum_q already includes the last accepted pixel because sum_d updated above)
                logic signed [SUM_W+DATA_W-1:0] mult = sum_d * $signed(gap_scale_q);
                feat_q       <= mult >>> SCALE_Q;
                feat_valid_q <= 1'b1;
            end else if (state_q == IDLE) begin
                feat_valid_q <= 1'b0;
            end
        end
    end

    // -------------------------------
    // FC compute + output streaming
    // -------------------------------
    // Use a 1-element skid so we can assert back-pressure via score_ready.
    // On each k_idx, compute logit_k = fc_w[k]*feat + fc_b[k].
    logic produce_now;
    assign produce_now = (state_q == EMIT) && feat_valid_q &&
                         (!score_hold_valid || (score_hold_valid && score_ready));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            score_hold_valid <= 1'b0;
            score_hold       <= '0;
        end else begin
            // Consume
            if (score_hold_valid && score_ready)
                score_hold_valid <= 1'b0;

            // Produce
            if (produce_now) begin
                // wide multiply then truncate to DATA_W (you can add saturation if desired)
                logic signed [SUM_W+DATA_W-1:0] prod = $signed(fc_w[k_idx_q]) * feat_q;
                logic signed [SUM_W+DATA_W-1:0] acc  = prod + $signed(fc_b[k_idx_q]);
                score_hold       <= acc[DATA_W-1:0];
                score_hold_valid <= 1'b1;
            end
        end
    end

    // Handshakes
    assign ready_out   = (state_q == ACCUM); // only accept pixels during accumulation
    assign score_out   = score_hold;
    assign score_valid = score_hold_valid;

    // Done when last score accepted
    assign done = (state_q == IDLE) && (state_d == IDLE) && !score_hold_valid; // 1-cycle after last accept
endmodule
