module cnn_top_tb;
    import obi_pkg::*;
    import cnn_pkg::*;  // Define CNN config if needed

    logic clk;
    logic rst_n;

    logic relu_valid_out, relu_ready_out;
    logic relu_valid_in, relu_ready_in;
    logic signed [31:0] relu_out_data;
    logic done;

    // Clock generation
    always #5 clk = ~clk;

    // Instantiate DUT
    OBI_BUS cnn_bus();

    cnn_top uut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .testmode_i(1'b0),
        .relu_valid_in(relu_valid_in),
        .relu_ready_in(relu_ready_in),
        .relu_out_data(relu_out_data),
        .relu_valid_out(relu_valid_out),
        .relu_ready_out(relu_ready_out),
        .cnn_if(cnn_bus),
        .done(done)
    );

    // Stimulus: OBI master to write weights/input base/output base/start
    task write_reg(input [31:0] addr, input [31:0] data);
        cnn_bus.req   = 1'b1;
        cnn_bus.we    = 1'b1;
        cnn_bus.a     = addr;
        cnn_bus.wdata = data;
        @(posedge clk); // Wait 1 cycle
        cnn_bus.req = 1'b0;
    endtask

    task read_reg(input [31:0] addr, output [31:0] data);
        cnn_bus.req = 1'b1;
        cnn_bus.we  = 1'b0;
        cnn_bus.a   = addr;
        @(posedge clk);
        while (!cnn_bus.rvalid) @(posedge clk);
        data = cnn_bus.rdata;
        cnn_bus.req = 1'b0;
    endtask

    // Add tasks to load input pixels, weights, and observe output

    initial begin
        clk = 0;
        rst_n = 0;
        #20 rst_n = 1;

        // Initialize inputs, weights
        // Wait for done = 1
    end
endmodule
