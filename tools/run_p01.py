#!/usr/bin/env python3
"""Retain an early P01 integer-reduction comparison, not release qualification."""

import argparse
import hashlib
import json
import platform
import random
import re
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
METTLE = """fn reduce(limit: i32): i32 {
    var state = 1
    var index = 0
    while index < limit {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        index += 1
    }
    state & 127
}
fn main(): i32 { reduce(SIZE) }
"""
RUST = """#![no_main]
fn reduce(limit: i32) -> i32 {
    let mut state: i32 = 1;
    let mut index = 0;
    while index < limit {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        index += 1;
    }
    state & 127
}
#[unsafe(no_mangle)]
pub extern "C" fn main() -> i32 { reduce(SIZE) }
"""


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def expected(size):
    def signed(value):
        value &= 0xffffffff
        return value if value < 0x80000000 else value - 0x100000000
    state = 1
    for _ in range(size):
        state = signed(state ^ signed(state << 13))
        state = signed(state ^ (state >> 17))
        state = signed(state ^ signed(state << 5))
    return state & 127


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "build/p01")
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    evidence = {
        "scope": "I02 P01 engineering signal, not the registered pilot or release experiment",
        "status": "in_progress", "host": platform.platform(), "machine": platform.machine(),
        "compiler_sha256": digest(compiler), "seed": 20261028, "sizes": [10000, 100000, 1000000],
        "warmups_per_program": 1, "pairs_per_size": 6, "commands": [], "cases": [],
        "metric": "whole-process elapsed seconds; includes process startup",
        "release_gate": "not_evaluated",
        "limitations": ["One uncontrolled shared-host session, not two pilot sessions",
                       "Installed Rust comparator may differ from frozen 1.99.1",
                       "No release confidence/precision claim or native Linux timing"],
    }
    generator = random.Random(evidence["seed"])

    def run(command, code=0):
        start = time.perf_counter()
        result = subprocess.run(list(map(str, command)), text=True, capture_output=True)
        elapsed = time.perf_counter() - start
        evidence["commands"].append({"command": list(map(str, command)), "seconds": elapsed,
                                    "exit_status": result.returncode, "stdout": result.stdout,
                                    "stderr": result.stderr})
        if result.returncode != code:
            raise RuntimeError(f"{command}: expected {code}, got {result.returncode}\n{result.stderr}")
        return result.stdout.strip(), elapsed

    def build(command, metrics):
        flags = ["-l"] if platform.system() == "Darwin" else ["-v"]
        _, seconds = run(["/usr/bin/time", *flags, "-o", metrics, *command])
        report = metrics.read_text()
        pattern = (r"(\d+)\s+maximum resident set size" if platform.system() == "Darwin"
                   else r"Maximum resident set size \(kbytes\):\s*(\d+)")
        match = re.search(pattern, report)
        if not match:
            raise RuntimeError("Missing compiler process memory measurement")
        return {"elapsed_seconds": seconds, "peak_rss_bytes": int(match[1]) *
                (1 if platform.system() == "Darwin" else 1024),
                "memory_scope": "compiler process maximum RSS, not aggregate process-tree memory",
                "raw_measurement": report}

    try:
        evidence["mettle_version"] = run([compiler, "--version"])[0]
        evidence["rust_version"] = run(["rustc", "-vV"])[0]
        evidence["frozen_rust_version_matched"] = "rustc 1.99.1 " in evidence["rust_version"]
        for size in evidence["sizes"]:
            directory = args.output / str(size)
            directory.mkdir(exist_ok=True)
            mettle_source, rust_source = directory / "reduce.mt", directory / "reduce.rs"
            mettle_source.write_text(METTLE.replace("SIZE", str(size)))
            rust_source.write_text(RUST.replace("SIZE", str(size)))
            mettle_program, rust_program = directory / "mettle", directory / "rust"
            compilation = {
                "mettle": build([compiler, "build", mettle_source, "-o", mettle_program,
                                 "--profile", "release"], directory / "mettle-time.txt"),
                "rust": build(["rustc", rust_source, "--edition=2024", "-O",
                               "-C", "overflow-checks=off", "-C", "panic=abort",
                               "-C", "target-cpu=generic", "-o", rust_program],
                              directory / "rust-time.txt")}
            result = expected(size)
            programs = {"mettle": mettle_program, "rust": rust_program}
            for program in programs.values():
                run([program], result)
            pairs = []
            for _ in range(evidence["pairs_per_size"]):
                order = ["mettle", "rust"]
                generator.shuffle(order)
                sample = {"order": order}
                for name in order:
                    sample[name] = run([programs[name]], result)[1]
                sample["ratio"] = sample["mettle"] / sample["rust"]
                pairs.append(sample)
            evidence["cases"].append({
                "size": size, "expected_exit": result, "compilation": compilation, "pairs": pairs,
                "source_sha256": {"mettle": digest(mettle_source), "rust": digest(rust_source)},
                "program_sha256": {name: digest(path) for name, path in programs.items()}})
        evidence["status"] = "passed_engineering_measurements"
    except Exception as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
        raise
    finally:
        (args.output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("P01 engineering measurements retained; no runtime parity verdict.")


if __name__ == "__main__":
    main()
