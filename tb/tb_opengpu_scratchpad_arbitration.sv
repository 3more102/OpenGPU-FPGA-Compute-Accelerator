module tb_opengpu_scratchpad_arbitration;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic [2:0] req_valid=0;
  logic req_write=0;
  logic [11:0] addr=0;
  logic [95:0] wdata=0;
  wire [95:0] rdata;
  logic host_valid=0, host_write=0;
  logic [1:0] host_lane=0;
  logic [3:0] host_addr=0;
  logic [31:0] host_wdata=0;
  wire [31:0] host_rdata;
  wire host_ready, host_error;
  opengpu_scratchpad #(.LANES(3),.WIDTH(32),.ADDR_BITS(4)) dut(
    .clk(clk),.rst_n(rst_n),.req_valid(req_valid),.req_write(req_write),
    .addr(addr),.wdata(wdata),.rdata(rdata),
    .host_valid(host_valid),.host_write(host_write),.host_lane(host_lane),
    .host_addr(host_addr),.host_wdata(host_wdata),.host_rdata(host_rdata),
    .host_ready(host_ready),.host_error(host_error));
  initial begin
    #2000;
    $fatal(1,"test timeout");
  end
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk);
    host_valid=1; host_write=1; host_lane=1; host_addr=4;
    host_wdata=32'h1234ABCD;
    if(!host_ready || host_error) $fatal(1,"valid host request rejected");
    @(negedge clk);
    host_write=0;
    @(negedge clk);
    if(host_rdata !== 32'h1234ABCD) $fatal(1,"host readback mismatch");
    // Simultaneous requests: core wins, host is not accepted.
    host_write=1; host_wdata=32'hDEADBEEF;
    req_valid=3'b010; req_write=1;
    addr[7:4]=4; wdata[63:32]=32'hCAFEBABE;
    #1;
    if(host_ready) $fatal(1,"host ready during core request");
    @(negedge clk);
    req_valid=0; req_write=0; host_write=0;
    @(negedge clk);
    if(host_rdata !== 32'hCAFEBABE) $fatal(1,"core priority or memory readback failed");
    // Invalid lane index must not modify any memory bank.
    host_lane=3; host_write=1; host_wdata=32'hFFFFFFFF;
    #1;
    if(!host_error || !host_ready) $fatal(1,"invalid lane not flagged");
    @(negedge clk);
    host_lane=1; host_write=0;
    @(negedge clk);
    if(host_rdata !== 32'hCAFEBABE) $fatal(1,"invalid lane corrupted memory");
    host_valid=0;
    $display("PASS: arbitration, core priority, invalid lane and data integrity");
    $finish;
  end
endmodule
