// Convolution module: 3x3 kernel
module conv #(parameter DATA_WIDTH = 8, ACC_WIDTH = 32) (
    input logic signed [DATA_WIDTH-1:0] window[0:8],
    input logic signed [DATA_WIDTH-1:0] weight[0:8],
    output logic signed [ACC_WIDTH-1:0] conv_out
);

    always_comb begin
        conv_out = 0;
        for (int i = 0; i < 9; i++) begin
            conv_out += window[i] * weight[i];
        end
    end

endmodule