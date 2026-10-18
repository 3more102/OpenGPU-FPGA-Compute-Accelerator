// Twelve-word demo program: arithmetic, private-memory round trip, ADDI, taken and not-taken branches.
module opengpu_program_rom #(
    parameter int ADDR_W = 4
) (
    input  logic [ADDR_W-1:0] addr,
    output logic [31:0] instruction
);
    always_comb begin
        case (addr)
            0:  instruction = 32'h0624_0000; // ADD r3, r1, r2
            1:  instruction = 32'h8824_0000; // XOR r4, r1, r2
            2:  instruction = 32'hEA24_0000; // MUL r5, r1, r2
            3:  instruction = 32'h2C64_0000; // SUB r6, r3, r2
            4:  instruction = 32'h0B01_8000; // STORE r5, [r8 + 0]
            5:  instruction = 32'h1301_0000; // LOAD r9, [r8 + 0]
            6:  instruction = 32'h1522_0000; // ADD r10, r9, r1
            7:  instruction = 32'h163F_0005; // ADDI r11, r1, 5
            8:  instruction = 32'h225D_0001; // BNE r1, r2, +1 (uniformly taken in the demo)
            9:  instruction = 32'h183F_0063; // ADDI r12, r1, 99 (skipped by the branch)
            10: instruction = 32'h1B62_0000; // ADD r13, r11, r1
            11: instruction = 32'h223D_0001; // BNE r1, r1, +1 (not taken)
            default: instruction = 32'h0000_0000; // ADD r0, r0, r0
        endcase
    end
endmodule
