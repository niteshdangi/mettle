#!/usr/bin/env python3
"""D17 comparison harness: Mettle versus Rust/Cargo (docs/process/performance.md).

Measures, for paired workloads under benchmarks/ and a synthetic N-modules x
M-functions scaling family: run time, clean build, no-op rebuild, comment-edit
and semantic-edit rebuilds, check-only time, retained build-cache bytes and
binary size. Applies the section 4 decision rule (paired log ratios, Student-t
bounds, Bonferroni alpha = 0.05/K) and writes results.json and results.md.

Standard library only; no network. Without --qualified-runner and at least 30
pairs the output is an engineering signal and never a qualification.
"""

import argparse
import hashlib
import json
import math
import os
import platform
import random
import re
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BENCHMARKS = ROOT / "benchmarks"
FROZEN_RUSTC = "1.99.1"
MARKER = "bench-edit-point"
RESOLUTION = math.log(1.005)
MOD = 1000003
TIME_METRICS = ["runtime", "clean_build", "noop_build", "comment_edit_build",
                "semantic_edit_build", "check"]
BYTE_METRICS = ["retained_bytes_clean", "retained_bytes_after_edits"]
GATE_KIND = {"runtime": "runtime"}


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def tail(text, lines=15):
    return "\n".join(text.strip().splitlines()[-lines:])


class Failure(Exception):
    pass


class Runner:
    """Runs commands, recording wall time and child peak RSS (wait4)."""

    def __init__(self, logs):
        self.logs = Path(logs)
        self.logs.mkdir(parents=True, exist_ok=True)
        self.count = 0

    def run(self, command, cwd=None, env=None):
        self.count += 1
        out = self.logs / f"{self.count:05d}.out"
        err = self.logs / f"{self.count:05d}.err"
        command = [str(part) for part in command]
        with open(out, "wb") as stdout, open(err, "wb") as stderr:
            start = time.perf_counter()
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout,
                                       stderr=stderr, stdin=subprocess.DEVNULL)
            _, status, usage = os.wait4(process.pid, 0)
            elapsed = time.perf_counter() - start
        process.returncode = os.waitstatus_to_exitcode(status)
        scale = 1 if sys.platform == "darwin" else 1024
        return {"command": command, "seconds": elapsed, "returncode": process.returncode,
                "peak_rss_bytes": usage.ru_maxrss * scale,
                "stdout": out.read_bytes(), "stderr": err.read_text(errors="replace")}

    def must(self, command, **options):
        result = self.run(command, **options)
        if result["returncode"] != 0:
            raise Failure(f"{' '.join(result['command'])}: exit {result['returncode']}\n"
                          f"{tail(result['stderr'])}")
        return result

    def program(self, executable):
        result = self.run([executable])
        if not 0 <= result["returncode"] < 128:
            raise Failure(f"{executable}: expected a 7-bit checksum, "
                          f"got exit {result['returncode']}\n{tail(result['stderr'])}")
        return result


def allocated_bytes(path):
    """Allocated bytes (st_blocks) of a tree, each inode counted once."""
    path = Path(path)
    if not path.exists():
        return 0
    seen, total = set(), 0
    stack = [path]
    while stack:
        current = stack.pop()
        info = current.lstat()
        key = (info.st_dev, info.st_ino)
        if key not in seen:
            seen.add(key)
            total += info.st_blocks * 512
        if current.is_dir() and not current.is_symlink():
            stack.extend(current.iterdir())
    return total


# ---------------------------------------------------------------- statistics

def _betacf(a, b, x):
    tiny = 1e-300
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    d = 1.0 / (d if abs(d) > tiny else tiny)
    h = d
    for m in range(1, 300):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < 1e-15:
            break
    return h


def _betai(a, b, x):
    if x <= 0.0 or x >= 1.0:
        return min(max(x, 0.0), 1.0)
    front = math.exp(math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) +
                     a * math.log(x) + b * math.log(1.0 - x))
    if x < (a + 1.0) / (a + b + 2.0):
        return front * _betacf(a, b, x) / a
    return 1.0 - front * _betacf(b, a, 1.0 - x) / b


