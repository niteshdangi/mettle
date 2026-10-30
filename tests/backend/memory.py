#!/usr/bin/env python3
"""Check emitted atomic code with TSan and independent C++ thread litmus cases."""

import argparse
import hashlib
import importlib.util
import itertools
import json
import os
import platform
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STARTUP = "int main() { return 0; }\n"
RACE = """
#include <thread>
volatile int value = 0;
void race() { for (int i=0;i<10000;++i) value = value + 1; }
int main() {
    std::thread first(race), second(race);
    first.join();
    second.join();
}
"""


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def sequential_model():
    outcomes = set()
    for order in itertools.permutations(("store-x", "read-y", "store-y", "read-x")):
        if order.index("store-x") > order.index("read-y") or \
                order.index("store-y") > order.index("read-x"):
            continue
        x = y = first = second = 0
        for event in order:
            if event == "store-x":
                x = 1
            elif event == "store-y":
                y = 1
            elif event == "read-y":
                first = y
            else:
                second = x
        outcomes.add((first, second))
    if (0, 0) in outcomes:
        raise AssertionError("Sequential-consistency model admitted a forbidden outcome")
    return sorted(outcomes)


def instrument(text):
    count = 0
    result = []
    for line in text.splitlines():
        if line.startswith("define ") and line.endswith(" {"):
            head = line[:-2]
            if " personality " in head:
                head = head.replace(" personality ", " sanitize_thread personality ", 1)
            else:
                head += " sanitize_thread"
            line = head + " {"
            count += 1
        result.append(line)
    if not count:
        raise AssertionError("No emitted function definitions were instrumented")
    return "\n".join(result) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    parser.add_argument("cxx", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--sysroot")
    parser.add_argument("--link-arg", action="append", default=[])
    parser.add_argument("--sanitizers", action="store_true")
    args = parser.parse_args()
    directory = args.directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ,
                       TSAN_OPTIONS="halt_on_error=1:abort_on_error=0:exitcode=99")
    evidence = {"status": "in_progress", "host": platform.platform(),
                "scope": "Emitted atomic instrumentation and selected thread litmus cases; "
                         "not a complete language memory-model proof",
                "instrumentation": "Test-only sanitize_thread function attributes; "
                                   "pinned Clang TSan at -O1 for both source emission profiles",
                "compiler_sha256": digest(args.compiler),
                "cxx_sha256": digest(args.cxx), "commands": [], "cases": [],
                "source_inputs": {name: digest(ROOT / name) for name in
                                  ("runtime/panic.cpp", "runtime/panic.h",
                                   "runtime/thread.cpp", "runtime/thread.h",
                                   "tests/backend/memory.py",
                                   "tests/backend/machine.py",
                                   "tests/backend/machine_callbacks.c",
                                   "tests/backend/machine_unwind.cpp")}}
    flags = ["-O1", "-g", "-fsanitize=thread", "-fno-omit-frame-pointer"]
    if args.sysroot:
        flags.append("--sysroot=" + args.sysroot)

    def run(command, expected=0, timeout=60):
        command = list(map(str, command))
        result = subprocess.run(command, env=environment, text=True,
                                capture_output=True, timeout=timeout)
        evidence["commands"].append({"command": command, "exit_status": result.returncode,
                                     "stdout": result.stdout, "stderr": result.stderr})
        if result.returncode != expected:
            raise AssertionError(f"{command!r}: expected {expected}, got {result.returncode}\n"
                                 f"{result.stdout}{result.stderr}")
        return result

    try:
        version = run([args.cxx, "--version"]).stdout
        pinned = json.loads((ROOT / "docs/toolchain-pins.json").read_text())["sources"][0]["tag"]
        if "clang version " + pinned.removeprefix("llvmorg-") not in version:
            raise AssertionError("Memory-model checker must use the pinned Clang")
        runtime = Path(run([args.cxx, "--print-runtime-dir"]).stdout.strip())
        evidence["tsan_runtime"] = {str(path): digest(path)
                                    for path in sorted(runtime.glob("*tsan*"))
                                    if path.is_file()}
        if not evidence["tsan_runtime"]:
            raise AssertionError("Pinned ThreadSanitizer runtime was not found")
        evidence["sequential_model_outcomes"] = sequential_model()
        for name, source, expected in (("startup", STARTUP, 0), ("detector", RACE, 99)):
            path, program = directory / (name + ".cpp"), directory / name
            path.write_text(source)
            run([args.cxx, "-std=c++20", *flags, path, "-o", program, *args.link_arg])
            result = run([program], expected=expected, timeout=15)
            if expected and "ThreadSanitizer: data race" not in result.stderr:
                raise AssertionError("TSan detector did not report the intentional race")
        objects = []
        for name in ("runtime/panic.cpp", "runtime/thread.cpp",
                     "tests/backend/machine_callbacks.c",
                     "tests/backend/machine_unwind.cpp"):
            source = ROOT / name
            obj = directory / (source.stem + ".o")
            c = source.suffix == ".c"
            tool = args.cxx.with_name("clang") if c else args.cxx
            run([tool, "-std=c11" if c else "-std=c++20", *flags,
                 "-Wall", "-Wextra", "-Wpedantic", "-Werror",
                 "-c", source, "-o", obj])
            objects.append(obj)
        spec = importlib.util.spec_from_file_location("machine", ROOT / "tests/backend/machine.py")
        machine = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(machine)
        cases = {name: source for name, source in machine.SOURCES.items()
                 if name.startswith("c-thread-")}
        if len(cases) < 3:
            raise AssertionError("Expected publication, failed-CAS and SC litmus cases")
        for name, source in cases.items():
            path = directory / (name + ".mt")
            path.write_text(source)
            for profile in ("debug", "release"):
                ir = directory / (name + "-" + profile + ".ll")
                run([args.compiler, "build", path, "--emit", "llvm", "--profile", profile,
                     "-o", ir])
                instrumented = ir.with_suffix(".tsan.ll")
                instrumented.write_text(instrument(ir.read_text()))
                obj, program = ir.with_suffix(".o"), ir.with_suffix("")
                run([args.cxx, "-x", "ir", *flags, "-c", instrumented, "-o", obj])
                symbols = run([args.cxx.with_name("llvm-nm"), "--undefined-only", obj])
                if "tsan_atomic32_" not in symbols.stdout:
                    raise AssertionError("Generated Mettle atomic code lacks TSan instrumentation")
                run([args.cxx, *flags, obj, *objects, "-o", program, *args.link_arg])
                run([program])
                evidence["cases"].append({"name": name, "profile": profile,
                                          "source_sha256": digest(path),
                                          "ir_sha256": digest(ir),
                                          "instrumented_ir_sha256": digest(instrumented),
                                          "object_sha256": digest(obj),
                                          "program_sha256": digest(program)})
        evidence["status"] = "passed"
    finally:
        (directory / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"Memory-model checks: {len(evidence['cases'])} instrumented profile cases passed")


if __name__ == "__main__":
    main()
