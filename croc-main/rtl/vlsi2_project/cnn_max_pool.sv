// Max pooling module (2x2 window)
module max_pool #(parameter DATA_WIDTH = 8) (
    input logic [DATA_WIDTH-1:0] pool_window[0:3],
    output logic [DATA_WIDTH-1:0] pool_out
);

    logic [DATA_WIDTH-1:0] max1, max2;

    always_comb begin
        max1 = (pool_window[0] > pool_window[1]) ? pool_window[0] : pool_window[1];
        max2 = (pool_window[2] > pool_window[3]) ? pool_window[2] : pool_window[3];
        pool_out = (max1 > max2) ? max1 : max2;
    end

endmodule