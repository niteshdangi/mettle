#!/usr/bin/env python3
"""Builds and runs the native `alloc` library programs in tests/alloc.

A program exits 0 on success. `// expect-exit: trap` marks a program that must
terminate with SIGABRT. `// expect-error: PHASE LINE:COL MESSAGE` requires
the phase, location and message to identify the same compiler diagnostic.
Optional trailing profile names select debug/release; both run by default.
Use -j N to select workers and --filter REGEX to select source stems.
"""

import argparse
import re
import signal
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import processes
import directives


def check(executable, source, output, profile="debug"):
    source = source.resolve()
    text = source.read_text()
    header = text.splitlines()[0] if text else ""
    program = output / source.stem
    prefix = "// expect-error: "
    error = directives.parse_error(header[len(prefix):]) if header.startswith(prefix) else None
    build = processes.run([executable, "build", str(source), "-o", str(program),
                           "--profile", profile],
                           text=True, capture_output=True)
    if error:
        if build.returncode != 1 or not directives.matches_error(source, error, build.stderr):
            raise AssertionError(f"{source.name}: expected {error} diagnostic\n{build.stderr}")
        return
    if build.returncode != 0:
        raise AssertionError(f"{source.name}: build failed\n{build.stderr}")
    run = processes.run([str(program)], text=True, capture_output=True)
    if header.startswith("// expect-exit: trap"):
        if run.returncode != -signal.SIGABRT:
            raise AssertionError(
                f"{source.name}: expected SIGABRT, got {run.returncode}\n{run.stderr}")
    elif run.returncode != 0:
        raise AssertionError(f"{source.name}: exited {run.returncode}\n{run.stdout}{run.stderr}")


def main(executable, output, sources, profiles=("debug", "release"), *, jobs=4, pattern=None):
    if jobs < 1:
        raise ValueError("jobs must be positive")
    executable = str(Path(executable).resolve())
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    selected = re.compile(pattern) if pattern is not None else None
    files = [source for source in sorted(Path(sources).glob("*.mt"))
             if selected is None or selected.search(source.stem)]
    if not files:
        raise ValueError("no alloc cases selected")
    profiles = tuple(dict.fromkeys(profiles))
    if not profiles or not set(profiles) <= {"debug", "release"}:
        raise ValueError("profiles must select debug or release")
    cases = []
    for profile in profiles:
        target = output / profile
        target.mkdir(exist_ok=True)
        cases.extend((source, target, profile) for source in files)
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results = [(source, profile, pool.submit(check, executable, source, target, profile))
                   for source, target, profile in cases]
    failures = []
    for source, profile, future in results:
        try:
            future.result()
        except Exception as error:  # noqa: BLE001
            failures.append(f"{source.name} ({profile}): {error}")
    if failures:
        raise AssertionError("\n".join(failures))
    print(f"{Path(sources).name} library programs passed: {len(cases)} source/profile cases")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable")
    parser.add_argument("output")
    parser.add_argument("sources")
    parser.add_argument("profiles", nargs="*", choices=("debug", "release"))
    parser.add_argument("-j", "--jobs", type=int, default=4)
    parser.add_argument("--filter")
    args = parser.parse_args()
    main(args.executable, args.output, args.sources, tuple(args.profiles) or ("debug", "release"),
         jobs=args.jobs, pattern=args.filter)
