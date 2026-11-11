#!/usr/bin/env python3
"""Runs the one-file-per-case compiler programs in tests/source.

  source.py run  COMPILER OUTDIR [-j N] [--filter REGEX]   tests/source/run/*.mt
  source.py fail COMPILER OUTDIR [-j N] [--filter REGEX]   tests/source/fail/*.mt

Every case is a standalone program whose leading `// key: value` comment lines
(see directives.py) configure it. The lines stay in the file, so diagnostic
line numbers count them. The case name is the file name without `.mt`.

run cases are built and executed once per profile:
  expect-exit          exit status of the program, or `trap` for an abort (default 0)
  expect-exit-debug    overrides expect-exit under the debug profile
  expect-exit-release  overrides expect-exit under the release profile
  profiles             space-separated subset of `debug release` (default both)
  flags                extra `mettle build` arguments
  arch                 `aarch64` or `x86_64`: skipped on any other host
  truncated            reason: the file deliberately lacks its final newline because the
                       program ends mid-construct (the only way to omit it)

fail cases must be rejected with exit status 1, leave a pre-existing output
file untouched, and report every expected diagnostic:
  expect-error         `PHASE LINE:COL MESSAGE`; one diagnostic must carry all three
  expect-error-count   exact number of diagnostics (optional)
  expect-note/help     expected related diagnostic text (optional)
  profiles, flags, arch as above (default profile: debug)
"""

import argparse
import concurrent.futures
import hashlib
import json
import os
import platform
import re
import resource
import shlex
import signal
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import directives
import processes

ROOT = Path(__file__).resolve().parent / "source"
PROFILES = ("debug", "release")
COMMON_KEYS = {"profiles", "flags", "arch", "truncated"}
KEYS = {"run": COMMON_KEYS | {"expect-exit", "expect-exit-debug", "expect-exit-release"},
        "fail": COMMON_KEYS | {"expect-error", "expect-error-count",
                               "expect-note", "expect-help"}}
ERROR = re.compile(r"(\w+) (\d+):(\d+) (.+)")
PRESERVED = b"preserve existing artifact"


@dataclass
class Case:
    name: str
    path: Path
    kind: str
    profiles: tuple
    flags: list
    arch: object
    exits: dict = field(default_factory=dict)
    errors: list = field(default_factory=list)
    related: list = field(default_factory=list)
    count: object = None
    header_lines: int = 0


def host_arch():
    machine = platform.machine().lower()
    return {"arm64": "aarch64", "amd64": "x86_64"}.get(machine, machine)


def single(options, key, default, name):
    values = options.get(key)
    if values is None:
        return default
    if len(values) != 1:
        raise ValueError(f"{name}: directive `{key}` must appear once")
    return values[0]


def parse_exit(value, name):
    if value == "trap":
        return value
    try:
        return int(value)
    except ValueError:
        raise ValueError(f"{name}: expect-exit must be an integer or `trap`, not {value!r}") from None


def parse_case(path, kind):
    name = path.stem
    options, header_lines = directives.parse(path.read_text())
    unknown = set(options) - KEYS[kind]
    if unknown:
        raise ValueError(f"{name}: unknown {kind} directive(s) {sorted(unknown)}")
    profiles = tuple(single(options, "profiles", "debug release" if kind == "run" else "debug",
                            name).split())
    if not profiles or not set(profiles) <= set(PROFILES):
        raise ValueError(f"{name}: profiles must be a non-empty subset of {PROFILES}")
    if ("truncated" in options) == path.read_bytes().endswith(b"\n"):
        raise ValueError(f"{name}: a `truncated` directive and a missing final newline "
                         "must go together")
    case = Case(name, path, kind, profiles, shlex.split(single(options, "flags", "", name)),
                single(options, "arch", None, name),
                header_lines=header_lines)
    if kind == "run":
        default = parse_exit(single(options, "expect-exit", "0", name), name)
        for profile in PROFILES:
            case.exits[profile] = parse_exit(
                single(options, f"expect-exit-{profile}", str(default), name), name)
    else:
        if "expect-error" not in options:
            raise ValueError(f"{name}: fail case requires an expect-error directive")
        for entry in options["expect-error"]:
            match = ERROR.fullmatch(entry)
            if not match:
                raise ValueError(f"{name}: expect-error must be `PHASE LINE:COL MESSAGE`, "
                                 f"not {entry!r}")
            case.errors.append((match[1], int(match[2]), int(match[3]), match[4]))
        for kind in ("note", "help"):
            for entry in options.get(f"expect-{kind}", []):
                case.related.append((kind, entry))
        if "expect-error-count" in options:
            case.count = int(single(options, "expect-error-count", None, name))
    return case


