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
    input  logic [LANES*ADDR_BITS-1:0] addr,
    input  logic [LANES*WIDTH-1:0] wdata,
    output wire [LANES*WIDTH-1:0] rdata
);
    localparam int DEPTH = 1 << ADDR_BITS;

    for (genvar lane = 0; lane < LANES; lane++) begin : gen_lane_bank
        logic [WIDTH-1:0] mem [0:DEPTH-1];
        logic [WIDTH-1:0] rdata_reg;
        wire [ADDR_BITS-1:0] lane_addr = addr[lane*ADDR_BITS +: ADDR_BITS];
        wire [WIDTH-1:0] lane_wdata = wdata[lane*WIDTH +: WIDTH];

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                rdata_reg <= '0;
            end else if (req_valid[lane]) begin
                if (req_write) begin
                    mem[lane_addr] <= lane_wdata;
                end else begin
                    rdata_reg <= mem[lane_addr];
                end
            end
        end

        assign rdata[lane*WIDTH +: WIDTH] = rdata_reg;
    end
endmodule
