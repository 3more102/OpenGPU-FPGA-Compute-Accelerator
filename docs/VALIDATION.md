# Validation Status

## Automated checks

- Python reference tests: python -m unittest discover -s tests -v.
- RTL simulation: make test-rtl runs the default-ROM regression and the uploaded-program regression using Icarus Verilog.
- Generic synthesis smoke test: make test-synth using Yosys.
- The MMIO integration regression checks instruction upload, host register writes, start, status polling, per-lane register readback, cycle/retirement/branch counters, cycle/retirement/branch counters, a backward-branch loop kernel with negative PC-relative offset, and misaligned-address error reporting.
- Python assembler tests check parity with the RTL demo words, branch-label resolution, signed-field limits, disassembly round trips, and invalid source diagnostics.
- CI runs all checks on pushes and pull requests.

The default-ROM test covers arithmetic, memory round trip, immediate execution, taken/not-taken branches, masking, restart, and divergence fault. The program-loader test checks host register preload, instruction RAM writes, per-word ROM override, active program length, execution of uploaded instructions, and blocked writes while running.

## Evidence policy

A green CI run demonstrates Python reference behavior, RTL simulation, and generic Yosys synthesis only. It does not prove target-FPGA resource utilization, timing closure, power, bitstream correctness, or on-board operation. Those require a named FPGA part, clock constraints, target-specific implementation tools, and hardware validation. No such hardware results are claimed.
