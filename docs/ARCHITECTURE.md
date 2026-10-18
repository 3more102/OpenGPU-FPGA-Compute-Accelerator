# OpenGPU Phase 7 — MMIO host control and readback

## Implemented RTL

- rtl/opengpu_mmio.sv: single-outstanding 32-bit request/response register bus.
- rtl/opengpu_top.sv: host-programmable instruction RAM, active program length, execution controller and status.
- rtl/opengpu_core.sv: host register write and selected-register readback ports, SIMT execution, memory, immediate operations and branches.
- tb/tb_opengpu_mmio.sv: uploaded-kernel execution through the bus, status polling, per-lane register readback and invalid-access response checks.

## Register map

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
| 0x20 | W/R | REG_CMD: write bit 0 to commit REG_WDATA to selected lane/register |
| 0x24 | R/W | EXEC_MASK |
| 0x28 | R | RETIRE_INFO: active mask in low bits, destination register in the next four bits |
| 0x2C | R | RETIRE_DATA for the selected lane |
| 0x30 | R | REG_RDATA for the selected lane/register |
| 0x34 | R | Current program counter |

All addresses are byte addresses and must be word-aligned. Requests are accepted when req_valid and req_ready are both high. A response is held until rsp_valid and rsp_ready handshake. Unsupported or misaligned accesses return rsp_error. Only one response may be outstanding.

## Program launch sequence

1. Set PROGRAM_LENGTH.
2. For each instruction, write PROGRAM_ADDR, write PROGRAM_DATA, then write PROGRAM_CMD=1.
3. Use REG_SELECT, REG_WDATA, and REG_CMD=1 to preload registers.
4. Configure EXEC_MASK if needed.
5. Write CONTROL=1 to launch.
6. Poll STATUS until done or fault; read REG_SELECT and REG_RDATA to inspect results.

The wrapper returns an error for launch requests while busy/faulted and blocks program/register commit operations while the core is executing. This is a basic synchronous host interface, not AXI-Lite, a DMA engine, or a standardized software ABI.
