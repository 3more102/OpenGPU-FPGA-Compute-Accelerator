module tb_opengpu_scratchpad_mmio;
    logic clk = 1'b0, rst_n = 1'b0;
    logic req_valid = 1'b0, req_ready, req_write = 1'b0;
    logic [7:0] req_addr = '0;
    logic [31:0] req_wdata = '0;
    logic rsp_valid, rsp_ready = 1'b0, rsp_error;
    logic [31:0] rsp_rdata, value, status;
    int polls;

    always #5 clk = ~clk;
    opengpu_mmio #(.LANES(8), .WIDTH(32), .PROGRAM_WORDS(12)) dut (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_ready(req_ready),
        .req_write(req_write), .req_addr(req_addr), .req_wdata(req_wdata),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_rdata(rsp_rdata),
        .rsp_error(rsp_error)
    );

    task automatic bus_req(input bit wr, input logic [7:0] addr,
                           input logic [31:0] wdata, input bit expect_error,
                           output logic [31:0] response);
        begin
            @(negedge clk);
            if (!req_ready) $fatal(1, "bus not ready");
            req_valid = 1'b1;
            req_write = wr;
            req_addr = addr;
            req_wdata = wdata;
            @(posedge clk);
            #1;
            if (!rsp_valid || (rsp_error !== expect_error))
                $fatal(1, "bus rsp addr=%h valid=%b error=%b expected_error=%b",
                    addr, rsp_valid, rsp_error, expect_error);
            response = rsp_rdata;
            @(negedge clk);
            req_valid = 1'b0;
            if (!rsp_valid) $fatal(1, "response not held");
            rsp_ready = 1'b1;
            @(negedge clk);
            rsp_ready = 1'b0;
        end
    endtask

    task automatic wr(input logic [7:0] addr, input logic [31:0] data);
        logic [31:0] ignored;
        begin bus_req(1'b1, addr, data, 1'b0, ignored); end
    endtask
    task automatic rd(input logic [7:0] addr, output logic [31:0] data);
        begin bus_req(1'b0, addr, 32'd0, 1'b0, data); end
    endtask
    task automatic mem_select(input int lane, input int word_addr);
        begin wr(8'h44, (word_addr << 8) | lane); end
    endtask
    task automatic mem_write(input int lane, input int word_addr, input logic [31:0] data);
        begin
            mem_select(lane, word_addr);
            wr(8'h48, data);
            wr(8'h4C, 32'd2);
        end
    endtask
    task automatic mem_read(input int lane, input int word_addr, output logic [31:0] data);
        begin
            mem_select(lane, word_addr);
            wr(8'h4C, 32'd1);
            rd(8'h50, data);
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // Upload a four-word kernel: LOAD r3,[r0+0], ADDI r4,r3,7,
        // STORE r4,[r0+1], LOAD r5,[r0+1].
        wr(8'h08, 32'd4);
        wr(8'h0C, 32'd0); wr(8'h10, 32'h0601_0000); wr(8'h14, 1);
        wr(8'h0C, 32'd1); wr(8'h10, 32'h087F_0007); wr(8'h14, 1);
        wr(8'h0C, 32'd2); wr(8'h10, 32'h0801_8001); wr(8'h14, 1);
        wr(8'h0C, 32'd3); wr(8'h10, 32'h0A01_0001); wr(8'h14, 1);

        // Prepare input and sentinel output for every lane.
        for (int lane=0; lane<8; lane++) begin
            mem_write(lane, 0, lane*17+5);
            mem_write(lane, 1, 32'hBEEF0300+lane);
        end
        // Confirm preloaded memory readback before execution.
        for (int lane=0; lane<8; lane++) begin
            mem_read(lane, 0, value);
            if (value !== lane*17+5)
                $fatal(1, "host preload/readback lane=%0d got=%h", lane, value);
        end

        // Reject noncanonical selectors rather than silently truncating them.
        bus_req(1'b1, 8'h44, 32'h00004000, 1'b1, value);
        bus_req(1'b1, 8'h44, 32'h00000008, 1'b1, value);
        rd(8'h44, value);
        if (value !== ((0 << 8) | 7))
            $fatal(1, "rejected memory selector modified active selection");
        // Reject invalid command encoding before any kernel memory accesses.
        bus_req(1'b1, 8'h4C, 32'd3, 1'b1, value);

        // Execute only even-numbered lanes; inactive lane outputs are untouched.
        wr(8'h24, 32'h55);
        wr(8'h00, 1);
        // An attempted host memory write while the kernel is RUN must
        // receive a bus error and must not corrupt the selected bank.
        bus_req(1'b1, 8'h4C, 32'd2, 1'b1, value);
        polls = 0;
        status = 0;
        while (!status[1] && !status[2] && polls < 100) begin
            rd(8'h04, status);
            polls++;
        end
        if (status[2]) $fatal(1, "data-transfer kernel faulted");
        if (!status[1]) $fatal(1, "data-transfer kernel timed out");

        rd(8'h3C, value);
        if (value !== 4) $fatal(1, "expected four retirements, got %0d", value);
        for (int lane=0; lane<8; lane++) begin
            mem_read(lane, 1, value);
            if ((lane % 2) == 0) begin
                if (value !== lane*17+12)
                    $fatal(1, "computed output wrong lane=%0d value=%h", lane, value);
            end else if (value !== (32'hBEEF0300+lane)) begin
                $fatal(1, "masked-off lane memory modified lane=%0d value=%h", lane, value);
            end
            mem_read(lane, 0, value);
            if (value !== lane*17+5)
                $fatal(1, "input word modified lane=%0d value=%h", lane, value);
            wr(8'h18, (5 << 4) | lane);
            rd(8'h30, value);
            if ((lane % 2) == 0) begin
                if (value !== lane*17+12)
                    $fatal(1, "register and scratchpad results differ for lane %0d", lane);
            end else if (value !== 0) begin
                $fatal(1, "masked-off lane register modified lane=%0d", lane);
            end
        end

        $display("PASS: host scratchpad I/O, masked kernel computation, readback, memory isolation, and invalid commands");
        $finish;
    end
endmodule
