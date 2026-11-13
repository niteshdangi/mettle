#!/usr/bin/env python3
"""Cross-emit on macOS, then link and execute source/cleanup objects on Linux x86-64."""

import argparse
import importlib.util
import json
import os
import platform
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from bootstrap import ROOT, artifacts, host_platform, sha256


TARGET_PROBE = """
import hashlib, json, platform, subprocess, sys
from pathlib import Path
clang, cxx = sys.argv[1:3]
files = [Path(subprocess.check_output([cxx, "-print-file-name=" + name], text=True).strip())
         for name in ("Scrt1.o", "crti.o", "crtn.o", "libc.so.6", "libstdc++.so", "libgcc_s.so.1")]
files.append(Path("/usr/include/features.h"))
print(json.dumps({
    "system": platform.system(), "kernel": platform.release(), "machine": platform.machine(),
    "libc": platform.libc_ver(), "os_release": Path("/etc/os-release").read_text(),
    "virtualization": Path("/sys/class/dmi/id/sys_vendor").read_text().strip(),
    "clang": subprocess.check_output([clang, "--version"], text=True).strip(),
    "clang++": subprocess.check_output([cxx, "--version"], text=True).strip(),
    "compiler_target": subprocess.check_output([cxx, "-dumpmachine"], text=True).strip(),
    "sysroot_files": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in files},
    "packages": subprocess.check_output(
        ["dpkg-query", "-W", "-f=${binary:Package}\\t${Version}\\t${Architecture}\\n"], text=True)
}))
"""

SOURCE_EXECUTION = """
import concurrent.futures, hashlib, json, os, resource, signal, subprocess, sys
from pathlib import Path
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
cxx, runtime, cases = sys.argv[1], sys.argv[2], json.loads(Path(sys.argv[3]).read_text())
def execute(case):
    libraries = case.get("libraries", []) + ([] if case.get("freestanding") else [runtime])
    undefined = None
    if case.get("freestanding"):
        command = [str(Path(cxx).with_name("llvm-nm")), "--undefined-only", case["object"]]
        symbols = subprocess.run(command, text=True, capture_output=True)
        if symbols.returncode or symbols.stdout.strip():
            raise RuntimeError("Freestanding object has unresolved dependencies: " +
                               symbols.stdout + symbols.stderr)
        undefined = []
    command = [cxx, "--target=x86_64-unknown-linux-gnu", "-fuse-ld=lld",
               case["object"], *libraries, "-o", case["program"]]
    environment = dict(os.environ, TMPDIR=str(Path(case["program"]).parent))
    link = subprocess.run(command, text=True, capture_output=True, env=environment)
    if link.returncode:
        raise RuntimeError(str(command) + "\\n" + link.stdout + link.stderr)
    result = subprocess.run([case["program"]], text=True, capture_output=True)
    expected = case["expected"]
    if (expected == "trap" and result.returncode != -signal.SIGABRT) or (
            expected != "trap" and result.returncode != expected):
        raise RuntimeError(str(case) + ": got " + str(result.returncode))
    for stream, wanted in case.get("output", {}).items():
        actual = getattr(result, stream)
        matches = actual == wanted if stream == "stdout" else wanted in actual
        if not matches:
            raise RuntimeError(case["program"] + ": expected " + stream + " " +
                               repr(wanted) + ", got " + repr(actual))
    output = dict(case, exit_status=result.returncode, link_command=command,
                  program_sha256=hashlib.sha256(Path(case["program"]).read_bytes()).hexdigest())
    if undefined is not None:
        output["undefined_symbols"] = undefined
    return output
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(execute, cases))
print(json.dumps(results))
"""

