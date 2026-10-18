# OpenGPU Architecture and Development Phases

## Current architecture

OpenGPU is an experimental 8-lane, single-warp, 32-bit integer SIMT compute prototype. The synthesizable RTL includes:

- rtl/opengpu_alu.sv: ADD, SUB, AND, OR, XOR, logical SHL/SHR, and low-32-bit MUL.
- rtl/opengpu_scratchpad.sv: one synchronous 64-word x 32-bit private memory bank per lane.
- rtl/opengpu_core.sv: 16 registers per lane, r0 hard-wired to zero, host register writes/readback, lane masking, arithmetic, immediate operations, memory operations, branch checks, and retirement.
- rtl/opengpu_program_rom.sv: twelve-word built-in demonstration program.
- rtl/opengpu_top.sv: host-programmable instruction memory, active program-length latch, branch target checks, completion, and sticky FAULT state.
- rtl/opengpu_mmio.sv: simple single-outstanding 32-bit request/response host interface.
- tools/opengpu_asm.py: assembler, label resolver, disassembler, and hex/JSON image output.
- rtl/opengpu_top.sv: 32-bit cycle, retired-instruction, and taken-branch performance counters reset on accepted launch.

## Program memory and control flow

The instruction store has 2^ADDR_W words. Each word has a valid bit. On reset, valid bits clear and the built-in ROM is the fallback. A host write while IDLE or DONE stores a word and marks it valid; uploaded words override ROM contents at matching addresses. Program length is captured when start is accepted. A length of zero selects PROGRAM_WORDS; oversized values are clamped to the instruction-store depth.

Program writes are accepted only while IDLE or DONE. Writes during RUN, DRAIN, or FAULT are ignored. Reset clears the valid map but does not reset the underlying instruction RAM bits.

The built-in twelve-word program executes arithmetic, a lane-local STORE/LOAD round trip, ADDI, a taken BNE that skips a sentinel instruction, an instruction at the branch target, and a not-taken BNE.

## MMIO register map

All addresses are byte addresses and must be word-aligned. The bus accepts a request when req_valid and req_ready are both high. A response is held until rsp_valid and rsp_ready handshake. Unsupported or misaligned accesses return rsp_error.

| Address | Access | Meaning |
|---|---|---|
| 0x00 | W/R | CONTROL: write bit 0 to start; reads return zero |
| 0x04 | R | STATUS: bit 0 busy, bit 1 done, bit 2 fault, bit 3 program-write-ready |
| 0x08 | R/W | PROGRAM_LENGTH; zero selects the compiled-in default |
| 0x0C | R/W | PROGRAM_ADDR |
| 0x10 | R/W | PROGRAM_DATA |
| 0x14 | W/R | PROGRAM_CMD: write bit 0 to commit PROGRAM_DATA at PROGRAM_ADDR |
| 0x18 | R/W | REG_SELECT: lane index in low bits, register index in bits 7:4 |
| 0x1C | R/W | REG_WDATA |
| 0x20 | W/R | REG_CMD: write bit 0 to commit REG_WDATA to the selected lane/register |
| 0x24 | R/W | EXEC_MASK |
| 0x28 | R | RETIRE_INFO: active mask in low bits, destination register in the next four bits |
| 0x2C | R | RETIRE_DATA for the selected lane |
| 0x30 | R | REG_RDATA for the selected lane/register |
| 0x34 | R | Current program counter |\n| 0x38 | R | Cycles spent in RUN and DRAIN |\n| 0x3C | R | Instructions retired in the latest run |\n| 0x40 | R | Uniform taken branches in the latest run |

## Assembler and program-image workflow

The assembler supports register ALU operations, signed-immediate ALU operations, LOAD/STORE, BEQ/BNE, signed and unsigned relational branches, JUMP, labels, and NOP. It checks signed field widths and resolves labels into PC-relative word offsets.

- Source example: examples/demo.ogasm
- Tool: tools/opengpu_asm.py
- Build image: make assemble-demo, which writes build/demo.hex
- Disassemble an image: python tools/opengpu_asm.py build/demo.hex --disassemble

To load a kernel, write PROGRAM_LENGTH, then for each instruction write PROGRAM_ADDR, PROGRAM_DATA, and PROGRAM_CMD=1. Preload lane registers with REG_SELECT, REG_WDATA, and REG_CMD=1. Configure EXEC_MASK, write CONTROL=1, poll STATUS, and inspect REG_RDATA.

## SIMT branch policy and fault behavior

Branches are warp-uniform in this phase. All active lanes must evaluate the predicate identically. A divergent predicate, invalid extended encoding, reserved branch opcode, or out-of-range taken target latches FAULT and stops issue. Branches with no active lanes are treated as not taken. Divergence stacks, reconvergence, and exception recovery are not implemented.

## Validation boundaries

The CI suite runs Python reference and assembler tests, three Icarus Verilog testbenches, and a Yosys generic synthesis smoke test. A green run does not establish target-FPGA resource utilization, timing closure, power, bitstream correctness, or physical hardware operation. The MMIO wrapper is a small custom synchronous interface, not AXI-Lite. OpenGPU does not yet provide a compiler, standardized ABI, DMA, shared/global memory, caches, multi-warp scheduling, floating point, tensor acceleration, graphics, or CUDA compatibility.
