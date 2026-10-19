module tb_opengpu_warp_context;
  logic clk=0, rst_n=0, write_valid=0;
  logic [1:0] write_warp=0, read_warp=0;
  logic [7:0] write_pc=0;
  logic [3:0] write_mask=0;
  wire [7:0] read_pc;
  wire [3:0] read_mask;
  wire read_valid;
  always #5 clk=~clk;
  opengpu_warp_context #(.WARPS(3),.LANES(4),.PC_BITS(8)) dut(
    .clk(clk),.rst_n(rst_n),.write_valid(write_valid),
    .write_warp(write_warp),.write_pc(write_pc),.write_mask(write_mask),
    .read_warp(read_warp),.read_pc(read_pc),.read_mask(read_mask),
    .read_valid(read_valid));
  task automatic check(input bit v,input logic [7:0] pc,input logic [3:0] mask);
    #1;
    if(read_valid !== v || read_pc !== pc || read_mask !== mask)
      $fatal(1,"context mismatch warp=%0d valid=%b pc=%h mask=%h",read_warp,read_valid,read_pc,read_mask);
  endtask
  initial begin
    #500; $fatal(1,"context test timeout");
  end
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    read_warp=0; check(0,0,0);
    write_valid=1; write_warp=0; write_pc=8'h12; write_mask=4'h5;
    @(negedge clk);
    write_warp=2; write_pc=8'hE1; write_mask=4'hA;
    @(negedge clk); write_valid=0;
    read_warp=0; check(1,8'h12,4'h5);
    read_warp=1; check(0,0,0);
    read_warp=2; check(1,8'hE1,4'hA);
    read_warp=3; check(0,0,0);
    write_valid=1; write_warp=3; write_pc=8'hFF; write_mask=4'hF;
    @(negedge clk); write_valid=0;
    read_warp=0; check(1,8'h12,4'h5);
    read_warp=2; check(1,8'hE1,4'hA);
    rst_n=0; #1; read_warp=0; check(0,0,0);
    $display("PASS: warp context isolation, invalid index and reset");
    $finish;
  end
endmodule
