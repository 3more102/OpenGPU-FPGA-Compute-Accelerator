// Multi-kernel, source-assembled differential integration regression.
// Reads vectors from Python fixture generator via vvp +PROGRAM=... etc.
module tb_opengpu_kernel_differential;
    logic clk = 1'b0, rst_n = 1'b0;
    logic req_valid = 1'b0, req_ready, req_write = 1'b0;
    logic [7:0] req_addr = '0;
    logic [31:0] req_wdata = '0;
    logic rsp_valid, rsp_ready = 1'b0, rsp_error;
    logic [31:0] rsp_rdata, value, status;

    logic [31:0] program_words [0:15];
    logic [31:0] inputs [0:7];
    logic [31:0] sentinels [0:7];
    logic [31:0] expected_memory [0:7];
    logic [31:0] expected_r5 [0:7];
    reg [1023:0] program_file, inputs_file, sentinels_file;
    reg [1023:0] expected_memory_file, expected_r5_file;
    reg [7:0] exec_mask;
    integer length_words, polls;

    always #5 clk = ~clk;

    opengpu_mmio #(.LANES(8), .WIDTH(32), .PROGRAM_WORDS(12)) dut (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_ready(req_ready),
        .req_write(req_write), .req_addr(req_addr), .req_wdata(req_wdata),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_rdata(rsp_rdata),
        .rsp_error(rsp_error)
    );

    task automatic bus_request(input bit write_enable, input logic [7:0] address,
                               input logic [31:0] data, output logic [31:0] response);
        begin
            @(negedge clk);
            if (!req_ready) $fatal(1, "MMIO bus unexpectedly not ready");
            req_valid = 1'b1;
            req_write = write_enable;
            req_addr = address;
            req_wdata = data;
            @(posedge clk);
            #1;
            if (!rsp_valid || rsp_error)
                $fatal(1, "MMIO error at address 0x%02h valid=%b err=%b",
                       address, rsp_valid, rsp_error);
            response = rsp_rdata;
            @(negedge clk);
            req_valid = 1'b0;
            if (!rsp_valid) $fatal(1, "response lost before rsp_ready");
            rsp_ready = 1'b1;
            @(negedge clk);
            rsp_ready = 1'b0;
        end
    endtask

    task automatic wr(input logic [7:0] addr, input logic [31:0] data);
        logic [31:0] ignored;
        begin bus_request(1'b1, addr, data, ignored); end
    endtask

    task automatic rd(input logic [7:0] addr, output logic [31:0] data);
        begin bus_request(1'b0, addr, 32'd0, data); end
    endtask

    task automatic mem_select(input integer lane, input integer word);
        begin wr(8'h44, (word << 8) | lane); end
    endtask

    task automatic mem_write(input integer lane, input integer word,
                             input logic [31:0] data);
        begin
            mem_select(lane, word);
            wr(8'h48, data);
            wr(8'h4C, 32'd2);
        end
    endtask

    task automatic mem_read(input integer lane, input integer word,
                            output logic [31:0] data);
        begin
            mem_select(lane, word);
            wr(8'h4C, 32'd1);
            rd(8'h50, data);
        end
    endtask

    initial begin
        if (!$value$plusargs("PROGRAM=%s", program_file))
            $fatal(1, "missing +PROGRAM= fixture path");
        if (!$value$plusargs("INPUTS=%s", inputs_file))
            $fatal(1, "missing +INPUTS= fixture path");
        if (!$value$plusargs("SENTINELS=%s", sentinels_file))
            $fatal(1, "missing +SENTINELS= fixture path");
        if (!$value$plusargs("EXPECTED_MEMORY=%s", expected_memory_file))
            $fatal(1, "missing +EXPECTED_MEMORY= fixture path");
        if (!$value$plusargs("EXPECTED_R5=%s", expected_r5_file))
            $fatal(1, "missing +EXPECTED_R5= fixture path");
        if (!$value$plusargs("MASK=%h", exec_mask))
            $fatal(1, "missing +MASK= hex mask");
        if (!$value$plusargs("LENGTH=%d", length_words))
            $fatal(1, "missing +LENGTH= decimal program length");
        if (length_words < 1 || length_words > 16)
            $fatal(1, "invalid kernel word count %0d", length_words);

        $readmemh(program_file, program_words);
        $readmemh(inputs_file, inputs);
        $readmemh(sentinels_file, sentinels);
        $readmemh(expected_memory_file, expected_memory);
        $readmemh(expected_r5_file, expected_r5);

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // Upload actual assembled program words through MMIO.
        wr(8'h08, length_words);
        for (integer pc=0; pc<length_words; pc++) begin
            wr(8'h0C, pc);
            wr(8'h10, program_words[pc]);
            wr(8'h14, 32'd1);
        end

        // Stage one input and one sentinel output word per lane.
        for (integer lane=0; lane<8; lane++) begin
            mem_write(lane, 0, inputs[lane]);
            mem_write(lane, 1, sentinels[lane]);
        end
        wr(8'h24, {24'd0, exec_mask});
        wr(8'h00, 32'd1);

        status = 32'd0;
        polls = 0;
        while (!status[1] && !status[2] && polls < 100) begin
            rd(8'h04, status);
            polls = polls + 1;
        end
        if (!status[1] || status[2])
            $fatal(1, "kernel failed to complete: status=%h polls=%0d", status, polls);
        rd(8'h3C, value);
        if (value !== length_words)
            $fatal(1, "retirement count %0d differs from program length %0d",
                   value, length_words);
        rd(8'h40, value);
        if (value !== 0) $fatal(1, "straight-line kernel unexpectedly took branches");

        for (integer lane=0; lane<8; lane++) begin
            mem_read(lane, 0, value);
            if (value !== inputs[lane])
                $fatal(1, "lane %0d input modified: value=%h expected=%h",
                       lane, value, inputs[lane]);
            mem_read(lane, 1, value);
            if (value !== expected_memory[lane])
                $fatal(1, "lane %0d output mismatch: value=%h expected=%h",
                       lane, value, expected_memory[lane]);
            wr(8'h18, (5 << 4) | lane);
            rd(8'h30, value);
            if (value !== expected_r5[lane])
                $fatal(1, "lane %0d r5 mismatch: value=%h expected=%h",
                       lane, value, expected_r5[lane]);
        end

        $display("PASS: kernel differential comparison (%0d words, mask=%02h)",
                 length_words, exec_mask);
        $finish;
    end
endmodule
