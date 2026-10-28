#!/usr/bin/env python3
"""Validate compiler ownership, dependency DAG and direct public-header boundaries."""

import json
import re
import sys
from pathlib import Path, PurePosixPath

CPP = {".cpp", ".h", ".hpp", ".cc", ".cxx", ".c"}


def manifest(root):
    data = json.loads((Path(root) / "compiler/modules.json").read_text())
    if data.get("schema") != 1 or not isinstance(data.get("modules"), list):
        raise ValueError("expected module manifest schema 1")
    return data["modules"]


def module_failures(root):
    root = Path(root).resolve()
    try:
        modules = manifest(root)
    except (OSError, ValueError, KeyError) as error:
        return [f"Invalid compiler module manifest: {error}"]
    failures, names, files = [], {}, {}
    executables = []
    for module in modules:
        name = module.get("name", "")
        if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or name in names:
            failures.append(f"Invalid/duplicate compiler component: {name}")
        names[name] = module
        directory = module.get("directory", "")
        if not directory or PurePosixPath(directory).is_absolute() or ".." in PurePosixPath(directory).parts:
            failures.append(f"{name}: invalid component directory")
        kind = module.get("kind")
        if kind not in {"STATIC", "INTERFACE", "EXECUTABLE"}:
            failures.append(f"{name}: invalid component target kind")
        if kind == "EXECUTABLE":
            executables.append(name)
        if module.get("llvm") and name not in {"backend_llvm", "driver"}:
            failures.append(f"{name}: LLVM is only allowed in its adapter/driver")
        dependencies = module.get("dependencies", [])
        if len(set(dependencies)) != len(dependencies):
            failures.append(f"{name}: duplicate component dependency")
        members = module.get("files", [])
        if not members:
            failures.append(f"{name}: empty components are not architecture")
        if kind in {"STATIC", "EXECUTABLE"} and not any(
                PurePosixPath(member).suffix in {".cpp", ".cc", ".cxx", ".c"} for member in members):
            failures.append(f"{name}: compiled component has no implementation")
        for member in members:
            path = PurePosixPath(member)
            if (path.is_absolute() or ".." in path.parts or path.as_posix() != member or
                    not path.is_relative_to(PurePosixPath(directory)) or path.suffix not in CPP):
                failures.append(f"{name}: invalid source membership {member}")
                continue
            actual = root / "compiler" / member
            if not actual.is_file() or not actual.resolve().is_relative_to(root / "compiler"):
                failures.append(f"{name}: missing/escaping source {member}")
            if member in files:
                failures.append(f"{member}: source belongs to multiple components")
            files[member] = name
            if kind == "INTERFACE" and path.suffix not in {".h", ".hpp"}:
                failures.append(f"{name}: interface component contains compiled source")
        for header in module.get("public_headers", []):
            if header not in members or PurePosixPath(header).suffix not in {".h", ".hpp"}:
                failures.append(f"{name}: public header is not an owned header: {header}")
    if executables != ["driver"]:
        failures.append("The compiler driver must be the sole production executable component")
    pending = {}
    for name, module in names.items():
        dependencies = set(module.get("dependencies", []))
        if dependencies - names.keys():
            failures.append(f"{name}: unknown component dependencies {sorted(dependencies - names.keys())}")
        pending[name] = dependencies
    while pending:
        ready = {name for name, dependencies in pending.items() if not dependencies}
        if not ready:
            failures.append(f"Compiler dependency cycle or unresolved dependency: {sorted(pending)}")
            break
        pending = {name: dependencies - ready for name, dependencies in pending.items() if name not in ready}
    actual_files = {str(path.relative_to(root / "compiler"))
                    for path in (root / "compiler").rglob("*")
                    if path.is_file() and path.suffix in CPP}
    for member in sorted(actual_files - files.keys()):
        failures.append(f"{member}: compiler source has no component owner")
    return failures


def include_failures(path, root, modules=None):
    path, root = Path(path).resolve(), Path(root).resolve()
    relative = path.relative_to(root)
    if path.suffix not in CPP or relative.parts[0] not in {"compiler", "runtime", "library"}:
        return []
    modules = manifest(root) if modules is None else modules
    owners = {member: module for module in modules for member in module["files"]}
    member = str(path.relative_to(root / "compiler")) if relative.parts[0] == "compiler" else ""
    owner = owners.get(member)
    failures = []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        include = re.match(r'\s*#\s*include\s*[<"]([^>"]+)[>"]', line)
        if not include:
            continue
        name = include[1].replace("\\", "/")
        if PurePosixPath(name).is_absolute():
            failures.append(f"{relative}:{number}: nonportable absolute include '{name}'")
            continue
        if name.startswith("."):
            target = (path.parent / name).resolve()
        else:
            target = (root / "compiler" / name.removeprefix("compiler/")).resolve()
        target_member = str(target.relative_to(root / "compiler")) if target.is_relative_to(root / "compiler") else ""
        dependency = owners.get(target_member)
        llvm = name.startswith("llvm/")
        if owner is None:
            if dependency or llvm:
                failures.append(f"{relative}:{number}: runtime/library cannot include compiler/LLVM headers")
        elif llvm and not owner.get("llvm"):
            failures.append(f"{relative}:{number}: LLVM is forbidden in {owner['name']}")
        elif dependency is not None and dependency["name"] != owner["name"]:
            if dependency["name"] not in owner["dependencies"]:
                failures.append(f"{relative}:{number}: undeclared dependency on {dependency['name']}")
            if target_member not in dependency["public_headers"]:
                failures.append(f"{relative}:{number}: private header of {dependency['name']}")
    return failures


def check(root):
    root = Path(root).resolve()
    failures = module_failures(root)
    if failures:
        return failures
    modules = manifest(root)
    for module in modules:
        for member in module["files"]:
            failures.extend(include_failures(root / "compiler" / member, root, modules))
    for directory in ("runtime", "library"):
        for path in (root / directory).rglob("*"):
            if path.is_file() and path.suffix in CPP:
                failures.extend(include_failures(path, root, modules))
    return failures


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
    failures = check(root)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print("Compiler module ownership, public headers and dependency DAG: passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
