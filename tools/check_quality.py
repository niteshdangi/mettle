#!/usr/bin/env python3
"""Check repository quality policies; optionally build, analyze and run CTest."""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

if __package__:
    from .bootstrap import ROOT, artifacts, host_platform, sha256
    from .check_modules import include_failures, module_failures
else:
    from bootstrap import ROOT, artifacts, host_platform, sha256
    from check_modules import include_failures, module_failures


EXCLUDED = {".git", ".tools", "build", "__pycache__", "vendor", "third_party"}
CPP = {".cpp", ".h", ".hpp", ".cc", ".cxx", ".c"}
TEXT = CPP | {".py", ".md", ".mt", ".cmake", ".yaml", ".yml"}
CONFIG = {"CMakeLists.txt", ".clang-format", ".clang-tidy", ".editorconfig", ".gitignore"}


def owned_files(root):
    root = Path(root)
    for directory, children, files in os.walk(root):
        children[:] = sorted(name for name in children if name not in EXCLUDED and
                             not (Path(directory) / name).is_symlink())
        for name in sorted(files):
            path = Path(directory) / name
            if path.suffix in TEXT or name in CONFIG:
                yield path


def text_failures(path, root):
    path, root = Path(path), Path(root).resolve()
    relative = str(path.relative_to(root))
    if not path.resolve().is_relative_to(root):
        return [f"{relative}: source symlink escapes the project"]
    data = path.read_bytes()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return [f"{relative}: source must be UTF-8"]
    failures = []
    if "\r" in text:
        failures.append(f"{relative}: use LF line endings")
    if text and not text.endswith("\n"):
        failures.append(f"{relative}: missing final newline")
    for number, line in enumerate(text.splitlines(), 1):
        if line.rstrip(" \t") != line:
            failures.append(f"{relative}:{number}: trailing whitespace")
        if "\t" in line[:len(line) - len(line.lstrip(" \t"))]:
            failures.append(f"{relative}:{number}: use spaces for indentation")
    if path.suffix == ".py":
        try:
            compile(text, str(path), "exec")
        except SyntaxError as error:
            failures.append(f"{relative}:{error.lineno}: Python syntax: {error.msg}")
    return failures


def snapshot(root):
    paths = set(owned_files(root))
    paths.update(path for pattern in (
        "tools/toolchain-artifacts.json", "docs/toolchain-pins.json", "compiler/modules.json",
        "docs/capabilities.csv", "docs/baseline/supporting-protocols.json",
        "examples/**/expectations.json") for path in root.glob(pattern))
    return {str(path.relative_to(root)): sha256(path) for path in sorted(paths)}


