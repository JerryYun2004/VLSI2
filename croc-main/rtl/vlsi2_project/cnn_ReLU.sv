// Updated Streaming ReLU with ready/valid handshake
module relu_streaming_ready_valid #(
    parameter DATA_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [DATA_WIDTH-1:0] in_data,
    input  logic                  valid_in,
    input  logic                  ready_in,
    output logic [DATA_WIDTH-1:0] out_data,
    output logic                  valid_out,
    output logic                  ready_out
);

    logic [DATA_WIDTH-1:0] data_reg;
    logic                  data_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_reg   <= 0;
            data_valid <= 0;
        end else if (valid_in && ready_in) begin
            data_reg   <= (in_data < 0) ? 0 : in_data;
            data_valid <= 1;
        end else if (valid_out && ready_out) begin
            data_valid <= 0;
        end
    end

    assign out_data  = data_reg;
    assign valid_out = data_valid;
    assign ready_out = 1'b1;  // always ready to forward
    assign ready_in  = ~data_valid || (valid_out && ready_out);

endmodule
