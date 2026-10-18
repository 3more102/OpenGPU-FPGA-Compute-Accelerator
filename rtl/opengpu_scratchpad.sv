// Private synchronous scratchpad for each lane, with a host port accessible
// only when the surrounding controller gates host_valid during IDLE/DONE.
// Memory contents are not reset. Host read data is registered (one-clock read).
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
    output wire [LANES*WIDTH-1:0] rdata,
    input  logic host_valid,
    input  logic host_write,
    input  logic [((LANES <= 1) ? 1 : $clog2(LANES))-1:0] host_lane,
    input  logic [ADDR_BITS-1:0] host_addr,
    input  logic [WIDTH-1:0] host_wdata,
    output wire [WIDTH-1:0] host_rdata
);
    localparam int DEPTH = 1 << ADDR_BITS;
    wire [LANES*WIDTH-1:0] host_rdata_banks;
    assign host_rdata = (host_lane < LANES) ?
        host_rdata_banks[host_lane*WIDTH +: WIDTH] : '0;

    for (genvar lane = 0; lane < LANES; lane++) begin : gen_lane_bank
        logic [WIDTH-1:0] mem [0:DEPTH-1];
        logic [WIDTH-1:0] rdata_reg;
        logic [WIDTH-1:0] host_rdata_reg;
        wire [ADDR_BITS-1:0] lane_addr = addr[lane*ADDR_BITS +: ADDR_BITS];
        wire [WIDTH-1:0] lane_wdata = wdata[lane*WIDTH +: WIDTH];
        wire selected = host_valid && (host_lane == lane);

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                rdata_reg <= '0;
                host_rdata_reg <= '0;
            end else if (selected) begin
                // Port arbitration is exclusive: one host access per cycle
                // takes precedence over this lane's execution request.
                if (host_write)
                    mem[host_addr] <= host_wdata;
                else
                    host_rdata_reg <= mem[host_addr];
            end else if (req_valid[lane]) begin
                if (req_write)
                    mem[lane_addr] <= lane_wdata;
                else
                    rdata_reg <= mem[lane_addr];
            end
        end

        assign rdata[lane*WIDTH +: WIDTH] = rdata_reg;
        assign host_rdata_banks[lane*WIDTH +: WIDTH] = host_rdata_reg;
    end
endmodule
