module line_buffer #(
    parameter DATA_WIDTH = 8,
    parameter WIDTH = 28
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [DATA_WIDTH-1:0] pixel_in,
    input  logic valid_in,
    output logic [DATA_WIDTH-1:0] window[0:8],
    output logic window_valid
);

    logic [DATA_WIDTH-1:0] row_buffer0[0:WIDTH-1]; // newest row
    logic [DATA_WIDTH-1:0] row_buffer1[0:WIDTH-1];
    logic [DATA_WIDTH-1:0] row_buffer2[0:WIDTH-1];

    integer row_ptr, col_ptr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_ptr <= 0;
            row_ptr <= 0;
        end else if (valid_in) begin
            // Shift data in the row buffers
            row_buffer2[col_ptr] <= row_buffer1[col_ptr];
            row_buffer1[col_ptr] <= row_buffer0[col_ptr];
            row_buffer0[col_ptr] <= pixel_in;

            col_ptr <= (col_ptr == WIDTH-1) ? 0 : col_ptr + 1;
            if (col_ptr == WIDTH-1) row_ptr <= row_ptr + 1;
        end
    end

    always_comb begin
        window_valid = 0;
        for (int i = 0; i < 9; i++) window[i] = 0;

        if (row_ptr >= 2 && col_ptr >= 2) begin
            window_valid = 1;
            window[0] = row_buffer2[col_ptr - 2];
            window[1] = row_buffer2[col_ptr - 1];
            window[2] = row_buffer2[col_ptr];
            window[3] = row_buffer1[col_ptr - 2];
            window[4] = row_buffer1[col_ptr - 1];
            window[5] = row_buffer1[col_ptr];
            window[6] = row_buffer0[col_ptr - 2];
            window[7] = row_buffer0[col_ptr - 1];
            window[8] = row_buffer0[col_ptr];
        end
    end
endmodule
