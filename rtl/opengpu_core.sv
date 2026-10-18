// Single-warp, in-order SIMT execution core.
// Host writes are accepted only when issue_ready is high; r0 is hard-wired to zero.
module opengpu_core #(
    parameter int LANES = 8,
    parameter int WIDTH = 32,
    parameter int REGS  = 16
) (
    input  logic clk,
    input  logic rst_n,
    input  logic issue_valid,
    input  logic [31:0] instruction,
    input  logic [LANES-1:0] exec_mask,
    output logic issue_ready,
    input  logic host_we,
    input  logic [((LANES <= 1) ? 1 : $clog2(LANES))-1:0] host_lane,
    input  logic [3:0] host_rd,
    input  logic [WIDTH-1:0] host_wdata,
    output logic retire_valid,
    output logic [LANES-1:0] retire_mask,
    output logic [3:0] retire_rd,
    output logic [WIDTH-1:0] retire_data [LANES]
);
    // ISA: [31:29] op, [28:25] rd, [24:21] rs1, [20:17] rs2.
    // [16:0] is reserved and must be zero in canonical instructions.
    logic [WIDTH-1:0] rf [LANES][REGS];
    logic [WIDTH-1:0] a [LANES];
    logic [WIDTH-1:0] b [LANES];
    logic [WIDTH-1:0] result [LANES];
    logic [2:0] op;
    logic [3:0] rd;
    logic [3:0] rs1;
    logic [3:0] rs2;

    assign op  = instruction[31:29];
    assign rd  = instruction[28:25];
    assign rs1 = instruction[24:21];
    assign rs2 = instruction[20:17];

    // Host writes stall issue to avoid a same-cycle register-file write conflict.
    assign issue_ready = !host_we;

    always_comb begin
        for (int lane = 0; lane < LANES; lane++) begin
            a[lane] = (rs1 == 0) ? '0 : rf[lane][rs1];
            b[lane] = (rs2 == 0) ? '0 : rf[lane][rs2];
        end
    end

    opengpu_alu #(.LANES(LANES), .WIDTH(WIDTH)) alu (
        .mask(exec_mask),
        .op(op),
        .a(a),
        .b(b),
        .y(result)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            retire_valid <= 1'b0;
            retire_mask  <= '0;
            retire_rd    <= '0;
            for (int lane = 0; lane < LANES; lane++) begin
                retire_data[lane] <= '0;
                for (int reg_idx = 0; reg_idx < REGS; reg_idx++) begin
                    rf[lane][reg_idx] <= '0;
                end
            end
        end else begin
            retire_valid <= issue_valid && issue_ready;

            if (issue_valid && issue_ready) begin
                retire_mask <= exec_mask;
                retire_rd   <= rd;
                for (int lane = 0; lane < LANES; lane++) begin
                    retire_data[lane] <= exec_mask[lane] ? result[lane] : '0;
                    if (exec_mask[lane] && (rd != 0)) begin
                        rf[lane][rd] <= result[lane];
                    end
                end
            end else if (host_we && (host_rd != 0) && (host_lane < LANES)) begin
                rf[host_lane][host_rd] <= host_wdata;
            end
        end
    end
endmodule
