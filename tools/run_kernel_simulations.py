"""Run OpenGPU RTL against the deterministic assembler/reference fixtures."""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vectors", type=Path, default=Path("build/kernel_vectors"))
    parser.add_argument("--sim", type=Path, default=Path("build/opengpu_kernel_tb"))
    args = parser.parse_args()
    manifest = json.loads((args.vectors / "manifest.json").read_text(encoding="utf-8"))
    if not manifest:
        raise ValueError("No kernel fixtures found")
    for case in manifest:
        name = case["name"]
        command = [
            "vvp", str(args.sim),
            f"+PROGRAM={args.vectors / (name + '_program.hex')}",
            f"+INPUTS={args.vectors / (name + '_inputs.hex')}",
            f"+SENTINELS={args.vectors / (name + '_sentinels.hex')}",
            f"+EXPECTED_MEMORY={args.vectors / (name + '_expected_memory.hex')}",
            f"+EXPECTED_R5={args.vectors / (name + '_expected_r5.hex')}",
            f"+MASK={case['mask']:02x}",
            f"+LENGTH={case['length']}",
        ]
        result = subprocess.run(command, check=False, capture_output=True,
                                text=True, timeout=60)
        print(f"[{name}] {result.stdout.strip()}", flush=True)
        if result.returncode or "PASS: kernel differential comparison" not in result.stdout:
            if result.stderr:
                print(result.stderr, flush=True)
            raise RuntimeError(f"OpenGPU RTL mismatch for {name}: exit={result.returncode}")
    print(f"PASS: {len(manifest)} assembler -> model -> RTL kernel comparisons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
