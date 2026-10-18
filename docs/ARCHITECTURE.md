# OpenGPU Phase 3 — Integrated Execution

## Implemented in RTL

- rtl/opengpu_alu.sv: combinational 32-bit integer ALU, eight operations, lane mask.
- rtl/opengpu_core.sv: one in-order warp, 16 registers per lane, r0 write-protected, one-cycle registered retirement, host register preload port.
- rtl/opengpu_program_rom.sv: synthesizable four-word demo ROM; unused addresses return the safe encoding ADD r0,r0,r0.
- rtl/opengpu_top.sv: FSM for IDLE -> RUN -> DRAIN -> DONE, ROM address/issue control, host preload while idle or done, and restart after completion.
- tb/tb_opengpu_top.sv: top-level simulation checks all four retired instructions, all eight lanes, masked-off lane zeros, and restart behavior.

## Data path

program_counter -> program_rom -> instruction decode/register read -> lane ALU -> register writeback + retirement trace

The host preload port writes one lane/register per accepted clock. Host writes are blocked during execution. r0 reads as zero and host/core writes to r0 are ignored.

## Demo program

| PC | Instruction | Meaning |
|---:|---|---|
| 0 | ADD r3, r1, r2 | Per-lane sum |
| 1 | XOR r4, r1, r2 | Per-lane bitwise XOR |
| 2 | MUL r5, r1, r2 | Per-lane low 32-bit product |
| 3 | SUB r6, r3, r2 | Reconstructs r1 after the sum |

The demo uses host-loaded lane data; it does not imply a memory subsystem, instruction cache, compiler, or general-purpose programming model.

## Scope boundaries

Still not implemented: load/store, local/shared/global memory, branches, divergence/reconvergence, multiple warps, warp scheduling, floating point, tensor/matrix units, DMA, cache hierarchy, graphics, CUDA compatibility, or a production software stack.

## Parameter assumptions

The instruction format provides four-bit register fields, so REGS must be 16 for this ISA. PROGRAM_WORDS is intended to be 1–4 for the current demo ROM; addresses outside the four defined words return the safe zero-register ADD. The default lane count is eight. The demo and testbench are not a board-specific pin/clock wrapper.
