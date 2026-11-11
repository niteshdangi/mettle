#!/usr/bin/env python3
"""Builds and runs the hosted `std` library programs in tests/std.

Leading `// directive: value` comment lines configure one program. A program
runs in its own fresh working directory with the compiled binary's absolute
path as argv[0]; `\\n` in a value is a newline.
Optional trailing profile names select debug/release; both run by default.
Use -j N to select workers and --filter REGEX to select source stems.

  expect-exit    exit status (default 0)
  expect-stdout  exact standard output
  expect-stderr  substring of standard error
  args           space-separated arguments
  stdin          standard input
  file           `name=content` created in the working directory first (repeatable)
  expect-file    `name=content` that must exist afterwards (repeatable)
  expect-error   `PHASE LINE:COL MESSAGE` identifying one compiler diagnostic
"""

import argparse
import re
import shutil
from pathlib import Path

import directives as shared
import processes
import scheduling

SINGLETONS = {"expect-exit", "expect-stdout", "args", "stdin", "expect-error"}
REPEATED = {"expect-stderr", "file", "expect-file"}


def directives(text):
    found, _ = shared.parse(text)
    unknown = set(found) - SINGLETONS - REPEATED
    if unknown:
        raise ValueError(f"unknown std directive(s): {sorted(unknown)}")
    for key in SINGLETONS & found.keys():
        if len(found[key]) != 1:
            raise ValueError(f"directive `{key}` must appear once")
    return {key: [value.replace("\\n", "\n") for value in values]
            for key, values in found.items()}


def split_file(entry):
    name, _, content = entry.partition("=")
    return name, content


def check(executable, source, output, profile="debug"):
    source = source.resolve()
    options = directives(source.read_text())
    error = shared.parse_error(options["expect-error"][0]) if "expect-error" in options else None
    program = output / source.stem
    build = processes.run([executable, "build", str(source), "-o", str(program),
                           "--profile", profile],
                           text=True, capture_output=True)
    if error:
        if build.returncode != 1 or not shared.matches_error(source, error, build.stderr):
            raise AssertionError(f"{source.name}: expected {error} diagnostic\n{build.stderr}")
        return
    if build.returncode != 0:
        raise AssertionError(f"{source.name}: build failed\n{build.stderr}")
    work = output / f"{source.stem}.dir"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    for entry in options.get("file", []):
        name, content = split_file(entry)
        (work / name).write_bytes(content.encode())
    arguments = options.get("args", [""])[0].split()
    run = processes.run([str(program), *arguments], cwd=work, capture_output=True,
                         input=options.get("stdin", [""])[0].encode())
    stdout, stderr = run.stdout.decode(errors="replace"), run.stderr.decode(errors="replace")
    expected = int(options.get("expect-exit", ["0"])[0])
    if run.returncode != expected:
        raise AssertionError(f"{source.name}: exited {run.returncode}, expected {expected}\n{stdout}{stderr}")
    if "expect-stdout" in options and stdout != options["expect-stdout"][0]:
        raise AssertionError(f"{source.name}: stdout {stdout!r} != {options['expect-stdout'][0]!r}")
    for needle in options.get("expect-stderr", []):
        if needle not in stderr:
            raise AssertionError(f"{source.name}: stderr lacks {needle!r}: {stderr!r}")
    for entry in options.get("expect-file", []):
        name, content = split_file(entry)
        path = work / name
        if not path.exists() or path.read_bytes() != content.encode():
            raise AssertionError(f"{source.name}: file {name} differs from {content!r}")


def main(executable, output, sources, profiles=("debug", "release"), *, jobs=4, pattern=None,
         shard_index=0, shard_count=1):
    if jobs < 1:
        raise ValueError("jobs must be positive")
    executable = str(Path(executable).resolve())
    output = Path(output).resolve()
    if shard_count > 1:
        output /= f"shard-{shard_index}"
    output.mkdir(parents=True, exist_ok=True)
    selected = re.compile(pattern) if pattern is not None else None
    files = [source for source in sorted(Path(sources).glob("*.mt"))
             if selected is None or selected.search(source.stem)]
    if not files:
        raise ValueError("no std cases selected")
    profiles = tuple(dict.fromkeys(profiles))
    if not profiles or not set(profiles) <= {"debug", "release"}:
        raise ValueError("profiles must select debug or release")
    cases = []
    for profile in profiles:
        target = output / profile
        target.mkdir(exist_ok=True)
        cases.extend((source, target, profile) for source in files)
    key = lambda item: f"{item[0].stem}:{item[2]}"
    cases = scheduling.select(cases, key, shard_index, shard_count)
    results = scheduling.run(cases, lambda item: check(executable, *item),
                             output, jobs, key)
    failures = []
    for (source, _, profile), _, error, _ in results:
        if error:
            failures.append(f"{source.name} ({profile}): {error}")
    if failures:
        raise AssertionError("\n".join(failures))
    print(f"std library programs passed: {len(cases)} source/profile cases")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable")
    parser.add_argument("output")
    parser.add_argument("sources")
    parser.add_argument("profiles", nargs="*", choices=("debug", "release"))
    scheduling.arguments(parser, 4)
    parser.add_argument("--filter")
    args = parser.parse_args()
    main(args.executable, args.output, args.sources, tuple(args.profiles) or ("debug", "release"),
         jobs=args.jobs, pattern=args.filter,
         shard_index=args.shard_index, shard_count=args.shard_count)
