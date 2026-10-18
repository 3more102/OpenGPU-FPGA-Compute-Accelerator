# OpenGPU v0 instruction set

## Register-register arithmetic

Canonical arithmetic instructions use this 32-bit layout:

- opcode: bits 31:29
- rd: bits 28:25
- rs1: bits 24:21
- rs2: bits 20:17
- reserved: bits 16:0, all zero

There are 16 registers per lane. r0 always reads as zero and writes are discarded. The eight ALU operations are ADD=0, SUB=1, AND=2, OR=3, XOR=4, SHL=5, SHR=6, and MUL=7. Results wrap to 32 bits. Shifts are logical and use the low five bits of operand B.

All lanes execute the same instruction with independent register values. A masked-off lane does not write a register and retires zero data.

## Lane-local memory extension

Bit 16, previously reserved, marks a memory instruction. Memory instructions must set opcode bits 31:29 to zero and rs2 bits 20:17 to zero.

- bit 16: 1, memory extension marker
- bit 15: 0 for LOAD, 1 for STORE
- bits 14:0: signed two's-complement word offset
- rd: destination register for LOAD; source-data register for STORE
- rs1: base word-address register

The effective word address is the unsigned value in rs1 plus the signed offset. The low six address bits select one of 64 words in that lane's private 32-bit memory bank; addresses wrap modulo 64. Each lane has an independent bank, so one lane cannot read another lane's stored values.

LOAD has a synchronous one-cycle memory-read latency. The core deasserts issue_ready while the load is pending, then writes the returned data to rd and emits the load retirement record. STORE writes on its accepted issue edge and retires in the normal one-cycle path. A STORE retirement reports rd=0 and zero retire data. Masked-off lanes neither access memory nor update registers and report zero retire data.

Memory contents are not reset or initialized by RTL. Software or the host must store a location before loading it. The seven-word demo program does this by storing r5 before loading it back into r9.

## Timing

Arithmetic and STORE instructions accepted at rising edge N update state and assert retire_valid after that edge. A LOAD is accepted at edge N, its memory read is captured synchronously, and its retirement/writeback occurs at the next rising edge. issue_ready is low while that load is completing, so the external instruction source must hold the next instruction stable until the core accepts it.

No branch, immediate arithmetic, atomics, shared memory, compiler support, or global-memory interface is implemented.
