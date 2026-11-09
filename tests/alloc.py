#!/usr/bin/env python3
"""Builds and runs the native `alloc` library programs in tests/alloc.

A program exits 0 on success. `// expect-exit: trap` marks a program that must
terminate abnormally (a runtime panic) and `// expect-error: <phase>` one that
must be rejected by the compiler in that phase.
"""

import re
import signal
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def check(executable, source, output):
    text = source.read_text()
    header = text.splitlines()[0] if text else ""
    program = output / source.stem
    error = re.match(r"// expect-error: (\w+)", header)
    build = subprocess.run([executable, "build", str(source), "-o", str(program)],
                           text=True, capture_output=True, timeout=600)
    if error:
        if build.returncode != 1 or f"error[{error.group(1)}]" not in build.stderr:
            raise AssertionError(f"{source.name}: expected {error.group(1)} error\n{build.stderr}")
        return
    if build.returncode != 0:
        raise AssertionError(f"{source.name}: build failed\n{build.stderr}")
    run = subprocess.run([str(program)], text=True, capture_output=True, timeout=60)
    if header.startswith("// expect-exit: trap"):
        if run.returncode != -signal.SIGABRT:
            raise AssertionError(
                f"{source.name}: expected SIGABRT, got {run.returncode}\n{run.stderr}")
    elif run.returncode != 0:
        raise AssertionError(f"{source.name}: exited {run.returncode}\n{run.stdout}{run.stderr}")


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
    print(f"{Path(sources).name} library programs passed: {len(files)}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
