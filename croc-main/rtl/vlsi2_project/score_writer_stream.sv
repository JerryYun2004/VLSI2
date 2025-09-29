// score_writer_stream.sv
module score_writer_stream #(
    parameter int DATA_W   = 32,
    parameter int ADDR_W   = 32,
    parameter int K        = 10
) (
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic                 start,         // pulse when first score may arrive
    input  logic [ADDR_W-1:0]    dst_base,

    // Score stream in
    input  logic [DATA_W-1:0]    in_data,
    input  logic                 valid_in,
    output logic                 ready_out,

    // Abstract memory write port (map to OBI)
    output logic                 wr_valid,
    input  logic                 wr_ready,
    output logic [ADDR_W-1:0]    wr_addr,
    output logic [DATA_W-1:0]    wr_data,

    output logic                 done
);
    typedef enum logic [1:0] {S_IDLE, S_WRITE, S_DONE} wstate_e;
    wstate_e st_q, st_d;

    logic [$clog2(K):0] count_q, count_d;
    logic [ADDR_W-1:0]  addr_q, addr_d;

    wire accept = valid_in && ready_out;

    always_comb begin
        st_d    = st_q;
        count_d = count_q;
        addr_d  = addr_q;

        wr_valid = 1'b0;
        wr_addr  = addr_q;
        wr_data  = in_data;

        case (st_q)
            S_IDLE: begin
                if (start) begin
                    st_d    = S_WRITE;
                    count_d = '0;
                    addr_d  = dst_base;
                end
            end

            S_WRITE: begin
                // Ready to accept a score only when bus can take a write
                wr_valid = valid_in;
                if (valid_in && wr_ready) begin
                    // consumed one score and issued one write
                    addr_d  = addr_q + (DATA_W/8);
                    count_d = count_q + 1;
                    if (count_q + 1 == K)
                        st_d = S_DONE;
                end
            end

            S_DONE: begin
                // one-cycle done
                st_d = S_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q    <= S_IDLE;
            count_q <= '0;
            addr_q  <= '0;
        end else begin
            st_q    <= st_d;
            count_q <= count_d;
            addr_q  <= addr_d;
        end
    end

    assign ready_out = (st_q == S_WRITE) ? wr_ready : 1'b0;
    assign done      = (st_q == S_DONE);
endmodule
