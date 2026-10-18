// Small synthesizable demo program ROM. Unlisted addresses are safe ADD r0,r0,r0.
// Program: r3=r1+r2; r4=r1^r2; r5=r1*r2; r6=r3-r2.
module opengpu_program_rom #(
    parameter int ADDR_W = 2
) (
    input  logic [ADDR_W-1:0] addr,
    output logic [31:0] instruction
);
    always_comb begin
        case (addr)
            0: instruction = 32'h0624_0000; // ADD r3, r1, r2
            1: instruction = 32'h8824_0000; // XOR r4, r1, r2
            2: instruction = 32'hEA24_0000; // MUL r5, r1, r2
            3: instruction = 32'h2C64_0000; // SUB r6, r3, r2
            default: instruction = 32'h0000_0000; // ADD r0, r0, r0
        endcase
    end
endmodule
