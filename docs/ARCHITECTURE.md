# OpenGPU Phase 5 — Immediate operations and control flow

## Implemented RTL

- rtl/opengpu_alu.sv: combinational 32-bit integer ALU with eight operations and lane masking.
- rtl/opengpu_scratchpad.sv: synchronous 64-word x 32-bit memory bank per lane; memory contents are not reset.
- rtl/opengpu_core.sv: 16 registers per lane, host preload, register-register and immediate ALU operations, lane-local LOAD/STORE, branch predicates, uniformity detection, and retirement trace.
- rtl/opengpu_program_rom.sv: twelve-word demonstration program.
- rtl/opengpu_top.sv: IDLE -> RUN -> DRAIN -> DONE controller with branch redirection and sticky FAULT handling.
- tb/tb_opengpu_top.sv: arithmetic, memory, immediate, taken/not-taken branch, mask, restart, and divergent-branch fault checks.

## Demo program

| PC | Instruction | Purpose |
|---:|---|---|
| 0 | ADD r3, r1, r2 | Per-lane sum |
| 1 | XOR r4, r1, r2 | Bitwise operation |
| 2 | MUL r5, r1, r2 | Per-lane product |
| 3 | SUB r6, r3, r2 | Verify dependent arithmetic |
| 4 | STORE r5, [r8 + 0] | Save product in each lane's private bank |
| 5 | LOAD r9, [r8 + 0] | Synchronous memory read |
| 6 | ADD r10, r9, r1 | Consume loaded value |
| 7 | ADDI r11, r1, 5 | Sign-extended immediate |
| 8 | BNE r1, r2, +1 | Taken branch skips PC 9 |
| 9 | ADDI r12, r1, 99 | Sentinel; must not execute in the default test |
| 10 | ADD r13, r11, r1 | Dependent instruction at branch target |
| 11 | BNE r1, r1, +1 | Not taken; fall through to program completion |

The default preload sets r1 to lane+1, r2 to 10, and r8 to zero. Thus PC 8 branches uniformly to PC 10. The testbench then changes r2 in lane 0 only, creating a mixed BNE predicate; the core must stop at PC 8 with fault asserted.

## Datapath and control flow

Program counter -> ROM -> decode/register read -> ALU or lane-local memory -> register writeback and retirement. On a taken uniform branch, the PC becomes PC+1+signed_offset. The target is range-checked before redirect. A divergent branch, invalid extended instruction, reserved branch opcode, or invalid target stops issue and latches FAULT until reset.

## Scope boundaries

Not implemented: divergent branch stacks/reconvergence, loops with dynamic iteration support beyond the simple branch mechanism, shared/global memory, atomics, DMA, caches, multiple warps, warp scheduling, floating point, tensor/matrix units, graphics, CUDA compatibility, compiler/runtime, board-specific wrapper, or target FPGA timing/resource reports.
