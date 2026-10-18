# OpenGPU v0 instruction set

Each 32-bit instruction has fields: `opcode[31:29]`, `rd[28:25]`, `rs1[24:21]`, `rs2[20:17]`, reserved `[16:0]` (software must write zero). 16 registers per lane, `r0` always zero. All lanes in a warp execute the same instruction with independent register values. Masked-off lanes do not write back; their retire data is zero. Eight operations: ADD=0, SUB=1, AND=2, OR=3, XOR=4, SHL=5, SHR=6, MUL=7. Results wrap to 32 bits. Shifts are logical and use the low five bits of operand B. No branches, load/store, immediate instructions, or compiler support yet. The external instruction stream must supply valid opcodes and legal register indices.

## Timing

An instruction accepted at rising edge N updates the register file and asserts `retire_valid` after that edge. `retire_data` is registered. The next instruction may be issued at edge N+1; reads observe the previous write. There is no reset initialization of instruction memory because instruction memory is external. `issue_ready` is tied high; issue must be externally controlled.
