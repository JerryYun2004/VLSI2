// 2x2 MaxPool (stride=2) with streaming ready/valid.
// - One input pixel per cycle after reset.
// - Emits one pooled output per 2x2 block: on every 2nd column of every 2nd row.
// - Handles downstream back-pressure (ready_in). When holding an output not yet
//   accepted, it stalls upstream (ready_out=0) to keep alignment.
// Assumptions:
// - WIDTH is even (so stride-2 pooling tiles perfectly).
// - Input order: raster scan, left-to-right, top-to-bottom.
// - DATA_WIDTH can be signed or unsigned; max works the same for ReLU outputs.
module max_pool2x2_streaming #(
    parameter int DATA_WIDTH = 32,
    parameter int WIDTH      = 28
) (
    input  logic                     clk,
    input  logic                     rst_n,

    // Upstream stream
    input  logic [DATA_WIDTH-1:0]    in_data,
    input  logic                     valid_in,
    output logic                     ready_out,

    // Downstream stream
    output logic [DATA_WIDTH-1:0]    out_data,
    output logic                     valid_out,
    input  logic                     ready_in
);
    // -----------------------------
    // Output hold register (skid)
    // -----------------------------
    logic [DATA_WIDTH-1:0] out_data_q;
    logic                  out_valid_q;

    // Back-pressure rule:
    //  - If we are holding a valid output and downstream isn't ready,
    //    we must not accept new inputs.
    assign ready_out = !(out_valid_q && !ready_in);

    // -----------------------------
    // Row/column bookkeeping
    // -----------------------------
    logic [$clog2(WIDTH)-1:0] col_idx;
    logic                     row_parity;   // 0 on first row of a 2-row pair, 1 on second
    logic                     col_parity;   // 0 on first col of a 2-col pair, 1 on second
    logic                     have_prev_row; // becomes 1 after first row completes

    // Accept this cycle?
    wire accept = valid_in && ready_out;

    // -----------------------------
    // One-line delay (previous row)
    // -----------------------------
    logic [DATA_WIDTH-1:0] linebuf [0:WIDTH-1];
    logic [DATA_WIDTH-1:0] d_cur, d_prev_row;

    // -----------------------------
    // Horizontal 2-pixel pair maxima (current and previous rows)
    // We form a pair on col_parity == 1
    // -----------------------------
    logic [DATA_WIDTH-1:0] h_prev_cur,  h_pair_cur;
    logic [DATA_WIDTH-1:0] h_prev_prev, h_pair_prev;
    logic                  h_pair_cur_v, h_pair_prev_v;

    // -----------------------------
    // Vertical max when row_parity == 1 and both h-pairs valid
    // -----------------------------
    logic produce_out;
    logic [DATA_WIDTH-1:0] v_pair_max;

    // -----------------------------
    // Assertions / assumptions
    // -----------------------------
    // synthesis translate_off
    initial begin
        if (WIDTH % 2 != 0) begin
            $error("max_pool2x2_streaming: WIDTH (%0d) must be even for stride-2 pooling.", WIDTH);
        end
    end
    // synthesis translate_on

    // ==========================================================
    // Main sequential logic
    // ==========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_idx       <= '0;
            row_parity    <= 1'b0;
            col_parity    <= 1'b0;
            have_prev_row <= 1'b0;

            h_prev_cur    <= '0;
            h_prev_prev   <= '0;
            h_pair_cur    <= '0;
            h_pair_prev   <= '0;
            h_pair_cur_v  <= 1'b0;
            h_pair_prev_v <= 1'b0;

            out_data_q    <= '0;
            out_valid_q   <= 1'b0;
        end else begin
            // Default: if holding a valid output and downstream takes it, clear flag
            if (out_valid_q && ready_in)
                out_valid_q <= 1'b0;

            if (accept) begin
                // Current pixel
                d_cur = in_data;

                // Read corresponding pixel from previous row
                d_prev_row = linebuf[col_idx];

                // Write current pixel into line buffer (for next row use)
                linebuf[col_idx] <= d_cur;

                // --- Horizontal pair on current row ---
                if (col_parity == 1'b0) begin
                    h_prev_cur   <= d_cur;     // store first pixel of the pair
                    h_pair_cur_v <= 1'b0;
                end else begin
                    // second pixel -> form pair max
                    h_pair_cur   <= (d_cur > h_prev_cur) ? d_cur : h_prev_cur;
                    h_pair_cur_v <= 1'b1;
                end

                // --- Horizontal pair on previous row (valid after first row) ---
                if (have_prev_row) begin
                    if (col_parity == 1'b0) begin
                        h_prev_prev   <= d_prev_row;
                        h_pair_prev_v <= 1'b0;
                    end else begin
                        h_pair_prev   <= (d_prev_row > h_prev_prev) ? d_prev_row : h_prev_prev;
                        h_pair_prev_v <= 1'b1;
                    end
                end else begin
                    h_pair_prev_v <= 1'b0;
                end

                // --- Advance column, wrap to next row ---
                if (col_idx == WIDTH-1) begin
                    col_idx    <= '0;
                    col_parity <= 1'b0;
                    // toggle row parity; after the first wrap we "have" a previous row
                    row_parity    <= ~row_parity;
                    have_prev_row <= 1'b1;
                end else begin
                    col_idx    <= col_idx + 1;
                    col_parity <= ~col_parity;
                end

                // --- Produce output at bottom-right of each 2x2 (col_parity==1 & row_parity==1) ---
                produce_out = (col_parity == 1'b1) && (row_parity == 1'b1) &&
                              h_pair_cur_v && h_pair_prev_v && have_prev_row;

                if (produce_out) begin
                    v_pair_max = (h_pair_cur > h_pair_prev) ? h_pair_cur : h_pair_prev;

                    // If output register is free (not holding) or being consumed this cycle, store new value
                    if (!out_valid_q || ready_in) begin
                        out_data_q  <= v_pair_max;
                        out_valid_q <= 1'b1;
                    end
                    // else: we shouldn't reach here because ready_out would have been 0 and accept==0
                end
            end
        end
    end

    assign out_data  = out_data_q;
    assign valid_out = out_valid_q;

endmodule
