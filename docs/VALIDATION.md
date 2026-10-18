# Validation Status

## Automated checks

- Python reference tests: python -m unittest discover -s tests -v.
- RTL integration simulation: make test-rtl using Icarus Verilog.
- Generic synthesis smoke test: make test-synth using Yosys.
- CI runs all three checks on pushes and pull requests.

The reference tests cover randomized ALU behavior, signed immediates and wraparound, all implemented branch predicates, PC-relative taken/not-taken control flow, divergent-branch rejection, invalid branch targets, lane-local memory, and inactive-lane masking. The RTL integration test checks arithmetic values, STORE/LOAD round trip, load-use dependency, ADDI, branch redirection, branch fall-through, sticky divergence fault, retirement metadata, completion, and restart.

## Evidence policy

A green CI run demonstrates Python reference behavior, RTL simulation, and generic Yosys synthesis only. It does not prove target-FPGA resource utilization, timing closure, power, bitstream correctness, or on-board operation. Those require a named FPGA part, clock constraints, target-specific implementation tools, and hardware validation. No such hardware results are claimed.
