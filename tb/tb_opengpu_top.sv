module tb_opengpu_top;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic start = 1'b0;
    logic [7:0] exec_mask = 8'hFF;
    logic host_we = 1'b0;
    logic [2:0] host_lane = '0;
    logic [3:0] host_rd = '0;
    logic [31:0] host_wdata = '0;
    logic program_we = 1'b0;
    logic [3:0] program_addr = '0;
    logic [31:0] program_wdata = '0;
    logic [4:0] program_length = 5'd12;
    logic program_write_ready;
    logic busy;
    logic done;
    logic fault;
    logic [3:0] program_counter;
    logic retire_valid;
    logic [7:0] retire_mask;
    logic [3:0] retire_rd;
    logic [8*32-1:0] retire_data;
    int retire_count;
    int timeout_count;

    always #5 clk = ~clk;

    opengpu_top #(.LANES(8), .WIDTH(32), .REGS(16), .PROGRAM_WORDS(12)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .exec_mask(exec_mask),
        .host_we(host_we), .host_lane(host_lane), .host_rd(host_rd),
        .host_wdata(host_wdata), .program_we(program_we), .program_addr(program_addr),
        .program_wdata(program_wdata), .program_length(program_length),
        .program_write_ready(program_write_ready), .busy(busy), .done(done), .fault(fault),
        .program_counter(program_counter), .retire_valid(retire_valid),
        .retire_mask(retire_mask), .retire_rd(retire_rd), .retire_data(retire_data)
    );

    task automatic preload(input logic [2:0] lane, input logic [3:0] rd,
                           input logic [31:0] value);
        begin
            @(negedge clk);
            host_we = 1'b1;
            host_lane = lane;
            host_rd = rd;
            host_wdata = value;
            @(negedge clk);
            host_we = 1'b0;
        end
    endtask

    task automatic launch;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task automatic check_run(input logic [7:0] expected_mask);
        logic [3:0] expected_rd;
        logic [31:0] expected_value;
        begin
            retire_count = 0;
            timeout_count = 0;
            while (!done && !fault && timeout_count < 200) begin
                @(posedge clk);
                #1;
                timeout_count++;
                if (retire_valid) begin
                    case (retire_count)
                        0: expected_rd = 3;
                        1: expected_rd = 4;
                        2: expected_rd = 5;
                        3: expected_rd = 6;
                        4: expected_rd = 0;
                        5: expected_rd = 9;
                        6: expected_rd = 10;
                        7: expected_rd = 11;
                        8: expected_rd = 0;
                        9: expected_rd = 13;
                        10: expected_rd = 0;
                        default: expected_rd = 15;
                    endcase
                    if (retire_count >= 11) $fatal(1, "Unexpected extra retirement");
                    if (retire_rd !== expected_rd)
                        $fatal(1, "Retire %0d: rd=%0d expected=%0d", retire_count, retire_rd, expected_rd);
                    if (retire_mask !== expected_mask)
                        $fatal(1, "Retire %0d: mask=%h expected=%h", retire_count, retire_mask, expected_mask);
                    for (int lane = 0; lane < 8; lane++) begin
                        case (retire_count)
                            0: expected_value = lane + 11;
                            1: expected_value = (lane + 1) ^ 10;
                            2: expected_value = (lane + 1) * 10;
                            3: expected_value = lane + 1;
                            4: expected_value = 0;
                            5: expected_value = (lane + 1) * 10;
                            6: expected_value = (lane + 1) * 11;
                            7: expected_value = lane + 6;
                            8: expected_value = 0;
                            9: expected_value = (2 * lane) + 7;
                            10: expected_value = 0;
                            default: expected_value = '0;
                        endcase
                        if (!expected_mask[lane]) expected_value = '0;
                        if (retire_data[lane*32 +: 32] !== expected_value)
                            $fatal(1, "Retire %0d lane %0d data=%h expected=%h", retire_count, lane, retire_data[lane*32 +: 32], expected_value);
                    end
                    if ((retire_count == 8) && (program_counter !== 4'd10))
                        $fatal(1, "Taken branch did not redirect PC to 10 (PC=%0d)", program_counter);
                    retire_count++;
                end
            end
            if (fault) $fatal(1, "Unexpected fault at PC=%0d", program_counter);
            if (!done) $fatal(1, "Timed out waiting for done");
            if (retire_count != 11) $fatal(1, "Retired %0d instructions, expected 11", retire_count);
            if (busy) $fatal(1, "busy must be low when done is high");
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // Preload per-lane arithmetic inputs and a zero word address in r8.
        for (int lane = 0; lane < 8; lane++) begin
            preload(lane[2:0], 4'd1, lane + 1);
            preload(lane[2:0], 4'd2, 32'd10);
            preload(lane[2:0], 4'd8, 32'd0);
        end

        if (dut.core.rf[0][1] !== 32'd1 || dut.core.rf[0][2] !== 32'd10)
            $fatal(1, "Host preload failed: lane0 r1=%h r2=%h", dut.core.rf[0][1], dut.core.rf[0][2]);
        if (dut.instruction !== 32'h0624_0000)
            $fatal(1, "Unexpected ROM word at PC0: %h", dut.instruction);
        if (dut.core.result[31:0] !== 32'd11)
            $fatal(1, "ALU result failed before launch: result=%h", dut.core.result[31:0]);

        launch();
        check_run(8'hFF);

        // Masked restart checks inactive-lane write suppression and private-memory access.
        exec_mask = 8'h55;
        launch();
        check_run(8'h55);

        // Make BNE r1,r2 disagree across active lanes: lane 0 is equal; lanes 1-7 differ.
        exec_mask = 8'hFF;
        for (int lane = 0; lane < 8; lane++) begin
            preload(lane[2:0], 4'd2, (lane == 0) ? 32'd1 : 32'd10);
        end
        launch();
        timeout_count = 0;
        while (!fault && !done && timeout_count < 200) begin
            @(posedge clk);
            #1;
            timeout_count++;
        end
        if (!fault) $fatal(1, "Expected sticky fault for divergent branch");
        if (done || busy) $fatal(1, "Fault state must stop execution without done/busy");
        if (program_counter !== 4'd8)
            $fatal(1, "Divergent branch should fault at PC 8, got PC=%0d", program_counter);

        $display("PASS: OpenGPU immediate ALU, branch redirect, branch-not-taken, divergence fault, memory, masking and restart");
        $finish;
    end
endmodule
