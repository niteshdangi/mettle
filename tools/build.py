#!/usr/bin/env python3
"""Build/test the native compiler and runtime; record reproducible build evidence."""

import argparse
import json
import os
import platform
import re
import subprocess
from pathlib import Path

from bootstrap import ROOT, artifacts, host_platform, sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=("Debug", "Release"), default="Debug")
    parser.add_argument("--sanitizers", action="store_true", help="enable compiler ASan/UBSan")
    arguments = parser.parse_args()
    selected = host_platform()
    items = artifacts(selected)
    prefix = ROOT / ".tools" / selected
    binaries = {name: prefix / name / item["bin"] for name, item in items.items()}
    cmake, ctest = binaries["cmake"] / "cmake", binaries["cmake"] / "ctest"
    clang, cxx = binaries["llvm"] / "clang", binaries["llvm"] / "clang++"
    ninja = binaries["ninja"] / "ninja"
    for name, item in items.items():
        marker = prefix / name / ".artifact.json"
        if not marker.is_file() or json.loads(marker.read_text()) != item:
            raise RuntimeError(f"Missing/unrecognized pinned {name}; run python3 tools/bootstrap.py")
    directory = arguments.configuration + ("-sanitized" if arguments.sanitizers else "")
    build = ROOT / "build" / selected / directory
    build.mkdir(parents=True, exist_ok=True)
    commands = [
        [str(cmake), "-S", str(ROOT), "-B", str(build), "-G", "Ninja",
         f"-DCMAKE_BUILD_TYPE={arguments.configuration}", f"-DCMAKE_C_COMPILER={clang}",
         f"-DCMAKE_CXX_COMPILER={cxx}", f"-DCMAKE_MAKE_PROGRAM={ninja}",
         f"-DLLVM_DIR={prefix / 'llvm/lib/cmake/llvm'}", "-DBUILD_TESTING=ON",
         f"-DMETTLE_ENABLE_SANITIZERS={'ON' if arguments.sanitizers else 'OFF'}"],
        [str(cmake), "--build", str(build), "--target", "clean"],
        [str(cmake), "--build", str(build), "--parallel", str(min(os.cpu_count() or 1, 4))],
        [str(ctest), "--test-dir", str(build), "--output-on-failure", "--verbose"],
        [str(cmake), "--build", str(build), "--target", "clean"],
        [str(cmake), "--build", str(build), "--parallel", str(min(os.cpu_count() or 1, 4))],
    ]
    evidence = {
        "scope": "Native compiler/runtime checks including I03 cleanup; not milestone qualification",
        "system": platform.platform(), "machine": platform.machine(),
        "configuration": arguments.configuration, "commands": commands,
        "sanitizers": ["address", "undefined"] if arguments.sanitizers else [],
        "sanitizer_scope": ("Project C++ code, including the native runtime; prebuilt LLVM and "
                            "emitted Mettle code are not instrumented"),
        "artifact_archives": {name: item["sha256"] for name, item in items.items()},
        "executables": {},
        "source_inputs": {
            str(path.relative_to(ROOT)): sha256(path)
            for path in sorted(
                [ROOT / "CMakeLists.txt", ROOT / "docs/toolchain-pins.json",
                 ROOT / ".clang-format", ROOT / ".clang-tidy", ROOT / ".editorconfig"] +
                [path for directory in ("compiler", "runtime", "tests", "tools", "examples")
                 for path in (ROOT / directory).rglob("*")
                 if path.is_file() and path.suffix in {".cpp", ".h", ".py", ".json", ".yaml", ".mt"}])
        },
        "steps": [],
        "status": "in_progress",
    }
    environment = os.environ.copy()
    # Apple debug maps otherwise retain each object file's modification time.
    environment["ZERO_AR_DATE"] = "1"
    evidence["build_environment"] = {"ZERO_AR_DATE": "1"}
    if arguments.sanitizers:
        environment["ASAN_OPTIONS"] = "halt_on_error=1:abort_on_error=0:exitcode=99"
        environment["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1:exitcode=99"
        evidence["build_environment"].update(
            {name: environment[name] for name in ("ASAN_OPTIONS", "UBSAN_OPTIONS")})
    manifest = build / "foundation-evidence.json"

    def probe(command, timeout=120):
        result = subprocess.run(command, text=True, capture_output=True, env=environment,
                                timeout=timeout)
        if result.returncode:
            raise RuntimeError(
                f"Probe {command!r} failed ({result.returncode}):\n{result.stdout}{result.stderr}")
        return (result.stdout + result.stderr).strip()

    def binary_hashes():
        modules = json.loads((ROOT / "compiler/modules.json").read_text())["modules"]
        names = ["mettle", "mettle-object-smoke", "mettle-ir-tests",
                 "libmettle_runtime.a", "mettle-runtime-tests",
                 "mettle-cleanup-frame-tests", "mettle-cleanup-program-tests",
                 "mettle-cleanup-source-tests"]
        names.extend("libmettle_" + module["name"] + ".a" for module in modules
                     if module["kind"] == "STATIC")
        return {name: sha256(build / name) for name in names}

    try:
        tools = [cmake, ctest, clang, cxx, ninja, binaries["llvm"] / "llvm-config"]
        if selected == "linux-x86_64":
            tools.append(binaries["llvm"] / "ld.lld")
            evidence["os_release"] = Path("/etc/os-release").read_text()
            evidence["packages"] = probe(
                ["dpkg-query", "-W", "-f=${binary:Package}\t${Version}\t${Architecture}\n"])
            sysroot_files = [
                Path(probe([str(clang), f"-print-file-name={name}"]))
                for name in ("Scrt1.o", "crti.o", "crtn.o", "libc.so.6", "libstdc++.so",
                             "libgcc_s.so.1")]
            sysroot_files.append(Path("/usr/include/features.h"))
            evidence["execution"] = (
                "QEMU x86-64 emulation; not native hardware/performance evidence"
                if Path("/sys/class/dmi/id/sys_vendor").read_text().strip() == "QEMU"
                else "Linux host; see system and kernel identity")
        else:
            sdk = Path(probe(["xcrun", "--show-sdk-path"]))
            commands[0].append(f"-DCMAKE_OSX_SYSROOT={sdk}")
            linker = Path(probe(["xcrun", "--find", "ld"]))
            evidence["platform_linker"] = {"path": str(linker), "sha256": sha256(linker)}
            evidence["sdk"] = {"path": str(sdk), "version": probe(["xcrun", "--show-sdk-version"])}
            sysroot_files = [sdk / "SDKSettings.json", sdk / "usr/lib/libSystem.tbd",
                             sdk / "usr/include/stdlib.h"]
            evidence["execution"] = "Native macOS ARM64 host; not Linux target proof"
        evidence["sysroot_files"] = {str(path): sha256(path) for path in sysroot_files}
        evidence["target"] = probe([str(clang), "-dumpmachine"])
        evidence["llvm_targets"] = probe([str(binaries["llvm"] / "llvm-config"), "--targets-built"])
        for path in tools:
            evidence["executables"][str(path)] = {
                "sha256": sha256(path), "version": probe([str(path), "--version"]),
            }
        if arguments.sanitizers:
            runtime = Path(probe([str(clang), "--print-runtime-dir"]))
            runtime_files = set(runtime.glob("libclang_rt.*asan*"))
            runtime_files.update(runtime.glob("libclang_rt.*ubsan*"))
            if not runtime_files:
                raise RuntimeError("The selected compiler has no sanitizer runtime artifacts")
            evidence["sanitizer_runtime_files"] = {
                str(path): sha256(path) for path in sorted(runtime_files) if path.is_file()}
        for number, command in enumerate(commands, 1):
            print(subprocess.list2cmdline(command), flush=True)
            log = build / f"step-{number}.log"
            with log.open("w") as stream:
                result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                        env=environment)
            print(log.read_text(), flush=True)
            evidence["steps"].append(
                {"command": command, "exit_status": result.returncode, "log": str(log)})
            if result.returncode:
                raise subprocess.CalledProcessError(result.returncode, command)
            if number == 3:
                evidence["first_build"] = binary_hashes()
                if arguments.sanitizers:
                    command = [str(build / "mettle"), "--version"]
                    evidence["sanitizer_startup"] = {
                        "command": command, "timeout_seconds": 15, "status": "in_progress"}
                    try:
                        evidence["sanitizer_startup"]["output"] = probe(command, timeout=15)
                    except Exception:
                        evidence["sanitizer_startup"]["status"] = "failed"
                        raise
                    evidence["sanitizer_startup"]["status"] = "passed"
                executable = str(build / "mettle-object-smoke")
                report = probe(["ldd", executable] if selected == "linux-x86_64"
                               else ["otool", "-L", executable])
                evidence["runtime_dependency_report"] = report
                evidence["runtime_dependency_hashes"] = {
                    path: sha256(Path(path))
                    for path in sorted(set(re.findall(r"(/[^\s()]+)", report)))
                    if Path(path).is_file()
                }
                if arguments.configuration == "Debug":
                    evidence["debug_information_verification"] = probe(
                        [str(binaries["llvm"] / "llvm-dwarfdump"), "--verify",
                         str(build / "CMakeFiles/mettle.dir/compiler/driver/main.cpp.o")])
        evidence["rebuilt_artifacts"] = binary_hashes()
        if evidence["rebuilt_artifacts"] != evidence["first_build"]:
            raise RuntimeError("Clean rebuild changed compiler artifacts in the same environment")
        evidence["clean_rebuild_byte_identical"] = True
        evidence["status"] = "passed"
    except Exception as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
        raise
    finally:
        manifest.write_text(json.dumps(evidence, indent=2) + "\n")


if __name__ == "__main__":
    main()
