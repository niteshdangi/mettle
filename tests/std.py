#!/usr/bin/env python3
"""Builds and runs the hosted `std` library programs in tests/std.

Leading `// directive: value` comment lines configure one program. A program
runs in its own fresh working directory with the compiled binary's absolute
path as argv[0]; `\\n` in a value is a newline.

  expect-exit    exit status (default 0)
  expect-stdout  exact standard output
  expect-stderr  substring of standard error
  args           space-separated arguments
  stdin          standard input
  file           `name=content` created in the working directory first (repeatable)
  expect-file    `name=content` that must exist afterwards (repeatable)
  expect-error   `phase`: the program must be rejected by the compiler there
"""

import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import directives as shared


def directives(text):
    found, _ = shared.parse(text)
    return {key: [value.replace("\\n", "\n") for value in values]
            for key, values in found.items()}


def split_file(entry):
    name, _, content = entry.partition("=")
    return name, content


def check(executable, source, output):
    options = directives(source.read_text())
    program = output / source.stem
    build = subprocess.run([executable, "build", str(source), "-o", str(program)],
                           text=True, capture_output=True, timeout=900)
    if "expect-error" in options:
        phase = options["expect-error"][0]
        if build.returncode != 1 or f"error[{phase}]" not in build.stderr:
            raise AssertionError(f"{source.name}: expected {phase} error\n{build.stderr}")
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
    run = subprocess.run([str(program), *arguments], cwd=work, capture_output=True,
                         input=options.get("stdin", [""])[0].encode(), timeout=120)
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


def main(executable, output, sources):
    executable = str(Path(executable).resolve())
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    files = sorted(Path(sources).glob("*.mt"))
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda f: (f, pool.submit(check, executable, f, output)), files))
    failures = []
    for source, future in results:
        try:
            future.result()
        except Exception as error:  # noqa: BLE001
            failures.append(str(error))
    if failures:
        raise AssertionError("\n".join(failures))
    print(f"std library programs passed: {len(files)}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
