# OpenGPU FPGA Compute Accelerator

Experimental **8-lane single-warp integer SIMT compute core** in synthesizable SystemVerilog. This is an FPGA-oriented compute prototype, not a complete GPU.

## Implemented

- 32-bit modular integer ALU: ADD, SUB, AND, OR, XOR, logical SHL/SHR, and low-32-bit MUL.
- Eight SIMT lanes, 16 registers per lane, write-protected r0, execution masks, and registered retirement.
- Register-register operations plus signed 16-bit ALU-immediate instructions.
- BEQ, BNE, signed/unsigned relational branches, and unconditional jump with PC-relative word offsets.
- Warp-uniform branch validation; divergent predicates, invalid extended encodings, and out-of-range taken targets latch a fault instead of silently executing incorrectly.
- One 64-word x 32-bit lane-local memory bank per lane, with synchronous LOAD and STORE support.
- Twelve-word demo ROM exercises arithmetic, memory, ADDI, taken branch, skipped sentinel instruction, branch target execution, and not-taken branch.
- Python reference model, deterministic tests, Icarus Verilog integration simulation, Yosys generic synthesis smoke test, and CI.

## Run tests

Python reference: python -m unittest discover -s tests -v

RTL simulation: make test-rtl

Generic synthesis smoke test: make test-synth

All checks: make test

## Not implemented / not validated

- Divergence stack/reconvergence, multi-warp scheduling, shared/global memory, atomics, DMA, caches, floating point, tensor/matrix acceleration, graphics, or CUDA compatibility.
- Compiler, runtime, board-specific top wrapper, pin/clock constraints, target FPGA timing/resource reports, bitstream generation, power estimates, or physical hardware validation.

Memory contents are not reset; software must store a word before loading it. Generic Yosys synthesis is not evidence of timing closure or on-board operation. See docs/ISA.md, docs/ARCHITECTURE.md, and docs/VALIDATION.md.
