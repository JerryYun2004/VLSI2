// Auto-generated testbench for cnn_top
`timescale 1ns/1ps
module cnn_top_tb;

    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 32;
    localparam IMAGE_SIZE = 28 * 28;
    localparam MAX_TESTS  = 100;
    localparam INPUT_BASE  = 32'h1A10_0000;
    localparam OUTPUT_BASE = 32'h1A10_0400;

    logic clk;
    logic rst_n;
    logic testmode;
    logic [DATA_WIDTH-1:0] mem [0:65535];

    typedef struct packed {
        logic req;
        struct packed {
            logic we;
            logic [ADDR_WIDTH-1:0] addr;
            logic [DATA_WIDTH-1:0] wdata;
            logic [3:0] aid;
        } a;
    } obi_req_t;

    typedef struct packed {
        logic gnt;
        logic rvalid;
        struct packed {
            logic [DATA_WIDTH-1:0] rdata;
            logic [3:0] rid;
            logic err;
            logic [1:0] r_optional;
        } r;
    } obi_rsp_t;

    obi_req_t obi_req;
    obi_rsp_t obi_rsp;

    logic [ADDR_WIDTH-1:0] user_addr;
    logic [DATA_WIDTH-1:0] user_data_out;
    logic [DATA_WIDTH-1:0] user_data_in;
    logic user_rd_en, user_wr_en;
    logic done;

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

    initial clk = 0;
    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (user_rd_en)
            user_data_in <= mem[user_addr];
        if (user_wr_en)
            mem[user_addr] <= user_data_out;
    end

    // Test loop logic
    integer i, errors = 0;
    logic [31:0] golden;

    initial begin
        rst_n = 0;
        testmode = 0;
        obi_req = '0;
        #20 rst_n = 1;

        for (i = 0; i < MAX_TESTS; i++) begin
            // Random test image input (for demo purpose)
            foreach (mem[INPUT_BASE +: IMAGE_SIZE]) begin
                mem[INPUT_BASE + i] = $urandom_range(0, 255);
            end

            // Write INPUT_BASE
            obi_req.a.addr = 32'h08;
            obi_req.a.wdata = INPUT_BASE;
            obi_req.a.we = 1;
            obi_req.req = 1;
            #10 obi_req.req = 0;

            // Write OUTPUT_BASE
            obi_req.a.addr = 32'h0C;
            obi_req.a.wdata = OUTPUT_BASE;
            obi_req.a.we = 1;
            obi_req.req = 1;
            #10 obi_req.req = 0;

            // CTRL to start
            obi_req.a.addr = 32'h00;
            obi_req.a.wdata = 32'h1;
            obi_req.a.we = 1;
            obi_req.req = 1;
            #10 obi_req.req = 0;

            wait (done == 1);
            #10;

            // Mock expected value: hardcoded for now
            // expected digit label, placeholder for now (simulate random digit 0-9)
            golden = $urandom_range(0, 9);

            if (mem[OUTPUT_BASE] !== golden) begin
                $display("[FAIL] Test %0d: Got %0d, expected %0d", i, mem[OUTPUT_BASE], golden);
                errors++;
            end else begin
                $display("[PASS] Test %0d: Got %0d", i, mem[OUTPUT_BASE]);
            end
        end

        $display("\nTotal tests: %0d", MAX_TESTS);
        $display("Errors:      %0d", errors);
        $display("Accuracy:    %0.2f%%", 100.0 * (MAX_TESTS - errors) / MAX_TESTS);
        $finish;
    end

endmodule
