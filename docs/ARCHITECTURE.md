# OpenGPU Phase 6 — Host-programmable instruction memory

## Implemented RTL

- rtl/opengpu_alu.sv: eight-operation 32-bit integer ALU.
- rtl/opengpu_scratchpad.sv: synchronous private memory bank per lane.
- rtl/opengpu_core.sv: SIMT register file, arithmetic, signed immediate operations, lane-local LOAD/STORE, uniform branches, and divergence detection.
- rtl/opengpu_program_rom.sv: built-in twelve-word demonstration program.
- rtl/opengpu_top.sv: program-memory overrides, active-length latch, run controller, branch target checking, and sticky FAULT.
- tb/tb_opengpu_top.sv: default-ROM integration and divergence fault regression.
- tb/tb_opengpu_program_load.sv: host-uploaded kernel, active length, execution, and write-protection test.

## Program loading behavior

The instruction store contains 2^ADDR_W words. A valid bit accompanies each word. On reset, valid bits clear and the built-in ROM becomes the fallback source. A host write while IDLE or DONE stores a 32-bit instruction and sets that address valid. A valid uploaded word takes priority over the ROM; unmodified addresses continue to read the ROM.

The program length is a host input captured when start is accepted. Zero selects the compiled-in PROGRAM_WORDS default; larger values are clamped to the instruction-store depth. Program writes are accepted only while IDLE or DONE. Writes while RUN, DRAIN, or FAULT are ignored. A program must be fully uploaded before start. Reset invalidates uploaded words but does not clear the underlying RAM bits.

## Uploaded-kernel test

The testbench uploads a three-word kernel:

1. ADDI r3, r1, 5
2. ADDI r4, r3, -2
3. ADD r5, r4, r1

With r1 initialized to lane+1, expected per-lane results are r3=lane+6, r4=lane+4, and r5=2*lane+5. The test also attempts to overwrite word 0 during RUN and confirms that the write is blocked.

## Boundaries

This is a basic host programming port, not a standardized bus, DMA engine, software driver, or binary loader. Program and data memories are separate; the core remains single-warp and integer-only. Target FPGA resource mapping and timing are not established by generic Yosys synthesis.
