# OpenGPU Phase 8 — Assembler and program-image tooling

## Implemented

- tools/opengpu_asm.py: two-pass assembler, label resolver, canonical disassembler, and command-line hex/JSON image output.
- examples/demo.ogasm: source version of the twelve-word RTL demonstration program.
- tests/test_assembler.py: ISA word parity, branch labels, signed immediate and memory-offset limits, disassembly round trips, NOP alias, and invalid-source tests.
- Makefile target assemble-demo: emits build/demo.hex for use with the host program-write interface.

## Supported syntax

- Register ALU: ADD, SUB, AND, OR, XOR, SHL, SHR, MUL.
- Immediate ALU: ADDI, SUBI, ANDI, ORI, XORI, SHLI, SHRI, MULI.
- Memory: LOAD rD, [rBase + offset] and STORE rS, [rBase - offset].
- Control flow: BEQ, BNE, BLT, BGE, BLTU, BGEU, JUMP; labels are resolved to signed PC-relative word offsets.
- NOP alias for ADD r0, r0, r0.
- Comments beginning with #, //, or semicolon.

The assembler enforces the v0.2 signed field widths and the current 16-word default image limit. The CLI can emit one eight-digit hexadecimal word per line or a JSON array. The disassembler accepts a hexadecimal image and prints canonical assembly; branch offsets are shown numerically.

## Workflow

1. Edit examples/demo.ogasm or another source file.
2. Run make assemble-demo or invoke tools/opengpu_asm.py directly.
3. Load each generated word through the MMIO PROGRAM_ADDR, PROGRAM_DATA, and PROGRAM_CMD registers.
4. Preload lane registers, set the active program length, launch, poll STATUS, and inspect REG_RDATA.

This is an assembler for the prototype ISA, not a compiler, linker, ABI, or CUDA toolchain.
