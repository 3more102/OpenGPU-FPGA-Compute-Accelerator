# Validation Status

## Automated checks

- Python reference unit tests: python -m unittest discover -s tests -v.
- RTL integration simulation: make test-rtl using Icarus Verilog (iverilog and vvp).
- Generic synthesis smoke test: make test-synth using Yosys.
- CI installs Icarus Verilog and Yosys and runs all three checks on pushes and pull requests.

The top-level testbench checks all seven retirement records, arithmetic values for every lane, store/load round-trip behavior, a load-use dependency, the synchronous load stall, masked-off lane zeros, completion/drain behavior, and restarting the program.

## Evidence policy

A green CI run demonstrates Python reference behavior, RTL simulation, and generic synthesis only. It does not prove target-FPGA resource utilization, timing closure, power, bitstream correctness, or on-board behavior. Those require a named FPGA part, clock constraints, a target-specific implementation toolchain, and hardware validation. No such hardware results are claimed here.