def t_cdf(t, df):
    tail_mass = 0.5 * _betai(df / 2.0, 0.5, df / (df + t * t))
    return 1.0 - tail_mass if t > 0 else tail_mass


def t_quantile(probability, df):
    low, high = 0.0, 1.0
    while t_cdf(high, df) < probability and high < 1e12:
        high *= 2.0
    for _ in range(200):
        middle = (low + high) / 2.0
        if t_cdf(middle, df) < probability:
            low = middle
        else:
            high = middle
    return (low + high) / 2.0


def decide(mettle, rust, endpoints, kind):
    """Section 4 rule on paired block metrics; ratio above one is worse."""
    pairs = list(zip(mettle, rust))
    if len(pairs) < 2 or any(m <= 0 or r <= 0 for m, r in pairs):
        return {"verdict": "inconclusive", "gate": "inconclusive",
                "reason": "fewer than two valid pairs"}
    logs = [math.log(m / r) for m, r in pairs]
    mean, spread = statistics.fmean(logs), statistics.stdev(logs)
    alpha = 0.05 / endpoints
    half = t_quantile(1.0 - alpha / 2.0, len(logs) - 1) * spread / math.sqrt(len(logs))
    lower, upper = math.exp(mean - half), math.exp(mean + half)
    if half > RESOLUTION:
        verdict = "inconclusive"
    elif lower > 1.0:
        verdict = "slowdown"
    elif upper < 1.0:
        verdict = "win"
    else:
        verdict = "tie"
    if verdict == "inconclusive":
        gate = "inconclusive"
    elif kind == "runtime":
        gate = "pass" if verdict in ("win", "tie") else "fail"
    else:
        gate = "pass" if verdict == "win" else "fail"
    return {"verdict": verdict, "gate": gate, "ratio": math.exp(mean), "lower": lower,
            "upper": upper, "pairs": len(logs), "alpha": alpha,
            "half_width_log": half}


def decide_bytes(mettle, rust):
    if not mettle or not rust or min(rust) <= 0:
        return {"verdict": "inconclusive", "gate": "inconclusive", "reason": "no bytes"}
    ratio = statistics.median(mettle) / statistics.median(rust)
    stable = (max(mettle) - min(mettle)) <= 0.01 * max(mettle) and \
             (max(rust) - min(rust)) <= 0.01 * max(rust)
    verdict = "win" if ratio < 1 else "slowdown"
    gate = ("pass" if ratio < 1 else "fail") if stable else "inconclusive"
    return {"verdict": verdict, "gate": gate, "ratio": ratio, "stable_within_1_percent": stable,
            "mettle_bytes": mettle, "rust_bytes": rust}


# ----------------------------------------------------------------- workloads

CARGO_TOML = """[package]
name = "scale_gen"
version = "0.1.0"
edition = "2024"

[workspace]

[profile.release]
opt-level = 3
debug = false
lto = false
codegen-units = 16
panic = "abort"
overflow-checks = false
incremental = false
"""

METTLE_MANIFEST = """name: "scale-gen"
version: "0.1.0"
"""


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def module_plain(index, functions):
    """Returns (mettle, rust) module sources: a call chain of M functions."""
    seed_m = seed_r = ""
    first_m = first_r = f"{index}"
    if index == 0:
        seed_m = f"fn seed(): i32 {{ 12345 }} // {MARKER}\n"
        seed_r = f"fn seed() -> i32 {{ 12345 }} // {MARKER}\n"
        first_m = first_r = "seed()"
    mettle, rust = [seed_m], [seed_r]
    for j in range(functions):
        inner_m = f"(x * 3 + {first_m}) % {MOD}" if j == 0 else \
            f"(f{j - 1}(x) * 3 + {j}) % {MOD}"
        mettle.append(f"fn f{j}(x: i32): i32 {{ {inner_m} }}\n")
        rust.append(f"fn f{j}(x: i32) -> i32 {{ {inner_m} }}\n")
    mettle.append(f"pub fn run(x: i32): i32 {{ f{functions - 1}(x) }}\n")
    rust.append(f"pub fn run(x: i32) -> i32 {{ f{functions - 1}(x) }}\n")
    return "".join(mettle), "".join(rust)


