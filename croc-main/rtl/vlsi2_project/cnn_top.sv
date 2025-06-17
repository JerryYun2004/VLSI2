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

    // CNN datapath signals
    logic [DATA_WIDTH-1:0] pixel_in;
    logic valid_in;
    logic [DATA_WIDTH-1:0] window[0:8];
    logic window_valid;
    logic signed [31:0] conv_out;
    logic signed [31:0] relu_out_data;
    logic relu_valid_in, relu_ready_in;
    logic relu_valid_out, relu_ready_out;
    logic signed [31:0] pooled_out;

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
    localparam ADDR_CTRL        = 32'h00;
    localparam ADDR_STATUS      = 32'h04;
    localparam ADDR_INPUT_BASE  = 32'h08;
    localparam ADDR_OUTPUT_BASE = 32'h0C;
    localparam ADDR_WEIGHT0     = 32'h10;
    localparam ADDR_WEIGHT8     = 32'h30;

    logic status_reg;

    // Register access and response logic
    always_comb begin
        rsp_data = '0;
        rsp_err  = 1'b0;
        rvalid_q = 1'b0;
        if (req_q) begin
            if (we_q) begin
                unique case (addr_q)
                    ADDR_CTRL:        start_reg = 1'b1;
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
                    ADDR_STATUS:      rsp_data = status_reg;
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

    // Datapath module instantiations
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

    relu_streaming_ready_valid #(.DATA_WIDTH(32)) u_relu (
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
        .pool_window('{relu_out_data, relu_out_data, relu_out_data, relu_out_data}),
        .pool_out(pooled_out)
    );

    // Control signal flow for placeholder logic
    assign relu_valid_in  = window_valid;
    assign relu_ready_out = 1'b1; // always ready
    assign relu_ready_in  = 1'b1; // always ready

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            status_reg <= 1'b0;
        end else if (start_reg) begin
            status_reg <= 1'b1;
        end
    end

    assign done = status_reg;

endmodule
