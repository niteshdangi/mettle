#!/usr/bin/env python3
"""Compile and execute cleanup LLVM fixtures, optionally across compiler hosts."""

import hashlib
import json
import os
import platform
import resource
import signal
import struct
import subprocess
import sys
from pathlib import Path


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    arguments = sys.argv[1:]
    phase = "native"
    if arguments[0] in ("--emit-objects", "--run-objects"):
        phase = arguments[0][2:]
        arguments = arguments[1:]
    stateful = arguments[0] == "--state-file"
    source_trace = arguments[0] == "--source-trace"
    if stateful or source_trace:
        arguments = arguments[1:]
    generator, compiler, callbacks, runtime, directory, *flags = arguments
    output = Path(directory)
    output.mkdir(parents=True, exist_ok=True)
    build_environment = dict(os.environ, TMPDIR=str(output.resolve()))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    kind = "constructed-cleanup-frame-LLVM-not-Mettle-source"
    if stateful:
        kind = "constructed-cleanup-program-LLVM-not-Mettle-source"
    elif source_trace:
        kind = "instrumented-source-IR-trace"
    cases = (("normal", [], 0), ("doublepanic", ["doublepanic"], -signal.SIGABRT))
    if source_trace:
        cases = (("scopes", [], 0), ("argument-unwind", ["argument-unwind"], 0))
    evidence = {
        "kind": kind, "phase": phase,
        "system": platform.system(), "machine": platform.machine(),
        "generator_sha256": sha256(generator), "compiler_sha256": sha256(compiler),
        "callbacks_sha256": sha256(callbacks), "runtime_archive_sha256": sha256(runtime),
        "build_environment": {"TMPDIR": build_environment["TMPDIR"]},
        "runner_sha256": sha256(__file__), "commands": [], "cases": {}, "status": "in_progress",
    }

    def run(command, expected=0, environment=None):
        result = subprocess.run(command, capture_output=True, text=True, timeout=90,
                                env=build_environment if environment is None else environment)
        step = {"command": command, "exit_status": result.returncode}
        if environment is not None:
            step["state_file"] = environment["METTLE_CLEANUP_STATE_FILE"]
        evidence["commands"].append(step)
        if result.returncode != expected:
            raise AssertionError(
                f"{command!r}: expected exit {expected}, got {result.returncode}\n"
                f"{result.stdout}{result.stderr}")
        return result.stdout

    try:
        if phase == "run-objects":
            emission_path = output / "emission-evidence.json"
            emission = json.loads(emission_path.read_text())
            if emission["status"] != "emitted" or emission["kind"] != kind:
                raise AssertionError("Missing or incompatible host object-emission evidence")
            for key in ("generator_sha256", "callbacks_sha256", "runtime_archive_sha256",
                        "runner_sha256"):
                if emission[key] != evidence[key]:
                    raise AssertionError(f"Object-emission input changed: {key}")
            evidence["emission_manifest_sha256"] = sha256(emission_path)
        for name, arguments, expected in cases:
            ir_file, object_file = output / (name + ".ll"), output / (name + ".o")
            program = output / name
            if phase != "run-objects":
                ir_file.write_text(run([generator, *arguments]))
            if phase == "emit-objects":
                run([compiler, *flags, "-Wno-override-module", "-c", str(ir_file),
                     "-o", str(object_file)])
                evidence["cases"][name] = {
                    "llvm_sha256": sha256(ir_file), "object_sha256": sha256(object_file),
                    "expected_exit_status": expected,
                }
                continue
            if phase == "run-objects":
                emitted = emission["cases"][name]
                if (emitted["llvm_sha256"] != sha256(ir_file) or
                        emitted["object_sha256"] != sha256(object_file) or
                        emitted["expected_exit_status"] != expected):
                    raise AssertionError(f"Host-emitted case changed: {name}")
            link_input = object_file if phase == "run-objects" else ir_file
            command = [
                compiler, *flags, "-std=c++20", "-Wall", "-Wextra", "-Wpedantic", "-Werror",
                "-Wno-override-module", str(link_input), callbacks, runtime, "-o", str(program)]
            run(command)
            environment = None
            state = output / (name + ".state")
            if stateful:
                state.unlink(missing_ok=True)
                environment = dict(build_environment, METTLE_CLEANUP_STATE_FILE=str(state))
            stdout = run([str(program)], expected=expected, environment=environment)
            case = {
                "llvm_sha256": sha256(ir_file), "program_sha256": sha256(program),
                "exit_status": expected,
            }
            if phase == "run-objects":
                case["object_sha256"] = sha256(object_file)
            if source_trace:
                case["trace_stdout"] = stdout
            if stateful:
                observed = struct.unpack("=ii", state.read_bytes())
                required = (30, 31) if name == "normal" else (20, 99)
                if observed != required:
                    raise AssertionError(f"{name}: expected shared state {required}, got {observed}")
                case.update(state=observed, state_sha256=sha256(state))
            evidence["cases"][name] = case
        evidence["status"] = "emitted" if phase == "emit-objects" else "passed"
    except Exception as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
        raise
    finally:
        report = json.dumps(evidence, indent=2) + "\n"
        name = "emission-evidence.json" if phase == "emit-objects" else "evidence.json"
        (output / name).write_text(report)
        print(report, end="")


if __name__ == "__main__":
    main()
