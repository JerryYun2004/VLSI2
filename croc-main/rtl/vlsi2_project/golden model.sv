// Top-level CNN accelerator with OBI slave interface
`include "obi/typedef.svh"
`include "obi/assign.svh"

module cnn_top #(parameter DATA_WIDTH = 8, ADDR_WIDTH = 32) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic testmode_i,

    // OBI slave interface
    OBI_BUS.Subordinate cnn_if,

    output logic done
);

    // OBI typedefs
    `OBI_TYPEDEF_ALL(cnn_obi, obi_pkg::ObiDefaultConfig)
    cnn_obi_req_t cnn_req;
    cnn_obi_rsp_t cnn_rsp;

    // Assign OBI interface
    `OBI_ASSIGN_TO_REQ(cnn_req, cnn_if, obi_pkg::ObiDefaultConfig)
    `OBI_ASSIGN_FROM_RSP(cnn_if, cnn_rsp, obi_pkg::ObiDefaultConfig)

    // Register map
    localparam ADDR_START       = 32'h00;
    localparam ADDR_DONE        = 32'h04;
    localparam ADDR_INPUT_BASE  = 32'h08;
    localparam ADDR_OUTPUT_BASE = 32'h0C;
    localparam ADDR_WEIGHT0     = 32'h10;
    localparam ADDR_WEIGHT8     = 32'h30;

    logic [ADDR_WIDTH-1:0] input_base, output_base;
    logic start_reg;
    logic signed [DATA_WIDTH-1:0] weights[0:8];

    // OBI handshake state
    logic rvalid_q;
    logic [31:0] rdata_q;

    assign cnn_rsp.rvalid = rvalid_q;
    assign cnn_rsp.rdata  = rdata_q;

    // Register access via OBI
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            input_base <= 0;
            output_base <= 0;
            start_reg <= 0;
            for (int i = 0; i < 9; i++) weights[i] <= 0;
            rvalid_q <= 1'b0;
            rdata_q <= 32'b0;
        end else begin
            rvalid_q <= 1'b0;
            if (cnn_req.req && cnn_req.we) begin
                unique case (cnn_req.a)
                    ADDR_START:      start_reg <= 1'b1;
                    ADDR_INPUT_BASE: input_base <= cnn_req.wdata;
                    ADDR_OUTPUT_BASE: output_base <= cnn_req.wdata;
                    default: begin
                        if (cnn_req.a >= ADDR_WEIGHT0 && cnn_req.a <= ADDR_WEIGHT8)
                            weights[(cnn_req.a - ADDR_WEIGHT0) >> 2] <= cnn_req.wdata[DATA_WIDTH-1:0];
                    end
                endcase
            end else if (cnn_req.req && !cnn_req.we) begin
                rvalid_q <= 1'b1;
                unique case (cnn_req.a)
                    ADDR_DONE:        rdata_q <= done;
                    ADDR_INPUT_BASE:  rdata_q <= input_base;
                    ADDR_OUTPUT_BASE: rdata_q <= output_base;
                    default: begin
                        if (cnn_req.a >= ADDR_WEIGHT0 && cnn_req.a <= ADDR_WEIGHT8)
                            rdata_q <= weights[(cnn_req.a - ADDR_WEIGHT0) >> 2];
                        else
                            rdata_q <= 32'hDEAD_BEEF;
                    end
                endcase
            end
            if (!cnn_req.req) begin
                start_reg <= 0;
            end
        end
    end

    // Accelerator control FSM
    typedef enum logic [1:0] {IDLE, LOAD, COMPUTE, WRITE} state_t;
    state_t state, next_state;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:    if (start_reg) next_state = LOAD;
            LOAD:    next_state = COMPUTE;
            COMPUTE: next_state = WRITE;
            WRITE:   next_state = IDLE;
        endcase
    end

    assign done = (state == WRITE);

    // Instantiate datapath modules
    logic [DATA_WIDTH-1:0] pixel_in;
    logic valid_in;
    logic [DATA_WIDTH-1:0] window[0:8];
    logic signed [31:0] conv_out, relu_out;

    line_buffer #(.DATA_WIDTH(DATA_WIDTH), .WIDTH(28)) u_line_buffer (
        .clk(clk_i),
        .rst_n(rst_ni),
        .pixel_in(pixel_in),
        .valid_in(valid_in),
        .window(window)
    );

    conv #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(32)) u_conv (
        .window(window),
        .weight(weights),
        .conv_out(conv_out)
    );

    relu #(.DATA_WIDTH(32)) u_relu (
        .in(conv_out),
        .out(relu_out)
    );

    max_pool #(.DATA_WIDTH(32)) u_max_pool (
        .in(relu_out),
        .out()
    );
endmodule

// GOLDEN MODEL for functional reference
module cnn_golden_model #(parameter DATA_WIDTH = 8, ACC_WIDTH = 32) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic [DATA_WIDTH-1:0] image[0:27][0:27],
    input  logic signed [DATA_WIDTH-1:0] weight[0:8],
    output logic signed [ACC_WIDTH-1:0] result[0:25][0:25],
    output logic done
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 0;
        end else if (start) begin
            for (int i = 0; i < 26; i++) begin
                for (int j = 0; j < 26; j++) begin
                    result[i][j] = 0;
                    for (int m = 0; m < 3; m++) begin
                        for (int n = 0; n < 3; n++) begin
                            int idx = m * 3 + n;
                            result[i][j] += image[i+m][j+n] * weight[idx];
                        end
                    end
                    if (result[i][j] < 0) result[i][j] = 0; // ReLU
                end
            end
            done <= 1;
        end
    end
endmodule