def module_generic(index, functions):
    """Each function slot is a distinct type monomorphized through one generic."""
    start = "x + seed()" if index == 0 else "x"
    mettle = []
    rust = []
    if index == 0:
        mettle.append(f"fn seed(): i32 {{ 12345 }} // {MARKER}\n")
        rust.append(f"fn seed() -> i32 {{ 12345 }} // {MARKER}\n")
    mettle.append("interface Step { fn apply(value: i32): i32; }\n"
                  "fn drive<S: Step>(read step: S, value: i32): i32 "
                  "{ step.apply(step.apply(value)) }\n")
    rust.append("trait Step { fn apply(&self, value: i32) -> i32; }\n"
                "fn drive<S: Step>(step: &S, value: i32) -> i32 "
                "{ step.apply(step.apply(value)) }\n")
    for j in range(functions):
        body = f"(value * self.k + {j}) % {MOD}"
        mettle.append(f"type S{j} {{ k: i32 }}\n"
                      f"extend S{j} implements Step {{ fn apply(value: i32): i32 {{ {body} }} }}\n")
        rust.append(f"struct S{j} {{ k: i32 }}\n"
                    f"impl Step for S{j} {{ fn apply(&self, value: i32) -> i32 {{ {body} }} }}\n")
    mettle.append(f"pub fn run(x: i32): i32 {{\n    var v = {start}\n")
    rust.append(f"pub fn run(x: i32) -> i32 {{\n    let mut v = {start};\n")
    for j in range(functions):
        mettle.append(f"    v = drive(S{j}(k: {j % 7 + 2}), v)\n")
        rust.append(f"    v = drive(&S{j} {{ k: {j % 7 + 2} }}, v);\n")
    mettle.append("    v\n}\n")
    rust.append("    v\n}\n")
    return "".join(mettle), "".join(rust)


def generate_scale(destination, modules, functions, generic):
    """N modules x M functions for both languages; returns the two trees."""
    mettle_tree, rust_tree = destination / "mettle", destination / "rust"
    write(mettle_tree / "package.mettle", METTLE_MANIFEST)
    write(rust_tree / "Cargo.toml", CARGO_TOML)
    main_m = [f"module m{i};\n" for i in range(modules)]
    main_r = [f"mod m{i};\n" for i in range(modules)]
    main_m.append("\nfn main(): i32 {\n    var acc = 1\n")
    main_r.append("\nfn main() {\n    let mut acc = 1;\n")
    for i in range(modules):
        make = module_generic if generic else module_plain
        text_m, text_r = make(i, functions)
        write(mettle_tree / "src" / f"m{i}.mt", text_m)
        write(rust_tree / "src" / f"m{i}.rs", text_r)
        main_m.append(f"    acc = (acc + m{i}.run(acc)) % {MOD}\n")
        main_r.append(f"    acc = (acc + m{i}::run(acc)) % {MOD};\n")
    main_m.append("    acc % 128\n}\n")
    main_r.append("    std::process::exit(acc % 128);\n}\n")
    write(mettle_tree / "src" / "main.mt", "".join(main_m))
    write(rust_tree / "src" / "main.rs", "".join(main_r))
    return mettle_tree, rust_tree


def single_workload(name, work):
    source = BENCHMARKS / name
    mettle_tree, rust_tree = work / "mettle", work / "rust"
    shutil.copytree(source, mettle_tree, ignore=shutil.ignore_patterns("rust"))
    shutil.copytree(source / "rust", rust_tree)
    return mettle_tree, rust_tree, mettle_tree / "main.mt"


def cargo_name(rust_tree):
    match = re.search(r'^name\s*=\s*"([^"]+)"', (rust_tree / "Cargo.toml").read_text(), re.M)
    return match[1]


def marker_file(tree):
    for path in sorted(tree.rglob("*")):
        if path.suffix in (".mt", ".rs") and "target" not in path.parts and \
                MARKER in path.read_text():
            return path
    raise Failure(f"no '{MARKER}' line under {tree}")


def comment_edit(tree):
    path = marker_file(tree)
    path.write_text(path.read_text() + "\n// harness comment-only edit\n")


