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

import processes


def run(arguments, expected=0, contains=None):
    result = processes.run(arguments, text=True, capture_output=True, timeout=90)
    if result.returncode != expected:
        raise AssertionError(
            f"{arguments!r}: expected exit {expected}, got {result.returncode}\n"
            f"{result.stdout}{result.stderr}")
    if contains and contains not in result.stdout + result.stderr:
        raise AssertionError(f"{arguments!r}: missing {contains!r}\n{result.stdout}{result.stderr}")
    return result


def harness_cases(root, executable):
    import alloc
    import std
    from unittest.mock import patch

    def rejected(action, exception):
        try:
            action()
        except exception:
            return
        raise AssertionError(f"expected {exception.__name__}")

    rejected(lambda: std.directives("// expect-stdou: required\n"), ValueError)
    rejected(lambda: std.directives("// expect-exit: 0\n// expect-exit: 42\n"),
             ValueError)
    repeated = std.directives("// expect-stderr: first\n// expect-stderr: second\n")
    assert repeated["expect-stderr"] == ["first", "second"]
    empty = root / "empty"
    empty.mkdir()
    for runner in (alloc, std):
        rejected(lambda: runner.main(executable, root / "out", empty), ValueError)
    source = (root / "profile.mt").resolve()
    source.write_text("fn main(): i32 { 0 }\n")
    import processes
    for runner in (alloc, std):
        result = subprocess.CompletedProcess([], 0, b"", b"")
        with patch.object(processes, "run", return_value=result) as invoke:
            runner.check(executable, source, root, profile="release")
        build = invoke.call_args_list[0].args[0]
        assert build[build.index("--profile") + 1] == "release", build
    source.write_text("// expect-error: type 2:1 unknown name\nmissing\n")
    for runner in (alloc, std):
        wrong = f"{source}:2:1: error[type]: other failure\n{source}:9:1: error[type]: unknown name\n"
        result = subprocess.CompletedProcess([], 1, "", wrong)
        with patch.object(processes, "run", return_value=result):
            rejected(lambda: runner.check(executable, source, root), AssertionError)
        result.stderr = f"{source}:2:1: error[type]: unknown name `missing`\n"
        with patch.object(processes, "run", return_value=result):
            runner.check(executable, source, root)
    packages = Path(__file__).with_name("packages.py")
    run([sys.executable, str(packages), executable, str(root / "packages"),
         str(empty), "^definitely-not-a-case$"], expected=1,
        contains="no package cases selected")
    machine = Path(__file__).parent / "backend" / "machine.py"
    run([sys.executable, str(machine), executable, executable, executable,
         executable, str(root / "machine"), "--case-prefix",
         "definitely-not-a-case"], expected=1, contains="no machine cases selected")
    assert json.loads((root / "machine" / "evidence.json").read_text())["status"] == "failed"
    events = []

    class TimedOut:
        pid = 12345

        def __enter__(self):
            return self

        def __exit__(self, *arguments):
            return False

        def communicate(self, input=None, timeout=None):
            events.append("communicate")
            if timeout is not None:
                raise subprocess.TimeoutExpired(["mock-child"], timeout)
            return b"", b""

    with patch.object(processes.subprocess, "Popen", return_value=TimedOut()) as spawn:
        with patch.object(processes, "kill", side_effect=lambda child: events.append("kill")):
            rejected(lambda: processes.run(["mock-child"], timeout=1),
                     subprocess.TimeoutExpired)
    assert events == ["communicate", "kill", "communicate"], events
    assert spawn.call_args.kwargs["start_new_session"] == (os.name == "posix")
    if os.name == "posix":
        with patch.object(processes.os, "killpg") as terminate:
            processes.kill(TimedOut())
        terminate.assert_called_once_with(TimedOut.pid, processes.signal.SIGKILL)
    print("Harness diagnostic, selection, profile and timeout behavior passed")


def main():
    mode, executable, *arguments = sys.argv[1:]
    executable = str(Path(executable).resolve())
    with tempfile.TemporaryDirectory(prefix="mettle-foundation-") as temporary:
        root = Path(temporary)
        if mode == "harnesses":
            harness_cases(root, executable)
        elif mode == "cli":
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
