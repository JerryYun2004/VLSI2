module relu_streaming_ready_valid #(parameter DATA_WIDTH = 32) (
    input  logic clk,
    input  logic rst_n,

    input  logic signed [DATA_WIDTH-1:0] in_data,
    input  logic                        valid_in,
    output logic                        ready_in,

    output logic signed [DATA_WIDTH-1:0] out_data,
    output logic                         valid_out,
    input  logic                         ready_out
);

    // Internal pipeline register
    logic signed [DATA_WIDTH-1:0] data_reg;
    logic                         valid_reg;

    // Ready to accept input when internal stage is not full or downstream is ready
    assign ready_in = !valid_reg || ready_out;

    // ReLU logic and pipelining
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_reg <= 1'b0;
            data_reg  <= '0;
        end else if (ready_in && valid_in) begin
            // Compute ReLU
            if (in_data[DATA_WIDTH-1])
                data_reg <= '0;
            else
                data_reg <= in_data;
            valid_reg <= 1'b1;
        end else if (valid_reg && ready_out) begin
            // Downstream consumed current output
            valid_reg <= 1'b0;
        end
    end

    assign out_data  = data_reg;
    assign valid_out = valid_reg;

endmodule
