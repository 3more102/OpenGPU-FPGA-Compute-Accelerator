# OpenGPU Phase 4 — Lane-Local Memory

## Implemented in RTL

- rtl/opengpu_alu.sv: combinational 32-bit integer ALU with eight operations and lane masking.
- rtl/opengpu_core.sv: single in-order warp, 16 registers per lane, host preload, arithmetic execution, load/store decode, load backpressure, and retirement trace.
- rtl/opengpu_scratchpad.sv: synchronous 64-word x 32-bit memory bank per lane. Read data is registered; memory contents are not reset.
- rtl/opengpu_program_rom.sv: seven-word demo program with arithmetic, store, load, and dependent arithmetic.
- rtl/opengpu_top.sv: IDLE -> RUN -> DRAIN -> DONE controller. PC advances only when the core accepts the current instruction.
- tb/tb_opengpu_top.sv: verifies arithmetic, store/load round trip, load-use dependency, retirement metadata, lane masks, completion, and restart.

## Data path

program counter -> ROM -> instruction decode/register read -> ALU or lane-local memory -> register writeback + retirement trace

For memory instructions, the base register contains a word address and the signed immediate is also measured in words. The low six bits index a 64-word bank for that lane. Banks are independent: this is not cross-lane shared memory.

## Demo program

| PC | Instruction | Meaning |
|---:|---|---|
| 0 | ADD r3, r1, r2 | Per-lane sum |
| 1 | XOR r4, r1, r2 | Per-lane bitwise XOR |
| 2 | MUL r5, r1, r2 | Per-lane low 32-bit product |
| 3 | SUB r6, r3, r2 | Reconstruct r1 |
| 4 | STORE r5, [r8 + 0] | Save product in the lane's bank |
| 5 | LOAD r9, [r8 + 0] | Read the saved product |
| 6 | ADD r10, r9, r1 | Consume loaded data |

The demo host-preloads r1 and r2 with lane-specific values and r8 with zero. STORE occurs before LOAD, so the test does not rely on uninitialized memory.

## Scope boundaries

Not implemented: shared/global memory, atomics, DMA, caches, branches, divergence/reconvergence, multiple warps, warp scheduling, floating point, tensor/matrix units, graphics, CUDA compatibility, or a production software stack.

## Parameter assumptions

The instruction format has four-bit register fields, so REGS must be 16. The current ROM contains seven defined instructions; PROGRAM_WORDS is intended to be 1–7. The default memory has 64 words per lane and 32-bit words. This is not a board-specific pin/clock wrapper.
