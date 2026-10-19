# Phase 14 — Memory Arbitration and FPGA Readiness

Status: engineering specification; RTL integration and verification pending.

## Objective
Extend the existing lane-local scratchpad architecture without breaking Phase 13's configurable-lane simulation results.

## Requirements
1. Preserve current LOAD/STORE semantics, MMIO addresses and inactive-lane write suppression.
2. Introduce an explicitly arbitrated host-versus-core scratchpad access interface. Host commands are accepted only in IDLE/DONE until arbitration is verified.
3. Define synchronous read latency and read-after-write behavior in cycle-accurate tests.
4. Add out-of-range address checks and deterministic error responses; never silently alias addresses.
5. Validate configurations LANES=1,2,4,8,16 and execution masks zero, full and alternating.
6. Compare complete scratchpad and register results with the independent Python ISA model.
7. Measure generic Yosys cell counts and document that these are not FPGA utilization or timing results.

## Acceptance gates
- Existing `make test` passes unchanged.
- New directed tests cover host/core exclusion, lane isolation, masking, boundary addresses and read/write ordering.
- Seeded differential tests pass for all supported lane counts.
- CI runs the tests and publishes reproducible logs.
- No claim of physical FPGA readiness without target board, pin constraints, synthesis, place-and-route and hardware measurements.

## Follow-on milestones
Phase 15: multi-warp scheduler with isolated warp state.
Phase 16: controlled divergence/reconvergence.
Phase 17: external memory and burst transfers.
Phase 18: FPGA board implementation and measured timing/resource utilization.
