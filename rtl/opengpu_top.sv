// Integrated FPGA-oriented OpenGPU top with host-programmable instruction RAM.
module opengpu_top #(
    parameter int LANES = 8,
    parameter int WIDTH = 32,
    parameter int REGS = 16,
    parameter int PROGRAM_WORDS = 12,
    parameter int ADDR_W = (PROGRAM_WORDS <= 1) ? 1 : $clog2(PROGRAM_WORDS),
    parameter int MEM_ADDR_BITS = 6
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic [LANES-1:0] exec_mask,
    input  logic host_we,
    input  logic [((LANES <= 1) ? 1 : $clog2(LANES))-1:0] host_lane,
    input  logic [3:0] host_rd,
    input  logic [WIDTH-1:0] host_wdata,
    input  logic program_we,
    input  logic [ADDR_W-1:0] program_addr,
    input  logic [31:0] program_wdata,
    input  logic [ADDR_W:0] program_length,
    output logic program_write_ready,
    output logic busy,
    output logic done,
    output logic fault,
    output logic [ADDR_W-1:0] program_counter,
    output logic retire_valid,
    output logic [LANES-1:0] retire_mask,
    output logic [3:0] retire_rd,
    output logic [LANES*WIDTH-1:0] retire_data,
    output logic [WIDTH-1:0] host_rdata
);
    localparam int PROGRAM_DEPTH = 1 << ADDR_W;
    typedef enum logic [2:0] {IDLE, RUN, DRAIN, DONE, FAULT} state_t;
    state_t state;
    logic [ADDR_W-1:0] pc;
    logic [31:0] instruction;
    logic [31:0] rom_instruction;
    logic [31:0] program_mem [0:PROGRAM_DEPTH-1];
    logic [PROGRAM_DEPTH-1:0] program_valid;
    logic [ADDR_W:0] program_limit;
    logic [ADDR_W:0] active_program_limit;
    logic issue_valid;
    logic issue_ready;
    logic core_host_we;
    logic branch_valid;
    logic branch_taken;
    logic branch_divergent;
    logic signed [15:0] branch_offset;
    logic signed [31:0] branch_target_calc;
    logic illegal_instruction;

    assign program_counter = pc;
    assign busy = (state == RUN) || (state == DRAIN);
    assign done = (state == DONE);
    assign fault = (state == FAULT);
    assign issue_valid = (state == RUN);
    assign core_host_we = host_we && ((state == IDLE) || (state == DONE));
    assign program_write_ready = rst_n && ((state == IDLE) || (state == DONE));

    // A zero program_length selects the compiled-in default length. Clamp larger
    // host values to the representable instruction-memory depth.
    always_comb begin
        if (program_length == 0) begin
            if (PROGRAM_WORDS > PROGRAM_DEPTH)
                program_limit = PROGRAM_DEPTH;
            else
                program_limit = PROGRAM_WORDS;
        end else if (program_length > PROGRAM_DEPTH) begin
            program_limit = PROGRAM_DEPTH;
        end else begin
            program_limit = program_length;
        end
        branch_target_calc = $signed({1'b0, pc}) + 32'sd1 + $signed(branch_offset);
    end

    opengpu_program_rom #(.ADDR_W(ADDR_W)) program_rom (
        .addr(pc), .instruction(rom_instruction)
    );

    // Written words override the demonstration ROM. RAM data itself is not reset;
    // reset clears only the valid map, restoring the built-in demo as the fallback.
    always_comb begin
        if (program_valid[pc])
            instruction = program_mem[pc];
        else
            instruction = rom_instruction;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            program_valid <= '0;
        end else if (program_we && program_write_ready) begin
            program_mem[program_addr] <= program_wdata;
            program_valid[program_addr] <= 1'b1;
        end
    end

    opengpu_core #(
        .LANES(LANES), .WIDTH(WIDTH), .REGS(REGS), .MEM_ADDR_BITS(MEM_ADDR_BITS)
    ) core (
        .clk(clk), .rst_n(rst_n), .issue_valid(issue_valid), .instruction(instruction),
        .exec_mask(exec_mask), .issue_ready(issue_ready), .host_we(core_host_we),
        .host_lane(host_lane), .host_rd(host_rd), .host_wdata(host_wdata),
        .retire_valid(retire_valid), .retire_mask(retire_mask), .retire_rd(retire_rd),
        .retire_data(retire_data), .host_rdata(host_rdata),
        .branch_valid(branch_valid), .branch_taken(branch_taken),
        .branch_divergent(branch_divergent), .branch_offset(branch_offset),
        .illegal_instruction(illegal_instruction)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pc <= '0;
            active_program_limit <= PROGRAM_WORDS;
        end else begin
            case (state)
                IDLE: begin
                    pc <= '0;
                    if (start) begin
                        active_program_limit <= program_limit;
                        state <= RUN;
                    end
                end
                RUN: begin
                    if (issue_valid && issue_ready) begin
                        if (illegal_instruction || (branch_valid && branch_divergent)) begin
                            state <= FAULT;
                        end else if (branch_valid && branch_taken) begin
                            if ((branch_target_calc < 0) ||
                                (branch_target_calc >= $signed({1'b0, active_program_limit}))) begin
                                state <= FAULT;
                            end else begin
                                pc <= branch_target_calc[ADDR_W-1:0];
                            end
                        end else if (({1'b0, pc}) == (active_program_limit - 1'b1)) begin
                            state <= DRAIN;
                        end else begin
                            pc <= pc + 1'b1;
                        end
                    end
                end
                DRAIN: begin
                    if (retire_valid) state <= DONE;
                end
                DONE: begin
                    if (start) begin
                        pc <= '0;
                        active_program_limit <= program_limit;
                        state <= RUN;
                    end
                end
                FAULT: begin
                    state <= FAULT;
                end
                default: begin
                    state <= IDLE;
                    pc <= '0;
                end
            endcase
        end
    end
endmodule