LIBRARY_EXECUTION = """
import concurrent.futures, hashlib, json, os, resource, shutil, signal, subprocess, sys
from pathlib import Path
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
cxx, runtime, cases = sys.argv[1], sys.argv[2], json.loads(Path(sys.argv[3]).read_text())
def execute(case):
    command = [cxx, "--target=x86_64-unknown-linux-gnu", "-fuse-ld=lld",
               case["object"], runtime, "-o", case["program"]]
    environment = dict(os.environ, TMPDIR=str(Path(case["program"]).parent))
    link = subprocess.run(command, text=True, capture_output=True, env=environment)
    if link.returncode:
        raise RuntimeError(case["name"] + ": " + link.stdout + link.stderr)
    work = Path(case["program"] + ".dir")
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    for name, content in case.get("files", []):
        (work / name).write_bytes(content.encode())
    result = subprocess.run([case["program"], *case.get("args", [])], cwd=work,
                            input=case.get("stdin", "").encode(), capture_output=True)
    stdout, stderr = result.stdout.decode(errors="replace"), result.stderr.decode(errors="replace")
    expected = case["expected"]
    problems = []
    if result.returncode != expected:
        problems.append("exit " + str(result.returncode) + " != " + str(expected))
    if "stdout" in case and stdout != case["stdout"]:
        problems.append("stdout " + repr(stdout))
    for needle in case.get("stdout_contains", []):
        if needle not in stdout:
            problems.append("stdout lacks " + repr(needle) + ": " + repr(stdout))
    for needle in case.get("stderr_contains", []):
        if needle not in stderr:
            problems.append("stderr lacks " + repr(needle) + ": " + repr(stderr))
    for name, content in case.get("expect_files", []):
        path = work / name
        if not path.exists() or path.read_bytes() != content.encode():
            problems.append("file " + name + " differs")
    if problems:
        raise RuntimeError(case["name"] + ": " + "; ".join(problems) + "\\n" + stdout + stderr)
    return {"name": case["name"], "exit_status": result.returncode,
            "program_sha256": hashlib.sha256(Path(case["program"]).read_bytes()).hexdigest()}
def attempt(case):
    try:
        return execute(case)
    except Exception as error:
        return {"name": case["name"], "failure": str(error)}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(attempt, cases))
failures = [result["failure"] for result in results if "failure" in result]
if failures:
    sys.exit("\\n".join(failures))
print(json.dumps(results))
"""


def stage_source_inputs(case, directory):
    from source import source_receipt
    shutil.copyfile(case.path, directory / "source.mt")
    dependencies = {}
    for name in source_receipt(case.path)["helper_sha256"]:
        helper = Path(name)
        relative = helper.relative_to(case.path.parent)
        destination = directory / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(helper, destination)
        dependencies[relative.as_posix()] = sha256(destination)
    return {"source_dependencies": dependencies, "output": case.output}


