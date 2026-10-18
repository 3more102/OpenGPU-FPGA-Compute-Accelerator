module opengpu_alu #(
    parameter int LANES = 8,
    parameter int WIDTH = 32
) (
    input  logic [LANES-1:0] mask,
    input  logic [2:0] op,
    input  logic [LANES*WIDTH-1:0] a,
    input  logic [LANES*WIDTH-1:0] b,
    output wire [LANES*WIDTH-1:0] y
);
    localparam logic [2:0] ADD = 3'd0;
    localparam logic [2:0] SUB = 3'd1;
    localparam logic [2:0] AND_OP = 3'd2;
    localparam logic [2:0] OR_OP = 3'd3;
    localparam logic [2:0] XOR_OP = 3'd4;
    localparam logic [2:0] SHL = 3'd5;
    localparam logic [2:0] SHR = 3'd6;
    localparam logic [2:0] MUL = 3'd7;

    for (genvar lane = 0; lane < LANES; lane++) begin : gen_lane_alu
        wire [WIDTH-1:0] lane_a = a[lane*WIDTH +: WIDTH];
        wire [WIDTH-1:0] lane_b = b[lane*WIDTH +: WIDTH];
        logic [WIDTH-1:0] lane_y;

        always_comb begin
            lane_y = '0;
            if (mask[lane]) begin
                case (op)
                    ADD:     lane_y = lane_a + lane_b;
                    SUB:     lane_y = lane_a - lane_b;
                    AND_OP:  lane_y = lane_a & lane_b;
                    OR_OP:   lane_y = lane_a | lane_b;
                    XOR_OP:  lane_y = lane_a ^ lane_b;
                    SHL:     lane_y = lane_a << (lane_b % WIDTH);
                    SHR:     lane_y = lane_a >> (lane_b % WIDTH);
                    MUL:     lane_y = lane_a * lane_b;
                    default: lane_y = '0;
                endcase
            end
        end

        assign y[lane*WIDTH +: WIDTH] = lane_y;
    end
endmodule
