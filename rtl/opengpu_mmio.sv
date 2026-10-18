// Simple single-outstanding 32-bit control/status interface for OpenGPU.
module opengpu_mmio #(
    parameter int LANES = 8,
    parameter int WIDTH = 32,
    parameter int REGS = 16,
    parameter int PROGRAM_WORDS = 12,
    parameter int ADDR_W = (PROGRAM_WORDS <= 1) ? 1 : $clog2(PROGRAM_WORDS),
    parameter int MEM_ADDR_BITS = 6
) (
    input  logic clk,
    input  logic rst_n,
    input  logic req_valid,
    output logic req_ready,
    input  logic req_write,
    input  logic [7:0] req_addr,
    input  logic [31:0] req_wdata,
    output logic rsp_valid,
    input  logic rsp_ready,
    output logic [31:0] rsp_rdata,
    output logic rsp_error
);
    localparam int LANE_W = (LANES <= 1) ? 1 : $clog2(LANES);

    // Word-addressed register map:
    // 0x00 CONTROL (W bit0=start), 0x04 STATUS (R),
    // 0x08 PROGRAM_LENGTH, 0x0C PROGRAM_ADDR, 0x10 PROGRAM_DATA,
    // 0x14 PROGRAM_CMD (W bit0=write word), 0x18 REG_SELECT (lane[3:0], reg[7:4]),
    // 0x1C REG_WDATA, 0x20 REG_CMD (W bit0=write register),
    // 0x24 EXEC_MASK, 0x28 RETIRE_INFO (R), 0x2C RETIRE_DATA (R selected lane),
    // 0x30 REG_RDATA (R selected register), 0x34 PC (R).
    logic start_pulse;
    logic host_we;
    logic program_we;
    logic [LANE_W-1:0] selected_lane;
    logic [3:0] selected_rd;
    logic [WIDTH-1:0] host_wdata_reg;
    logic [ADDR_W-1:0] program_addr_reg;
    logic [31:0] program_wdata_reg;
    logic [ADDR_W:0] program_length_reg;
    logic [LANES-1:0] exec_mask_reg;

    logic program_write_ready;
    logic busy;
    logic done;
    logic fault;
    logic [ADDR_W-1:0] program_counter;
    logic retire_valid;
    logic [LANES-1:0] retire_mask;
    logic [3:0] retire_rd;
    logic [LANES*WIDTH-1:0] retire_data;
    logic [WIDTH-1:0] host_rdata;

    assign req_ready = !rsp_valid || rsp_ready;

    opengpu_top #(
        .LANES(LANES), .WIDTH(WIDTH), .REGS(REGS), .PROGRAM_WORDS(PROGRAM_WORDS),
        .ADDR_W(ADDR_W), .MEM_ADDR_BITS(MEM_ADDR_BITS)
    ) core_top (
        .clk(clk), .rst_n(rst_n), .start(start_pulse), .exec_mask(exec_mask_reg),
        .host_we(host_we), .host_lane(selected_lane), .host_rd(selected_rd),
        .host_wdata(host_wdata_reg), .program_we(program_we), .program_addr(program_addr_reg),
        .program_wdata(program_wdata_reg), .program_length(program_length_reg),
        .program_write_ready(program_write_ready), .busy(busy), .done(done), .fault(fault),
        .program_counter(program_counter), .retire_valid(retire_valid),
        .retire_mask(retire_mask), .retire_rd(retire_rd), .retire_data(retire_data),
        .host_rdata(host_rdata)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid <= 1'b0;
            rsp_rdata <= '0;
            rsp_error <= 1'b0;
            start_pulse <= 1'b0;
            host_we <= 1'b0;
            program_we <= 1'b0;
            selected_lane <= '0;
            selected_rd <= '0;
            host_wdata_reg <= '0;
            program_addr_reg <= '0;
            program_wdata_reg <= '0;
            program_length_reg <= PROGRAM_WORDS;
            exec_mask_reg <= '1;
        end else begin
            start_pulse <= 1'b0;
            host_we <= 1'b0;
            program_we <= 1'b0;

            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;

            if (req_valid && req_ready) begin
                rsp_valid <= 1'b1;
                rsp_rdata <= '0;
                rsp_error <= 1'b0;

                if (req_addr[1:0] != 2'b00) begin
                    rsp_error <= 1'b1;
                end else if (req_write) begin
                    case (req_addr)
                        8'h00: begin
                            if (req_wdata[0]) begin
                                if (busy || fault)
                                    rsp_error <= 1'b1;
                                else
                                    start_pulse <= 1'b1;
                            end
                        end
                        8'h08: begin
                            if (program_write_ready)
                                program_length_reg <= req_wdata[ADDR_W:0];
                            else
                                rsp_error <= 1'b1;
                        end
                        8'h0C: begin
                            if (program_write_ready)
                                program_addr_reg <= req_wdata[ADDR_W-1:0];
                            else
                                rsp_error <= 1'b1;
                        end
                        8'h10: begin
                            if (program_write_ready)
                                program_wdata_reg <= req_wdata;
                            else
                                rsp_error <= 1'b1;
                        end
                        8'h14: begin
                            if (req_wdata[0]) begin
                                if (program_write_ready)
                                    program_we <= 1'b1;
                                else
                                    rsp_error <= 1'b1;
                            end
                        end
                        8'h18: begin
                            if (req_wdata[LANE_W-1:0] < LANES) begin
                                selected_lane <= req_wdata[LANE_W-1:0];
                                selected_rd <= req_wdata[7:4];
                            end else begin
                                rsp_error <= 1'b1;
                            end
                        end
                        8'h1C: begin
                            host_wdata_reg <= req_wdata;
                        end
                        8'h20: begin
                            if (req_wdata[0]) begin
                                if (program_write_ready)
                                    host_we <= 1'b1;
                                else
                                    rsp_error <= 1'b1;
                            end
                        end
                        8'h24: begin
                            if (program_write_ready)
                                exec_mask_reg <= req_wdata[LANES-1:0];
                            else
                                rsp_error <= 1'b1;
                        end
                        default: rsp_error <= 1'b1;
                    endcase
                end else begin
                    case (req_addr)
                        8'h00: rsp_rdata <= 32'd0;
                        8'h04: rsp_rdata <= {28'd0, program_write_ready, fault, done, busy};
                        8'h08: rsp_rdata <= program_length_reg;
                        8'h0C: rsp_rdata <= program_addr_reg;
                        8'h10: rsp_rdata <= program_wdata_reg;
                        8'h14: rsp_rdata <= 32'd0;
                        8'h18: begin
                            rsp_rdata <= 32'd0;
                            rsp_rdata[LANE_W-1:0] <= selected_lane;
                            rsp_rdata[7:4] <= selected_rd;
                        end
                        8'h1C: rsp_rdata <= host_wdata_reg;
                        8'h20: rsp_rdata <= 32'd0;
                        8'h24: rsp_rdata <= exec_mask_reg;
                        8'h28: begin
                            rsp_rdata <= 32'd0;
                            rsp_rdata[LANES-1:0] <= retire_mask;
                            rsp_rdata[LANES+3:LANES] <= retire_rd;
                        end
                        8'h2C: begin
                            if (selected_lane < LANES)
                                rsp_rdata <= retire_data[selected_lane*WIDTH +: WIDTH];
                            else
                                rsp_error <= 1'b1;
                        end
                        8'h30: rsp_rdata <= host_rdata;
                        8'h34: rsp_rdata <= program_counter;
                        default: rsp_error <= 1'b1;
                    endcase
                end
            end
        end
    end
endmodule
