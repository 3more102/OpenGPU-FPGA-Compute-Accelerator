module tb_opengpu_warp_scheduler;
    logic clk=0, rst_n=0, issue_accept=0;
    logic [2:0] runnable=0;
    wire issue_valid;
    wire [1:0] issue_warp;
    always #5 clk=~clk;
    opengpu_warp_scheduler #(.WARPS(3)) dut (
        .clk(clk), .rst_n(rst_n), .runnable(runnable),
        .issue_accept(issue_accept), .issue_valid(issue_valid), .issue_warp(issue_warp)
    );
    task automatic check(input bit valid, input int warp);
        #1;
        if(issue_valid !== valid || (valid && issue_warp !== warp))
            $fatal(1,"expected valid=%b warp=%0d got valid=%b warp=%0d",
                valid,warp,issue_valid,issue_warp);
    endtask
    initial begin
        #500; $fatal(1,"scheduler test timeout");
    end
    initial begin
        repeat(2) @(negedge clk);
        rst_n=1; runnable=3'b111;
        check(1,0);
        issue_accept=1;
        @(negedge clk); check(1,1);
        @(negedge clk); check(1,2);
        @(negedge clk); check(1,0);
        issue_accept=0;
        @(negedge clk); check(1,0);
        runnable=3'b100; check(1,2);
        issue_accept=1;
        @(negedge clk); check(1,2);
        runnable=0; check(0,0);
        runnable=3'b010; check(1,1);
        $display("PASS: three-warp round-robin, stall, skip and empty runnable set");
        $finish;
    end
endmodule
