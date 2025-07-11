`include "../rtl/obi/include/obi/assign.svh"
`include "../rtl/obi/include/obi/typedef.svh"
import obi_pkg::*;

module cnn_top #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 32,
    /// The OBI configuration for all ports.
    parameter obi_pkg::obi_cfg_t ObiCfg      = obi_pkg::ObiDefaultConfig,
    /// The request struct for all ports.
    parameter type               obi_req_t   = logic,
    /// The response struct for all ports.
    parameter type               obi_rsp_t   = logic
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

    // Memory-mapped default patch for Croc compatibility
    localparam logic [ADDR_WIDTH-1:0] DEFAULT_INPUT_BASE  = 32'h1A10_0000;
    localparam logic [ADDR_WIDTH-1:0] DEFAULT_OUTPUT_BASE = 32'h1A10_0010;

    // Internal registers for OBI handshake (subordinate interface)
    logic req_q;
    logic we_q;
    logic [ObiCfg.AddrWidth-1:0] addr_q;
    logic [ObiCfg.IdWidth-1:0] id_q;
    logic [ObiCfg.DataWidth-1:0] wdata_q;
    logic [ObiCfg.DataWidth-1:0] rsp_data;
    logic rsp_err;
    logic rvalid_q;

    // Accelerator registers
    logic [ADDR_WIDTH-1:0] input_base, output_base;
    logic start_reg;
    logic status_reg;
    logic signed [DATA_WIDTH-1:0] weights_reg [0:8];

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

    // Memory interface counters
    logic [ADDR_WIDTH-1:0] read_addr;
    logic [ADDR_WIDTH-1:0] write_addr;

    // Latch subordinate OBI request fields
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            req_q     <= '0;
            we_q      <= '0;
            addr_q    <= '0;
            id_q      <= '0;
            wdata_q   <= '0;
            input_base  <= DEFAULT_INPUT_BASE;
            output_base <= DEFAULT_OUTPUT_BASE;
            start_reg   <= 1'b0;
        end else begin
            req_q   <= sbr_obi_req_i.req;
            we_q    <= sbr_obi_req_i.a.we;
            addr_q  <= sbr_obi_req_i.a.addr;
            id_q    <= sbr_obi_req_i.a.aid;
            wdata_q <= sbr_obi_req_i.a.wdata;
        end
    end

    // Register map
    localparam ADDR_CTRL         = 32'h00;
    localparam ADDR_STATUS       = 32'h04;
    localparam ADDR_INPUT_BASE   = 32'h08;
    localparam ADDR_OUTPUT_BASE  = 32'h0C;
    localparam ADDR_WEIGHT_BASE  = 32'h10;

    // Register access and response logic
    always_comb begin
        rsp_data = '0;
        rsp_err  = 1'b0;
        rvalid_q = 1'b0;

        if (req_q) begin
            if (we_q) begin
                if (addr_q >= ADDR_WEIGHT_BASE && addr_q < ADDR_WEIGHT_BASE + 9*4) begin
                    weights_reg[(addr_q - ADDR_WEIGHT_BASE) >> 2] = wdata_q[DATA_WIDTH-1:0];
                end else begin
                    unique case (addr_q)
                        ADDR_CTRL:         start_reg   = 1'b1;
                        ADDR_INPUT_BASE:   input_base  = wdata_q;
                        ADDR_OUTPUT_BASE:  output_base = wdata_q;
                        default:           rsp_err     = 1'b1;
                    endcase
                end
            end else begin
                rvalid_q = 1'b1;
                if (addr_q >= ADDR_WEIGHT_BASE && addr_q < ADDR_WEIGHT_BASE + 9*4) begin
                    rsp_data = {{(32-DATA_WIDTH){1'b0}}, weights_reg[(addr_q - ADDR_WEIGHT_BASE) >> 2]};
                end else begin
                    unique case (addr_q)
                        ADDR_STATUS:       rsp_data = status_reg;
                        ADDR_INPUT_BASE:   rsp_data = input_base;
                        ADDR_OUTPUT_BASE:  rsp_data = output_base;
                        default:           rsp_data = 32'hDEAD_BEEF;
                    endcase
                end
            end
        end
    end

    // Subordinate OBI response
    assign sbr_obi_rsp_o.gnt = sbr_obi_req_i.req;
    assign sbr_obi_rsp_o.rvalid = rvalid_q;
    assign sbr_obi_rsp_o.r.rdata = rsp_data;
    assign sbr_obi_rsp_o.r.rid = id_q;
    assign sbr_obi_rsp_o.r.err = rsp_err;
    assign sbr_obi_rsp_o.r.r_optional = '0;

    // Manager OBI memory access: assign request signals
    assign mgr_obi_req_o.req = (state == READ || state == WRITE);
    assign mgr_obi_req_o.a.we = (state == WRITE);
    assign mgr_obi_req_o.a.addr = (state == READ) ? read_addr : write_addr;
    assign mgr_obi_req_o.a.wdata = user_mem_data_out;
    assign mgr_obi_req_o.a.be = '1;         // all bytes enabled
    assign mgr_obi_req_o.a.aid = '0;        // default
    assign mgr_obi_req_o.a.user = '0;
    assign mgr_obi_req_o.a.region = '0;

    // Read data from mgr_obi_rsp_i
    assign user_mem_data_in = mgr_obi_rsp_i.r.rdata;

    // Datapath
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
        .weight(weights_reg),
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

    assign relu_valid_in  = window_valid;
    assign relu_ready_out = 1'b1;
    assign relu_ready_in  = 1'b1;

    // FSM
    typedef enum logic [1:0] {IDLE, READ, PROCESS, WRITE} state_t;
    state_t state, next_state;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            read_addr <= 0;
            write_addr <= 0;
        end else begin
            state <= next_state;
            if (state == IDLE && start_reg) begin
                read_addr <= input_base;
                write_addr <= output_base;
                start_reg <= 1'b0;
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
            IDLE:    if (start_reg) next_state = READ;
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
