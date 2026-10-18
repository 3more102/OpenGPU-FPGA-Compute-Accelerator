// One in-order warp; one issued instruction per cycle, combinational ALU.
// No memory operations, branches, hazard bypass, or multiple resident warps.
module opengpu_core #(parameter int LANES=8, WIDTH=32, REGS=16)(
 input logic clk, rst_n,
 input logic issue_valid,
 input logic [31:0] instruction,
 input logic [LANES-1:0] exec_mask,
 output logic issue_ready,
 output logic retire_valid,
 output logic [LANES-1:0] retire_mask,
 output logic [3:0] retire_rd,
 output logic [WIDTH-1:0] retire_data [LANES]
);
 // ISA: [31:29] op, [28:25] rd, [24:21] rs1, [20:17] rs2;
 // remaining bits reserved, must be zero in canonical encoding.
 logic [WIDTH-1:0] rf [LANES][REGS];
 logic [WIDTH-1:0] a [LANES], b [LANES], result [LANES];
 logic [2:0] op;
 logic [3:0] rd,rs1,rs2;
 assign op=instruction[31:29];
 assign rd=instruction[28:25];
 assign rs1=instruction[24:21];
 assign rs2=instruction[20:17];
 assign issue_ready=1'b1;
 always_comb begin
   for(int i=0;i<LANES;i++) begin
     a[i]=rf[i][rs1];
     b[i]=rf[i][rs2];
   end
 end
 opengpu_alu #(.LANES(LANES),.WIDTH(WIDTH)) alu(
  .mask(exec_mask),.op(op),.a(a),.b(b),.y(result));
 always_ff @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin
     retire_valid<=0;
     retire_mask<='0;
     retire_rd<='0;
     for(int i=0;i<LANES;i++) begin
       retire_data[i]<='0;
       for(int j=0;j<REGS;j++) rf[i][j]<='0;
     end
   end else begin
     retire_valid<=issue_valid;
     if(issue_valid) begin
       retire_mask<=exec_mask;
       retire_rd<=rd;
       for(int i=0;i<LANES;i++) begin
         retire_data[i]<=result[i];
         if(exec_mask[i] && rd!=0) rf[i][rd]<=result[i];
       end
     end
   end
 end
endmodule
