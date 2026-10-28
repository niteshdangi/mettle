#!/usr/bin/env python3
"""Compiler-foundation fixtures; this does not compile Mettle source."""

import json
import hashlib
import os
import platform
import subprocess
import sys
import tempfile
from pathlib import Path


def run(arguments, expected=0, contains=None):
    result = subprocess.run(arguments, text=True, capture_output=True, timeout=90)
    if result.returncode != expected:
        raise AssertionError(
            f"{arguments!r}: expected exit {expected}, got {result.returncode}\n"
            f"{result.stdout}{result.stderr}")
    if contains and contains not in result.stdout + result.stderr:
        raise AssertionError(f"{arguments!r}: missing {contains!r}\n{result.stdout}{result.stderr}")
    return result


def main():
    mode, executable, *arguments = sys.argv[1:]
    executable = str(Path(executable).resolve())
    with tempfile.TemporaryDirectory(prefix="mettle-foundation-") as temporary:
        root = Path(temporary)
        if mode == "cli":
            run([executable, "--version"], contains="I02 scalar source compiler")
            run([executable, "--help"], contains="mettle build")
            source = root / "example.mt"
            source.write_text("fn main(): i32 { 0 }\n")
            run([executable, "check", str(source)])
            run([executable, "--unknown"], expected=2)
            run([executable], expected=2)
        elif mode == "object":
            compiler, *linker_flags = arguments
            object_file, program = root / "smoke.o", root / "smoke"
            run([executable, str(object_file)])
            if not object_file.is_file() or object_file.stat().st_size == 0:
                raise AssertionError("Backend did not emit an object")
            command = [compiler, *linker_flags, str(object_file), "-o", str(program)]
            link_plan = run([*command, "-###"]).stderr
            run(command)
            run([str(program)], expected=37)
            print(json.dumps({
                "kind": "constructed-LLVM-module-not-Mettle-source",
                "system": platform.system(), "machine": platform.machine(),
                "object_bytes": object_file.stat().st_size, "exit_status": 37,
                "object_sha256": hashlib.sha256(object_file.read_bytes()).hexdigest(),
                "program_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
                "link_command": command, "driver_link_plan": link_plan,
            }, sort_keys=True))
        elif mode == "errors":
            output = root / "invalid.o"
            run([executable, str(output), "unknown-mettle-target"], expected=1,
                contains="mettle-object-smoke:")
            if output.exists():
                raise AssertionError("Unknown target created an output artifact")
            run([executable, str(root / "absent" / "smoke.o")], expected=1,
                contains="cannot create object file")
            output.write_bytes(b"preserve existing output")
            run([executable, str(output), "--invalid-module"], expected=1,
                contains="invalid backend module")
            if output.read_bytes() != b"preserve existing output":
                raise AssertionError("Invalid backend module overwrote an existing artifact")
            if platform.system() == "Linux":
                run([executable, "/dev/full"], expected=1, contains="cannot write object file")
        elif mode == "sanitizers":
            compiler, *linker_flags = arguments
            os.environ["ASAN_OPTIONS"] = "halt_on_error=1:abort_on_error=0:exitcode=99"
            os.environ["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1:exitcode=99"
            run([executable, "--version"], contains="I02 scalar source compiler")
            probes = {
                "address": (
                    "int main(int argc, char **) { int *p = new int[1]{0}; "
                    "volatile int offset = argc; int result = p[offset]; "
                    "delete[] p; return result; }\n",
                    "AddressSanitizer: heap-buffer-overflow"),
                "undefined": (
                    "int main(int argc, char **) { volatile int maximum = 2147483647; "
                    "return maximum + argc; }\n",
                    "runtime error: signed integer overflow"),
            }
            for name, (text, diagnostic) in probes.items():
                source, program = root / (name + ".cpp"), root / name
                source.write_text(text)
                run([compiler, *linker_flags, "-std=c++20", "-fsanitize=address,undefined",
                     "-fno-sanitize-recover=all", "-fno-omit-frame-pointer",
                     str(source), "-o", str(program)])
                result = run([str(program)], expected=99, contains=diagnostic)
                print(json.dumps({"sanitizer": name, "exit_status": result.returncode,
                                  "diagnostic": diagnostic, "report": result.stderr},
                                 sort_keys=True))
        else:
            raise ValueError(f"Unknown fixture mode: {mode}")


if __name__ == "__main__":
    main()
