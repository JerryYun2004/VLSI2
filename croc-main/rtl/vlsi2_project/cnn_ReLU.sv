// ReLU module
module relu #(parameter DATA_WIDTH = 32) (
    input logic signed [DATA_WIDTH-1:0] in,
    output logic signed [DATA_WIDTH-1:0] out
);
    always_comb begin
        if (in[DATA_WIDTH-1])
            out = 0;
        else
            out = in;
    end
endmodule