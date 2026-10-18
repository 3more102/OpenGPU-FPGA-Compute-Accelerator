# Validation Status

## Automated checks

- Python reference tests: python -m unittest discover -s tests -v.
- RTL simulation: make test-rtl runs the default-ROM regression and the uploaded-program regression using Icarus Verilog.
- Generic synthesis smoke test: make test-synth using Yosys.
- The MMIO integration regression checks instruction upload, host register writes, start, status polling, per-lane register readback, cycle/retirement/branch counters, a backward-branch loop kernel with negative PC-relative offset, and misaligned-address error reporting.
- Python assembler tests check parity with the RTL demo words, branch-label resolution, signed-field limits, disassembly round trips, and invalid source diagnostics.
- Phase 11 RTL regression checks host scratchpad writes, registered reads, lane masking, private-memory input preservation, result readback, and illegal memory-command error reporting.
- CI runs all checks on pushes and pull requests.

The default-ROM test covers arithmetic, memory round trip, immediate execution, taken/not-taken branches, masking, restart, and divergence fault. The program-loader test checks host register preload, instruction RAM writes, per-word ROM override, active program length, execution of uploaded instructions, and blocked writes while running.

## Evidence policy

A green CI run demonstrates Python reference behavior, RTL simulation, and generic Yosys synthesis only. It does not prove target-FPGA resource utilization, timing closure, power, bitstream correctness, or on-board operation. Those require a named FPGA part, clock constraints, target-specific implementation tools, and hardware validation. No such hardware results are claimed.

## Phase 12 — Model-to-RTL differential checks

`make test-rtl` generates four reproducible source-assembled test cases, runs a separately implemented Python architectural model, and compares the simulated RTL's full register-file state (8 lanes × 16 registers), one memory word per lane, and completion/retirement metadata against the model. Cases use fixed seeds 7, 19, 41, and 137 and execution masks 0xFF, 0x55, 0xA3, and 0x00. The 12-word kernel includes every ALU operation, lane-local store/load, and two signed-immediate operations. Regressions are deterministic and runnable without an FPGA board. This does not test every possible program or prove timing closure.

## Phase 12 — Five mathematical-oracle comparisons

`make test-programs` checks five assembled straight-line kernels with independent arithmetic oracles, Python-model agreement, Icarus-Verilog MMIO execution, lane masks, scratchpad input preservation, memory output, register r5 readback, and retirement counts. No timing closure or hardware operation is implied.