def library_cases(output):
    """(group, name, source text, expectations) for the core, alloc and std programs."""
    sys.path.insert(0, str(ROOT / "tests"))
    from std import directives, split_file
    cases = []
    for program in sorted((ROOT / "tests/library").glob("*.mt")):
        cases.append(("core", program.stem, program.read_text(), {"expected": 0}))
    cases.append(("core", "unwrap-none-aborts",
                  "import core.option;\nfn nothing(): i32? { none }\n"
                  "fn main(): i32 { nothing().or_panic() }\n",
                  {"expected": 101, "stderr_contains": [
                      "panicked: called `or_panic` on an absent value"]}))
    cases.append(("core", "panic-reports-message",
                  "fn nothing(): i32? { none }\n"
                  "fn main(): i32 { let guard = nothing()\n guard.or_panic(\"value was required\") }\n",
                  {"expected": 101, "stderr_contains": ["panicked: value was required"]}))
    cases.append(("core", "panic-function-unwinds",
                  "fn check(ok: bool) { if !ok { panic(\"check failed\") } }\n"
                  "fn main(): i32 { check(false)\n 0 }\n",
                  {"expected": 101, "stderr_contains": ["panicked: check failed"]}))
    for program in sorted((ROOT / "tests/alloc").glob("*.mt")):
        text = program.read_text()
        header = text.splitlines()[0] if text else ""
        if header.startswith("// expect-error:"):
            continue
        cases.append(("alloc", program.stem, text, {
            "expected": -6 if header.startswith("// expect-exit: trap") else 0}))
    for program in sorted((ROOT / "tests/std").glob("*.mt")):
        text = program.read_text()
        options = directives(text)
        if "expect-error" in options:
            continue
        expectations = {
            "expected": int(options.get("expect-exit", ["0"])[0]),
            "args": options.get("args", [""])[0].split(),
            "stdin": options.get("stdin", [""])[0],
            "files": [split_file(entry) for entry in options.get("file", [])],
            "expect_files": [split_file(entry) for entry in options.get("expect-file", [])],
            "stderr_contains": options.get("expect-stderr", []),
            "stdout_contains": options.get("linux-expect-stdout", [])}
        if "expect-stdout" in options:
            expectations["stdout"] = options["expect-stdout"][0]
        cases.append(("std", program.stem, text, expectations))
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--instance", default="mettle-linux-x64")
    parser.add_argument("--source", action="store_true",
                        help="also execute current source run-pass/arithmetic and I03 cleanup cases")
    parser.add_argument("--libraries", action="store_true",
                        help="also execute the core, alloc and std library programs")
    arguments = parser.parse_args()
    if host_platform() != "macos-arm64":
        raise RuntimeError("This runner uses the native macOS ARM64 foundation builds")
    environment = os.environ.copy()
    environment.setdefault("LIMA_HOME", str(ROOT / ".tools/lima"))
    remote = ["limactl", "--tty=false", "shell", f"--workdir={ROOT}", arguments.instance]
    directory = ROOT / "build/linux-target"
    directory.mkdir(parents=True, exist_ok=True)
    environment["TMPDIR"] = str(directory)
    evidence = {
        "scope": "Native macOS compiler host; Linux x86-64 target execution" +
                 (" including source and I03 native cleanup" if arguments.source else "") +
                 (" and core/alloc/std library programs" if arguments.libraries else "") +
                 ("" if arguments.source or arguments.libraries else "; constructed LLVM only"),
        "host": platform.platform(), "status": "in_progress", "commands": [], "cases": {},
        "limits": "Emulated target, not native x86 hardware/performance or Linux compiler-host qualification",
    }
    native_manifests = []

    def run(command, expected=0):
        result = subprocess.run(command, env=environment, text=True, capture_output=True)
        evidence["commands"].append(
            {"command": command, "exit_status": result.returncode,
             "stdout": result.stdout, "stderr": result.stderr})
        if result.returncode != expected:
            raise RuntimeError(
                f"{command!r}: expected {expected}, got {result.returncode}\n"
                f"{result.stdout}{result.stderr}")
        return result.stdout.strip()

    try:
        llvm = ROOT / ".tools/linux-x86_64/llvm"
        selected = artifacts("linux-x86_64")["llvm"]
        if json.loads((llvm / ".artifact.json").read_text()) != selected:
            raise RuntimeError("Missing or unrecognized pinned Linux LLVM; run bootstrap first")
        clang = str(llvm / "bin/clang")
        cxx, archiver = str(llvm / "bin/clang++"), str(llvm / "bin/llvm-ar")
        target = json.loads(run([*remote, "python3", "-c", TARGET_PROBE, clang, cxx]))
        if (target["system"], target["machine"]) != ("Linux", "x86_64"):
            raise RuntimeError("Runner is not executing an x86-64 Linux kernel")
        if f"clang version {selected['version']}" not in target["clang"]:
            raise RuntimeError("Runner Clang version differs from the artifact lock")
        if f"clang version {selected['version']}" not in target["clang++"]:
            raise RuntimeError("Runner Clang++ version differs from the artifact lock")
        evidence["target"] = target
        evidence["target_tools"] = {
            "archive_sha256": selected["sha256"], "clang_sha256": sha256(llvm / "bin/clang"),
            "clang++_sha256": sha256(llvm / "bin/clang++"),
            "llvm_ar_sha256": sha256(llvm / "bin/llvm-ar"),
            "llvm_ar_version": run([*remote, archiver, "--version"]),
            "llvm_nm_sha256": sha256(llvm / "bin/llvm-nm"),
            "llvm_nm_version": run([*remote, str(llvm / "bin/llvm-nm"), "--version"]),
            "lld_sha256": sha256(llvm / "bin/ld.lld"),
            "lld_version": run([*remote, str(llvm / "bin/ld.lld"), "--version"]),
        }
        runtime_archive = directory / "runtime/libmettle_runtime.a"
        host_llvm = ROOT / ".tools/macos-arm64/llvm/bin"
        host_cxx, readobj = host_llvm / "clang++", host_llvm / "llvm-readobj"
        if arguments.source or arguments.libraries:
            runtime_archive.parent.mkdir(exist_ok=True)
            runtime_sources = ("runtime/panic.cpp", "runtime/alloc.cpp", "runtime/sys.cpp", "runtime/thread.cpp")
            runtime_objects = [runtime_archive.parent / Path(name).with_suffix(".o").name
                               for name in runtime_sources]
            compile_commands = [[
                cxx, "--target=x86_64-unknown-linux-gnu", "-std=c++20",
                "-Wall", "-Wextra", "-Wpedantic", "-Werror", "-O2", "-g",
                "-c", str(ROOT / name), "-o", str(obj)]
                for name, obj in zip(runtime_sources, runtime_objects)]
            archive_runtime = [archiver, "rcsD", str(runtime_archive),
                               *map(str, runtime_objects)]
            for compile_runtime in compile_commands:
                run([*remote, "env", f"TMPDIR={runtime_archive.parent}", *compile_runtime])
            run([*remote, *archive_runtime])
            evidence["runtime"] = {
                "target": "x86_64-unknown-linux-gnu",
                "source_inputs": {name: sha256(ROOT / name)
                                  for name in ("runtime/panic.cpp", "runtime/panic.h",
                                             "runtime/alloc.cpp", "runtime/alloc.h",
                                             "runtime/sys.cpp", "runtime/sys.h",
                                             "runtime/thread.cpp", "runtime/thread.h")},
                "compile_commands": compile_commands, "archive_command": archive_runtime,
                "object_sha256": {obj.name: sha256(obj) for obj in runtime_objects},
                "archive_sha256": sha256(runtime_archive),
            }
            evidence["host_tools"] = {
                str(path): {"sha256": sha256(path), "version": run([str(path), "--version"])}
                for path in (host_cxx, readobj)}
        if arguments.source:
            callbacks_archive = runtime_archive.parent / "libmettle_machine_callbacks.a"
            callbacks_sources = ("tests/backend/machine_callbacks.c",
                                 "tests/backend/machine_unwind.cpp",
                                 "tests/backend/machine_vectors.c",
                                 "tests/backend/foreign_storage.c")
            callbacks_objects = []
            for name in callbacks_sources:
                obj = runtime_archive.parent / (ROOT / name).with_suffix(".o").name
                tool = clang if name.endswith(".c") else cxx
                standard = "-std=c11" if name.endswith(".c") else "-std=c++20"
                run([*remote, "env", f"TMPDIR={runtime_archive.parent}", tool,
                     "--target=x86_64-unknown-linux-gnu", standard, "-O2", "-g",
                     "-Wall", "-Wextra", "-Wpedantic", "-Werror",
                     *(["-mavx"] if name.endswith("machine_vectors.c") else []),
                     "-c", str(ROOT / name), "-o", str(obj)])
                callbacks_objects.append(str(obj))
            run([*remote, archiver, "rcsD", str(callbacks_archive), *callbacks_objects])
            evidence["machine_callbacks"] = {
                "source_inputs": {name: sha256(ROOT / name) for name in callbacks_sources},
                "archive_sha256": sha256(callbacks_archive)}
        for configuration in ("Debug", "Release"):
            host = ROOT / "build/macos-arm64" / configuration
            manifest = host / "foundation-evidence.json"
            previous = json.loads(manifest.read_text())
            if previous["status"] != "passed" or not previous["clean_rebuild_byte_identical"]:
                raise RuntimeError(f"Native {configuration} foundation checks have not passed")
            if "tools/test_linux_target.py" not in previous["source_inputs"]:
                raise RuntimeError("Refresh native build evidence before target validation")
            for name, digest in previous["source_inputs"].items():
                if sha256(ROOT / name) != digest:
                    raise RuntimeError(f"Native evidence is stale: {name}")
            native_manifests.append((manifest, sha256(manifest), previous["source_inputs"]))
            emitter = host / "mettle-object-smoke"
            if sha256(emitter) != previous["rebuilt_artifacts"][emitter.name]:
                raise RuntimeError("Native object emitter differs from its passing build evidence")
            output = directory / configuration
            output.mkdir(exist_ok=True)
            object_file, program = output / "smoke.o", output / "smoke"
            run([str(emitter), str(object_file), "x86_64-unknown-linux-gnu"])
            headers = run([str(readobj), "--file-headers", str(object_file)])
            if "Format: elf64-x86-64" not in headers:
                raise RuntimeError("Cross-emitter did not produce an x86-64 ELF object")
            run([*remote, clang, "-fuse-ld=lld", str(object_file), "-o", str(program)])
            run([*remote, str(program)], expected=37)
            evidence["cases"][configuration] = {
                "native_build_manifest_sha256": sha256(manifest), "object_headers": headers,
                "object_sha256": sha256(object_file), "program_sha256": sha256(program),
                "exit_status": 37,
            }
            print(f"{configuration}: x86-64 ELF emitted, linked and executed on Linux; exit 37",
                  flush=True)
            if arguments.source:
                sys.path.insert(0, str(ROOT / "tests"))
                from modules import TARGET_FILES
                def target_cases(name, path):
                    spec = importlib.util.spec_from_file_location(name, path)
                    module = importlib.util.module_from_spec(spec)
                    module.TARGET_ARCH = "x86_64"
                    spec.loader.exec_module(module)
                    return module
                import source as source_cases
                # Programs run under both profiles with no extra build flags.
                run_cases = [case for case in source_cases.load_cases("run", arch="x86_64")
                             if not case.flags and case.profiles == source_cases.PROFILES]
                machine = target_cases("machine_cases", ROOT / "tests/backend/machine.py")
                machine_sources = {"machine-" + name: text
                                   for name, text in machine.SOURCES.items()}
                compiler = host / "mettle"
                if sha256(compiler) != previous["rebuilt_artifacts"]["mettle"]:
                    raise RuntimeError("Source compiler differs from passing build evidence")
                cases = []
                selected_sources = {case.name: (case.path.read_text(), case.exits["debug"],
                                                case.exits["release"], case)
                                    for case in run_cases}
                selected_sources.update({
                    "modules-" + name: (files["main.mt"], 0, 0, None)
                    for name, files in TARGET_FILES.items()})
                selected_sources.update({name: (text, 0, 0, None)
                                         for name, text in machine_sources.items()})
                evidence["cases"][configuration]["source_selection"] = {
                    "run": sorted(case.name for case in run_cases),
                    "modules": sorted(TARGET_FILES), "machine": sorted(machine_sources),
                    "freestanding": ["no-hosted-runtime", "assembly-simd-no-services"]}
                for profile in ("debug", "release"):
                    for name, (text, debug, release, native_case) in selected_sources.items():
                        case_directory = output / "source" / profile / name
                        case_directory.mkdir(parents=True, exist_ok=True)
                        source = case_directory / "source.mt"
                        inputs = {"source_dependencies": {}, "output": {}}
                        if native_case:
                            inputs = stage_source_inputs(native_case, case_directory)
                        else:
                            source.write_text(text)
                        dependencies = inputs["source_dependencies"]
                        if name.startswith("modules-"):
                            for relative, content in TARGET_FILES[name[len("modules-"):]].items():
                                if relative == "main.mt":
                                    continue
                                dependency = case_directory / relative
                                dependency.parent.mkdir(parents=True, exist_ok=True)
                                dependency.write_text(content)
                                dependencies[relative] = sha256(dependency)
                        obj, executable = case_directory / "source.o", case_directory / "program"
                        run([str(compiler), "build", str(source), "-o", str(obj),
                             "--emit", "object", "--target", "x86_64-unknown-linux-gnu",
                             "--profile", profile])
                        cases.append({"name": name, "profile": profile, "object": str(obj),
                                      "program": str(executable), "source_sha256": sha256(source),
                                      "object_sha256": sha256(obj),
                                      **inputs,
                                      "libraries": ([str(callbacks_archive)]
                                                    if name in machine_sources else []),
                                      "expected": debug if profile == "debug" else release})
                    for name, text in (
                            ("freestanding-no-hosted-runtime", machine.FREESTANDING_SOURCE),
                            ("freestanding-assembly-simd-no-services", machine.MACHINE_FREESTANDING_SOURCE)):
                        standalone = output / "source" / profile / name
                        standalone.mkdir(parents=True, exist_ok=True)
                        source = standalone / "source.mt"
                        source.write_text(text)
                        driver = standalone / "driver.c"
                        driver.write_text(machine.FREESTANDING_DRIVER)
                        driver_object = standalone / "driver.o"
                        run([*remote, clang, "-std=c11", "-c", str(driver),
                             "-o", str(driver_object)])
                        obj, executable = standalone / "source.o", standalone / "program"
                        run([str(compiler), "build", str(source), "--freestanding",
                             "--emit", "object", "--target", "x86_64-unknown-linux-gnu",
                             "--profile", profile, "-o", str(obj)])
                        cases.append({"name": name, "profile": profile,
                                      "object": str(obj), "program": str(executable),
                                      "source_sha256": sha256(source), "object_sha256": sha256(obj),
                                      "source_dependencies": {"driver.c": sha256(driver)},
                                      "libraries": [str(driver_object)], "freestanding": True,
                                      "expected": 0})
                cases_file = output / "source-cases.json"
                cases_file.write_text(json.dumps(cases, indent=2) + "\n")
                evidence["cases"][configuration]["source_cases_input_sha256"] = sha256(cases_file)
                evidence["cases"][configuration]["source_cases"] = json.loads(run(
                    [*remote, "python3", "-c", SOURCE_EXECUTION,
                     cxx, str(runtime_archive), str(cases_file)]))
                print(f"{configuration}: {len(cases)} source cases linked/executed on Linux",
                      flush=True)
                cleanup_runner = ROOT / "tests/backend/cleanup_frame.py"
                cleanup_tests = evidence["cases"][configuration]["cleanup_tests"] = {}
                for fixture, mode in (("frame", []), ("program", ["--state-file"]),
                                      ("source", ["--source-trace"])):
                    generator = host / f"mettle-cleanup-{fixture}-tests"
                    if sha256(generator) != previous["rebuilt_artifacts"].get(generator.name):
                        raise RuntimeError(f"Cleanup generator lacks current native evidence: {generator}")
                    callbacks = ROOT / f"tests/backend/cleanup_{fixture}_callbacks.cpp"
                    suite_directory = output / "cleanup" / fixture
                    emission = json.loads(run(
                        [sys.executable, str(cleanup_runner), "--emit-objects", *mode,
                         str(generator), str(host_cxx), str(callbacks), str(runtime_archive),
                         str(suite_directory), "--target=x86_64-unknown-linux-gnu"]))
                    suite = cleanup_tests[fixture] = {"emission": emission, "object_headers": {}}
                    for name in emission["cases"]:
                        obj = suite_directory / (name + ".o")
                        headers = run([str(readobj), "--file-headers", str(obj)])
                        if "Format: elf64-x86-64" not in headers:
                            raise RuntimeError(f"Cleanup cross-emission is not x86-64 ELF: {obj}")
                        suite["object_headers"][name] = headers
                    suite["execution"] = json.loads(run(
                        [*remote, "python3", str(cleanup_runner), "--run-objects", *mode,
                         str(generator), cxx, str(callbacks), str(runtime_archive),
                         str(suite_directory), "--target=x86_64-unknown-linux-gnu", "-fuse-ld=lld"]))
                print(f"{configuration}: six backend cleanup cases linked/executed on Linux",
                      flush=True)
            if arguments.libraries:
                compiler = host / "mettle"
                if sha256(compiler) != previous["rebuilt_artifacts"]["mettle"]:
                    raise RuntimeError("Source compiler differs from passing build evidence")
                library_directory = output / "libraries"
                cases = []
                for group, name, text, expectations in library_cases(output):
                    case_directory = library_directory / group / name
                    case_directory.mkdir(parents=True, exist_ok=True)
                    source = case_directory / "main.mt"
                    source.write_text(text)
                    obj = case_directory / "source.o"
                    cases.append({"name": f"{group}-{name}", "object": str(obj),
                                  "program": str(case_directory / "program"),
                                  "source": str(source), **expectations})
                def emit(case):
                    run([str(compiler), "build", case["source"], "-o", case["object"],
                         "--emit", "object", "--target", "x86_64-unknown-linux-gnu"])
                    case["source_sha256"] = sha256(Path(case["source"]))
                    case["object_sha256"] = sha256(Path(case["object"]))
                with ThreadPoolExecutor(max_workers=4) as pool:
                    list(pool.map(emit, cases))
                cases_file = output / "library-cases.json"
                cases_file.write_text(json.dumps(cases, indent=2) + "\n")
                evidence["cases"][configuration]["library_cases_input_sha256"] = sha256(cases_file)
                evidence["cases"][configuration]["library_cases"] = json.loads(run(
                    [*remote, "python3", "-c", LIBRARY_EXECUTION,
                     cxx, str(runtime_archive), str(cases_file)]))
                counts = {group: sum(case["name"].startswith(group + "-") for case in cases)
                          for group in ("core", "alloc", "std")}
                evidence["cases"][configuration]["library_counts"] = counts
                print(f"{configuration}: library programs linked/executed on Linux: {counts}",
                      flush=True)
        for manifest, digest, source_inputs in native_manifests:
            if sha256(manifest) != digest:
                raise RuntimeError(f"Native build evidence changed during target checks: {manifest}")
            for name, expected in source_inputs.items():
                if sha256(ROOT / name) != expected:
                    raise RuntimeError(f"Native source evidence changed during target checks: {name}")
        evidence["status"] = "passed"
    except Exception as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
        raise
    finally:
        (directory / "foundation-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")


if __name__ == "__main__":
    main()
