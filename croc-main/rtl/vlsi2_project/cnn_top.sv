`include "../rtl/obi/include/obi/typedef.svh"
`include "../rtl/obi/include/obi/assign.svh"
`include "../rtl/common_cells/include/common_cells/registers.svh"
import obi_pkg::*;

module cnn_top #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    parameter type sbr_obi_req_t = logic,
    parameter type sbr_obi_rsp_t = logic,
    parameter type mgr_obi_req_t = logic,
    parameter type mgr_obi_rsp_t = logic
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic testmode_i,
    input  sbr_obi_req_t sbr_obi_req_i,
    output sbr_obi_rsp_t sbr_obi_rsp_o,
    output mgr_obi_req_t mgr_obi_req_o,
    input  mgr_obi_rsp_t mgr_obi_rsp_i,
    output logic done
);

    localparam logic [31:0] CNN_CLASS_SCORES_BASE = 32'h20001020;
    localparam logic [31:0] ADDR_PIXEL_IN  = 32'h20001018;
    localparam logic [31:0] ADDR_CLASS_IDX = 32'h20001014;
    localparam logic [31:0] ADDR_CTRL      = 32'h20001000;

    localparam logic signed [DATA_WIDTH-1:0] HARD_WEIGHTS [0:8] = '{
        8'sd17, 8'sd89, 8'sd39,
        8'sd100, 8'sd70, 8'sd78,
        8'sd11, 8'sd74, 8'sd52
    };

    typedef enum logic [1:0] {IDLE, PROCESS, WRITE} state_t;
    state_t state_q, state_d;

    logic [DATA_WIDTH-1:0] pixel_in;
    logic valid_in, window_valid;
    logic [DATA_WIDTH-1:0] window[0:8];
    logic signed [31:0] conv_out, relu_out_data, pooled_out;

    logic relu_valid_in, relu_ready_in;
    logic relu_valid_out, relu_ready_out;

    logic [3:0] class_idx_q, class_idx_d;
    logic signed [31:0] class_scores_q [0:9], class_scores_d [0:9];
    logic start_reg_q, start_reg_d;

    logic [12:0] window_counter_q, window_counter_d; // Enough for 28x28 = 784 max
    localparam int TOTAL_WINDOWS = (28-2)*(28-2); // 26x26 = 676

    logic req_q, req_d, we_q, we_d;
    logic [31:0] addr_q, addr_d, wdata_q, wdata_d;
    logic rvalid_q, rvalid_d;

    assign relu_valid_in = window_valid;
    assign relu_ready_in = 1'b1;
    assign relu_ready_out = 1'b1;
    assign sbr_obi_rsp_o.gnt = sbr_obi_req_i.req;
    logic obi_handshake = sbr_obi_req_i.req && !rvalid_q;

    `FF(req_q, req_d, '0)
    `FF(we_q, we_d, '0)
    `FF(addr_q, addr_d, '0)
    `FF(wdata_q, wdata_d, '0)
    `FF(rvalid_q, rvalid_d, '0)
    `FF(class_idx_q, class_idx_d, '0)
    `FF(class_scores_q, class_scores_d, '{default:0})
    `FF(start_reg_q, start_reg_d, 1'b0)
    `FF(state_q, state_d, IDLE)
    `FF(window_counter_q, window_counter_d, 0)

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

    // OBI transaction handling
    always_comb begin
        req_d   = obi_handshake;
        we_d    = obi_handshake ? sbr_obi_req_i.a.we : we_q;
        addr_d  = obi_handshake ? sbr_obi_req_i.a.addr : addr_q;
        wdata_d = obi_handshake ? sbr_obi_req_i.a.wdata : wdata_q;

        rvalid_d = (obi_handshake) ? 1'b1 :
                   (rvalid_q && !sbr_obi_req_i.req) ? 1'b0 : rvalid_q;

        pixel_in = '0;
        valid_in = 1'b0;

        class_idx_d = class_idx_q;
        start_reg_d = start_reg_q;

        if (req_q && we_q) begin
            case (addr_q)
                ADDR_CTRL:      start_reg_d = 1'b1;
                ADDR_CLASS_IDX: class_idx_d = wdata_q[3:0];
                ADDR_PIXEL_IN: begin
                    pixel_in = wdata_q[7:0];
                    valid_in = 1'b1;
                end
                default: ;
            endcase
        end
    end

    // FSM for processing
    always_comb begin
        state_d = state_q;
        window_counter_d = window_counter_q;
        class_scores_d = class_scores_q;
        start_reg_d = start_reg_q;

        done = 1'b0;
        mgr_obi_req_o = '0; // Not used

        case (state_q)
            IDLE: if (start_reg_q) state_d = PROCESS;

            PROCESS: if (window_valid && relu_valid_out) begin
                class_scores_d[class_idx_q] = class_scores_q[class_idx_q] + pooled_out;
                window_counter_d = window_counter_q + 1;

                if (window_counter_q == TOTAL_WINDOWS - 1) begin
                    state_d = WRITE;
                end
            end

            WRITE: begin
                mgr_obi_req_o.req = 1'b1;
                mgr_obi_req_o.a.addr  = CNN_CLASS_SCORES_BASE + (class_idx_q * 4);
                mgr_obi_req_o.a.we    = 1'b1;
                mgr_obi_req_o.a.be    = 4'b1111;
                mgr_obi_req_o.a.wdata = class_scores_d[class_idx_q];

                done = 1'b1;
                start_reg_d = 1'b0;
                window_counter_d = 0;
                state_d = IDLE;
            end
        endcase
    end

    assign sbr_obi_rsp_o.r.rdata =
        (addr_q == ADDR_CLASS_IDX) ? {{28'd0}, class_idx_q} :
        (addr_q == ADDR_CTRL)      ? {{31'd0}, start_reg_q} :
        32'd0;

    assign sbr_obi_rsp_o.r.rid = '0;
    assign sbr_obi_rsp_o.r.err = 1'b0;
    assign sbr_obi_rsp_o.r.r_optional = '0;
    assign sbr_obi_rsp_o.rvalid = rvalid_q;

endmodule
