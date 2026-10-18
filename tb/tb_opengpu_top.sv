module tb_opengpu_top;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic start = 1'b0;
    logic [7:0] exec_mask = 8'hFF;
    logic host_we = 1'b0;
    logic [2:0] host_lane = '0;
    logic [3:0] host_rd = '0;
    logic [31:0] host_wdata = '0;
    logic busy;
    logic done;
    logic [2:0] program_counter;
    logic retire_valid;
    logic [7:0] retire_mask;
    logic [3:0] retire_rd;
    logic [7:0][31:0] retire_data;
    int retire_count;
    int timeout_count;

    always #5 clk = ~clk;

    opengpu_top #(.LANES(8), .WIDTH(32), .REGS(16), .PROGRAM_WORDS(7)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .exec_mask(exec_mask),
        .host_we(host_we), .host_lane(host_lane), .host_rd(host_rd),
        .host_wdata(host_wdata), .busy(busy), .done(done),
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
            while (!done && timeout_count < 100) begin
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
                        default: expected_rd = 15;
                    endcase
                    if (retire_count >= 7) $fatal(1, "Unexpected extra retirement");
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
                            default: expected_value = '0;
                        endcase
                        if (!expected_mask[lane]) expected_value = '0;
                        if (retire_data[lane] !== expected_value)
                            $fatal(1, "Retire %0d lane %0d data=%h expected=%h", retire_count, lane, retire_data[lane], expected_value);
                    end
                    retire_count++;
                end
            end
            if (!done) $fatal(1, "Timed out waiting for done");
            if (retire_count != 7) $fatal(1, "Retired %0d instructions, expected 7", retire_count);
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
        if (dut.core.result[0] !== 32'd11)
            $fatal(1, "ALU result failed before launch: a=%h b=%h result=%h", dut.core.a[0], dut.core.b[0], dut.core.result[0]);

        launch();
        check_run(8'hFF);

        // Restart with only even lanes active; stores and loads must remain masked.
        exec_mask = 8'h55;
        launch();
        check_run(8'h55);

        $display("PASS: OpenGPU arithmetic, lane-local store/load, load dependency, masking and restart");
        $finish;
    end
endmodule
