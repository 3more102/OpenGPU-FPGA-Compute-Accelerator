module tb_opengpu_program_load;
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
    logic [4:0] program_length = 5'd3;
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

    task automatic preload_register(input logic [2:0] lane, input logic [3:0] rd,
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

    task automatic write_instruction(input logic [3:0] addr, input logic [31:0] value);
        begin
            @(negedge clk);
            if (!program_write_ready) $fatal(1, "Program writes should be ready while idle");
            program_we = 1'b1;
            program_addr = addr;
            program_wdata = value;
            @(negedge clk);
            program_we = 1'b0;
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

    task automatic check_program;
        logic [3:0] expected_rd;
        logic [31:0] expected_value;
        begin
            retire_count = 0;
            timeout_count = 0;
            while (!done && !fault && timeout_count < 80) begin
                @(posedge clk);
                #1;
                timeout_count++;
                if (retire_valid) begin
                    case (retire_count)
                        0: expected_rd = 3;
                        1: expected_rd = 4;
                        2: expected_rd = 5;
                        default: expected_rd = 15;
                    endcase
                    if (retire_count >= 3) $fatal(1, "Unexpected extra instruction retirement");
                    if (retire_rd !== expected_rd)
                        $fatal(1, "Retirement %0d rd=%0d expected=%0d", retire_count, retire_rd, expected_rd);
                    for (int lane = 0; lane < 8; lane++) begin
                        case (retire_count)
                            0: expected_value = lane + 6;
                            1: expected_value = lane + 4;
                            2: expected_value = (2 * lane) + 5;
                            default: expected_value = '0;
                        endcase
                        if (retire_data[lane*32 +: 32] !== expected_value)
                            $fatal(1, "Retirement %0d lane %0d data=%h expected=%h", retire_count, lane, retire_data[lane*32 +: 32], expected_value);
                    end
                    retire_count++;
                end
            end
            if (fault) $fatal(1, "Unexpected fault in uploaded program");
            if (!done) $fatal(1, "Uploaded program did not finish");
            if (retire_count != 3) $fatal(1, "Retired %0d instructions, expected 3", retire_count);
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        for (int lane = 0; lane < 8; lane++)
            preload_register(lane[2:0], 4'd1, lane + 1);

        // Uploaded kernel: ADDI r3,r1,5; ADDI r4,r3,-2; ADD r5,r4,r1.
        write_instruction(4'd0, 32'h063F_0005);
        write_instruction(4'd1, 32'h087F_FFFE);
        write_instruction(4'd2, 32'h0A82_0000);

        if (dut.instruction !== 32'h063F_0005)
            $fatal(1, "Uploaded instruction at word 0 did not override ROM");

        launch();

        // An attempted write while running must be ignored.
        @(negedge clk);
        if (program_write_ready) $fatal(1, "Program writes must be blocked while running");
        program_we = 1'b1;
        program_addr = 4'd0;
        program_wdata = 32'h0000_0000;
        @(negedge clk);
        program_we = 1'b0;

        check_program();
        if (dut.program_mem[0] !== 32'h063F_0005)
            $fatal(1, "Program memory changed despite write protection while running");

        $display("PASS: host program upload, active length, instruction override, run-time write protection and execution");
        $finish;
    end
endmodule
