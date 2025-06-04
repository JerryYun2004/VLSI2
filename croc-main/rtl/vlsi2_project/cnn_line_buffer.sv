// Line buffer with border handling and valid window signal
module line_buffer #(parameter DATA_WIDTH = 8, WIDTH = 28) (
    input  logic clk,
    input  logic rst_n,
    input  logic [DATA_WIDTH-1:0] pixel_in,
    input  logic valid_in,
    output logic [DATA_WIDTH-1:0] window[0:8], // 3x3 output window
    output logic window_valid                  // Asserted when window is fully valid
);

    // 3 line buffers, each of WIDTH pixels
    logic [DATA_WIDTH-1:0] row_buffer[0:2][0:WIDTH-1];

    logic [9:0] col_cnt;
    logic [9:0] row_cnt;

    // Track how many rows and cols have been received
    logic row_ready, col_ready;

    // Column counter (resets at WIDTH)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_cnt <= 0;
        end else if (valid_in) begin
            col_cnt <= (col_cnt == WIDTH-1) ? 0 : col_cnt + 1;
        end
    end

    // Row counter (increases when a row is complete)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_cnt <= 0;
        end else if (valid_in && col_cnt == WIDTH-1) begin
            row_cnt <= (row_cnt < 3) ? row_cnt + 1 : row_cnt;
        end
    end

    assign row_ready = (row_cnt >= 3);
    assign col_ready = (col_cnt >= 2); // minimum 2 columns before current

    // Shift the line buffers vertically
    always_ff @(posedge clk) begin
        if (valid_in) begin
            row_buffer[2][col_cnt] <= row_buffer[1][col_cnt];
            row_buffer[1][col_cnt] <= row_buffer[0][col_cnt];
            row_buffer[0][col_cnt] <= pixel_in;
        end
    end

    // Output valid when both enough rows and columns have arrived
    assign window_valid = row_ready && col_ready;

    // Generate 3x3 window with zero-padding at borders
    always_comb begin
        for (int i = 0; i < 3; i++) begin
            for (int j = 0; j < 3; j++) begin
                int idx = i * 3 + j;
                int row_idx = i;
                int col_offset = col_cnt - 1 + j;

                // Handle horizontal and vertical padding
                if (col_offset < 0 || col_offset >= WIDTH || row_cnt < 3) begin
                    window[idx] = '0;
                end else begin
                    window[idx] = row_buffer[row_idx][col_offset];
                end
            end
        end
    end

endmodule
