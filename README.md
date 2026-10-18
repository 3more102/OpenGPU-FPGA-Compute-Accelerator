# OpenGPU FPGA Compute Accelerator

Experimental **8-lane single-warp integer SIMT execution core**, written in synthesizable SystemVerilog. This is **not yet a complete GPU**.

## Implemented
- Custom fixed-width 32-bit register-register ISA with 8 arithmetic/bitwise operations.
- Combinational 8-lane ALU, lane execution mask, 16 x 32-bit registers per lane (r0 write-protected).
- One instruction per cycle interface with registered retirement result and resettable register file.
- Python architectural reference model and deterministic unit tests.

## Not implemented / not validated
- FPGA synthesis, timing closure, resource utilization, hardware bring-up.
- RTL simulator cross-check, UVM testbench, warp scheduler, instruction fetch, memory, branches, divergence, floating point, CUDA, or graphics.

## Run reference tests

```bash
python -m unittest discover -s tests -v
```

## Next milestones
1. Run RTL simulation and compare retirement trace against the Python model.
2. Implement instruction fetch and small program ROM; add a deterministic data initialization mechanism.
3. Implement load/store and FPGA BRAM, then multi-warp scheduling.

See `docs/ISA.md` for encoding and execution semantics.
