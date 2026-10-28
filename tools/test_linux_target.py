#!/usr/bin/env python3
"""Cross-emit on macOS, then link and execute source/cleanup objects on Linux x86-64."""

import argparse
import json
import os
import platform
import subprocess
import sys

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
import hashlib, json, os, resource, subprocess, sys
from pathlib import Path
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
cxx, runtime, cases = sys.argv[1], sys.argv[2], json.loads(Path(sys.argv[3]).read_text())
results = []
for case in cases:
    command = [cxx, "--target=x86_64-unknown-linux-gnu", "-fuse-ld=lld",
               case["object"], runtime, "-o", case["program"]]
    environment = dict(os.environ, TMPDIR=str(Path(case["program"]).parent))
    link = subprocess.run(command, text=True, capture_output=True, timeout=90, env=environment)
    if link.returncode:
        raise RuntimeError(str(command) + "\\n" + link.stdout + link.stderr)
    result = subprocess.run([case["program"]], capture_output=True, timeout=15)
    expected = case["expected"]
    if (expected == "trap" and result.returncode >= 0) or (
            expected != "trap" and result.returncode != expected):
        raise RuntimeError(str(case) + ": got " + str(result.returncode))
    results.append(dict(case, exit_status=result.returncode, link_command=command,
                        program_sha256=hashlib.sha256(Path(case["program"]).read_bytes()).hexdigest()))
print(json.dumps(results))
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--instance", default="mettle-linux-x64")
    parser.add_argument("--source", action="store_true",
                        help="also execute current source run-pass/arithmetic and I03 cleanup cases")
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
                 (" including source and I03 native cleanup" if arguments.source
                  else "; constructed LLVM only"),
        "host": platform.platform(), "status": "in_progress", "commands": [], "cases": {},
        "limits": "Emulated target, not native x86 hardware/performance or Linux compiler-host qualification",
    }
    native_manifests = []

    def run(command, expected=0, timeout=180):
        result = subprocess.run(command, env=environment, text=True, capture_output=True, timeout=timeout)
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
            "lld_sha256": sha256(llvm / "bin/ld.lld"),
            "lld_version": run([*remote, str(llvm / "bin/ld.lld"), "--version"]),
        }
        runtime_archive = directory / "runtime/libmettle_runtime.a"
        host_llvm = ROOT / ".tools/macos-arm64/llvm/bin"
        host_cxx, readobj = host_llvm / "clang++", host_llvm / "llvm-readobj"
        if arguments.source:
            runtime_archive.parent.mkdir(exist_ok=True)
            runtime_object = runtime_archive.parent / "panic.o"
            compile_runtime = [
                cxx, "--target=x86_64-unknown-linux-gnu", "-std=c++20",
                "-Wall", "-Wextra", "-Wpedantic", "-Werror", "-O2", "-g",
                "-c", str(ROOT / "runtime/panic.cpp"), "-o", str(runtime_object)]
            archive_runtime = [archiver, "rcsD", str(runtime_archive), str(runtime_object)]
            run([*remote, "env", f"TMPDIR={runtime_archive.parent}", *compile_runtime])
            run([*remote, *archive_runtime])
            evidence["runtime"] = {
                "target": "x86_64-unknown-linux-gnu",
                "source_inputs": {name: sha256(ROOT / name)
                                  for name in ("runtime/panic.cpp", "runtime/panic.h")},
                "compile_command": compile_runtime, "archive_command": archive_runtime,
                "object_sha256": sha256(runtime_object),
                "archive_sha256": sha256(runtime_archive),
            }
            evidence["host_tools"] = {
                str(path): {"sha256": sha256(path), "version": run([str(path), "--version"])}
                for path in (host_cxx, readobj)}
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
                from scalars import POSITIVE, ARITHMETIC
                compiler = host / "mettle"
                if sha256(compiler) != previous["rebuilt_artifacts"]["mettle"]:
                    raise RuntimeError("Source compiler differs from passing build evidence")
                cases = []
                selected_sources = {name: (text, 0, 0) for name, text in POSITIVE.items()}
                selected_sources.update({
                    name: ("fn main(): i32 { " + body + " }\n", debug, release)
                    for name, (body, debug, release) in ARITHMETIC.items()})
                evidence["cases"][configuration]["source_selection"] = {
                    "positive": sorted(POSITIVE), "arithmetic": sorted(ARITHMETIC)}
                for profile in ("debug", "release"):
                    for name, (text, debug, release) in selected_sources.items():
                        case_directory = output / "source" / profile / name
                        case_directory.mkdir(parents=True, exist_ok=True)
                        source = case_directory / "source.mt"
                        source.write_text(text)
                        obj, executable = case_directory / "source.o", case_directory / "program"
                        run([str(compiler), "build", str(source), "-o", str(obj),
                             "--emit", "object", "--target", "x86_64-unknown-linux-gnu",
                             "--profile", profile])
                        cases.append({"name": name, "profile": profile, "object": str(obj),
                                      "program": str(executable), "source_sha256": sha256(source),
                                      "object_sha256": sha256(obj),
                                      "expected": debug if profile == "debug" else release})
                cases_file = output / "source-cases.json"
                cases_file.write_text(json.dumps(cases, indent=2) + "\n")
                evidence["cases"][configuration]["source_cases_input_sha256"] = sha256(cases_file)
                evidence["cases"][configuration]["source_cases"] = json.loads(run(
                    [*remote, "python3", "-c", SOURCE_EXECUTION,
                     cxx, str(runtime_archive), str(cases_file)],
                    timeout=600))
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
                         str(suite_directory), "--target=x86_64-unknown-linux-gnu", "-fuse-ld=lld"],
                        timeout=300))
                print(f"{configuration}: six backend cleanup cases linked/executed on Linux",
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
