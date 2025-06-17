// Updated Convolution Module
module conv #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
) (
    input  logic signed [DATA_WIDTH-1:0] window[0:8],
    input  logic signed [DATA_WIDTH-1:0] weight[0:8],
    output logic signed [ACC_WIDTH-1:0]  conv_out
);

    logic signed [ACC_WIDTH-1:0] sum;

    always_comb begin
        sum = 0;
        for (int i = 0; i < 9; i++) begin
            sum += window[i] * weight[i];
        end
        conv_out = sum;
    end

endmodule
