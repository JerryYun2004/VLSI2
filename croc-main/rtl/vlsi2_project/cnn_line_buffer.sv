// cnn_line_buffer.sv
// Streaming 3x3 window generator with two line delays.
// Produces one 3x3 window per input pixel after the pipeline fills.
module line_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int WIDTH      = 28
) (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic [DATA_WIDTH-1:0]     pixel_in,
    input  logic                      valid_in,
    output logic [DATA_WIDTH-1:0]     window [0:8],
    output logic                      window_valid
);
    // Two line buffers implement delays of WIDTH cycles each.
    logic [DATA_WIDTH-1:0] lb1 [0:WIDTH-1];
    logic [DATA_WIDTH-1:0] lb2 [0:WIDTH-1];

    // Write index shared by both line buffers (circular).
    logic [$clog2(WIDTH)-1:0] widx;

    // The 3 horizontal shift registers for each of the 3 rows.
    logic [DATA_WIDTH-1:0] h0_2, h0_1, h0_0; // current row (newest)
    logic [DATA_WIDTH-1:0] h1_2, h1_1, h1_0; // previous row
    logic [DATA_WIDTH-1:0] h2_2, h2_1, h2_0; // two-rows-ago

    // Row fill counter to know when we have at least 2 full prior rows.
    logic [31:0] rows_filled;

    // Outputs from line buffers on this cycle.
    logic [DATA_WIDTH-1:0] d0, d1, d2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            widx        <= '0;
            rows_filled <= 0;
            h0_2 <= '0; h0_1 <= '0; h0_0 <= '0;
            h1_2 <= '0; h1_1 <= '0; h1_0 <= '0;
            h2_2 <= '0; h2_1 <= '0; h2_0 <= '0;
        end else if (valid_in) begin
            // Current sample
            d0 = pixel_in;
            // First line delay
            d1 = lb1[widx];
            lb1[widx] <= d0;
            // Second line delay
            d2 = lb2[widx];
            lb2[widx] <= d1;

            // Advance pointer and row count
            if (widx == WIDTH-1) begin
                widx <= '0;
                if (rows_filled != 32'hFFFF_FFFF) rows_filled <= rows_filled + 1;
            end else begin
                widx <= widx + 1;
            end

            // Horizontal shift registers
            {h0_2, h0_1, h0_0} <= {h0_1, h0_0, d0};
            {h1_2, h1_1, h1_0} <= {h1_1, h1_0, d1};
            {h2_2, h2_1, h2_0} <= {h2_1, h2_0, d2};
        end
    end

    // Output window + valid flag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_valid <= 1'b0;
            window[0] <= '0; window[1] <= '0; window[2] <= '0;
            window[3] <= '0; window[4] <= '0; window[5] <= '0;
            window[6] <= '0; window[7] <= '0; window[8] <= '0;
        end else begin
            // Valid only after at least two prior rows and two prior columns
            if (valid_in && rows_filled >= 2 && widx >= 2) begin
                window[0] <= h2_2; window[1] <= h2_1; window[2] <= h2_0;
                window[3] <= h1_2; window[4] <= h1_1; window[5] <= h1_0;
                window[6] <= h0_2; window[7] <= h0_1; window[8] <= h0_0;
                window_valid <= 1'b1;
            end else begin
                window_valid <= 1'b0;
            end
        end
    end
endmodule
