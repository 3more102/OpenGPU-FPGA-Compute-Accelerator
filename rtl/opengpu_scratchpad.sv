// Synchronous lane-local memory banks. Memory contents are intentionally not reset.
module opengpu_scratchpad #(
    parameter int LANES = 8,
    parameter int WIDTH = 32,
    parameter int ADDR_BITS = 6
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [LANES-1:0] req_valid,
    input  logic req_write,
    input  logic [LANES-1:0][ADDR_BITS-1:0] addr,
    input  logic [LANES-1:0][WIDTH-1:0] wdata,
    output logic [LANES-1:0][WIDTH-1:0] rdata
);
    localparam int DEPTH = 1 << ADDR_BITS;
    logic [WIDTH-1:0] mem [0:LANES-1][0:DEPTH-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata <= '0;
        end else begin
            for (int lane = 0; lane < LANES; lane++) begin
                if (req_valid[lane]) begin
                    if (req_write) begin
                        mem[lane][addr[lane]] <= wdata[lane];
                    end else begin
                        rdata[lane] <= mem[lane][addr[lane]];
                    end
                end
            end
        end
    end
endmodule
