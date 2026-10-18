# OpenGPU FPGA Compute Accelerator

Experimental **8-lane single-warp integer SIMT compute core** in synthesizable SystemVerilog. This is a small FPGA-oriented compute accelerator prototype, **not a complete GPU**.

## Implemented

- 32-bit modular integer ALU: ADD, SUB, AND, OR, XOR, logical SHL/SHR, and low-32-bit MUL.
- Eight SIMT lanes with a per-instruction execution mask and 16 x 32-bit registers per lane (r0 is write-protected and reads as zero).
- Single-issue in-order core with registered retirement trace and a host preload port for lane registers.
- Synthesizable four-word demo instruction ROM and top-level IDLE/RUN/DRAIN/DONE controller.
- Python architectural reference model, unit tests, SystemVerilog top-level testbench, and CI jobs for Python plus RTL simulation.

## Demo program

1. ADD r3, r1, r2
2. XOR r4, r1, r2
3. MUL r5, r1, r2
4. SUB r6, r3, r2

Host preload initializes r1 and r2 independently for each lane. The testbench checks every retired instruction, all lane results, masked-off lanes, and restarting the program.

## Run tests

    python -m unittest discover -s tests -v
    make test-rtl
    make test

The combined target requires Python and Icarus Verilog.

## Not implemented / not validated

- Load/store or any memory hierarchy, branches/divergence, multiple warps or a warp scheduler.
- Floating point, tensor/matrix acceleration, graphics, CUDA compatibility, compiler, or runtime.
- FPGA-specific board wrapper, synthesis/resource reports, timing closure, bitstream generation, power estimates, or physical hardware validation.

A passing simulation is not evidence of FPGA timing closure or on-board operation. See docs/ARCHITECTURE.md, docs/ISA.md, and docs/VALIDATION.md for scope and semantics.
