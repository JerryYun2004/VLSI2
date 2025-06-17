// Simple testbench for cnn_top
`timescale 1ns/1ps
module cnn_top_tb;

    // Parameters
    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 32;
    localparam MEM_DEPTH  = 64;

    localparam INPUT_BASE  = 32'h1A10_0000;
    localparam OUTPUT_BASE = 32'h1A10_0010;

    // DUT Inputs
    logic clk;
    logic rst_n;
    logic testmode;
    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    logic [DATA_WIDTH-1:0] mem_out_data;

    // OBI simplified
    typedef struct packed {
        logic                 req;
        struct packed {
            logic             we;
            logic [ADDR_WIDTH-1:0] addr;
            logic [DATA_WIDTH-1:0] wdata;
            logic [3:0]       aid;
        } a;
    } obi_req_t;

    typedef struct packed {
        logic                 gnt;
        logic                 rvalid;
        struct packed {
            logic [DATA_WIDTH-1:0] rdata;
            logic [3:0]            rid;
            logic                  err;
            logic [1:0]            r_optional;
        } r;
    } obi_rsp_t;

    obi_req_t obi_req;
    obi_rsp_t obi_rsp;

    // Memory interface wires
    logic [ADDR_WIDTH-1:0] user_addr;
    logic [DATA_WIDTH-1:0] user_data_out;
    logic [DATA_WIDTH-1:0] user_data_in;
    logic user_rd_en, user_wr_en;
    logic done;

    // Instantiate DUT
    cnn_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .testmode_i(testmode),
        .obi_req_i(obi_req),
        .obi_rsp_o(obi_rsp),
        .done(done),
        .user_mem_data_in(user_data_in),
        .user_mem_data_out(user_data_out),
        .user_mem_addr(user_addr),
        .user_mem_read_en(user_rd_en),
        .user_mem_write_en(user_wr_en)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Memory behavior
    always_ff @(posedge clk) begin
        if (user_rd_en)
            user_data_in <= mem[user_addr];
        if (user_wr_en)
            mem[user_addr] <= user_data_out;
    end

    // Stimulus
    initial begin
        rst_n = 0;
        testmode = 0;
        obi_req = '0;
        #20 rst_n = 1;

        // Store the input image (3x3) at valid address space
        mem[INPUT_BASE + 0] = 10;
        mem[INPUT_BASE + 1] = 20;
        mem[INPUT_BASE + 2] = 30;
        mem[INPUT_BASE + 3] = 40;
        mem[INPUT_BASE + 4] = 50;
        mem[INPUT_BASE + 5] = 60;
        mem[INPUT_BASE + 6] = 70;
        mem[INPUT_BASE + 7] = 80;
        mem[INPUT_BASE + 8] = 90;

        #10;
        // Write INPUT_BASE
        obi_req.a.addr  = 32'h08;
        obi_req.a.wdata = INPUT_BASE;
        obi_req.a.we    = 1;
        obi_req.req     = 1;
        #10 obi_req.req = 0;

        // Write OUTPUT_BASE
        obi_req.a.addr  = 32'h0C;
        obi_req.a.wdata = OUTPUT_BASE;
        obi_req.a.we    = 1;
        obi_req.req     = 1;
        #10 obi_req.req = 0;

        // Write CTRL to start
        obi_req.a.addr  = 32'h00;
        obi_req.a.wdata = 32'h1;
        obi_req.a.we    = 1;
        obi_req.req     = 1;
        #10 obi_req.req = 0;

        // Wait for done
        wait (done == 1);
        #20;

        $display("CNN done. Output at 0x%08h = %0d", OUTPUT_BASE, mem[OUTPUT_BASE]);
        $finish;
    end

endmodule
