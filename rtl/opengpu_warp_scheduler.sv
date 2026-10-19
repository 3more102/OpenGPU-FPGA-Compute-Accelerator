// Phase 15 round-robin warp selection with per-warp eligibility.
// This module selects a warp but does not yet provide register-file context
// switching, separate PCs, or instruction retirement tracking.
module opengpu_warp_scheduler #(
    parameter int WARPS = 2,
    parameter int WARP_W = (WARPS <= 1) ? 1 : $clog2(WARPS)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [WARPS-1:0] runnable,
    input  logic issue_accept,
    output logic issue_valid,
    output logic [WARP_W-1:0] issue_warp
);
    logic [WARP_W-1:0] next_warp;
    always_comb begin
        issue_valid = 1'b0;
        issue_warp = '0;
        for (int offset = 0; offset < WARPS; offset++) begin
            int idx;
            idx = next_warp + offset;
            if (idx >= WARPS) idx = idx - WARPS;
            if (!issue_valid && runnable[idx]) begin
                issue_valid = 1'b1;
                issue_warp = idx[WARP_W-1:0];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            next_warp <= '0;
        else if (issue_valid && issue_accept) begin
            if (issue_warp == WARPS-1)
                next_warp <= '0;
            else
                next_warp <= issue_warp + 1'b1;
        end
    end
endmodule
