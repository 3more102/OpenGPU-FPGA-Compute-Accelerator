// Integrated FPGA-oriented OpenGPU demo: host preload -> ROM fetch -> SIMT execute.
// This is a single warp and a four-instruction demonstration, not a complete GPU.
module opengpu_top #(
    parameter int LANES = 8,
    parameter int WIDTH = 32,
    parameter int REGS = 16,
    parameter int PROGRAM_WORDS = 4,
    parameter int ADDR_W = (PROGRAM_WORDS <= 1) ? 1 : $clog2(PROGRAM_WORDS)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic [LANES-1:0] exec_mask,
    input  logic host_we,
    input  logic [((LANES <= 1) ? 1 : $clog2(LANES))-1:0] host_lane,
    input  logic [3:0] host_rd,
    input  logic [WIDTH-1:0] host_wdata,
    output logic busy,
    output logic done,
    output logic [ADDR_W-1:0] program_counter,
    output logic retire_valid,
    output logic [LANES-1:0] retire_mask,
    output logic [3:0] retire_rd,
    output logic [LANES-1:0][WIDTH-1:0] retire_data
);
    typedef enum logic [1:0] {IDLE, RUN, DRAIN, DONE} state_t;
    state_t state;
    logic [ADDR_W-1:0] pc;
    logic [31:0] instruction;
    logic issue_valid;
    logic issue_ready;
    logic core_host_we;

    assign program_counter = pc;
    assign busy = (state == RUN) || (state == DRAIN);
    assign done = (state == DONE);
    assign issue_valid = (state == RUN);
    // Preload is accepted only while idle or after completion.
    assign core_host_we = host_we && ((state == IDLE) || (state == DONE));

    opengpu_program_rom #(.ADDR_W(ADDR_W)) program_rom (
        .addr(pc),
        .instruction(instruction)
    );

    opengpu_core #(.LANES(LANES), .WIDTH(WIDTH), .REGS(REGS)) core (
        .clk(clk),
        .rst_n(rst_n),
        .issue_valid(issue_valid),
        .instruction(instruction),
        .exec_mask(exec_mask),
        .issue_ready(issue_ready),
        .host_we(core_host_we),
        .host_lane(host_lane),
        .host_rd(host_rd),
        .host_wdata(host_wdata),
        .retire_valid(retire_valid),
        .retire_mask(retire_mask),
        .retire_rd(retire_rd),
        .retire_data(retire_data)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pc <= '0;
        end else begin
            case (state)
                IDLE: begin
                    pc <= '0;
                    if (start) begin
                        state <= RUN;
                    end
                end
                RUN: begin
                    if (issue_valid && issue_ready) begin
                        if (pc == PROGRAM_WORDS - 1) begin
                            state <= DRAIN;
                        end else begin
                            pc <= pc + 1'b1;
                        end
                    end
                end
                DRAIN: begin
                    if (retire_valid) begin
                        state <= DONE;
                    end
                end
                DONE: begin
                    if (start) begin
                        pc <= '0;
                        state <= RUN;
                    end
                end
                default: begin
                    state <= IDLE;
                    pc <= '0;
                end
            endcase
        end
    end
endmodule
