// Phase 16 per-warp control context. Stores each warp's PC and active mask.
// This block is independent of the execution core and does not implement
// register-file switching or branch reconvergence.
module opengpu_warp_context #(
    parameter int WARPS = 2,
    parameter int LANES = 8,
    parameter int PC_BITS = 8,
    parameter int WARP_W = (WARPS <= 1) ? 1 : $clog2(WARPS)
) (
    input logic clk,
    input logic rst_n,
    input logic write_valid,
    input logic [WARP_W-1:0] write_warp,
    input logic [PC_BITS-1:0] write_pc,
    input logic [LANES-1:0] write_mask,
    input logic [WARP_W-1:0] read_warp,
    output logic [PC_BITS-1:0] read_pc,
    output logic [LANES-1:0] read_mask,
    output logic read_valid
);
    logic [PC_BITS-1:0] pc_bank [0:WARPS-1];
    logic [LANES-1:0] mask_bank [0:WARPS-1];
    logic [WARPS-1:0] valid_bank;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_bank <= '0;
            for (int w=0; w<WARPS; w++) begin
                pc_bank[w] <= '0;
                mask_bank[w] <= '0;
            end
        end else if (write_valid && (write_warp < WARPS)) begin
            pc_bank[write_warp] <= write_pc;
            mask_bank[write_warp] <= write_mask;
            valid_bank[write_warp] <= 1'b1;
        end
    end
    always_comb begin
        read_pc = '0;
        read_mask = '0;
        read_valid = 1'b0;
        if (read_warp < WARPS) begin
            read_pc = pc_bank[read_warp];
            read_mask = mask_bank[read_warp];
            read_valid = valid_bank[read_warp];
        end
    end
endmodule
