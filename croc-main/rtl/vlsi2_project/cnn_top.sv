`include "obi/typedef.svh"
`include "obi/assign.svh"

module cnn_top #(
    parameter DATA_WIDTH = 8, ADDR_WIDTH = 32,
    parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    parameter type obi_req_t = logic,
    parameter type obi_rsp_t = logic
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic testmode_i,
    input  obi_req_t obi_req_i,
    output obi_rsp_t obi_rsp_o,
    output logic done
);

    // Internal registers for OBI handshake
    logic req_d, req_q;
    logic we_d, we_q;
    logic [ObiCfg.AddrWidth-1:0] addr_d, addr_q;
    logic [ObiCfg.IdWidth-1:0] id_d, id_q;
    logic [ObiCfg.DataWidth-1:0] wdata_d, wdata_q;
    logic [ObiCfg.DataWidth-1:0] rsp_data;
    logic rsp_err;

    // Accelerator registers
    logic [ADDR_WIDTH-1:0] input_base, output_base;
    logic start_reg;
    logic signed [DATA_WIDTH-1:0] weights[0:8];

    // OBI handshake state
    logic rvalid_q;

    // Latch OBI request fields
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            req_q   <= '0;
            we_q    <= '0;
            addr_q  <= '0;
            id_q    <= '0;
            wdata_q <= '0;
            input_base   <= 0;
            output_base  <= 0;
            start_reg    <= 0;
            for (int i = 0; i < 9; i++) weights[i] <= 0;
        end else begin
            req_q   <= obi_req_i.req;
            we_q    <= obi_req_i.a.we;
            addr_q  <= obi_req_i.a.addr;
            id_q    <= obi_req_i.a.aid;
            wdata_q <= obi_req_i.a.wdata;
        end
    end

    // Register map
    localparam ADDR_START       = 32'h00;
    localparam ADDR_DONE        = 32'h04;
    localparam ADDR_INPUT_BASE  = 32'h08;
    localparam ADDR_OUTPUT_BASE = 32'h0C;
    localparam ADDR_WEIGHT0     = 32'h10;
    localparam ADDR_WEIGHT8     = 32'h30;

    // Register access and response logic
    always_comb begin
        rsp_data = '0;
        rsp_err  = 1'b0;
        rvalid_q = 1'b0;
        if (req_q) begin
            if (we_q) begin
                unique case (addr_q)
                    ADDR_START:       start_reg = 1'b1;
                    ADDR_INPUT_BASE:  input_base = wdata_q;
                    ADDR_OUTPUT_BASE: output_base = wdata_q;
                    default: begin
                        if (addr_q >= ADDR_WEIGHT0 && addr_q <= ADDR_WEIGHT8)
                            weights[(addr_q - ADDR_WEIGHT0) >> 2] = wdata_q[DATA_WIDTH-1:0];
                        else
                            rsp_err = 1'b1;
                    end
                endcase
            end else begin
                rvalid_q = 1'b1;
                unique case (addr_q)
                    ADDR_DONE:        rsp_data = done;
                    ADDR_INPUT_BASE:  rsp_data = input_base;
                    ADDR_OUTPUT_BASE: rsp_data = output_base;
                    default: begin
                        if (addr_q >= ADDR_WEIGHT0 && addr_q <= ADDR_WEIGHT8)
                            rsp_data = weights[(addr_q - ADDR_WEIGHT0) >> 2];
                        else
                            rsp_data = 32'hDEAD_BEEF;
                    end
                endcase
            end
        end
    end

    // OBI response assignments
    assign obi_rsp_o.gnt = obi_req_i.req;
    assign obi_rsp_o.rvalid = rvalid_q;
    assign obi_rsp_o.r.rdata = rsp_data;
    assign obi_rsp_o.r.rid = id_q;
    assign obi_rsp_o.r.err = rsp_err;
    assign obi_rsp_o.r.r_optional = '0;

    // Accelerator control FSM
    typedef enum logic [1:0] {IDLE, LOAD, COMPUTE, WRITE} state_t;
    state_t state, next_state;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:    if (start_reg)         next_state = LOAD;
            LOAD:    if (window_valid)      next_state = COMPUTE;
            COMPUTE: if (relu_ready_in)     next_state = WRITE;  // Feed conv_out into ReLU
            WRITE:   if (relu_valid_out)    next_state = IDLE;   // Wait until ReLU output is valid
        endcase
    end

    assign done = (state == WRITE && relu_valid_out);


    // Instantiate datapath modules
    logic [DATA_WIDTH-1:0] pixel_in;
    logic valid_in;
    logic [DATA_WIDTH-1:0] window[0:8];
    logic window_valid;
    logic signed [31:0] conv_out, relu_out;

    // === PATCH: Include new window_valid signal ===
    line_buffer #(.DATA_WIDTH(DATA_WIDTH), .WIDTH(28)) u_line_buffer (
        .clk(clk_i),
        .rst_n(rst_ni),
        .pixel_in(pixel_in),
        .valid_in(valid_in),
        .window(window),
        .window_valid(window_valid)
    );

    conv #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(32)) u_conv (
        .window(window),
        .weight(weights),
        .conv_out(conv_out)
    );

    relu_streaming_ready_valid #(.DATA_WIDTH(32)) u_relu_stream (
        .clk(clk_i),
        .rst_n(rst_ni),
        .in_data(conv_out),
        .valid_in(relu_valid_in),
        .ready_in(relu_ready_in),
        .out_data(relu_out_data),
        .valid_out(relu_valid_out),
        .ready_out(relu_ready_out)
    );


    max_pool #(.DATA_WIDTH(32)) u_max_pool (
        .pool_window('{relu_out_data, relu_out_data, relu_out_data, relu_out_data}), // placeholder
        .pool_out(pooled_out)
    );

        // ReLU handshake wiring
    assign relu_valid_in  = (state == COMPUTE);
    assign relu_ready_out = (state == WRITE);  // Accept result only in WRITE state


endmodule
