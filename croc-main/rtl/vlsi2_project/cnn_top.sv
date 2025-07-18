`include "../rtl/obi/include/obi/typedef.svh"
`include "../rtl/obi/include/obi/assign.svh"
`include "../rtl/common_cells/include/common_cells/registers.svh"
import obi_pkg::*;

module cnn_top #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    parameter type obi_req_t = logic,
    parameter type obi_rsp_t = logic,
    parameter type  sbr_obi_req_t = logic,
    parameter type sbr_obi_rsp_t = logic,
    parameter type mgr_obi_req_t = logic,
    parameter type  mgr_obi_rsp_t = logic
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic testmode_i,
    input  sbr_obi_req_t sbr_obi_req_i,
    output sbr_obi_rsp_t sbr_obi_rsp_o,
    output mgr_obi_req_t mgr_obi_req_o,
    input  mgr_obi_rsp_t mgr_obi_rsp_i,
    output logic done,
    input  logic [DATA_WIDTH-1:0] user_mem_data_in,
    output logic [ADDR_WIDTH-1:0] user_mem_addr,
    output logic user_mem_read_en,
    output logic [DATA_WIDTH-1:0] user_mem_data_out,
    output logic user_mem_write_en
);

    localparam logic [ADDR_WIDTH-1:0] DEFAULT_INPUT_BASE  = 32'h1000_0A00;
    localparam logic [31:0] CNN_CLASS_SCORES_BASE = 32'h20001020;
    localparam logic [31:0] ADDR_INPUT_BASE = 32'h20001008;
    localparam logic [31:0] ADDR_CLASS_IDX  = 32'h20001014;
    localparam logic [31:0] ADDR_CTRL       = 32'h20001000;

    localparam logic signed [DATA_WIDTH-1:0] HARD_WEIGHTS [0:8] = '{
        8'sd17, 8'sd89, 8'sd39,
        8'sd100, 8'sd70, 8'sd78,
        8'sd11, 8'sd74, 8'sd52
    };

    logic signed [31:0] class_scores_q [0:9], class_scores_d [0:9];
    logic [3:0] class_idx_q, class_idx_d;
    logic [ADDR_WIDTH-1:0] input_base_q, input_base_d;
    logic start_reg_q, start_reg_d;

    logic req_q, req_d;
    logic we_q, we_d;
    logic [ObiCfg.AddrWidth-1:0] addr_q, addr_d;
    logic [ObiCfg.DataWidth-1:0] wdata_q, wdata_d;

    `FF(req_q, req_d, '0);
    `FF(we_q, we_d, '0);
    `FF(addr_q, addr_d, '0);
    `FF(wdata_q, wdata_d, '0);

    assign req_d = sbr_obi_req_i.req;
    assign we_d = sbr_obi_req_i.a.we;
    assign addr_d = sbr_obi_req_i.a.addr;
    assign wdata_d = sbr_obi_req_i.a.wdata;

    logic [DATA_WIDTH-1:0] pixel_in;
    logic valid_in;
    logic [DATA_WIDTH-1:0] window[0:8];
    logic window_valid;
    logic signed [31:0] conv_out, relu_out_data, pooled_out;
    logic relu_valid_in, relu_ready_in;
    logic relu_valid_out, relu_ready_out;

    typedef enum logic [1:0] {IDLE, READ, PROCESS, WRITE} state_t;
    state_t state_q, state_d;

    logic [ADDR_WIDTH-1:0] read_addr_q, read_addr_d;

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
        .weight(HARD_WEIGHTS),
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

    assign relu_valid_in = window_valid;
    assign relu_ready_out = 1'b1;
    assign relu_ready_in = 1'b1;

    always_comb begin
        state_d = state_q;
        read_addr_d = read_addr_q;
        class_scores_d = class_scores_q;
        class_idx_d = class_idx_q;
        start_reg_d = start_reg_q;
        input_base_d = input_base_q;

        user_mem_addr = '0;
        user_mem_read_en = 1'b0;
        user_mem_write_en = 1'b0;
        user_mem_data_out = '0;

        valid_in = 1'b0;
        pixel_in = '0;

        if (req_q && we_q) begin
            case(addr_q)
                ADDR_INPUT_BASE: begin
                    input_base_d = wdata_q;
                    $display("[CNN_OBI] Write to INPUT_BASE: 0x%0h", wdata_q);
                end
                ADDR_CLASS_IDX: begin
                    class_idx_d = wdata_q[3:0];
                    $display("[CNN_OBI] Write to CLASS_IDX: %0d", wdata_q[3:0]);
                end
                ADDR_CTRL: begin
                    start_reg_d = 1'b1;
                    $display("[CNN_OBI] Write to CTRL: Start signal asserted");
                end
                default: ;
            endcase
        end

        case (state_q)
            IDLE: begin
                if (start_reg_q) begin
                    read_addr_d = input_base_q;
                    state_d = READ;
                end
            end
            READ: begin
                user_mem_addr = read_addr_q;
                user_mem_read_en = 1'b1;
                pixel_in = user_mem_data_in;
                valid_in = 1'b1;

                read_addr_d = read_addr_q + 1;

                if (window_valid) begin
                    state_d = PROCESS;
                end
            end
            PROCESS: begin
                if (relu_valid_out) begin
                    state_d = WRITE;
                end
            end
            WRITE: begin
                class_scores_d[class_idx_q] = class_scores_q[class_idx_q] + pooled_out;
                user_mem_addr = CNN_CLASS_SCORES_BASE + (class_idx_q * 4);
                user_mem_data_out = class_scores_d[class_idx_q];
                user_mem_write_en = 1'b1;

                state_d = IDLE;
                start_reg_d = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            read_addr_q <= '0;
            class_scores_q <= '{default:0};
            class_idx_q <= '0;
            start_reg_q <= 1'b0;
            input_base_q <= DEFAULT_INPUT_BASE;
        end else begin
            state_q <= state_d;
            read_addr_q <= read_addr_d;
            class_scores_q <= class_scores_d;
            class_idx_q <= class_idx_d;
            start_reg_q <= start_reg_d;
            input_base_q <= input_base_d;
        end
    end

    assign sbr_obi_rsp_o.gnt = sbr_obi_req_i.req;
    assign sbr_obi_rsp_o.rvalid = req_q;
    assign sbr_obi_rsp_o.r.rdata = '0;
    assign sbr_obi_rsp_o.r.rid = '0;
    assign sbr_obi_rsp_o.r.err = 1'b0;
    assign sbr_obi_rsp_o.r.r_optional = '0;

    assign done = (state_q == IDLE);

endmodule
