# Validation Status

## Automated checks

- Python reference unit tests: python -m unittest discover -s tests -v.
- RTL integration simulation: make test-rtl using Icarus Verilog (iverilog and vvp).
- CI installs Icarus Verilog and runs both suites on pushes and pull requests.

The RTL testbench checks the ROM instruction sequence through observed retirement, lane-specific arithmetic results, execution masks, masked-off zero retirement data, completion/drain behavior, and restart.

## Evidence policy

A green CI run demonstrates simulation and Python tests only. It does not prove FPGA synthesis, timing closure, resource utilization, power, bitstream correctness, or on-board behavior. Those require a named FPGA part, clock constraints, a synthesis/implementation toolchain, and hardware validation. No such hardware results are claimed here.
