// Single-warp, in-order SIMT core: integer ALU, lane-local memory, immediates and uniform branches.
module opengpu_core #(
    parameter int LANES = 8,
    parameter int WIDTH = 32,
    parameter int REGS  = 16,
    parameter int MEM_ADDR_BITS = 6
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
    output logic [WIDTH-1:0] host_rdata,
    output logic retire_valid,
    output logic [LANES-1:0] retire_mask,
    output logic [3:0] retire_rd,
    output logic [LANES*WIDTH-1:0] retire_data,
    output logic branch_valid,
    output logic branch_taken,
    output logic branch_divergent,
    output logic signed [15:0] branch_offset,
    output logic illegal_instruction
);
    logic [WIDTH-1:0] rf [0:LANES-1][0:REGS-1];
    logic [LANES*WIDTH-1:0] a;
    logic [LANES*WIDTH-1:0] b;
    logic [LANES*WIDTH-1:0] result;
    logic [LANES*MEM_ADDR_BITS-1:0] mem_addr;
    logic [LANES*WIDTH-1:0] mem_wdata;
    logic [LANES*WIDTH-1:0] mem_rdata;
    logic [LANES-1:0] mem_req_valid;
    logic mem_instruction;
    logic mem_store;
    logic imm_instruction;
    logic branch_instruction;
    logic [2:0] op;
    logic [3:0] rd;
    logic [3:0] rs1;
    logic [3:0] rs2;
    logic [3:0] branch_rs_a;
    logic [3:0] branch_rs_b;
    logic accepted;
    logic load_pending;
    logic [3:0] pending_load_rd;
    logic [LANES-1:0] pending_load_mask;
    logic branch_predicate;
    logic branch_reference;
    logic branch_reference_set;

    assign op = instruction[31:29];
    assign rd = instruction[28:25];
    assign rs1 = instruction[24:21];
    assign rs2 = instruction[20:17];

    // Extended encodings are disambiguated by the four-bit tag in [20:17].
    // tag 0 + opcode 0 = lane-local memory; tag 15 = immediate ALU; tag 14 = branch.
    assign mem_instruction = instruction[16] && (op == 3'd0) && (rs2 == 4'd0);
    assign imm_instruction = instruction[16] && (rs2 == 4'd15);
    assign branch_instruction = instruction[16] && (rs2 == 4'd14);
    assign branch_valid = branch_instruction && (op != 3'd7);
    assign branch_offset = instruction[15:0];
    assign branch_rs_a = instruction[28:25];
    assign branch_rs_b = instruction[24:21];
    assign mem_store = instruction[15];
    assign accepted = issue_valid && issue_ready;
    assign issue_ready = !host_we && !load_pending;

    // Host readback port for software-visible register inspection.
    always_comb begin
        if ((host_lane < LANES) && (host_rd != 0))
            host_rdata = rf[host_lane][host_rd];
        else
            host_rdata = '0;
    end

    always_comb begin
        illegal_instruction = 1'b0;
        if (instruction[16]) begin
            if (!(mem_instruction || imm_instruction || branch_instruction))
                illegal_instruction = 1'b1;
            if (branch_instruction && (op == 3'd7))
                illegal_instruction = 1'b1;
        end
    end

    always_comb begin
        for (int lane = 0; lane < LANES; lane++) begin
            a[lane*WIDTH +: WIDTH] = (rs1 == 0) ? '0 : rf[lane][rs1];
            if (imm_instruction) begin
                b[lane*WIDTH +: WIDTH] = {{(WIDTH-16){instruction[15]}}, instruction[15:0]};
            end else begin
                b[lane*WIDTH +: WIDTH] = (rs2 == 0) ? '0 : rf[lane][rs2];
            end
            mem_addr[lane*MEM_ADDR_BITS +: MEM_ADDR_BITS] =
                rf[lane][rs1] + {{(WIDTH-15){instruction[14]}}, instruction[14:0]};
            mem_wdata[lane*WIDTH +: WIDTH] = (rd == 0) ? '0 : rf[lane][rd];
            mem_req_valid[lane] = accepted && mem_instruction && exec_mask[lane];
        end
    end

    // Branches are warp-uniform in this phase. A predicate disagreement across
    // active lanes is reported as divergence; the top-level controller halts.
    always_comb begin
        branch_taken = 1'b0;
        branch_divergent = 1'b0;
        branch_reference = 1'b0;
        branch_reference_set = 1'b0;
        branch_predicate = 1'b0;
        if (branch_valid) begin
            for (int lane = 0; lane < LANES; lane++) begin
                case (op)
                    3'd0: branch_predicate = rf[lane][branch_rs_a] == rf[lane][branch_rs_b]; // BEQ
                    3'd1: branch_predicate = rf[lane][branch_rs_a] != rf[lane][branch_rs_b]; // BNE
                    3'd2: branch_predicate = $signed(rf[lane][branch_rs_a]) < $signed(rf[lane][branch_rs_b]); // BLT
                    3'd3: branch_predicate = $signed(rf[lane][branch_rs_a]) >= $signed(rf[lane][branch_rs_b]); // BGE
                    3'd4: branch_predicate = rf[lane][branch_rs_a] < rf[lane][branch_rs_b]; // BLTU
                    3'd5: branch_predicate = rf[lane][branch_rs_a] >= rf[lane][branch_rs_b]; // BGEU
                    3'd6: branch_predicate = 1'b1; // JUMP
                    default: branch_predicate = 1'b0;
                endcase
                if (exec_mask[lane]) begin
                    if (!branch_reference_set) begin
                        branch_reference = branch_predicate;
                        branch_taken = branch_predicate;
                        branch_reference_set = 1'b1;
                    end else if (branch_predicate != branch_reference) begin
                        branch_divergent = 1'b1;
                    end
                end
            end
        end
    end

    opengpu_alu #(.LANES(LANES), .WIDTH(WIDTH)) alu (
        .mask(exec_mask), .op(op), .a(a), .b(b), .y(result)
    );

    opengpu_scratchpad #(.LANES(LANES), .WIDTH(WIDTH), .ADDR_BITS(MEM_ADDR_BITS)) scratchpad (
        .clk(clk), .rst_n(rst_n), .req_valid(mem_req_valid), .req_write(mem_store),
        .addr(mem_addr), .wdata(mem_wdata), .rdata(mem_rdata)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            retire_valid <= 1'b0;
            retire_mask <= '0;
            retire_rd <= '0;
            retire_data <= '0;
            load_pending <= 1'b0;
            pending_load_rd <= '0;
            pending_load_mask <= '0;
            for (int lane = 0; lane < LANES; lane++) begin
                for (int reg_idx = 0; reg_idx < REGS; reg_idx++) begin
                    rf[lane][reg_idx] <= '0;
                end
            end
        end else if (load_pending) begin
            // The synchronous memory read requested on the prior edge is now available.
            load_pending <= 1'b0;
            retire_valid <= 1'b1;
            retire_mask <= pending_load_mask;
            retire_rd <= pending_load_rd;
            for (int lane = 0; lane < LANES; lane++) begin
                retire_data[lane*WIDTH +: WIDTH] <= pending_load_mask[lane] ?
                    mem_rdata[lane*WIDTH +: WIDTH] : '0;
                if (pending_load_mask[lane] && (pending_load_rd != 0)) begin
                    rf[lane][pending_load_rd] <= mem_rdata[lane*WIDTH +: WIDTH];
                end
            end
        end else begin
            retire_valid <= 1'b0;
            if (accepted) begin
                if (mem_instruction && !mem_store) begin
                    load_pending <= 1'b1;
                    pending_load_rd <= rd;
                    pending_load_mask <= exec_mask;
                end else begin
                    retire_valid <= 1'b1;
                    retire_mask <= exec_mask;
                    if ((mem_instruction && mem_store) || branch_instruction || illegal_instruction)
                        retire_rd <= 4'd0;
                    else
                        retire_rd <= rd;

                    for (int lane = 0; lane < LANES; lane++) begin
                        if (!exec_mask[lane] || (mem_instruction && mem_store) ||
                            branch_instruction || illegal_instruction) begin
                            retire_data[lane*WIDTH +: WIDTH] <= '0;
                        end else begin
                            retire_data[lane*WIDTH +: WIDTH] <= result[lane*WIDTH +: WIDTH];
                        end

                        if (exec_mask[lane] && !mem_instruction && !branch_instruction &&
                            !illegal_instruction && (rd != 0)) begin
                            rf[lane][rd] <= result[lane*WIDTH +: WIDTH];
                        end
                    end
                end
            end else if (host_we && (host_rd != 0) && (host_lane < LANES)) begin
                rf[host_lane][host_rd] <= host_wdata;
            end
        end
    end
endmodule
