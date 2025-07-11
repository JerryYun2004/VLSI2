`include "../rtl/obi/include/obi/typedef.svh"
`include "../rtl/obi/include/obi/assign.svh"
`include "../rtl/common_cells/include/common_cells/registers.svh"
import obi_pkg::*;

module cnn_top #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    parameter type obi_req_t = logic,
    parameter type obi_rsp_t = logic
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic testmode_i,

    // Subordinate interface (register access)
    input  obi_req_t sbr_obi_req_i,
    output obi_rsp_t sbr_obi_rsp_o,

    // Manager interface (memory access)
    output obi_req_t mgr_obi_req_o,
    input  obi_rsp_t mgr_obi_rsp_i,

    output logic done,

    input  logic [DATA_WIDTH-1:0] user_mem_data_in,
    output logic [ADDR_WIDTH-1:0] user_mem_addr,
    output logic                  user_mem_read_en,
    output logic [DATA_WIDTH-1:0] user_mem_data_out,
    output logic                  user_mem_write_en
);

    localparam logic [ADDR_WIDTH-1:0] DEFAULT_INPUT_BASE  = 32'h1A10_0000;
    localparam logic [ADDR_WIDTH-1:0] DEFAULT_OUTPUT_BASE = 32'h1A10_0010;

    // OBI handshake registers
    logic req_q, req_d;
    logic we_q, we_d;
    logic [ObiCfg.AddrWidth-1:0] addr_q, addr_d;
    logic [ObiCfg.IdWidth-1:0] id_q, id_d;
    logic [ObiCfg.DataWidth-1:0] wdata_q, wdata_d;
    logic [ObiCfg.DataWidth-1:0] rsp_data;
    logic rsp_err;
    logic rvalid;

    // Accelerator config
    logic [ADDR_WIDTH-1:0] input_base_q, input_base_d;
    logic [ADDR_WIDTH-1:0] output_base_q, output_base_d;
    logic start_reg_q, start_reg_d;
    logic status_reg;
    logic signed [DATA_WIDTH-1:0] weights_reg[0:8];

    // CNN datapath
    logic [DATA_WIDTH-1:0] pixel_in;
    logic valid_in;
    logic [DATA_WIDTH-1:0] window[0:8];
    logic window_valid;
    logic signed [31:0] conv_out, relu_out_data, pooled_out;
    logic relu_valid_in, relu_ready_in;
    logic relu_valid_out, relu_ready_out;

    // Memory interface counters
    logic [ADDR_WIDTH-1:0] read_addr;
    logic [ADDR_WIDTH-1:0] write_addr;

    // Flip-flops
    `FF(req_q, req_d, '0)
    `FF(we_q, we_d, '0)
    `FF(addr_q, addr_d, '0)
    `FF(id_q, id_d, '0)
    `FF(wdata_q, wdata_d, '0)
    `FF(input_base_q, input_base_d, DEFAULT_INPUT_BASE)
    `FF(output_base_q, output_base_d, DEFAULT_OUTPUT_BASE)
    `FF(start_reg_q, start_reg_d, 1'b0)

    assign req_d = sbr_obi_req_i.req;
    assign we_d = sbr_obi_req_i.a.we;
    assign addr_d = sbr_obi_req_i.a.addr;
    assign id_d = sbr_obi_req_i.a.aid;
    assign wdata_d = sbr_obi_req_i.a.wdata;

    localparam ADDR_CTRL        = 32'h00;
    localparam ADDR_STATUS      = 32'h04;
    localparam ADDR_INPUT_BASE  = 32'h08;
    localparam ADDR_OUTPUT_BASE = 32'h0C;
    localparam ADDR_WEIGHT_BASE = 32'h10;

    always_comb begin
        rsp_data = '0;
        rsp_err = 1'b0;
        rvalid = 1'b0;
        input_base_d = input_base_q;
        output_base_d = output_base_q;
        start_reg_d = start_reg_q;

        if (req_q) begin
            if (we_q) begin
                if (addr_q >= ADDR_WEIGHT_BASE && addr_q < ADDR_WEIGHT_BASE + 9*4) begin
                    weights_reg[(addr_q - ADDR_WEIGHT_BASE) >> 2] = wdata_q[DATA_WIDTH-1:0];
                end else begin
                    unique case (addr_q)
                        ADDR_CTRL:        start_reg_d   = 1'b1;
                        ADDR_INPUT_BASE:  input_base_d  = wdata_q;
                        ADDR_OUTPUT_BASE: output_base_d = wdata_q;
                        default:          rsp_err       = 1'b1;
                    endcase
                end
            end else begin
                rvalid = 1'b1;
                if (addr_q >= ADDR_WEIGHT_BASE && addr_q < ADDR_WEIGHT_BASE + 9*4) begin
                    rsp_data = {{(32 - DATA_WIDTH){1'b0}}, weights_reg[(addr_q - ADDR_WEIGHT_BASE) >> 2]};
                end else begin
                    unique case (addr_q)
                        ADDR_STATUS:      rsp_data = status_reg;
                        ADDR_INPUT_BASE:  rsp_data = input_base_q;
                        ADDR_OUTPUT_BASE: rsp_data = output_base_q;
                        default:          rsp_data = 32'hDEAD_BEEF;
                    endcase
                end
            end
        end
    end

    assign sbr_obi_rsp_o.gnt = sbr_obi_req_i.req;
    assign sbr_obi_rsp_o.rvalid = rvalid;
    assign sbr_obi_rsp_o.r.rdata = rsp_data;
    assign sbr_obi_rsp_o.r.rid = id_q;
    assign sbr_obi_rsp_o.r.err = rsp_err;
    assign sbr_obi_rsp_o.r.r_optional = '0;

    // Manager OBI FSM
    typedef enum logic [1:0] {IDLE, READ, PROCESS, WRITE} state_t;
    state_t state, next_state;

    assign mgr_obi_req_o.req    = (state == READ || state == WRITE);
    assign mgr_obi_req_o.a.we   = (state == WRITE);
    assign mgr_obi_req_o.a.addr = (state == READ) ? read_addr : write_addr;
    assign mgr_obi_req_o.a.wdata = user_mem_data_out;
    assign mgr_obi_req_o.a.be     = '1;
    assign mgr_obi_req_o.a.aid    = '0;
    assign mgr_obi_req_o.a.user   = '0;
    assign mgr_obi_req_o.a.region = '0;

    // Read data from memory
    // (input from DMA/OBI manager)
    // This is correct, since we receive input from memory
    // and pass it to the CNN pipeline

    // Datapath
    cnn_line_buffer #(.DATA_WIDTH(DATA_WIDTH), .WIDTH(28)) u_line_buffer (
        .clk(clk_i),
        .rst_n(rst_ni),
        .pixel_in(pixel_in),
        .valid_in(valid_in),
        .window(window),
        .window_valid(window_valid)
    );

    cnn_conv #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(32)) u_conv (
        .window(window),
        .weight(weights_reg),
        .conv_out(conv_out)
    );

    cnn_ReLU #(.DATA_WIDTH(32)) u_relu (
        .clk(clk_i),
        .rst_n(rst_ni),
        .in_data(conv_out),
        .valid_in(relu_valid_in),
        .ready_in(relu_ready_in),
        .out_data(relu_out_data),
        .valid_out(relu_valid_out),
        .ready_out(relu_ready_out)
    );

    cnn_max_pool #(.DATA_WIDTH(32)) u_max_pool (
        .pool_window('{relu_out_data, relu_out_data, relu_out_data, relu_out_data}),
        .pool_out(pooled_out)
    );

    assign relu_valid_in  = window_valid;
    assign relu_ready_out = 1'b1;
    assign relu_ready_in  = 1'b1;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            read_addr <= '0;
            write_addr <= '0;
        end else begin
            state <= next_state;
            if (state == IDLE && start_reg_q) begin
                read_addr <= input_base_q;
                write_addr <= output_base_q;
                start_reg_d <= 1'b0;
            end
        end
    end

    always_comb begin
        next_state = state;
        valid_in = 0;
        user_mem_read_en = 0;
        user_mem_write_en = 0;
        user_mem_addr = 0;
        pixel_in = 0;
        user_mem_data_out = pooled_out[DATA_WIDTH-1:0];

        case (state)
            IDLE:    if (start_reg_q) next_state = READ;
            READ: begin
                user_mem_addr = read_addr;
                user_mem_read_en = 1;
                pixel_in = user_mem_data_in;
                valid_in = 1;
                next_state = PROCESS;
            end
            PROCESS: if (relu_valid_out) next_state = WRITE;
            WRITE: begin
                user_mem_addr = write_addr;
                user_mem_write_en = 1;
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            status_reg <= 1'b0;
        end else if (state == WRITE) begin
            status_reg <= 1'b1;
        end else if (state == IDLE) begin
            status_reg <= 1'b0;
        end
    end

    assign done = status_reg;

endmodule