def load_cases(kind, root=ROOT, arch=None):
    """Parses tests/source/<kind>/*.mt, keeping the cases that apply to `arch` (default: host)."""
    arch = arch or host_arch()
    cases = [parse_case(path, kind) for path in sorted((Path(root) / kind).glob("*.mt"))]
    return [case for case in cases if case.arch in (None, arch)]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class Runner:
    def __init__(self, executable, case):
        self.executable = executable
        self.case = case
        self.commands = []
        self.records = []

    def run(self, arguments, expected=0):
        begin = time.perf_counter()
        result = processes.run(arguments, text=True, capture_output=True)
        self.commands.append({"command": list(map(str, arguments)),
                              "exit_status": result.returncode,
                              "elapsed_seconds": time.perf_counter() - begin,
                              "stdout": result.stdout, "stderr": result.stderr})
        if (expected == "trap" and result.returncode != -signal.SIGABRT) or (
                expected != "trap" and result.returncode != expected):
            raise AssertionError(f"{self.case.name}: {arguments!r}: expected {expected}, got "
                                 f"{result.returncode}\n{result.stdout}{result.stderr}")
        return result

    def execute_run(self, directory):
        case = self.case
        for profile in case.profiles:
            program = directory / f"{case.name}-{profile}"
            self.run([self.executable, "build", case.path, "-o", program,
                      "--profile", profile, *case.flags])
            self.run([program], case.exits[profile])
            self.records.append({"file": str(case.path), "source_sha256": digest(case.path),
                                 "profile": profile, "expected": case.exits[profile],
                                 "program_sha256": digest(program)})

    def execute_fail(self, directory):
        case = self.case
        program = directory / f"{case.name}.out"
        program.write_bytes(PRESERVED)
        for profile in case.profiles:
            result = self.run([self.executable, "build", case.path, "-o", program,
                               "--profile", profile, *case.flags], 1)
            if program.read_bytes() != PRESERVED:
                raise AssertionError(f"{case.name}: failed compilation damaged existing output")
            for phase, line, column, message in case.errors:
                # The phase, message and location must belong to one diagnostic.
                intended = (re.escape(str(case.path)) + f":{line}:{column}: error\\[" +
                            re.escape(phase) + r"\]:[^\n]*" + re.escape(message))
                if not re.search(intended, result.stderr):
                    raise AssertionError(f"{case.name}: expected error[{phase}] containing "
                                         f"{message!r} at {line}:{column}:\n{result.stderr}")
            for kind, message in case.related:
                if f"{kind}: {message}" not in result.stderr:
                    raise AssertionError(f"{case.name}: expected {kind} containing "
                                         f"{message!r}:\n{result.stderr}")
            if case.count is not None and len(re.findall(r": error\[", result.stderr)) != case.count:
                raise AssertionError(f"{case.name}: expected exactly {case.count} "
                                     f"diagnostic(s):\n{result.stderr}")
            self.records.append({"file": str(case.path), "phase": case.errors[0][0],
                                 "profile": profile, "source_sha256": digest(case.path)})


def run_suite(kind, executable, output, jobs, pattern):
    executable = str(Path(executable).resolve())
    directory = Path(output).resolve() / kind
    directory.mkdir(parents=True, exist_ok=True)
    cases = [case for case in load_cases(kind) if not pattern or re.search(pattern, case.name)]
    if not cases:
        raise SystemExit(f"no {kind} cases selected")
    evidence = {"scope": "Source regressions through the initial I06 machine boundary; "
                         "not full language or release qualification",
                "status": "in_progress", "mode": kind, "compiler_sha256": digest(executable),
                "host": platform.platform(), "jobs": jobs, "commands": [], "cases": []}
    begin = time.perf_counter()

    def execute(case):
        runner = Runner(executable, case)
        try:
            getattr(runner, f"execute_{kind}")(directory)
        except Exception as error:  # noqa: BLE001
            return runner, str(error)
        return runner, None

    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        for runner, error in pool.map(execute, cases):
            evidence["commands"] += runner.commands
            evidence["cases"] += runner.records
            if error:
                failures.append(error)
    elapsed = time.perf_counter() - begin
    evidence["status"] = "failed" if failures else "passed"
    evidence["elapsed_seconds"] = elapsed
    evidence["child_peak_rss_high_water"] = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    evidence["rss_units"] = "bytes" if platform.system() == "Darwin" else "KiB"
    evidence["rss_scope"] = "cumulative child high-water mark, not isolated per-command memory"
    (directory / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    if failures:
        print("\n\n".join(failures), file=sys.stderr)
        raise SystemExit(f"{kind}: {len(failures)} of {len(cases)} case(s) failed")
    print(f"{kind}: passed {len(cases)} cases, {len(evidence['cases'])} retained executions, "
          f"{len(evidence['commands'])} commands in {elapsed:.1f}s with {jobs} jobs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("kind", choices=("run", "fail"))
    parser.add_argument("executable")
    parser.add_argument("output")
    parser.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1)
    parser.add_argument("--filter", help="only cases whose name matches this regular expression")
    arguments = parser.parse_args()
    run_suite(arguments.kind, arguments.executable, arguments.output, max(arguments.jobs, 1),
              arguments.filter)
