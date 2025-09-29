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

    logic [DATA_WIDTH-1:0] pixel_in_q;
    logic                  pixel_valid_q;


    logic [ADDR_WIDTH-1:0] input_base_q, input_base_d;
    logic start_reg_q, start_reg_d;
    logic status_reg;
    logic signed [DATA_WIDTH-1:0] weights_reg[0:8];
    logic [ADDR_WIDTH-1:0] read_addr_q, read_addr_d;

    logic [3:0] class_idx_q, class_idx_d;

    logic [DATA_WIDTH-1:0] window[0:8];
    logic window_valid;
    logic signed [31:0] conv_out, relu_out_data, pooled_out;
    logic relu_valid_in, relu_ready_in;
    logic relu_valid_out, relu_ready_out;

    logic [ADDR_WIDTH-1:0] read_addr;
    
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

    localparam ADDR_CTRL = 32'h20001000;
    localparam ADDR_STATUS = 32'h20001004;
    localparam ADDR_INPUT_BASE = 32'h20001008;
    localparam ADDR_WEIGHT_BASE = 32'h20001010;
    localparam ADDR_CLASS_IDX = 32'h20001014;

    localparam ADDR_CLASS_SCORES = 32'h20001020;

    logic start_reg_set; // Declare this at module scope
    logic write_enable;
    
    logic obi_busy;
    
    
    logic pending_read_q, pending_read_d;
    logic [ObiCfg.DataWidth-1:0] rsp_data_d, rsp_data_q;
    logic rsp_err_d, rsp_err_q;
    logic [ObiCfg.IdWidth-1:0] pending_rid_q, pending_rid_d;
    logic write_in_progress_q, write_in_progress_d;

    logic [3:0] weight_write_count_q, weight_write_count_d;
    logic weights_loaded_summary_q, weights_loaded_summary_d;
    
    `FF(weight_write_count_q, weight_write_count_d, 4'd0)
    `FF(weights_loaded_summary_q, weights_loaded_summary_d, 1'b0)
    
    always_comb begin
        // Defaults
        pending_read_d       = pending_read_q;
        rsp_data_d           = rsp_data_q;
        rsp_err_d            = rsp_err_q;
        pending_rid_d        = pending_rid_q;
        write_in_progress_d  = write_in_progress_q;
    
        input_base_d         = input_base_q;
        start_reg_set        = 1'b0;
        class_idx_d          = class_idx_q;
        class_scores_d       = class_scores_q;
        weight_write_count_d = weight_write_count_q;
        weights_loaded_summary_d = weights_loaded_summary_q;
    
        if (sbr_obi_req_i.req && !obi_busy) begin
            if (write_enable) begin
                if (sbr_obi_req_i.a.addr >= ADDR_WEIGHT_BASE && sbr_obi_req_i.a.addr < ADDR_WEIGHT_BASE + 9*4) begin
                    weights_reg[(sbr_obi_req_i.a.addr - ADDR_WEIGHT_BASE) >> 2] = sbr_obi_req_i.a.wdata[DATA_WIDTH-1:0];
                    weight_write_count_d = weight_write_count_q + 1;
                end else unique case (sbr_obi_req_i.a.addr)
                    ADDR_CTRL:     start_reg_set = 1'b1;
                    ADDR_INPUT_BASE: input_base_d = sbr_obi_req_i.a.wdata;
                    ADDR_CLASS_IDX:  class_idx_d  = sbr_obi_req_i.a.wdata[3:0];
                    default: rsp_err_d = 1'b1;
                endcase
    
                write_in_progress_d = 1'b1;
            end else if (sbr_obi_req_i.a.we && write_in_progress_q) begin
                // Skip repeated write attempts
            end else begin
                // ---- READ ----
                rsp_err_d = 1'b0;
                if (sbr_obi_req_i.a.addr >= ADDR_WEIGHT_BASE && sbr_obi_req_i.a.addr < ADDR_WEIGHT_BASE + 9*4) begin
                    rsp_data_d = {{(32 - DATA_WIDTH){1'b0}}, weights_reg[(sbr_obi_req_i.a.addr - ADDR_WEIGHT_BASE) >> 2]};
                end else unique case (sbr_obi_req_i.a.addr)
                    ADDR_STATUS:     rsp_data_d = status_reg;
                    ADDR_INPUT_BASE: rsp_data_d = input_base_q;
                    ADDR_CLASS_IDX:  rsp_data_d = {{28'd0}, class_idx_q};
                    default: begin
                        if (sbr_obi_req_i.a.addr >= ADDR_CLASS_SCORES && sbr_obi_req_i.a.addr < ADDR_CLASS_SCORES + 10*4) begin
                            rsp_data_d = class_scores_q[(sbr_obi_req_i.a.addr - ADDR_CLASS_SCORES) >> 2];
                        end else begin
                            rsp_data_d = 32'hDEAD_BEEF;
                            rsp_err_d  = 1'b1;
                        end
                    end
                endcase
    
                pending_read_d = 1'b1;
                pending_rid_d  = sbr_obi_req_i.a.aid;
            end
        end
    
        // Clear pending read
        if (pending_read_q && sbr_obi_rsp_o.rvalid)
            pending_read_d = 1'b0;
    
        if (write_in_progress_q && sbr_obi_rsp_o.gnt)
            write_in_progress_d = 1'b0;
    
        // Display weights summary when all are written
        if (weight_write_count_d == 9 && !weights_loaded_summary_q) begin
            weights_loaded_summary_d = 1'b1;
            $display("[CNN] All 9 weights loaded:");
            for (int i = 0; i < 9; i++) begin
                $display("  Weight[%0d] = %0d", i, weights_reg[i]);
            end
        end
    end
    
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            weight_write_count_q <= 4'd0;
            weights_loaded_summary_q <= 1'b0;
        end else begin
            weight_write_count_q <= weight_write_count_d;
            weights_loaded_summary_q <= weights_loaded_summary_d;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        pixel_in_q    <= '0;
        pixel_valid_q <= 1'b0;
      end else begin
        pixel_valid_q <= user_mem_read_en;          // valid is the previous cycle's read_en
        if (user_mem_read_en)
          pixel_in_q <= user_mem_data_in;           // capture the returned data
      end
    end

    
    assign handshake_done = sbr_obi_req_i.req && sbr_obi_rsp_o.gnt && sbr_obi_rsp_o.rvalid;
    assign obi_busy       = pending_read_q; // CNN is processing when not in IDLE
    assign write_enable   = sbr_obi_req_i.req && sbr_obi_req_i.a.we && !write_in_progress_q && sbr_obi_rsp_o.gnt;
    
    // OBI protocol signals
    assign sbr_obi_rsp_o.gnt = sbr_obi_req_i.req && (!obi_busy || sbr_obi_req_i.a.we);
    assign sbr_obi_rsp_o.rvalid = pending_read_q && !handshake_done;
    assign sbr_obi_rsp_o.r.rdata = rsp_data_q;
    assign sbr_obi_rsp_o.r.rid = pending_rid_q;  // track ID from req
    assign sbr_obi_rsp_o.r.err = rsp_err_q;
    assign sbr_obi_rsp_o.r.r_optional = '0;


    assign mgr_obi_req_o.req = (state == READ);
    assign mgr_obi_req_o.a.we = 1'b0;
    assign mgr_obi_req_o.a.addr = read_addr_q;
    assign mgr_obi_req_o.a.wdata = '0;
    assign mgr_obi_req_o.a.be = '1;
    assign mgr_obi_req_o.a.aid = '0;

    line_buffer #(.DATA_WIDTH(DATA_WIDTH), .WIDTH(28)) u_line_buffer (
      .clk         (clk_i),
      .rst_n       (rst_ni),
      .pixel_in    (pixel_in_q),
      .valid_in    (pixel_valid_q),
      .window      (window),
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

    max_pool2x2_streaming #(
      .DATA_WIDTH(32),
      .WIDTH      (FEATURE_MAP_WIDTH)   // e.g., 28 after ReLU if padding kept
    ) u_maxpool2x2 (
      .clk       (clk_i),
      .rst_n     (rst_ni),
    
      .in_data   (relu_out_data),
      .valid_in  (relu_valid_out),
      .ready_out (relu_ready_in),       // back-pressure to ReLU
    
      .out_data  (pool_out_data),
      .valid_out (pool_valid_out),
      .ready_in  (pool_ready_in)        // from your downstream (e.g., writer)
    );


    assign relu_valid_in = window_valid && relu_ready_in;

    // After your ReLU and MaxPool:
    logic [DATA_W-1:0] pool_data;
    logic              pool_v, pool_rdy;
    
    // GAP+FC head
    logic [DATA_W-1:0] score_data;
    logic              score_v, score_rdy, head_done;
    
    gap_fc_head_streaming #(
      .DATA_W (32),
      .K      (10),
      .SCALE_Q(16)
    ) u_head (
      .clk        (clk_i),
      .rst_n      (rst_ni),
      .start      (start_head),        // pulse when first pooled pixel of image arrives
      .npix       (npix_value),        // (WIDTH/2)*(HEIGHT/2)
    
      .in_data    (pool_data),
      .valid_in   (pool_v),
      .ready_out  (pool_rdy),
    
      .w_we       (fc_w_we), .w_waddr(fc_w_addr), .w_wdata(fc_w_data),
      .b_we       (fc_b_we), .b_waddr(fc_b_addr), .b_wdata(fc_b_data),
      .scale_we   (gap_scale_we), .scale_wdata(gap_scale_data),
    
      .score_out  (score_data),
      .score_valid(score_v),
      .score_ready(score_rdy),
    
      .done       (head_done)
    );
    
    // Back-pressure from head to MaxPool
    assign pool_ready_in = pool_rdy;
    
    // Score writer to SRAM
    logic wr_done;
    score_writer_stream #(
      .DATA_W(32), .ADDR_W(32), .K(10)
    ) u_writer (
      .clk       (clk_i),
      .rst_n     (rst_ni),
      .start     (start_writer),      // assert with/after first score expected; simplest: tie to 'score_v' rising edge with a 1-cycle pulse or to start_head delayed
      .dst_base  (scores_dst_base),
    
      .in_data   (score_data),
      .valid_in  (score_v),
      .ready_out (score_rdy),
    
      .wr_valid  (mem_wr_valid),
      .wr_ready  (mem_wr_ready),
      .wr_addr   (mem_wr_addr),
      .wr_data   (mem_wr_data),
    
      .done      (wr_done)
    );
    
    // FSM: assert start_head with first pooled pixel of each inference,
    // wait for 'wr_done' then raise STATUS.done.


    
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
        if (!rst_ni) begin
            pending_read_q      <= 1'b0;
            rsp_data_q          <= '0;
            rsp_err_q           <= 1'b0;
            pending_rid_q       <= '0;
            write_in_progress_q <= 1'b0;
        end else begin
            pending_read_q      <= pending_read_d;
            rsp_data_q          <= rsp_data_d;
            rsp_err_q           <= rsp_err_d;
            pending_rid_q       <= pending_rid_d;
            write_in_progress_q <= write_in_progress_d;
    
            if (write_enable && write_in_progress_q && sbr_obi_rsp_o.gnt) begin
                $error("[CNN] Double write hazard detected at time %0t", $time);
            end
            if (write_in_progress_q && sbr_obi_req_i.req && !sbr_obi_rsp_o.gnt) begin
                $error("[CNN] Write in progress but no grant issued at time %0t", $time);
            end
        end
    end

    typedef enum logic [1:0] {IDLE, READ, PROCESS, WRITE} state_t;
    state_t state, next_state;
    always_comb begin
        next_state = state;
        user_mem_read_en = 0;
        user_mem_write_en = 0;
        user_mem_addr = 0;
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
