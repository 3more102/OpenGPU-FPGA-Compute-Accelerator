// Single-warp, in-order SIMT execution core with lane-local load/store support.
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
    output logic retire_valid,
    output logic [LANES-1:0] retire_mask,
    output logic [3:0] retire_rd,
    output logic [LANES-1:0][WIDTH-1:0] retire_data
);
    localparam int MEM_DEPTH = 1 << MEM_ADDR_BITS;

    logic [WIDTH-1:0] rf [0:LANES-1][0:REGS-1];
    logic [LANES-1:0][WIDTH-1:0] a;
    logic [LANES-1:0][WIDTH-1:0] b;
    logic [LANES-1:0][WIDTH-1:0] result;
    logic [LANES-1:0][MEM_ADDR_BITS-1:0] mem_addr;
    logic [LANES-1:0][WIDTH-1:0] mem_wdata;
    logic [LANES-1:0][WIDTH-1:0] mem_rdata;
    logic [LANES-1:0] mem_req_valid;
    logic mem_instruction;
    logic mem_store;
    logic [2:0] op;
    logic [3:0] rd;
    logic [3:0] rs1;
    logic [3:0] rs2;
    logic accepted;
    logic load_pending;
    logic [3:0] pending_load_rd;
    logic [LANES-1:0] pending_load_mask;

    assign op = instruction[31:29];
    assign rd = instruction[28:25];
    assign rs1 = instruction[24:21];
    assign rs2 = instruction[20:17];
    assign mem_instruction = instruction[16];
    assign mem_store = instruction[15];
    assign accepted = issue_valid && issue_ready;
    assign issue_ready = !host_we && !load_pending;

    always_comb begin
        for (int lane = 0; lane < LANES; lane++) begin
            a[lane] = (rs1 == 0) ? '0 : rf[lane][rs1];
            b[lane] = (rs2 == 0) ? '0 : rf[lane][rs2];
            mem_addr[lane] = rf[lane][rs1] +
                             {{(WIDTH-15){instruction[14]}}, instruction[14:0]};
            mem_wdata[lane] = (rd == 0) ? '0 : rf[lane][rd];
            mem_req_valid[lane] = accepted && mem_instruction && exec_mask[lane];
        end
    end

    opengpu_alu #(.LANES(LANES), .WIDTH(WIDTH)) alu (
        .mask(exec_mask),
        .op(op),
        .a(a),
        .b(b),
        .y(result)
    );

    opengpu_scratchpad #(.LANES(LANES), .WIDTH(WIDTH), .ADDR_BITS(MEM_ADDR_BITS)) scratchpad (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(mem_req_valid),
        .req_write(mem_store),
        .addr(mem_addr),
        .wdata(mem_wdata),
        .rdata(mem_rdata)
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
                retire_data[lane] <= pending_load_mask[lane] ? mem_rdata[lane] : '0;
                if (pending_load_mask[lane] && (pending_load_rd != 0)) begin
                    rf[lane][pending_load_rd] <= mem_rdata[lane];
                end
            end
        end else begin
            retire_valid <= 1'b0;
            if (accepted) begin
                if (mem_instruction && !mem_store) begin
                    // Delay retirement and writeback until the registered memory read returns.
                    load_pending <= 1'b1;
                    pending_load_rd <= rd;
                    pending_load_mask <= exec_mask;
                end else begin
                    retire_valid <= 1'b1;
                    retire_mask <= exec_mask;
                    retire_rd <= (mem_instruction && mem_store) ? 4'd0 : rd;
                    for (int lane = 0; lane < LANES; lane++) begin
                        if (!exec_mask[lane] || (mem_instruction && mem_store)) begin
                            retire_data[lane] <= '0;
                        end else begin
                            retire_data[lane] <= result[lane];
                        end
                        if (exec_mask[lane] && !mem_instruction && (rd != 0)) begin
                            rf[lane][rd] <= result[lane];
                        end
                    end
                end
            end else if (host_we && (host_rd != 0) && (host_lane < LANES)) begin
                rf[host_lane][host_rd] <= host_wdata;
            end
        end
    end
endmodule
