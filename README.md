# OpenGPU FPGA Compute Accelerator

Experimental 8-lane single-warp integer SIMT compute core in synthesizable SystemVerilog. This is an FPGA-oriented compute prototype, not a complete GPU.

## Implemented

- 32-bit modular integer ALU: ADD, SUB, AND, OR, XOR, logical SHL/SHR, and low-32-bit MUL.
- Eight SIMT lanes, 16 registers per lane, write-protected r0, execution masks, and registered retirement.
- Register-register operations plus signed 16-bit ALU-immediate instructions.
- BEQ, BNE, signed/unsigned relational branches, and unconditional PC-relative jump.
- Warp-uniform branch validation; divergent predicates, invalid extended encodings, and out-of-range taken targets latch a fault.
- One 64-word x 32-bit lane-local memory bank per lane, with synchronous LOAD and STORE support.
- Host-programmable instruction RAM with per-word overrides of the built-in twelve-word demonstration ROM.
- Host-selected active program length, instruction-write readiness, and protection against program writes while execution is active.
- Simple 32-bit MMIO control/status wrapper for program upload, launch, status polling, execution-mask configuration, per-lane register preload, and register/retirement readback.
- Two-pass Python assembler/disassembler with labels, signed immediates, memory operands, PC-relative branches, and hex/JSON program images.
- 32-bit cycle, retired-instruction, and taken-branch counters, readable through MMIO and reset on each accepted launch.
- MMIO regression uploads and executes a backward-branch loop, checking the final per-lane result and two taken branches.
- Host scratchpad I/O through a gated per-lane MMIO read/write port (preload inputs, run a kernel, retrieve outputs).
- Phase 12 differential kernel suite: source assembler -> independent math checks and Python architectural reference -> MMIO-based RTL execution and readback.
- Python reference model, Icarus Verilog integration simulation, Yosys generic synthesis smoke test, and CI.

## Run tests

Python reference: python -m unittest discover -s tests -v

RTL simulation: make test-rtl

Multi-kernel differential checks: make test-programs

Generic synthesis smoke test: make test-synth

All checks: make test

Assemble the sample kernel: make assemble-demo. This writes build/demo.hex. Disassemble a hex image with python tools/opengpu_asm.py build/demo.hex --disassemble.

## Program loading interface

While IDLE or DONE, assert program_we for a clock edge, set program_addr and program_wdata, and confirm program_write_ready is high. Set program_length to the number of words to execute; zero selects the compiled-in default length. The program length is latched when start is accepted. Uploaded words override the ROM at matching addresses; unmodified words fall back to the ROM. Reset clears the valid map and restores ROM fallback. Program writes are blocked while RUN, DRAIN, or FAULT is active.

## MMIO register map

The optional opengpu_mmio wrapper exposes a single-outstanding request/response interface. Word addresses: 0x00 CONTROL (write bit 0 to start), 0x04 STATUS (busy/done/fault/program-write-ready in bits 0–3), 0x08 PROGRAM_LENGTH, 0x0C PROGRAM_ADDR, 0x10 PROGRAM_DATA, 0x14 PROGRAM_CMD (write bit 0), 0x18 REG_SELECT (lane in low bits, register index in bits 7:4), 0x1C REG_WDATA, 0x20 REG_CMD (write bit 0), 0x24 EXEC_MASK, 0x28 RETIRE_INFO, 0x2C RETIRE_DATA for the selected lane, 0x30 REG_RDATA, 0x34 PC, 0x38 CYCLE_COUNT, 0x3C RETIRED_COUNT, and 0x40 BRANCH_TAKEN_COUNT. Misaligned and unsupported addresses return rsp_error.

## Lane-local host data I/O

Example kernel: `examples/vector_add7.ogasm` (LOAD, ADDI, STORE, LOAD). Assemble it with `python tools/opengpu_asm.py examples/vector_add7.ogasm`. The Python regression independently checks the four encoded words and applies them to all eight lane memory banks under an 0x55 execution mask.



The custom MMIO map adds four addresses: 0x44 MEM_SELECT (lane index in low bits, word index in bits 8–13 for the default 64-word memory), 0x48 MEM_WDATA, 0x4C MEM_CMD (write exactly 1 for a synchronous read, exactly 2 for a write), and 0x50 MEM_RDATA (latest registered read for the selected lane). Host scratchpad commands are accepted only while the core is IDLE or DONE and cannot overlap kernel memory accesses. Memory contents are intentionally not reset. The phase-11 integration regression uploads two input/output words per lane, computes on active lanes, then reads back and checks all eight banks. This is a word-at-a-time host port, not DMA or a shared/global memory subsystem.

## Differential kernel validation (Phase 12)

`make test-programs` generates deterministic 32-bit instruction images, lane inputs, sentinels, expected scratchpad outputs, and expected r5 register values for five cases: ADDI +7 on all lanes, ADDI +7 with mask 0x55, bitwise invert, integer square +3 with mask 0xAA, and ADDI -17. The generator checks each program against an independent arithmetic oracle and executes the Python architectural model. The RTL testbench then uploads the generated instructions and inputs through MMIO, runs the kernels, checks retirement counts and output words, and compares every lane's r5 and scratchpad contents.

This is a correctness regression over five selected programs, not exhaustive verification, hardware benchmarking, or FPGA proof.

## Not implemented / not validated

- Divergence stack/reconvergence, multi-warp scheduling, shared/global memory, atomics, DMA, caches, floating point, tensor/matrix acceleration, graphics, or CUDA compatibility.
- Compiler, runtime, board-specific top wrapper, pin/clock constraints, target FPGA timing/resource reports, bitstream generation, power estimates, or physical hardware validation.

Memory contents are not reset; software must store a word before loading it. Generic Yosys synthesis is not evidence of timing closure or on-board operation. See docs/ISA.md, docs/ARCHITECTURE.md, and docs/VALIDATION.md.
