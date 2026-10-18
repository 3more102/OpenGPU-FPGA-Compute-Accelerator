# OpenGPU v0.2 instruction set

All instructions are 32 bits. The current core has 16 32-bit registers per lane, eight lanes by default, and a single warp. Register r0 always reads as zero and is write-protected. Arithmetic results wrap to 32 bits. The current hardware profile uses WIDTH=32.

## Register-register ALU

When bit 16 is zero:

- opcode: bits 31:29
- rd: bits 28:25
- rs1: bits 24:21
- rs2: bits 20:17
- bits 16:0: reserved and should be zero

ALU opcodes: ADD=0, SUB=1, AND=2, OR=3, XOR=4, SHL=5, SHR=6, MUL=7. Shifts are logical and use the low five bits of operand B. A masked-off lane does not write a register and retires zero data.

## Extended instruction formats

Bit 16 marks an extended instruction. The four-bit tag in bits 20:17 selects the format.

### Lane-local LOAD / STORE — opcode 000, tag 0000

- bit 15: 0 for LOAD, 1 for STORE
- bits 14:0: signed 15-bit word offset
- rd: LOAD destination or STORE source-data register
- rs1: base word-address register

The effective word address is the base register plus the signed offset; the low six bits index one of 64 words in that lane's private 32-bit bank. Banks are independent, not shared. LOAD has a synchronous one-cycle latency and backpressures issue. Memory is not reset; software must store before loading a location.

### ALU immediate — tag 1111

- opcode: bits 31:29, using the same eight ALU operations
- rd: bits 28:25
- rs1: bits 24:21
- bits 20:17: tag 1111
- bit 16: 1
- bits 15:0: signed two's-complement immediate

The immediate is sign-extended to 32 bits before the ALU operation. Shift operations use its low five bits as the shift amount. For example, ADDI r11, r1, 5 computes r11 = r1 + 5 in each active lane.

### Conditional branch / jump — tag 1110

- branch opcode: bits 31:29
- comparison register A: bits 28:25
- comparison register B: bits 24:21
- bits 20:17: tag 1110
- bit 16: 1
- bits 15:0: signed PC-relative offset in instruction words

Branch opcodes: BEQ=0, BNE=1, BLT=2 (signed), BGE=3 (signed), BLTU=4 (unsigned), BGEU=5 (unsigned), JUMP=6, reserved=7. The target is PC + 1 + offset. A taken target must be within the ROM program; an out-of-range target raises a sticky fault.

## SIMT branch policy and faults

This phase implements only warp-uniform control flow. All active lanes must evaluate a branch predicate identically. If active lanes disagree, the top-level controller enters a sticky FAULT state and stops issuing instructions. Branches with no active lanes are treated as not taken. Divergence stacks, reconvergence, nested divergent control flow, interrupts, and exception recovery are not implemented. Invalid extended encodings and reserved branch opcode 7 also fault.

Branches retire with rd=0 and zero data. Masked-off lanes do not participate in branch uniformity checks. The fault output remains asserted until reset.

## Timing and limitations

Arithmetic, immediate, branch, and STORE instructions retire through the normal registered path. LOAD is accepted, then retires/writebacks one cycle later; issue_ready stays low while the read completes. The ROM is a small demonstration program, not a compiler target or general-purpose instruction memory.