def semantic_edit(tree):
    path = marker_file(tree)
    lines = path.read_text().splitlines(keepends=True)
    for number, line in enumerate(lines):
        if MARKER in line:
            lines[number], count = re.subn(r"(\{\s*)(\d+)", lambda m: m[1] + str(int(m[2]) + 1),
                                           line, count=1)
            if count != 1:
                raise Failure(f"edit point has no integer literal: {line!r}")
            break
    path.write_text("".join(lines))


# -------------------------------------------------------------- measurement

def clean_environment(cargo_home, target):
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("CARGO", "RUSTFLAGS", "RUSTC", "METTLE"))}
    env.update({"CARGO_HOME": str(cargo_home), "CARGO_TARGET_DIR": str(target),
                "CARGO_NET_OFFLINE": "true", "CARGO_INCREMENTAL": "0"})
    return env


class Side:
    """One language's build state for one repetition."""

    def __init__(self, language, runner, compiler, tree, entry, directory, cargo_home):
        self.language, self.runner, self.compiler = language, runner, compiler
        self.tree, self.entry, self.directory = tree, entry, directory
        self.cargo_home = cargo_home
        self.cache = directory / "cache"
        self.target = directory / "target"
        self.check_target = directory / "check-target"
        self.executable = directory / "out" / "program"
        self.executable.parent.mkdir(parents=True, exist_ok=True)

    def build_command(self):
        if self.language == "mettle":
            return [self.compiler, "build", self.entry, "-o", self.executable, "--profile",
                    "release", "--overflow-checks", "off", "--cache-dir", self.cache]
        return ["cargo", "build", "--release", "--offline", "--quiet", "--manifest-path",
                self.tree / "Cargo.toml"]

    def build(self):
        env = None
        if self.language == "rust":
            env = clean_environment(self.cargo_home, self.target)
        result = self.runner.must(self.build_command(), env=env)
        if self.language == "rust":
            built = self.target / "release" / cargo_name(self.tree)
            shutil.copy2(built, self.executable)
        return result

    def check(self):
        if self.language == "mettle":
            return self.runner.must([self.compiler, "check", self.entry])
        env = clean_environment(self.cargo_home, self.check_target)
        return self.runner.must(["cargo", "check", "--release", "--offline", "--quiet",
                                 "--manifest-path", self.tree / "Cargo.toml"], env=env)

    def retained(self):
        if self.language == "mettle":
            local = sum(allocated_bytes(path) for path in self.tree.rglob("mettle")
                        if path.parent.name == "target")
            return {"cache": allocated_bytes(self.cache), "package_local": local,
                    "executable": allocated_bytes(self.executable),
                    "total": allocated_bytes(self.cache) + local +
                    allocated_bytes(self.executable)}
        total = allocated_bytes(self.target)
        return {"target": total, "total": total}

    def sample(self, first):
        """Clean, no-op, comment edit, semantic edit and check on this side."""
        row = {}
        clean = self.build()
        row["clean_build"] = clean["seconds"]
        row["compiler_peak_rss_bytes"] = clean["peak_rss_bytes"]
        row["binary_bytes"] = self.executable.stat().st_size
        row["retained_clean"] = self.retained()
        kept = None
        if first:
            kept = self.directory.parent.parent / "programs" / self.language
            kept.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.executable, kept)
        row["noop_build"] = self.build()["seconds"]
        time.sleep(0.05)
        comment_edit(self.tree)
        row["comment_edit_build"] = self.build()["seconds"]
        time.sleep(0.05)
        semantic_edit(self.tree)
        row["semantic_edit_build"] = self.build()["seconds"]
        row["retained_after_edits"] = self.retained()
        if first:
            edited = self.runner.program(self.executable)
            row["edited_output"] = [edited["returncode"], edited["stdout"].decode("latin-1")]
        row["check"] = self.check()["seconds"]
        return row, kept


def median(values):
    return statistics.median(values)


