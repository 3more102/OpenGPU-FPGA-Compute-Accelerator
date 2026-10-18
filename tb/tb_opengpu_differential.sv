module tb_opengpu_differential;
    logic clk = 1'b0, rst_n = 1'b0, start = 1'b0;
    logic [7:0] exec_mask = '0;
    logic host_we = 1'b0;
    logic [2:0] host_lane = '0;
    logic [3:0] host_rd = '0;
    logic [31:0] host_wdata = '0;
    logic [31:0] host_rdata;
    logic host_mem_valid = 1'b0, host_mem_write = 1'b0;
    logic [2:0] host_mem_lane = '0;
    logic [5:0] host_mem_addr = '0;
    logic [31:0] host_mem_wdata = '0, host_mem_rdata;
    logic program_we = 1'b0;
    logic [3:0] program_addr = '0;
    logic [31:0] program_wdata = '0;
    logic [4:0] program_length = 5'd12;
    logic program_write_ready;
    logic busy, done, fault;
    logic [3:0] program_counter, retire_rd;
    logic retire_valid;
    logic [7:0] retire_mask;
    logic [255:0] retire_data;
    logic [31:0] cycle_count, retired_count, branch_taken_count;
    logic [31:0] program [0:11];
    logic [31:0] initial_regs [0:15];
    logic [31:0] initial_mem [0:7];
    logic [31:0] expected_regs [0:127];
    logic [31:0] expected_mem [0:7];
    logic [7:0] masks [0:0];
    string filename;
    integer testcase, cycles;

    always #5 clk = ~clk;

    opengpu_top #(.LANES(8), .WIDTH(32), .REGS(16), .PROGRAM_WORDS(12)) dut (
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

    task automatic upload(input logic [3:0] addr, input logic [31:0] word);
        begin
            @(negedge clk);
            if (!program_write_ready) $fatal(1, "not ready for program upload");
            program_we = 1'b1;
            program_addr = addr;
            program_wdata = word;
            @(negedge clk);
            program_we = 1'b0;
        end
    endtask
    task automatic preload(input logic [2:0] lane,
                            input logic [3:0] reg_index, input logic [31:0] word);
        begin
            @(negedge clk);
            host_we = 1'b1;
            host_lane = lane;
            host_rd = reg_index;
            host_wdata = word;
            @(negedge clk);
            host_we = 1'b0;
        end
    endtask
    task automatic memory_write(input logic [2:0] lane, input logic [31:0] word);
        begin
            @(negedge clk);
            host_mem_valid = 1'b1;
            host_mem_write = 1'b1;
            host_mem_lane = lane;
            host_mem_addr = 6'd0;
            host_mem_wdata = word;
            @(negedge clk);
            host_mem_valid = 1'b0;
            host_mem_write = 1'b0;
        end
    endtask
    task automatic memory_read(input logic [2:0] lane, output logic [31:0] word);
        begin
            @(negedge clk);
            host_mem_valid = 1'b1;
            host_mem_write = 1'b0;
            host_mem_lane = lane;
            host_mem_addr = 6'd0;
            @(posedge clk);
            #1;
            word = host_mem_rdata;
            @(negedge clk);
            host_mem_valid = 1'b0;
        end
    endtask

    initial begin
        if (!$value$plusargs("CASE=%d", testcase))
            $fatal(1, "Pass +CASE=0..3");
        if (testcase < 0 || testcase > 3)
            $fatal(1, "invalid testcase %0d", testcase);

        filename = $sformatf("build/diff_%0d_program.hex", testcase);
        $readmemh(filename, program);
        filename = $sformatf("build/diff_%0d_preload.hex", testcase);
        $readmemh(filename, initial_regs);
        filename = $sformatf("build/diff_%0d_sentinels.hex", testcase);
        $readmemh(filename, initial_mem);
        filename = $sformatf("build/diff_%0d_expected_regs.hex", testcase);
        $readmemh(filename, expected_regs);
        filename = $sformatf("build/diff_%0d_expected_mem.hex", testcase);
        $readmemh(filename, expected_mem);
        filename = $sformatf("build/diff_%0d_mask.hex", testcase);
        $readmemh(filename, masks);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        exec_mask = masks[0];
        for (int pc = 0; pc < 12; pc++)
            upload(pc[3:0], program[pc]);
        for (int lane = 0; lane < 8; lane++) begin
            preload(lane[2:0], 4'd1, initial_regs[2*lane]);
            preload(lane[2:0], 4'd2, initial_regs[2*lane+1]);
            memory_write(lane[2:0], initial_mem[lane]);
        end

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        cycles = 0;
        while (!done && !fault && cycles < 120) begin
            @(posedge clk);
            #1;
            cycles++;
        end
        if (!done || fault)
            $fatal(1, "Differential case=%0d ended incorrectly: done=%b fault=%b pc=%0d",
                testcase, done, fault, program_counter);
        if (retired_count !== 12)
            $fatal(1, "Differential case=%0d retired=%0d expected 12",
                testcase, retired_count);
        if (branch_taken_count !== 0)
            $fatal(1, "Unexpected branch in branch-free differential kernel");

        for (int lane = 0; lane < 8; lane++) begin
            for (int reg_index = 0; reg_index < 16; reg_index++) begin
                @(negedge clk);
                host_lane = lane[2:0];
                host_rd = reg_index[3:0];
                #1;
                if (host_rdata !== expected_regs[lane*16+reg_index])
                    $fatal(1, "case=%0d lane=%0d r%0d RTL=%h Python=%h",
                        testcase, lane, reg_index, host_rdata,
                        expected_regs[lane*16+reg_index]);
            end
            begin
                logic [31:0] memword;
                memory_read(lane[2:0], memword);
                if (memword !== expected_mem[lane])
                    $fatal(1, "case=%0d lane=%0d scratchpad RTL=%h Python=%h",
                        testcase, lane, memword, expected_mem[lane]);
            end
        end
        $display("PASS: OpenGPU differential case=%0d mask=%h retired=%0d cycles=%0d",
            testcase, exec_mask, retired_count, cycle_count);
        $finish;
    end
endmodule
