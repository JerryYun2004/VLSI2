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

    logic signed [31:0] class_scores_q [0:9], class_scores_d [0:9];

    logic req_q, req_d;
    logic we_q, we_d;
    logic [ObiCfg.AddrWidth-1:0] addr_q, addr_d;
    logic [ObiCfg.IdWidth-1:0] id_q, id_d;
    logic [ObiCfg.DataWidth-1:0] wdata_q, wdata_d;
    logic [ObiCfg.DataWidth-1:0] rsp_data;
    logic rsp_err;
    logic rvalid;
    logic user_mem_write_en_q;

    logic [ADDR_WIDTH-1:0] input_base_q, input_base_d;
    logic start_reg_q, start_reg_d;
    logic status_reg;
    logic signed [DATA_WIDTH-1:0] weights_reg[0:8];
    logic [ADDR_WIDTH-1:0] read_addr_q, read_addr_d;

    logic [3:0] class_idx_q, class_idx_d;

    logic [DATA_WIDTH-1:0] pixel_in;
    logic valid_in;
    logic [DATA_WIDTH-1:0] window[0:8];
    logic window_valid;
    logic signed [31:0] conv_out, relu_out_data, pooled_out;
    logic relu_valid_in, relu_ready_in;
    logic relu_valid_out, relu_ready_out;

    logic [ADDR_WIDTH-1:0] read_addr;

    logic obi_busy;
    assign obi_busy = pending_read_q; // CNN is processing when not in IDLE

    logic pending_read_q, pending_read_d;
    logic [ObiCfg.DataWidth-1:0] rsp_data_d, rsp_data_q;
    logic rsp_err_d, rsp_err_q;
    logic [ObiCfg.IdWidth-1:0] pending_rid_q, pending_rid_d;
    
    `FF(req_q, req_d, '0)
    `FF(we_q, we_d, '0)
    `FF(addr_q, addr_d, '0)
    `FF(id_q, id_d, '0)
    `FF(wdata_q, wdata_d, '0)
    `FF(input_base_q, input_base_d, DEFAULT_INPUT_BASE)
    `FF(start_reg_q, start_reg_d, 1'b0)
    `FF(class_idx_q, class_idx_d, 4'd0)

    assign req_d = sbr_obi_req_i.req;
    assign we_d = sbr_obi_req_i.a.we;
    assign addr_d = sbr_obi_req_i.a.addr;
    assign id_d = sbr_obi_req_i.a.aid;
    assign wdata_d = sbr_obi_req_i.a.wdata;

    localparam ADDR_CTRL = 32'h00;
    localparam ADDR_STATUS = 32'h04;
    localparam ADDR_INPUT_BASE = 32'h08;
    localparam ADDR_WEIGHT_BASE = 32'h10;
    localparam ADDR_CLASS_IDX = 32'h14;

    localparam ADDR_CLASS_SCORES = 32'h20;

    logic start_reg_set; // Declare this at module scope

    // Combinational decoder
    always_comb begin
        pending_read_d = pending_read_q;
        rsp_data_d = rsp_data_q;
        rsp_err_d = rsp_err_q;
    
        input_base_d = input_base_q;
        start_reg_set = 1'b0;
        class_idx_d  = class_idx_q;
        class_scores_d = class_scores_q;
    
        // obi_busy = pending_read_q; // busy while waiting to complete a read
    
        if (sbr_obi_req_i.req && !obi_busy) begin
            $display("[CNN] Access: we=%0b addr=0x%0h wdata=0x%0h", sbr_obi_req_i.a.we, sbr_obi_req_i.a.addr, sbr_obi_req_i.a.wdata);
            
            if (sbr_obi_req_i.a.we) begin
                // WRITE ACCESS
                if (sbr_obi_req_i.a.addr >= ADDR_WEIGHT_BASE && sbr_obi_req_i.a.addr < ADDR_WEIGHT_BASE + 9*4) begin
                    weights_reg[(sbr_obi_req_i.a.addr - ADDR_WEIGHT_BASE) >> 2] = sbr_obi_req_i.a.wdata[DATA_WIDTH-1:0];
                    $display("[CNN] Weight[%0d] written with value %0d", 
                              (sbr_obi_req_i.a.addr - ADDR_WEIGHT_BASE) >> 2, 
                              sbr_obi_req_i.a.wdata[DATA_WIDTH-1:0]);
                end else begin
                    unique case (sbr_obi_req_i.a.addr)
                        ADDR_CTRL: begin
                            start_reg_set = 1'b1;
                            $display("[CNN] Start command issued.");
                        end
                        ADDR_INPUT_BASE: input_base_d = sbr_obi_req_i.a.wdata;
                        ADDR_CLASS_IDX:  class_idx_d  = sbr_obi_req_i.a.wdata[3:0];
                        default: rsp_err_d = 1'b1;
                    endcase
                end
            end else begin
                // READ ACCESS
                rsp_err_d = 1'b0;
                if (sbr_obi_req_i.a.addr >= ADDR_WEIGHT_BASE && sbr_obi_req_i.a.addr < ADDR_WEIGHT_BASE + 9*4) begin
                    rsp_data_d = {{(32 - DATA_WIDTH){1'b0}}, weights_reg[(sbr_obi_req_i.a.addr - ADDR_WEIGHT_BASE) >> 2]};
                end else begin
                    unique case (sbr_obi_req_i.a.addr)
                        ADDR_STATUS:     rsp_data_d = status_reg;
                        ADDR_INPUT_BASE: rsp_data_d = input_base_q;
                        ADDR_CLASS_IDX:  rsp_data_d = {{28'd0}, class_idx_q};
                        default: begin
                            if (sbr_obi_req_i.a.addr >= ADDR_CLASS_SCORES && sbr_obi_req_i.a.addr < ADDR_CLASS_SCORES + 10*4) begin
                                rsp_data_d = class_scores_q[(sbr_obi_req_i.a.addr - ADDR_CLASS_SCORES) >> 2];
                            end else begin
                                rsp_data_d = 32'hDEAD_BEEF;
                                rsp_err_d = 1'b1;
                            end
                        end
                    endcase
                end
            
                pending_read_d = 1'b1;  // mark read as pending
                pending_rid_d = sbr_obi_req_i.a.aid;  // latch the aid for r.rid response
            end
        end

    // Clear pending read after rvalid
    if (pending_read_q && sbr_obi_rsp_o.rvalid)
        pending_read_d = 1'b0;
    end
end

    assign handshake_done = sbr_obi_req_i.req && sbr_obi_rsp_o.gnt && sbr_obi_rsp_o.rvalid;

    // OBI protocol signals
    assign sbr_obi_rsp_o.gnt = sbr_obi_req_i.req && !obi_busy;
    assign sbr_obi_rsp_o.rvalid = pending_read_q && !handshake_done;
    assign sbr_obi_rsp_o.r.rdata = rsp_data_q;
    assign sbr_obi_rsp_o.r.rid = pending_rid_q;  // track ID from req
    assign sbr_obi_rsp_o.r.err = rsp_err_q;
    assign sbr_obi_rsp_o.r.r_optional = '0;

    typedef enum logic [1:0] {IDLE, READ, PROCESS, WRITE} state_t;
    state_t state, next_state;

    assign mgr_obi_req_o.req = (state == READ);
    assign mgr_obi_req_o.a.we = 1'b0;
    assign mgr_obi_req_o.a.addr = read_addr_q;
    assign mgr_obi_req_o.a.wdata = '0;
    assign mgr_obi_req_o.a.be = '1;
    assign mgr_obi_req_o.a.aid = '0;

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

    assign relu_valid_in = window_valid;
    assign relu_ready_out = 1'b1;
    assign relu_ready_in = 1'b1;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            read_addr_q <= '0;
            start_reg_q <= 1'b0;
            for (int i = 0; i < 10; i++) begin
                class_scores_q[i] <= 32'd0;
            end
        end else begin
            state <= next_state;
            read_addr_q <= read_addr_d;
            start_reg_q <= start_reg_d;
            for (int i = 0; i < 10; i++) begin
                class_scores_q[i] <= class_scores_d[i];
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            user_mem_write_en_q <= 0;
        end else begin
            user_mem_write_en_q <= user_mem_write_en;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            pending_read_q <= 1'b0;
        else
            pending_read_q <= pending_read_d;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rsp_data_q <= '0;
            rsp_err_q <= 1'b0;
        end else begin
            rsp_data_q <= rsp_data_d;
            rsp_err_q  <= rsp_err_d;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            pending_rid_q <= '0;
        else
            pending_rid_q <= pending_rid_d;
    end


   always_comb begin
        next_state = state;
        valid_in = 0;
        user_mem_read_en = 0;
        user_mem_write_en = 0;
        user_mem_addr = 0;
        pixel_in = 0;
        user_mem_data_out = '0;
        read_addr_d = read_addr_q;
        class_scores_d = class_scores_q;
        start_reg_d = start_reg_q; // default retain
    
        case (state)
            IDLE: begin
                if (start_reg_set) begin
                    $display("[CNN] FSM start: Moving to READ");
                    read_addr_d = input_base_q;
                    next_state = READ;
                    start_reg_d = 1'b1;  // latch start trigger
                end
            end
    
            READ: begin
                $display("[CNN] READ: read_addr_q=0x%0h, pixel_in=0x%0h", read_addr_q, pixel_in);
                user_mem_addr = read_addr_q;
                user_mem_read_en = 1;
                pixel_in = user_mem_data_in;
                valid_in = 1;
                read_addr_d = read_addr_q + 1;
    
                if (window_valid) begin
                    $display("[CNN] Window Valid! read_addr=0x%0h", read_addr_q);
                    $display("[CNN] Convolution output: conv_out=%0d", conv_out);
                    next_state = PROCESS;
                end
            end
    
            PROCESS: begin
                if (relu_valid_out) begin
                    $display("[CNN] ReLU Output: relu_out_data=%0d", relu_out_data);
                    next_state = WRITE;
                end
            end
    
            WRITE: begin
                $display("[CNN] Pooled Output: pooled_out=%0d", pooled_out);
                $display("[CNN] WRITE: class_idx=%0d, score=%0d", class_idx_q, pooled_out);
    
                class_scores_d[class_idx_q] = class_scores_q[class_idx_q] + pooled_out;
                $display("[CNN] Accumulated class_scores[%0d] = %0d", class_idx_q, class_scores_d[class_idx_q]);
    
                user_mem_addr = 32'h20001020 + (class_idx_q << 2);
                user_mem_data_out = class_scores_d[class_idx_q];
                user_mem_write_en = 1; // one-cycle pulse asserted here
    
                next_state = IDLE; // directly return to IDLE
                start_reg_d = 1'b0; // clear start flag
            end
        endcase
    end


    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            status_reg <= 1'b0;
        end else if (state == WRITE) begin
            status_reg <= 1'b1;
            $display("[CNN] status_reg set to 1 at WRITE");
        end else if (req_q && we_q && addr_q == ADDR_CTRL) begin
            status_reg <= 1'b0;
        end
    end

    assign done = status_reg;

endmodule
