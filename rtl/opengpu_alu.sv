module opengpu_alu #(
    parameter int LANES = 8,
    parameter int WIDTH = 32
) (
    input  logic [LANES-1:0] mask,
    input  logic [2:0] op,
    input  logic [WIDTH-1:0] a [0:LANES-1],
    input  logic [WIDTH-1:0] b [0:LANES-1],
    output logic [WIDTH-1:0] y [0:LANES-1]
);
    localparam logic [2:0] ADD = 3'd0;
    localparam logic [2:0] SUB = 3'd1;
    localparam logic [2:0] AND_OP = 3'd2;
    localparam logic [2:0] OR_OP = 3'd3;
    localparam logic [2:0] XOR_OP = 3'd4;
    localparam logic [2:0] SHL = 3'd5;
    localparam logic [2:0] SHR = 3'd6;
    localparam logic [2:0] MUL = 3'd7;

    always_comb begin
        for (int lane = 0; lane < LANES; lane++) begin
            y[lane] = '0;
            if (mask[lane]) begin
                case (op)
                    ADD:    y[lane] = a[lane] + b[lane];
                    SUB:    y[lane] = a[lane] - b[lane];
                    AND_OP: y[lane] = a[lane] & b[lane];
                    OR_OP:  y[lane] = a[lane] | b[lane];
                    XOR_OP: y[lane] = a[lane] ^ b[lane];
                    SHL:    y[lane] = a[lane] << b[lane][$clog2(WIDTH)-1:0];
                    SHR:    y[lane] = a[lane] >> b[lane][$clog2(WIDTH)-1:0];
                    MUL:    y[lane] = a[lane] * b[lane];
                    default: y[lane] = '0;
                endcase
            end
        end
    end
endmodule
