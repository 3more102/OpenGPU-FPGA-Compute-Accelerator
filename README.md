# OpenGPU FPGA Compute Accelerator

Experimental **8-lane single-warp integer SIMT compute core** in synthesizable SystemVerilog. This is an FPGA-oriented compute prototype, **not a complete GPU**.

## Implemented

- 32-bit modular integer ALU: ADD, SUB, AND, OR, XOR, logical SHL/SHR, and low-32-bit MUL.
- Eight SIMT lanes, per-instruction execution mask, and 16 x 32-bit registers per lane; r0 reads as zero and is write-protected.
- Single-issue in-order execution, registered retirement trace, and host register preload.
- Seven-word synthesizable demo ROM with arithmetic, STORE, LOAD, and a dependent arithmetic instruction.
- Six-bit word addressing with one 64 x 32-bit lane-local memory bank per lane.
- Synchronous load latency and issue backpressure while a load completes.
- Python reference model, deterministic unit tests, top-level SystemVerilog simulation, and CI for Python, Icarus Verilog, and Yosys generic synthesis.

## Demo program

1. ADD r3, r1, r2
2. XOR r4, r1, r2
3. MUL r5, r1, r2
4. SUB r6, r3, r2
5. STORE r5, [r8 + 0]
6. LOAD r9, [r8 + 0]
7. ADD r10, r9, r1

Host preload initializes r1, r2, and r8 for each lane. The demo stores and reloads the product in each lane's private bank, then consumes the loaded value in the final ADD. Each lane has its own memory bank; this is not shared memory.

## Run tests

    python -m unittest discover -s tests -v
    make test-rtl
    make test-synth
    make test

The combined target requires Python, Icarus Verilog, and Yosys.

## Not implemented / not validated

- Shared/global memory, atomics, DMA, caches, multi-warp scheduling, branches, divergence/reconvergence, or a compiler/runtime.
- Floating point, tensor/matrix acceleration, graphics, or CUDA compatibility.
- Board-specific constraints/wrapper, target-specific FPGA resource/timing reports, timing closure, bitstream generation, power estimates, or physical hardware validation.

The lane-local data memory is not reset; a program must write a location before reading it. Generic Yosys synthesis is a smoke test, not evidence of timing closure or on-board operation. See docs/ARCHITECTURE.md, docs/ISA.md, and docs/VALIDATION.md.