def measure_runtime(runner, programs, warmup, blocks, runs, rng):
    for program in programs.values():
        for _ in range(warmup):
            runner.program(program)
    samples = {"mettle": [], "rust": []}
    rss = {"mettle": [], "rust": []}
    outputs = {}
    for _ in range(blocks):
        order = ["mettle", "rust"]
        rng.shuffle(order)
        for side in order:
            times = []
            for _ in range(runs):
                result = runner.program(programs[side])
                outputs.setdefault(side, (result["returncode"], result["stdout"]))
                if (result["returncode"], result["stdout"]) != outputs[side]:
                    raise Failure(f"{side} program output is not deterministic")
                times.append(result["seconds"])
                rss[side].append(result["peak_rss_bytes"])
            samples[side].append(median(times))
    return samples, outputs, {side: median(values) for side, values in rss.items()}


def run_workload(label, prepare, args, runner, compiler, endpoints, rng, base):
    entry = {"name": label, "status": "ok"}
    work = base / label
    shutil.rmtree(work, ignore_errors=True)
    cargo_home = base / "cargo-home"
    cargo_home.mkdir(parents=True, exist_ok=True)
    rows = {"mettle": [], "rust": []}
    programs = {}
    try:
        for repetition in range(args.pairs):
            first = repetition == 0
            sides = {}
            sources = work / f"src{repetition}"
            mettle_tree, rust_tree, mettle_entry = prepare(sources)
            for language in ("mettle", "rust"):
                directory = work / f"rep{repetition}" / language
                tree = mettle_tree if language == "mettle" else rust_tree
                sides[language] = Side(language, runner, compiler, tree,
                                       mettle_entry, directory, cargo_home)
            order = ["mettle", "rust"]
            rng.shuffle(order)
            for language in order:
                try:
                    row, kept = sides[language].sample(first)
                except Failure as error:
                    if language == "mettle":
                        entry["status"] = "mettle_build_failed"
                    else:
                        entry["status"] = "rust_build_failed"
                    entry["error"] = str(error)
                    return entry
                row["order"] = order
                rows[language].append(row)
                if kept:
                    programs[language] = kept
            if not args.keep_work:
                shutil.rmtree(work / f"rep{repetition}", ignore_errors=True)
                shutil.rmtree(work / f"src{repetition}", ignore_errors=True)
        runtime, outputs, rss = measure_runtime(runner, programs, args.warmup,
                                                args.pairs, args.runs, rng)
        entry["output"] = {side: {"exit_status": value[0], "stdout_sha256":
                                  hashlib.sha256(value[1]).hexdigest()}
                           for side, value in outputs.items()}
        edited = {side: rows[side][0]["edited_output"] for side in rows}
        entry["outputs_match"] = outputs["mettle"] == outputs["rust"]
        entry["edited_outputs_match"] = edited["mettle"] == edited["rust"]
        entry["checksum"] = outputs["rust"][0]
        entry["program_peak_rss_bytes"] = rss
        entry["binary_bytes"] = {side: rows[side][0]["binary_bytes"] for side in rows}
        entry["compiler_peak_rss_bytes"] = {
            side: median([row["compiler_peak_rss_bytes"] for row in rows[side]])
            for side in rows}
        entry["samples"] = {"runtime": runtime}
        for metric in TIME_METRICS[1:]:
            entry["samples"][metric] = {side: [row[metric] for row in rows[side]]
                                        for side in rows}
        entry["bytes"] = {
            "retained_bytes_clean": {side: [row["retained_clean"]["total"]
                                            for row in rows[side]] for side in rows},
            "retained_bytes_after_edits": {side: [row["retained_after_edits"]["total"]
                                                  for row in rows[side]] for side in rows},
            "components_first_pair": {side: {"clean": rows[side][0]["retained_clean"],
                                             "after_edits": rows[side][0]["retained_after_edits"]}
                                      for side in rows}}
        if not (entry["outputs_match"] and entry["edited_outputs_match"]):
            entry["status"] = "output_mismatch"
            return entry
        entry["decisions"] = {}
        for metric in TIME_METRICS:
            samples = entry["samples"][metric]
            entry["decisions"][metric] = decide(
                samples["mettle"], samples["rust"], endpoints,
                GATE_KIND.get(metric, "compile"))
        for metric in BYTE_METRICS:
            samples = entry["bytes"][metric]
            entry["decisions"][metric] = decide_bytes(samples["mettle"], samples["rust"])
    finally:
        if not args.keep_work:
            shutil.rmtree(work, ignore_errors=True)
    return entry


