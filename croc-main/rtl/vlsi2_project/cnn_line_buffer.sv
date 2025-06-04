
// Line buffer: stores 3 rows of the image for 3x3 convolution
module line_buffer #(parameter DATA_WIDTH = 8, WIDTH = 28) (
    input logic clk,
    input logic rst_n,
    input logic [DATA_WIDTH-1:0] pixel_in,
    input logic valid_in,
    output logic [DATA_WIDTH-1:0] window[8:0] // 3x3 output
);

    logic [DATA_WIDTH-1:0] row_buffer[0:2][0:WIDTH-1];
    logic [9:0] col_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            col_cnt <= 0;
        else if (valid_in)
            col_cnt <= (col_cnt == WIDTH-1) ? 0 : col_cnt + 1;
    end

    always_ff @(posedge clk) begin
        if (valid_in) begin
            row_buffer[2][col_cnt] <= row_buffer[1][col_cnt];
            row_buffer[1][col_cnt] <= row_buffer[0][col_cnt];
            row_buffer[0][col_cnt] <= pixel_in;
        end
    end

    always_comb begin
        for (int i = 0; i < 3; i++) begin
            for (int j = 0; j < 3; j++) begin
                int idx = i*3 + j;
                int col = (col_cnt + j - 1) % WIDTH;
                window[idx] = row_buffer[i][col];
            end
        end
    end

endmodule
