// Golden model (behavioral reference model in SystemVerilog)
module cnn_golden_model #(parameter DATA_WIDTH = 8, ACC_WIDTH = 32) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic [DATA_WIDTH-1:0] image[0:27][0:27],
    input  logic signed [DATA_WIDTH-1:0] weight[0:8],
    output logic signed [ACC_WIDTH-1:0] result[0:25][0:25],
    output logic done
);
    int i, j, m, n;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 0;
        end else if (start) begin
            for (i = 0; i < 26; i++) begin
                for (j = 0; j < 26; j++) begin
                    result[i][j] = 0;
                    for (m = 0; m < 3; m++) begin
                        for (n = 0; n < 3; n++) begin
                            int idx = m * 3 + n;
                            result[i][j] += image[i+m][j+n] * weight[idx];
                        end
                    end
                    if (result[i][j] < 0) result[i][j] = 0; // ReLU
                end
            end
            done <= 1;
        end
    end
endmodule

// Basic testbench for CNN accelerator
module cnn_tb;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH = 32;

    logic clk;
    logic rst_n;
    logic write_en;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic done;

    // Instantiate DUT
    cnn_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .write_en(write_en),
        .addr(addr),
        .wdata(wdata),
        .rdata(rdata),
        .done(done)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Stimulus
    initial begin
        clk = 0;
        rst_n = 0;
        write_en = 0;
        #10 rst_n = 1;

        // Write weights
        for (int i = 0; i < 9; i++) begin
            @(posedge clk);
            write_en = 1;
            addr = 32'h14 + i * 4;
            wdata = $signed(i - 4);  // Example weights: -4 to 4
        end

        // Start operation
        @(posedge clk);
        write_en = 1;
        addr = 32'h00;
        wdata = 1;

        @(posedge clk);
        write_en = 0;

        // Wait for completion
        wait (done);
        $display("CNN accelerator completed.");

        // Optionally: compare to golden model result
        // Add check logic here if desired

        $finish;
    end
endmodule