# -------------------------------------------------------------------- report

def cell(decision):
    if "ratio" not in decision:
        return decision["gate"]
    text = f"{decision['ratio']:.3f}"
    if "lower" in decision:
        text += f" [{decision['lower']:.3f}, {decision['upper']:.3f}]"
    return f"{text} {decision['verdict']} ({decision['gate']})"


def markdown(evidence):
    lines = ["# D17 comparison results", "",
             f"Status: **{evidence['qualification']}**", "",
             "Ratios are Mettle / Rust (above one is worse); brackets are Bonferroni "
             f"Student-t bounds (K = {evidence['endpoints']}). Time endpoints use paired "
             "log ratios; byte endpoints compare medians directly.", ""]
    lines += ["## Environment", ""]
    for key in ("host", "mettle_version", "rustc", "cargo", "pairs", "runs", "warmup"):
        lines.append(f"- {key}: {evidence.get(key)}")
    lines += ["", "## Ratios", "",
              "| Workload | " + " | ".join(TIME_METRICS + BYTE_METRICS) + " |",
              "| --- | " + " | ".join(["---"] * (len(TIME_METRICS) + len(BYTE_METRICS))) + " |"]
    for workload in evidence["workloads"]:
        if "decisions" not in workload:
            lines.append(f"| {workload['name']} | {workload['status']}: "
                         f"{workload.get('error', '').splitlines()[0] if workload.get('error') else ''}"
                         " |" + " |" * (len(TIME_METRICS) + len(BYTE_METRICS) - 1))
            continue
        cells = [cell(workload["decisions"][m]) for m in TIME_METRICS + BYTE_METRICS]
        lines.append(f"| {workload['name']} | " + " | ".join(cells) + " |")
    lines += ["", "## Output equivalence and sizes", "",
              "| Workload | checksum (exit status) | outputs match | Mettle binary B | "
              "Rust binary B | Mettle compiler RSS B | Cargo RSS B |",
              "| --- | --- | --- | --- | --- | --- | --- |"]
    for workload in evidence["workloads"]:
        if "binary_bytes" not in workload:
            continue
        rss = workload["compiler_peak_rss_bytes"]
        lines.append(f"| {workload['name']} | {workload['checksum']} | "
                     f"{workload['outputs_match'] and workload['edited_outputs_match']} | "
                     f"{workload['binary_bytes']['mettle']} | {workload['binary_bytes']['rust']} | "
                     f"{int(rss['mettle'])} | {int(rss['rust'])} |")
    lines += ["", "## Gate summary", "", f"- passed: {evidence['gate_counts']['pass']}",
              f"- failed: {evidence['gate_counts']['fail']}",
              f"- inconclusive or not measured: {evidence['gate_counts']['other']}", "",
              "Caveats:", ""]
    lines += [f"- {text}" for text in evidence["caveats"]]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", type=Path, required=True, help="path to the mettle binary")
    parser.add_argument("--output", type=Path, default=ROOT / "build/bench-compare")
    parser.add_argument("--workloads", default="all",
                        help="comma-separated benchmarks/ names or 'all'")
    parser.add_argument("--scale-modules", default="4,8,16,32",
                        help="module counts for the scaling family ('' disables)")
    parser.add_argument("--scale-functions", type=int, default=50)
    parser.add_argument("--scale-generic", action="store_true",
                        help="also run the generic/monomorphization scaling family")
    parser.add_argument("--pairs", type=int, default=5,
                        help="independent paired repetitions (release needs >= 30)")
    parser.add_argument("--runs", type=int, default=5, help="executions per runtime block")
    parser.add_argument("--warmup", type=int, default=2)
    parser.add_argument("--seed", type=int, default=20261030)
    parser.add_argument("--qualified-runner", action="store_true",
                        help="operator asserts the host is a qualified runner")
    parser.add_argument("--keep-work", action="store_true")
    parser.add_argument("--fail-on-gate", action="store_true",
                        help="exit 1 unless every gate passes")
    args = parser.parse_args()
    if args.pairs < 2:
        parser.error("--pairs must be at least 2")
    compiler = args.compiler.resolve()
    base = args.output.resolve()
    base.mkdir(parents=True, exist_ok=True)
    runner = Runner(base / "logs")
    rng = random.Random(args.seed)

    names = sorted(p.name for p in BENCHMARKS.iterdir() if (p / "main.mt").exists())
    if args.workloads != "all":
        selected = args.workloads.split(",")
        unknown = [name for name in selected if name not in names]
        if unknown:
            parser.error(f"unknown workloads: {unknown}")
        names = selected
    jobs = []
    for name in names:
        jobs.append((name, lambda work, name=name: single_workload(name, work)))
    sizes = [int(part) for part in args.scale_modules.split(",") if part]
    families = [("plain", False)] + ([("generic", True)] if args.scale_generic else [])
    for family, generic in families:
        for modules in sizes:
            label = f"scale-{family}-{modules}x{args.scale_functions}"

            def prepare(work, modules=modules, generic=generic):
                mettle_tree, rust_tree = generate_scale(work, modules, args.scale_functions,
                                                        generic)
                return mettle_tree, rust_tree, mettle_tree
            jobs.append((label, prepare))
    endpoints = max(1, len(jobs) * len(TIME_METRICS))

    evidence = {"status": "in_progress", "seed": args.seed, "pairs": args.pairs,
                "runs": args.runs, "warmup": args.warmup, "endpoints": endpoints,
                "host": platform.platform(), "machine": platform.machine(),
                "compiler_sha256": sha256(compiler), "workloads": []}
    try:
        evidence["mettle_version"] = runner.must([compiler, "--version"])["stdout"].decode().strip()
        evidence["rustc"] = runner.must(["rustc", "-vV"])["stdout"].decode().strip()
        evidence["cargo"] = runner.must(["cargo", "-V"])["stdout"].decode().strip()
        for label, prepare in jobs:
            print(f"== {label}", flush=True)
            evidence["workloads"].append(
                run_workload(label, prepare, args, runner, compiler, endpoints, rng, base))
            print(f"   {evidence['workloads'][-1]['status']}", flush=True)
        evidence["status"] = "measured"
    except Exception as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
        raise
    finally:
        counts = {"pass": 0, "fail": 0, "other": 0}
        for workload in evidence["workloads"]:
            decisions = workload.get("decisions")
            if not decisions:
                counts["other"] += len(TIME_METRICS) + len(BYTE_METRICS)
                continue
            for decision in decisions.values():
                counts[decision["gate"] if decision["gate"] in ("pass", "fail") else "other"] += 1
        evidence["gate_counts"] = counts
        qualified = (args.qualified_runner and args.pairs >= 30 and
                     frozen_rustc(evidence))
        evidence["qualification"] = ("qualified-runner measurement (still subject to the "
                                     "registered plan)" if qualified else
                                     "engineering signal only, not a D17 gate verdict")
        evidence["caveats"] = [
            "Exit status carries the checksum (7 bits); outputs are compared byte-for-byte "
            "with the exit status.",
            "Each repetition runs the Mettle and Rust build sequences back to back in "
            "randomized order (pair-level interleaving), not per command.",
            "Mettle caching is whole-program content addressed; its edit rebuilds are cache "
            "hits or full rebuilds, not partial recompilation.",
            "Mettle retained bytes = cache directory + package-local target/mettle + the "
            "output executable; Cargo retained bytes = the whole target directory.",
            "Mettle's hash map and Rust's default SipHash HashMap use different hashers; "
            "checksums are order independent.",
            "Rust toolchain matches the frozen pin." if frozen_rustc(evidence) else
            "Rust toolchain differs from (or is unknown versus) the frozen 1.99.1 pin; "
            "qualification is forbidden.",
        ]
        (base / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
        if evidence["status"] == "measured":
            (base / "results.md").write_text(markdown(evidence))
    print(f"wrote results under {base}")
    if args.fail_on_gate and (counts["fail"] or counts["other"]):
        sys.exit(1)


def frozen_rustc(evidence):
    return f"release: {FROZEN_RUSTC}" in evidence.get("rustc", "")


if __name__ == "__main__":
    main()
