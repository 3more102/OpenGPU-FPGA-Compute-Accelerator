// Parameter-scaling regression for the single-warp OpenGPU datapath.
// Compiled with: iverilog -Ptb_opengpu_parameterized.LANES=<1,2,4,8,16>
module tb_opengpu_parameterized;
    parameter integer LANES = 8;
    localparam integer LANE_W = (LANES <= 1) ? 1 : $clog2(LANES);
    localparam integer ADDR_W = 4;

    logic clk = 1'b0, rst_n = 1'b0, start = 1'b0;
    logic [LANES-1:0] exec_mask = '1;
    logic host_we = 1'b0;
    logic [LANE_W-1:0] host_lane = '0;
    logic [3:0] host_rd = '0;
    logic [31:0] host_wdata = '0;
    logic [31:0] host_rdata;

    logic host_mem_valid = 1'b0, host_mem_write = 1'b0;
    logic [LANE_W-1:0] host_mem_lane = '0;
    logic [5:0] host_mem_addr = '0;
    logic [31:0] host_mem_wdata = '0, host_mem_rdata;

    logic program_we = 1'b0;
    logic [ADDR_W-1:0] program_addr = '0;
    logic [31:0] program_wdata = '0;
    logic [ADDR_W:0] program_length = 12;
    logic program_write_ready, busy, done, fault;
    logic [ADDR_W-1:0] program_counter;
    logic retire_valid;
    logic [LANES-1:0] retire_mask;
    logic [3:0] retire_rd;
    logic [LANES*32-1:0] retire_data;
    logic [31:0] cycle_count, retired_count, branch_taken_count;

    int observed;
    int cycles;
    logic [LANES-1:0] even_mask;

    always #5 clk = ~clk;

    opengpu_top #(.LANES(LANES), .WIDTH(32), .REGS(16),
                  .PROGRAM_WORDS(12), .MEM_ADDR_BITS(6)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .exec_mask(exec_mask),
        .host_we(host_we), .host_lane(host_lane), .host_rd(host_rd),
        .host_wdata(host_wdata), .host_rdata(host_rdata),
        .host_mem_valid(host_mem_valid), .host_mem_write(host_mem_write),
        .host_mem_lane(host_mem_lane), .host_mem_addr(host_mem_addr),
        .host_mem_wdata(host_mem_wdata), .host_mem_rdata(host_mem_rdata),
        .program_we(program_we), .program_addr(program_addr),
        .program_wdata(program_wdata), .program_length(program_length),
        .program_write_ready(program_write_ready),
        .busy(busy), .done(done), .fault(fault), .program_counter(program_counter),
        .retire_valid(retire_valid), .retire_mask(retire_mask),
        .retire_rd(retire_rd), .retire_data(retire_data),
        .cycle_count(cycle_count), .retired_count(retired_count),
        .branch_taken_count(branch_taken_count)
    );

    task automatic preload(input integer lane, input logic [3:0] rd,
                           input logic [31:0] val);
        begin
            @(negedge clk);
            if (!program_write_ready)
                $fatal(1, "cannot preload registers during active execution");
            host_we = 1'b1;
            host_lane = lane[LANE_W-1:0];
            host_rd = rd;
            host_wdata = val;
            @(negedge clk);
            host_we = 1'b0;
        end
    endtask

    task automatic read_reg(input integer lane, input logic [3:0] rd,
                            input logic [31:0] expected);
        begin
            @(negedge clk);
            host_lane = lane[LANE_W-1:0];
            host_rd = rd;
            #1;
            if (host_rdata !== expected)
                $fatal(1, "LANES=%0d lane=%0d r%0d: got %h expected %h",
                       LANES, lane, rd, host_rdata, expected);
        end
    endtask

    task automatic read_mem(input integer lane, input logic [31:0] expected);
        begin
            @(negedge clk);
            host_mem_lane = lane[LANE_W-1:0];
            host_mem_addr = 6'd0;
            host_mem_write = 1'b0;
            host_mem_valid = 1'b1;
            @(negedge clk);
            host_mem_valid = 1'b0;
            #1;
            if (host_mem_rdata !== expected)
                $fatal(1, "LANES=%0d lane=%0d scratchpad[0]: got %h expected %h",
                       LANES, lane, host_mem_rdata, expected);
        end
    endtask

    task automatic launch;
        begin
            @(negedge clk);
            if (!program_write_ready)
                $fatal(1, "launch requested while core not ready");
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task automatic check_run(input integer expected_retires,
                             input integer expected_taken_branches);
        begin
            observed = 0;
            cycles = 0;
            while (!done && !fault && cycles < 100) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
                if (retire_valid) begin
                    if (retire_mask !== exec_mask)
                        $fatal(1, "LANES=%0d retirement mask mismatch", LANES);
                    observed = observed + 1;
                end
            end
            if (fault || !done)
                $fatal(1, "LANES=%0d failed to complete; PC=%0d", LANES, program_counter);
            if (busy)
                $fatal(1, "LANES=%0d busy and done concurrently", LANES);
            if (observed != expected_retires || retired_count != expected_retires)
                $fatal(1, "LANES=%0d retired trace=%0d counter=%0d expected=%0d",
                       LANES, observed, retired_count, expected_retires);
            if (branch_taken_count != expected_taken_branches)
                $fatal(1, "LANES=%0d taken branches=%0d expected=%0d",
                       LANES, branch_taken_count, expected_taken_branches);
        end
    endtask

    initial begin
        if (LANES < 1 || LANES > 16)
            $fatal(1, "test expects LANES in 1..16");
        for (integer lane=0; lane<LANES; lane=lane+1)
            even_mask[lane] = ((lane % 2) == 0);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // Choose r2=100, so all active lanes uniformly take BNE r1,r2.
        for (integer lane=0; lane<LANES; lane=lane+1) begin
            preload(lane, 4'd0, 32'hDEADBEEF);  // r0 must stay zero
            preload(lane, 4'd1, lane + 1);
            preload(lane, 4'd2, 32'd100);
            preload(lane, 4'd8, 32'd0);
        end

        exec_mask = '1;
        launch();
        check_run(11, 1);
        for (integer lane=0; lane<LANES; lane=lane+1) begin
            read_reg(lane, 4'd0, 32'd0);
            read_reg(lane, 4'd5, (lane+1)*100);
            read_reg(lane, 4'd9, (lane+1)*100);
            read_reg(lane, 4'd10, (lane+1)*101);
            read_reg(lane, 4'd12, 32'd0);
            read_reg(lane, 4'd13, 2*lane+7);
            read_mem(lane, (lane+1)*100);
        end

        // Re-run with masked-off odd lanes. Host changes r1 in those lanes,
        // but the core must retain their earlier r13 and r5 results.
        for (integer lane=1; lane<LANES; lane=lane+2)
            preload(lane, 4'd1, lane+23);
        exec_mask = even_mask;
        launch();
        check_run(11, 1);
        for (integer lane=0; lane<LANES; lane=lane+1) begin
            read_reg(lane, 4'd0, 32'd0);
            read_reg(lane, 4'd5, (lane+1)*100);
            read_reg(lane, 4'd13, 2*lane+7);
            read_mem(lane, (lane+1)*100);
        end

        // With no active lanes, both branches fall through, including PC9.
        // No register or scratchpad bank may change and nothing is taken.
        exec_mask = '0;
        launch();
        check_run(12, 0);
        for (integer lane=0; lane<LANES; lane=lane+1) begin
            read_reg(lane, 4'd0, 32'd0);
            read_reg(lane, 4'd5, (lane+1)*100);
            read_reg(lane, 4'd13, 2*lane+7);
            read_mem(lane, (lane+1)*100);
        end

        $display("PASS: OpenGPU LANES=%0d, full/masked/zero masks, register/memory isolation",
                 LANES);
        $finish;
    end
endmodule
