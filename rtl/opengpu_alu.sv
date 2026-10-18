module opengpu_alu #(parameter int LANES=8, WIDTH=32)(
 input logic [LANES-1:0] mask,
 input logic [2:0] op,
 input logic [WIDTH-1:0] a [LANES], b [LANES],
 output logic [WIDTH-1:0] y [LANES]
);
 localparam logic [2:0] ADD=0,SUB=1,AND_OP=2,OR_OP=3,XOR_OP=4,SHL=5,SHR=6,MUL=7;
 always_comb begin
   for (int i=0;i<LANES;i++) begin
     y[i]='0;
     if (mask[i]) begin
       case(op)
         ADD: y[i]=a[i]+b[i];
         SUB: y[i]=a[i]-b[i];
         AND_OP: y[i]=a[i]&b[i];
         OR_OP: y[i]=a[i]|b[i];
         XOR_OP: y[i]=a[i]^b[i];
         SHL: y[i]=a[i] << b[i][$clog2(WIDTH)-1:0];
         SHR: y[i]=a[i] >> b[i][$clog2(WIDTH)-1:0];
         MUL: y[i]=a[i]*b[i];
         default: y[i]='0;
       endcase
     end
   end
 end
endmodule