def cache_entries(path):
    result = {}
    for line in path.read_text().splitlines():
        match = re.match(r"([^#/:][^:]*):[^=]+=(.*)$", line)
        if match:
            result[match[1]] = match[2]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path,
                        help="also rebuild, run clang-tidy and execute CTest in this configuration")
    args = parser.parse_args()
    scope = "fast" if args.build_dir is None else args.build_dir.resolve().name
    output = ROOT / "build/quality" / scope
    output.mkdir(parents=True, exist_ok=True)
    evidence = {"scope": "repository quality" if args.build_dir is None else "repository and native build quality",
                "status": "in_progress", "source_inputs": {}, "tools": {}, "steps": [],
                "limitations": ["Direct include checks are not a full dependency graph",
                               "No target/reproducibility/runtime-parity qualification implied"]}
    environment = os.environ.copy()

    def run(title, command, timeout=600):
        begin = time.perf_counter()
        log = output / f"step-{len(evidence['steps']) + 1}.log"
        timed_out = False
        with log.open("w") as stream:
            try:
                result = subprocess.run(list(map(str, command)), cwd=ROOT, stdout=stream,
                                        stderr=subprocess.STDOUT, timeout=timeout, env=environment)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = None
                timed_out = True
        evidence["steps"].append({"name": title, "command": list(map(str, command)),
                                  "exit_status": code, "timed_out": timed_out,
                                  "elapsed_seconds": time.perf_counter() - begin,
                                  "log": str(log), "log_sha256": sha256(log)})
        if timed_out or code:
            print(log.read_text(errors="replace")[-12000:], file=sys.stderr)
            reason = f"startup/check timed out after {timeout}s" if timed_out else f"exit {code}"
            raise RuntimeError(f"{title} failed ({reason})")
        print(f"{title}: passed", flush=True)

    try:
        files = list(owned_files(ROOT))
        failures = module_failures(ROOT)
        if failures:
            raise RuntimeError("\n".join(failures))
        for path in files:
            text_errors = text_failures(path, ROOT)
            failures.extend(text_errors)
            if not text_errors:
                failures.extend(include_failures(path, ROOT))
        if failures:
            raise RuntimeError("\n".join(failures[:50]))
        evidence["source_inputs"] = snapshot(ROOT)
        evidence["authored_files_checked"] = len(files)
        selected = host_platform()
        items = artifacts(selected)
        prefix = ROOT / ".tools" / selected

        def tool(package, name):
            item = items[package]
            marker = prefix / package / ".artifact.json"
            if not marker.is_file() or json.loads(marker.read_text()) != item:
                raise RuntimeError(f"Unrecognized/missing pinned {package}; run tools/bootstrap.py")
            executable = prefix / package / item["bin"] / name
            if not executable.is_file():
                raise RuntimeError(f"Missing selected tool: {executable}")
            version = subprocess.check_output([str(executable), "--version"], text=True).strip()
            if item["version"] not in version:
                raise RuntimeError(f"Tool version differs from the artifact lock: {executable}")
            evidence["tools"][name] = {"path": str(executable), "version": version,
                                      "sha256": sha256(executable), "archive_sha256": item["sha256"]}
            return executable

        formatter = tool("llvm", "clang-format")
        run("C++ formatting", [formatter, "--dry-run", "--Werror",
                              *[path for path in files if path.suffix in CPP]])
        run("Quality-rule regressions", [sys.executable, "-m", "unittest", "discover",
                                         "-s", "tests", "-p", "test_quality.py"])
        run("Specification-rule regressions", [sys.executable, "-m", "unittest", "discover",
                                               "-s", "docs/baseline", "-p", "test_*.py"])
        run("Specification audit", [sys.executable, ROOT / "docs/baseline/validate.py"])
        if args.build_dir is not None:
            build = args.build_dir.resolve()
            if not build.is_relative_to(ROOT / "build"):
                raise RuntimeError("Select a project build directory beneath build/")
            cache = cache_entries(build / "CMakeCache.txt")
            clang = prefix / "llvm" / items["llvm"]["bin"] / "clang++"
            if (Path(cache.get("CMAKE_HOME_DIRECTORY", "")).resolve() != ROOT or
                    Path(cache.get("CMAKE_CXX_COMPILER", "")).resolve() != clang.resolve()):
                raise RuntimeError("Build directory belongs to another project or compiler")
            evidence["build_directory"] = str(build)
            evidence["sanitizers"] = cache.get("METTLE_ENABLE_SANITIZERS") == "ON"
            if evidence["sanitizers"]:
                environment["ASAN_OPTIONS"] = "halt_on_error=1:abort_on_error=0:exitcode=99"
                environment["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1:exitcode=99"
                evidence["sanitizer_options"] = {
                    name: environment[name] for name in ("ASAN_OPTIONS", "UBSAN_OPTIONS")}
            cmake, ctest = tool("cmake", "cmake"), tool("cmake", "ctest")
            tidy = tool("llvm", "clang-tidy")
            run("Native build", [cmake, "--build", build, "--parallel", "4"])
            if evidence["sanitizers"]:
                run("Sanitizer runtime startup", [build / "mettle", "--version"], timeout=15)
            database = json.loads((build / "compile_commands.json").read_text())
            compiled = set()
            owned_cpp = {path.resolve() for path in files if path.suffix in CPP}
            for entry in database:
                path = Path(entry["file"])
                if not path.is_absolute():
                    path = Path(entry["directory"]) / path
                if path.resolve() in owned_cpp:
                    compiled.add(path.resolve())
            if not compiled:
                raise RuntimeError("Build has no owned C++ compilation commands")
            for path in sorted(compiled):
                run("Static analysis: " + str(path.relative_to(ROOT)),
                    [tidy, path, "-p", build, "--config-file=" + str(ROOT / ".clang-tidy"),
                     "--quiet"])
            run("CTest", [ctest, "--test-dir", build, "--output-on-failure"])
            evidence["compilation_database_sha256"] = sha256(build / "compile_commands.json")
            evidence["compiler_sha256"] = sha256(build / "mettle")
        after = snapshot(ROOT)
        if after != evidence["source_inputs"]:
            raise RuntimeError("Inputs changed during quality checks; rerun against the final revision")
        validation = json.loads((ROOT / "docs/baseline/validation.json").read_text())
        evidence["specification_sha256"] = validation["documentation_sha256"]
        evidence["status"] = "passed"
    except Exception as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
        print(f"Quality gate failed: {error}", file=sys.stderr)
        raise SystemExit(1)
    finally:
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"Quality evidence: {output / 'evidence.json'}")


if __name__ == "__main__":
    main()
