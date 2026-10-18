module tb_opengpu_mmio;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic req_valid = 1'b0;
    logic req_ready;
    logic req_write = 1'b0;
    logic [7:0] req_addr = '0;
    logic [31:0] req_wdata = '0;
    logic rsp_valid;
    logic rsp_ready = 1'b0;
    logic [31:0] rsp_rdata;
    logic rsp_error;
    logic [31:0] read_value;
    logic [31:0] status;
    int timeout_count;

    always #5 clk = ~clk;

    opengpu_mmio #(.LANES(8), .WIDTH(32), .REGS(16), .PROGRAM_WORDS(12)) dut (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_ready(req_ready),
        .req_write(req_write), .req_addr(req_addr), .req_wdata(req_wdata),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_rdata(rsp_rdata),
        .rsp_error(rsp_error)
    );

    task automatic bus_write(input logic [7:0] address, input logic [31:0] value);
        begin
            @(negedge clk);
            req_valid = 1'b1;
            req_write = 1'b1;
            req_addr = address;
            req_wdata = value;
            @(posedge clk);
            while (!req_ready) @(posedge clk);
            #1;
            if (!rsp_valid) $fatal(1, "Missing write response at address %h", address);
            @(negedge clk);
            req_valid = 1'b0;
            req_write = 1'b0;
            if (!rsp_valid) $fatal(1, "Write response was not held until ready");
            if (rsp_error) $fatal(1, "MMIO write error at address %h data=%h", address, value);
            rsp_ready = 1'b1;
            @(negedge clk);
            rsp_ready = 1'b0;
        end
    endtask

    task automatic bus_read(input logic [7:0] address, output logic [31:0] value);
        begin
            @(negedge clk);
            req_valid = 1'b1;
            req_write = 1'b0;
            req_addr = address;
            req_wdata = '0;
            @(posedge clk);
            while (!req_ready) @(posedge clk);
            #1;
            if (!rsp_valid) $fatal(1, "Missing read response at address %h", address);
            @(negedge clk);
            req_valid = 1'b0;
            if (!rsp_valid) $fatal(1, "Read response was not held until ready");
            if (rsp_error) $fatal(1, "MMIO read error at address %h", address);
            value = rsp_rdata;
            rsp_ready = 1'b1;
            @(negedge clk);
            rsp_ready = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // Upload a three-instruction kernel using only the bus register map.
        bus_write(8'h08, 32'd3);          // active program length
        bus_write(8'h0C, 32'd0);
        bus_write(8'h10, 32'h063F_0005);  // ADDI r3,r1,5
        bus_write(8'h14, 32'd1);
        bus_write(8'h0C, 32'd1);
        bus_write(8'h10, 32'h087F_FFFE);  // ADDI r4,r3,-2
        bus_write(8'h14, 32'd1);
        bus_write(8'h0C, 32'd2);
        bus_write(8'h10, 32'h0A82_0000);  // ADD r5,r4,r1
        bus_write(8'h14, 32'd1);

        // Preload r1=lane+1 using REG_SELECT / REG_WDATA / REG_CMD.
        for (int lane = 0; lane < 8; lane++) begin
            bus_write(8'h18, (32'd1 << 4) | lane);
            bus_write(8'h1C, lane + 1);
            bus_write(8'h20, 32'd1);
        end

        bus_read(8'h08, read_value);
        if (read_value != 3) $fatal(1, "Program length readback=%0d expected=3", read_value);

        bus_write(8'h00, 32'd1); // launch
        timeout_count = 0;
        status = '0;
        while (!status[1] && !status[2] && timeout_count < 100) begin
            bus_read(8'h04, status);
            timeout_count++;
        end
        if (status[2]) $fatal(1, "MMIO-launched kernel entered FAULT");
        if (!status[1]) $fatal(1, "MMIO-launched kernel timed out");
        if (status[0]) $fatal(1, "STATUS reports busy after done");

        bus_read(8'h38, read_value);
        if (read_value == 0) $fatal(1, "Cycle counter should be nonzero after execution");
        bus_read(8'h3C, read_value);
        if (read_value != 3) $fatal(1, "Retired counter=%0d expected=3", read_value);
        bus_read(8'h40, read_value);
        if (read_value != 0) $fatal(1, "Branch counter=%0d expected=0 for branch-free kernel", read_value);

        // Read back each lane's r5; expected value is 2*lane+5.
        for (int lane = 0; lane < 8; lane++) begin
            bus_write(8'h18, (32'd5 << 4) | lane);
            bus_read(8'h30, read_value);
            if (read_value != (2 * lane + 5))
                $fatal(1, "Lane %0d r5=%0d expected=%0d", lane, read_value, (2 * lane + 5));
        end

        // Misaligned accesses must return an error response.
        @(negedge clk);
        req_valid = 1'b1;
        req_write = 1'b0;
        req_addr = 8'h05;
        @(posedge clk);
        #1;
        if (!rsp_valid || !rsp_error) $fatal(1, "Misaligned access did not report an error");
        @(negedge clk);
        req_valid = 1'b0;
        rsp_ready = 1'b1;
        @(negedge clk);
        rsp_ready = 1'b0;

        $display("PASS: OpenGPU MMIO program upload, launch/status polling, register preload/readback and bus errors");
        $finish;
    end
endmodule
