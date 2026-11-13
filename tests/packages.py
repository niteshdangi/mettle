#!/usr/bin/env python3
"""Package manifest, resolution, lock, feature and offline regressions.

Usage: packages.py MettleExecutable EvidenceDir FixturesDir [REGEX] [-j N]
"""

import argparse
import hashlib
import json
import os
import re
import select
import shutil
import subprocess
import sys
import time
from pathlib import Path

import processes
import scheduling

COMMANDS = []


def reset():
    shutil.rmtree(evidence, ignore_errors=True)
    shutil.copytree(fixtures, evidence)


def invoke_result(arguments):
    environment = {**os.environ, "METTLE_CACHE_DIR": str(evidence / "cache")}
    command = [str(mettle), *map(str, arguments)]
    begin = time.perf_counter()
    result = processes.run(command, text=True, capture_output=True, env=environment)
    COMMANDS.append({"command": command, "exit_status": result.returncode,
                     "elapsed_seconds": time.perf_counter() - begin,
                     "stdout": result.stdout, "stderr": result.stderr})
    return result


def invoke(arguments, expected=0, contains=()):
    result = invoke_result(arguments)
    text = result.stdout + result.stderr
    if result.returncode != expected:
        raise AssertionError(f"{arguments}: expected {expected}, got "
                             f"{result.returncode}\n{text}")
    for needle in ([contains] if isinstance(contains, str) else contains):
        if needle not in text:
            raise AssertionError(f"{arguments}: missing {needle!r}\n{text}")
    return text


def invoke_json(arguments, expected=0):
    result = invoke_result(arguments)
    if result.returncode != expected:
        raise AssertionError(f"{arguments}: expected {expected}, got "
                             f"{result.returncode}\n"
                             f"{result.stdout}{result.stderr}")
    if result.stderr:
        raise AssertionError(f"{arguments}: unexpected stderr\n{result.stderr}")
    return [json.loads(line) for line in result.stdout.splitlines()]


def build_and_run(directory, *extra):
    output = evidence / "out.bin"
    output.unlink(missing_ok=True)
    invoke(["build", directory, "-o", output, *extra])
    result = processes.run([str(output)])
    assert result.returncode == 0, f"{directory}: program exited {result.returncode}"


def explained(directory, *extra, expected=0, contains=()):
    """Builds with the cache log; returns (log, output path)."""
    output = evidence / "out.bin"
    output.unlink(missing_ok=True)
    text = invoke(["build", directory, "-o", output, "--explain", *extra],
                  expected, contains)
    return text, output


def last_cache_event(text):
    """The cache line of the program itself (scripts compile before it)."""
    lookups = ("mettle: cache hit", "mettle: cache miss", "mettle: cache entry")
    events = [line for line in text.splitlines() if line.startswith(lookups)]
    return events[-1] if events else ""


def exit_code(program):
    return processes.run([str(program)]).returncode


def cache_files(kind):
    return [path for path in (evidence / "cache" / kind).rglob("*")
            if path.is_file()]


def cache_bytes():
    return sum(path.stat().st_size
               for kind in ("entries", "blobs") for path in cache_files(kind))


def edit(path, old, new):
    text = path.read_text()
    assert old in text, (path, old)
    path.write_text(text.replace(old, new))


def packages(name):
    return evidence / name


def lock_of(directory):
    return (directory / "lock.mettle").read_text()


def path_dependency():
    app = packages("path-dependency/app")
    build_and_run(app)
    lock = lock_of(app)
    assert 'name: "units"' in lock and "sha256:" in lock, lock
    build_and_run(app, "--locked")
    assert lock_of(app) == lock, "an unchanged build rewrote the lock"
    invoke(["check", app, "--frozen"])
    edit(packages("path-dependency/units/src/main.mt"), "21", "21 + 0")
    invoke(["build", app, "--locked", "-o", evidence / "x"], 1,
           ["--locked", "units"])
    invoke(["check", app])
    assert lock_of(app) != lock, "the lock was not refreshed"
    invoke(["check", app, "--locked"])


def restricted_dependency_visibility():
    app = packages("path-dependency/app")
    library = packages("path-dependency/units/src/main.mt")
    library.write_text("pub(units) fn secret(): i32 { 21 }\n"
                       "pub fn base(): i32 { secret() }\n")
    build_and_run(app)
    main = app / "src/main.mt"
    main.write_text("import units.secret\nfn main(): i32 { secret() }\n")
    text = invoke(["check", app], 1,
                  ["error[name]", "unresolved, inaccessible, ambiguous or "
                   "cyclic import"])
    assert re.search(r"main\.mt:1:1", text), text


def package_name_roots_own_modules():
    app = packages("path-dependency/app")
    (app / "src/main.mt").write_text(
        "module inner {\n    import path_app.helper.value\n"
        "    pub fn get(): i32 { value() }\n}\n"
        "fn main(): i32 { inner.get() - 42 }\n")
    (app / "src/helper.mt").write_text("pub fn value(): i32 { 42 }\n")
    build_and_run(app)
    (app / "src/main.mt").write_text("import package.helper.value\n"
                                     "fn main(): i32 { value() - 42 }\n")
    invoke(["check", app], 1, "use the package name `path_app` instead")
    manifest = app / "package.mettle"
    manifest.write_text(manifest.read_text().replace(
        "mathlib: \"../mathlib\"", "mathlib: \"../mathlib\"\n    path-app: \"../mathlib\""))
    text = invoke(["check", app], 1, "has the name of its own package")
    assert re.search(r"package\.mettle:\d+:\d+", text), text


def nested_dependency_imports():
    app = packages("path-dependency/app")
    library = packages("path-dependency/mathlib/src")
    (app / "src/main.mt").write_text("import client.answer\nfn main(): i32 { answer() - 42 }\n")
    (app / "src/client.mt").write_text("import mathlib.answer as library_answer\npub fn answer(): i32 { library_answer() }\n")
    (library / "main.mt").write_text("pub import nested.value as answer\n")
    units = packages("path-dependency/units/src/main.mt")
    units.write_text(units.read_text() + "\npub macro number { () => { 21 }; }\n")
    (library / "nested.mt").write_text(
        "import units.base\nimport units.number\n"
        "pub fn value(): i32 { base() + units.base() + number!() - 21 }\n")
    build_and_run(app)
    (library / "nested.mt").write_text(
        "module units { pub fn base(): i32 { 100 } }\n"
        "pub fn value(): i32 { self.units.base() - units.base() - 37 }\n")
    build_and_run(app)
    app = packages("registry-resolution/app")
    shapes = packages("registry/shapes/1.2.0/src")
    (shapes / "main.mt").write_text("pub import nested.corners\n")
    (shapes / "nested.mt").write_text(
        "import util.value\npub fn corners(): i32 { value() }\n")
    build_and_run(app)


def configured_entry():
    app = packages("path-dependency/app")
    manifest = app / "package.mettle"
    manifest.write_text('name: "path-app"\nversion: "0.1.0"\nentry: "app.mt"\n'
                        'dependencies { mathlib: "../mathlib" }\n')
    (app / "app.mt").write_text((app / "src/main.mt").read_text())
    build_and_run(app)
    (app / "inspect.mt").write_text("fn main(): i32 { 42 }\n")
    original = manifest.read_text()
    manifest.write_text(original.replace('entry: "app.mt"',
        'entry { main: "app.mt", inspect: "inspect.mt" }'))
    build_and_run(app)
    output = evidence / "inspect"
    invoke(["build", app, "--entry", "inspect", "-o", output])
    assert exit_code(output) == 42
    for field in ('targets {}', 'entries {}', 'language: "0.0.0"'):
        manifest.write_text(original + field + '\n')
        invoke(["check", app], 1, "unknown key")
    for value in ('{ kind: "executable", source: "inspect.mt" }', 'none', '""'):
        manifest.write_text(original.replace('entry: "app.mt"',
            f'entry {{ main: "app.mt", inspect: {value} }}'))
        invoke(["check", app], 1, "error[package]")
    manifest.write_text(original.replace('entry: "app.mt"', 'entry: ""'))
    invoke(["check", app], 1, "nonempty path")
    manifest.write_text(original.replace('entry: "app.mt"', 'entry { inspect: "inspect.mt" }'))
    invoke(["check", app], 1, "an entry map must define 'main'")


def mettle_version():
    app = packages("path-dependency/app")
    manifest = app / "package.mettle"
    original = manifest.read_text()
    current = re.search(r"\b(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)", invoke(["--version"])).group(1)
    manifest.write_text(original + f'mettle-version: "{current}"\n')
    invoke(["check", app])
    for value in ('"1"', '"mettle-1"', '"^1.0.0"', '1', 'none'):
        manifest.write_text(original + f'mettle-version: {value}\n')
        invoke(["check", app], 1, ["error[package]", "mettle-version"])
    future = str(int(current.split('.')[0]) + 1) + ".0.0"
    manifest.write_text(original + f'mettle-version: "{future}"\n')
    text = invoke(["check", app], 1, ["error[feature]", f"requires Mettle {future}"])
    assert re.search(r"package\.mettle:\d+:\d+: error\[feature\]", text), text
    manifest.write_text(original)
    dependency = packages("path-dependency/units/package.mettle")
    dependency.write_text(dependency.read_text() + f'mettle-version: "{future}"\n')
    invoke(["check", app], 1, ["error[feature]", "package 'units'"])


def library_entries():
    app = packages("path-dependency/app")
    manifest = app / "package.mettle"
    original = 'name: "native-library"\nversion: "1.0.0"\nkind: "library"\n'
    manifest.write_text(original)
    (app / "src/main.mt").write_text('@export_name("mettle_answer")\nextern "C" fn answer(value: i32): i32 { value + 2 }\n')
    invoke(["check", app])
    cxx = os.environ.get("CXX") or shutil.which("clang++")
    assert cxx, "the pinned Clang C++ linker must be on PATH or CXX"
    caller = evidence / "caller.cpp"
    caller.write_text('extern "C" int mettle_answer(int);\nint main() { return mettle_answer(40) - 42; }\n')
    shared_suffix = ".dylib" if sys.platform == "darwin" else ".so"
    for profile in ("debug", "release"):
        prefix = evidence / ("native-" + profile)
        manifest.write_text(original + 'emit: ["static", "shared", "llvm"]\n')
        invoke(["build", app, "-o", prefix, "--profile", profile])
        for suffix in (".a", shared_suffix):
            executable = evidence / ("caller-" + profile + suffix)
            result = processes.run([cxx, "-fuse-ld=lld", str(caller), str(prefix) + suffix,
                                     "-Wl,-rpath," + str(prefix.parent), "-pthread", "-o", str(executable)], capture_output=True, text=True)
            assert result.returncode == 0, result.stderr
            assert exit_code(executable) == 0
        assert 'define i32 @main(' not in Path(str(prefix) + ".ll").read_text()
    invoke(["run", app], 1, "a library entry cannot emit an executable")
    invoke(["build", app, "--emit", "executable", "-o", evidence / "bad"], 1,
           "a library entry cannot emit an executable")
    invoke(["build", app, "--emit", "package", "-o", evidence / "bad"], 1,
           "error[feature]")
    manifest.write_text(original + 'emit: "package"\n')
    invoke(["check", app])
    manifest.write_text(original)
    freestanding = evidence / "freestanding.a"
    invoke(["build", app, "-o", freestanding, "--freestanding", "--cc", "missing-mettle-linker"])
    result = processes.run([cxx, "-fuse-ld=lld", str(caller), str(freestanding), "-o", str(evidence / "freestanding")],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert exit_code(evidence / "freestanding") == 0
    prefix = evidence / "preserved"
    Path(str(prefix) + ".ll").write_text("existing output")
    manifest.write_text(original + 'emit: ["llvm", "shared"]\n')
    invoke(["build", app, "--cc", "missing-mettle-linker", "-o", prefix], 1, "error[link]")
    assert Path(str(prefix) + ".ll").read_text() == "existing output"
    manifest.write_text('name: "native-library"\nversion: "1.0.0"\nentry {\n'
                        'main { kind: "library", path: "src/main.mt" }\n'
                        'inspect: "inspect.mt"\n}\n')
    (app / "inspect.mt").write_text("fn main(): i32 { 42 }\n")
    output = evidence / "inspect"
    invoke(["build", app, "--entry", "inspect", "-o", output])
    assert exit_code(output) == 42
    invoke(["build", app, "--entry", "inspect", "--emit", "static", "-o", output], 1,
           "library emission requires a library entry")
    for field in ('kind: "library"', 'emit: "object"'):
        manifest.write_text(manifest.read_text() + field + '\n')
        invoke(["check", app], 1, "declares 'kind' and 'emit' per entry")
        manifest.write_text(manifest.read_text().rsplit(field, 1)[0])
    for field in ('emit: []', 'emit: ["static", "static"]', 'emit: "executable"', 'kind: "bad"'):
        manifest.write_text('name: "native-library"\nversion: "1.0.0"\n' +
                            ('kind: "library"\n' if not field.startswith('kind:') else '') + field + '\n')
        invoke(["check", app], 1, "error[package]")


def development_dependencies():
    app = packages("path-dependency/app")
    manifest = app / "package.mettle"
    original = manifest.read_text()
    manifest.write_text(original + 'dev-dependencies { extra: "../../features/extra" }\n')
    (app / "src/main.mt").write_text('fn main(): i32 { 0 }\n')
    current = re.search(r"\b(\d+)\.\d+\.\d+", invoke(["--version"]))
    future = str(int(current.group(1)) + 1) + ".0.0"
    extra = packages("features/extra/package.mettle")
    extra.write_text(extra.read_text() + f'mettle-version: "{future}"\n')
    invoke(["check", app])
    for command in ("test", "bench"):
        invoke([command, app], 1, ["error[feature]", f"package 'extra' requires Mettle {future}"])
    (app / "src/main.mt").write_text('import extra.value\nfn main(): i32 { value() }\n')
    invoke(["check", app], 1, "error[name]")


def missing_lock_locked():
    app = packages("path-dependency/app")
    invoke(["check", app, "--locked"], 1, "lock.mettle")
    assert not (app / "lock.mettle").exists()


def lock_corruption():
    app = packages("path-dependency/app")
    invoke(["check", app])
    lock = lock_of(app)
    (app / "lock.mettle").write_text(lock + "broken {\n")
    invoke(["check", app], 1, "lock.mettle")
    (app / "lock.mettle").write_text(lock)
    edit(app / "lock.mettle", 'version: 3\n', 'version: 99\n')
    invoke(["check", app], 1, "lock.mettle")


def registry_resolution():
    app = packages("registry-resolution/app")
    build_and_run(app)
    lock = lock_of(app)
    assert 'version: "1.2.0"' in lock and 'version: "1.3.0"' in lock, lock
    assert "1.4.0" not in lock, "a yanked version was selected"
    # A new release does not move a locked package.
    new = packages("registry/util/1.3.5")
    shutil.copytree(packages("registry/util/1.3.0"), new)
    edit(new / "package.mettle", "1.3.0", "1.3.5")
    edit(new / "src/main.mt", "13", "99")
    build_and_run(app, "--locked")
    assert lock_of(app) == lock
    data = packages("registry/util/1.3.0/spec.txt")
    data.write_text("changed build input\n")
    invoke(["check", app, "--locked"], 1, "checksum mismatch")
    data.unlink()
    linked = packages("registry/util/1.3.0/linked")
    linked.symlink_to(evidence, target_is_directory=True)
    invoke(["check", app, "--locked"], 1, "source link outside")
    linked.unlink()
    # Tampering with a locked registry package is always rejected.
    edit(packages("registry/util/1.3.0/src/main.mt"), "13", "13 + 0")
    invoke(["check", app], 1, "checksum mismatch")
    invoke(["check", app, "--locked"], 1, "checksum mismatch")


def version_conflict():
    app = packages("resolution/app")
    edit(packages("resolution/right/package.mettle"), "=1.0.0", "^2")
    invoke(["check", app], 0)
    lock = lock_of(app)
    assert 'name: "util"\n        version: "1.3.0"' in lock, lock
    assert 'name: "util"\n        version: "2.0.0"' in lock, lock
    edit(packages("resolution/right/package.mettle"), "^2", "=1.0.0")
    (app / "lock.mettle").unlink()


def wildcard_version_bounds():
    app = evidence / "wildcard-app"
    (app / "src").mkdir(parents=True)
    (app / "src/main.mt").write_text("fn main(): i32 { 0 }\n")
    release = packages("registry/util/1.2.0")
    shutil.copytree(packages("registry/util/1.3.0"), release)
    edit(release / "package.mettle", "1.3.0", "1.2.0")
    manifest = app / "package.mettle"
    for requirement, expected in (("1.2.*", "1.2.0"), ("1.2.x", "1.2.0"),
                                  ("1.*", "1.3.0"), ("1.2", "1.3.0")):
        manifest.write_text(
            'name: "wildcard-app"\nversion: "0.1.0"\n'
            'registry { path: "../registry" }\n'
            f'dependencies {{ util: "{requirement}" }}\n')
        (app / "lock.mettle").unlink(missing_ok=True)
        invoke(["check", app])
        assert f'version: "{expected}"' in lock_of(app), lock_of(app)
def backtracking():
    app = packages("resolution/app")
    build_and_run(app)
    lock = lock_of(app)
    assert 'name: "util"\n        version: "1.0.0"' in lock, lock


def cycle_backtracking():
    root = evidence / "cycle-backtracking"
    app = root / "app"
    (app / "src").mkdir(parents=True)
    (app / "src/main.mt").write_text("fn main(): i32 { 0 }\n")
    (app / "package.mettle").write_text(
        'name: "app"\nversion: "0.1.0"\nregistry { path: "../registry" }\n'
        'dependencies { alpha: "^1", beta: "^1" }\n')
    for name, version, dependencies in (
            ("alpha", "1.1.0", 'dependencies { beta: "^1" }\n'),
            ("alpha", "1.0.0", ""),
            ("beta", "1.0.0", 'dependencies { alpha: "^1" }\n')):
        package = root / "registry" / name / version
        (package / "src").mkdir(parents=True)
        (package / "src/main.mt").write_text("pub fn value(): i32 { 0 }\n")
        (package / "package.mettle").write_text(
            f'name: "{name}"\nversion: "{version}"\nkind: "library"\n' + dependencies)
    invoke(["check", app])
    lock = lock_of(app)
    assert 'name: "alpha"\n        version: "1.0.0"' in lock, lock
    assert 'version: "1.1.0"' not in lock, lock
    invoke(["check", app, "--locked"])
    manifest = root / "registry" / "alpha" / "1.0.0" / "package.mettle"
    manifest.write_text(manifest.read_text() + 'dependencies { beta: "^1" }\n')
    (app / "lock.mettle").unlink()
    invoke(["check", app], 1, [
        "dependency cycle: alpha 1.0.0 -> beta 1.0.0 -> alpha 1.0.0",
        "cyclic package compilation is not supported"])


def lock_publication_isolated():
    app = packages("path-dependency/app")
    sentinel = evidence / "unrelated-output"
    sentinel.write_bytes(b"preserve another writer's output")
    shared = app / "lock.mettle.tmp"
    shared.symlink_to(sentinel)
    invoke(["check", app])
    assert sentinel.read_bytes() == b"preserve another writer's output"
    expected = lock_of(app)
    (app / "lock.mettle").unlink()
    environment = {**os.environ, "METTLE_CACHE_DIR": str(evidence / "cache")}
    commands = [subprocess.Popen([str(mettle), "check", str(app)], env=environment,
                                 text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE) for _ in range(8)]
    try:
        for command in commands:
            stdout, stderr = command.communicate(timeout=90)
            assert command.returncode == 0, stdout + stderr
    finally:
        for command in commands:
            if command.poll() is None:
                command.kill()
                command.wait()
    assert lock_of(app) == expected
    assert sentinel.read_bytes() == b"preserve another writer's output"
    invoke(["check", app, "--locked"])


def offline():
    app = packages("registry-resolution/app")
    edit(app / "package.mettle", 'registry {\n    path: "../../registry"\n}\n', "")
    invoke(["check", app], 1, "no registry is configured")
    invoke(["check", app, "--offline"], 1, "no registry is configured")
    invoke(["check", app, "--offline", "--registry", evidence / "registry"], 0)
    app = packages("registry-resolution/app")
    edit(app / "package.mettle", 'shapes: "^1"', 'shapes: "^1"\nmissing: "^1"')
    invoke(["check", app, "--offline", "--registry", evidence / "registry"], 1,
           ["missing", "offline mode never fetches"])


def features():
    app = packages("features/app")
    # Root and dependency `@cfg` test their own resolved feature sets.
    build_and_run(app)
    build_and_run(app, "--features", "fancy")
    assert 'name: "extra"' in lock_of(app)
    invoke(["check", app, "--features", "nope"], 1, "no feature 'nope'")
    edit(app / "package.mettle", "default: []", 'default: ["fancy"]')
    build_and_run(app)
    build_and_run(app, "--no-default-features")
    main = app / "src/main.mt"
    edit(main, "@cfg(not(feature = \"fancy\"))\nfn main(): i32 { widget.base() - 100 }\n", "")
    edit(main, "@cfg(feature = \"fancy\")\n", "")
    invoke(["check", app, "--no-default-features"], 1, "unresolved value \'extra\'")


def coexisting_versions():
    app = packages("coexisting-versions/app")
    output = evidence / "out.bin"
    invoke(["build", app, "-o", output])
    result = processes.run([str(output)], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"{app}: program exited {result.returncode}")
    assert result.stdout == "alpha-1\nalpha-2\n", result.stdout
    lock = lock_of(app)
    assert 'name: "alpha"\n        version: "1.0.0"' in lock, lock
    assert 'name: "alpha"\n        version: "2.0.0"' in lock, lock


def git_source():
    app = packages("git-source/app")
    repository = packages("git-source/repository")
    repository.mkdir(parents=True)
    app.mkdir(parents=True)
    (repository / "src").mkdir()
    (app / "src").mkdir()
    (repository / "package.mettle").write_text(
        'name: "gitlib"\nversion: "0.1.0"\nkind: "library"\n'
        'dependencies { helper { path: "helper" } }\n')
    (repository / "src/main.mt").write_text("pub fn value(): i32 { 7 }\n")
    (repository / "helper/src").mkdir(parents=True)
    (repository / "helper/package.mettle").write_text(
        'name: "helper"\nversion: "0.1.0"\nkind: "library"\n')
    (repository / "helper/src/main.mt").write_text("pub fn value(): i32 { 1 }\n")
    (app / "src/main.mt").write_text(
        "fn main(): i32 { gitlib.value() - 7 }\n")
    processes.run(["git", "init", repository], check=True,
                   capture_output=True, text=True)
    processes.run(["git", "-C", repository, "checkout", "-b", "main"],
                   check=True, capture_output=True, text=True)
    processes.run(["git", "-C", repository, "config", "user.name",
                    "Mettle package test"], check=True, capture_output=True)
    processes.run(["git", "-C", repository, "config", "user.email",
                    "packages-test@example.invalid"], check=True,
                   capture_output=True)
    processes.run(["git", "-C", repository, "add", "package.mettle",
                    "src/main.mt", "helper"], check=True, capture_output=True)
    processes.run(["git", "-C", repository, "commit", "-m", "first"],
                   check=True, capture_output=True)
    first = processes.run(
        ["git", "-C", repository, "rev-parse", "HEAD"], check=True,
        capture_output=True, text=True).stdout.strip()
    processes.run(["git", "-C", repository, "branch", "other", first],
                   check=True, capture_output=True)
    processes.run(["git", "-C", repository, "tag", "first", first],
                   check=True, capture_output=True)
    (app / "package.mettle").write_text(
        'name: "git-app"\nversion: "0.1.0"\n'
        'dependencies {\n'
        f'    gitlib {{ git: "{repository.as_uri()}", branch: "main" }}\n'
        '}\n')
    build_and_run(app)
    lock = lock_of(app)
    assert first in lock and "sha256:" in lock, lock
    invoke(["check", app, "--locked", "--cache-dir", evidence / "other-cache"])
    assert lock_of(app) == lock
    invoke(["check", app, "--offline", "--locked"])
    edit(repository / "src/main.mt", "{ 7 }", "{ 8 }")
    processes.run(["git", "-C", repository, "add", "src/main.mt"],
                   check=True, capture_output=True)
    processes.run(["git", "-C", repository, "commit", "-m", "second"],
                   check=True, capture_output=True)
    invoke(["check", app, "--locked"], 1, "--locked forbids changing it")
    invoke(["check", app, "--offline", "--locked"])
    assert lock_of(app) == lock
    second = processes.run(
        ["git", "-C", repository, "rev-parse", "HEAD"], check=True,
        capture_output=True, text=True).stdout.strip()
    manifest = app / "package.mettle"
    original = manifest.read_text()
    for selector in ('branch: "other"', f'rev: "{first}"',
                     'tag: "first"', f'rev: "{second}"'):
        manifest.write_text(original.replace('branch: "main"', selector))
        invoke(["check", app, "--frozen"], 1, "--locked forbids changing it")
        assert lock_of(app) == lock
    manifest.write_text(original)
    invoke(["check", app, "--frozen"])
    (app / "lock.mettle").write_text(re.sub(
        r"^        git_selectors:.*\n", "",
        lock.replace("version: 3\n", "version: 2\n"), flags=re.MULTILINE))
    invoke(["check", app, "--frozen"], 1, "lock format requires")
    invoke(["check", app])
    assert lock_of(app).startswith(
        "// Generated by mettle; edit package.mettle to change dependencies.\n"
        "version: 3\n")
    invoke(["check", app, "--frozen"])


def git_concurrent_output():
    if os.name == "nt":
        print("SKIP git_concurrent_output: POSIX git wrapper")
        return
    root = evidence / "git-concurrent"
    root.mkdir()
    git = shutil.which("git")
    assert git
    barrier = root / "barrier"
    barrier.mkdir()
    wrapper = root / "git"
    wrapper.write_text(
        "#!/usr/bin/env python3\n"
        "import os, pathlib, subprocess, sys, time\n"
        "result = subprocess.run([os.environ['REAL_GIT'], *sys.argv[1:]], "
        "stdout=subprocess.PIPE)\n"
        "sys.stdout.buffer.write(result.stdout)\n"
        "sys.stdout.buffer.flush()\n"
        "if sys.argv[1:][-3:] == ['--verify', '--end-of-options', 'HEAD^{commit}']:\n"
        "    barrier = pathlib.Path(os.environ['GIT_BARRIER'])\n"
        "    (barrier / str(os.getpid())).touch()\n"
        "    deadline = time.monotonic() + 30\n"
        "    while len(list(barrier.iterdir())) < 2:\n"
        "        if time.monotonic() > deadline: sys.exit(2)\n"
        "        time.sleep(0.01)\n"
        "    time.sleep(0.1 if os.getpid() == "
        "min(int(p.name) for p in barrier.iterdir()) else 0.5)\n"
        "sys.exit(result.returncode)\n")
    wrapper.chmod(0o755)
    apps = []
    for name in ("first", "second"):
        repo, app = root / f"{name}-repo", root / f"{name}-app"
        (repo / "src").mkdir(parents=True)
        (repo / "package.mettle").write_text(
            f'name: "{name}"\nversion: "0.1.0"\nkind: "library"\n')
        (repo / "src/main.mt").write_text("pub fn value(): i32 { 0 }\n")
        processes.run([git, "init", repo], check=True, capture_output=True)
        processes.run([git, "-C", repo, "add", "."], check=True, capture_output=True)
        processes.run([git, "-C", repo, "-c", "user.name=Test", "-c",
                       "user.email=test@example.invalid", "commit", "-m", name],
                      check=True, capture_output=True)
        (app / "src").mkdir(parents=True)
        (app / "src/main.mt").write_text("fn main(): i32 { 0 }\n")
        (app / "package.mettle").write_text(
            f'name: "{name}-app"\nversion: "0.1.0"\n'
            f'dependencies {{ {name} {{ git: "{repo.as_uri()}" }} }}\n')
        apps.append(app)
    env = {**os.environ, "PATH": f"{root}{os.pathsep}{os.environ['PATH']}",
           "REAL_GIT": git, "GIT_BARRIER": str(barrier),
           "METTLE_CACHE_DIR": str(root / "cache")}
    commands = [subprocess.Popen([str(mettle), "check", str(app)], env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 text=True) for app in apps]
    try:
        results = [command.communicate(timeout=90) for command in commands]
    finally:
        for command in commands:
            if command.poll() is None:
                command.kill()
                command.wait()
    for command, (stdout, stderr) in zip(commands, results):
        assert command.returncode == 0, stdout + stderr


def host_target_separation():
    app = packages("host-target-separation/app")
    build_and_run(app)
    lock = lock_of(app)
    assert ('name: "helper"' in lock and '"host"' in lock and
            '"target"' in lock), lock


def manifest_diagnostics():
    app = packages("path-dependency/app")
    manifest = app / "package.mettle"
    original = manifest.read_text()
    manifest.write_text(original.replace("name:", "name =", 1))
    invoke(["check", app], 1, "package.mettle:1")
    manifest.write_text(original.replace('name: "path-app"',
                                         'name: "path-app"\nbogus: 1'))
    invoke(["check", app], 1, "bogus")
    manifest.write_text(original.replace(
        'mathlib: "../mathlib"',
        'mathlib { git: "https://example.invalid/x.git" }'))
    invoke(["check", app], 1, "git")
    manifest.write_text(original.replace(
        'mathlib: "../mathlib"',
        'mathlib { path: "../mathlib", version: "^1.q" }'))
    invoke(["check", app], 1, "version")
    manifest.write_text(original.replace('"../mathlib"', '"../nowhere"'))
    invoke(["check", app], 1, "nowhere")
    manifest.write_text(original)
    # A dependency cycle names the path.
    units = packages("path-dependency/units/package.mettle")
    units.write_text(units.read_text() + 'dependencies { mathlib: "../mathlib" }\n')
    invoke(["check", app], 1, "mathlib 0.3.1 -> units 0.1.4 -> mathlib 0.3.1")


def data_format():
    app = packages("path-dependency/app")
    manifest = app / "package.mettle"
    original = manifest.read_text()
    manifest.write_text('/* outer /* nested */ comment */\r\n{\r\n' +
                        original.replace('"path-app"', '"path\\u{2d}app"')
                        .replace('"../mathlib"', '"..\\x2fmathlib"') +
                        ', // trailing comma\n}\n')
    invoke(["check", manifest])
    manifest.write_text(original)
    invoke(["check", app])
    cases = [
        ('name: "a"\nname: "b"\n', "duplicate key 'name'"),
        ('mettle-version: "0.0.0"\n"mettle-version": "1.0.0"\n', "duplicate key 'mettle-version'"),
        ('name: "a" version: "0.1.0"\n', "between entries"),
        ('name: "a"\nversion: ["0.1.0"\n', "unterminated list"),
        ('name: "a"\ndependencies {\n', "unterminated object"),
        ('name: "\\u{d800}"\n', "invalid Unicode scalar"),
        ('name: "\\u{110000}"\n', "invalid Unicode scalar"),
        ('name: "\\x80"\n', "text byte escape"),
        ('name: "\\q"\n', "invalid string escape"),
        ('name: "unterminated\n', "unescaped control character"),
        ('name: "a"\n/* unterminated', "unterminated block comment"),
        ('name: 1.\n', "digits after decimal point"),
        ('name: 1e+\n', "exponent digits"),
        ('name: 01\n', "invalid decimal number"),
        ('name: 9223372036854775808\n', "integer out of range"),
        ('name: ${ENV}\n', "expected a data value"),
        ('[package]\nname = "a"\n', "expected a data value"),
        ('description: ' + '[' * 130 + 'none' + ']' * 130, "nesting limit"),
    ]
    for text, message in cases:
        manifest.write_text(text)
        result = invoke(["check", app], 1, ["error[manifest]", message])
        assert re.search(r"package\.mettle:\d+:\d+: error\[manifest\]", result), result
    for value in ("none", "true", "1.5e-2", "-9223372036854775808"):
        manifest.write_text(f'name: {value}\nversion: "0.1.0"\n')
        invoke(["check", app], 1, ["error[package]", "'name' must be a string"])
    manifest.write_bytes(b'name: "\xff"\n')
    invoke(["check", app], 1, ["error[manifest]", "not valid UTF-8"])
    manifest.write_text(original.replace('mathlib: "../mathlib"', 'mathlib: "mathlib"'))
    invoke(["check", app], 1, "invalid version requirement")


def lock_structure():
    app = packages("path-dependency/app")
    invoke(["check", app])
    path = app / "lock.mettle"
    original = path.read_text()
    assert "packages: [" in original
    cases = [
        ('version: 2\npackages: [none]\n', "lock package must be an object"),
        ('version: 2\npackages: []\nbogus: true\n', "unknown lock key"),
        ('version: 2\npackages: none\n', "must be a list of objects"),
        ('version: 2\n', "must be a list of objects"),
        (original.replace('packages: [', 'packages: [\n{ id: "bad", name: "bad", version: "0.1.0", source: "root", dependencies: ["absent"] },', 1),
         "unknown locked dependency"),
    ]
    for text, message in cases:
        path.write_text(text)
        invoke(["check", app], 1, ["error[lock]", message])
    path.write_text(original)
    invoke(["check", app, "--locked"])
    assert path.read_text() == original


def incremental_reuse():
    app = packages("incremental/app")
    first, built = explained(app)
    assert "cache miss" in first and "cache stored" in first, first
    assert exit_code(built) == 0
    bytes_built = built.read_bytes()
    second, reused = explained(app)
    assert "cache hit" in second, second
    assert reused.read_bytes() == bytes_built
    assert os.access(reused, os.X_OK) and exit_code(reused) == 0
    # Check the mode bits: os.access reports root as able to write any file.
    blob_mode = cache_files("blobs")[0].stat().st_mode
    assert not blob_mode & 0o222, "shared blob is writable"
    # An incremental result equals a clean build without any cache.
    # The linker embeds the output's file name, so compare like names.
    clean = evidence / "clean" / "out.bin"
    clean.parent.mkdir(exist_ok=True)
    invoke(["build", app, "-o", clean, "--no-cache"])
    assert clean.read_bytes() == bytes_built


def checked_core_reuse():
    directory = evidence / "checked-core"
    directory.mkdir()
    library = directory / "library"
    shutil.copytree(Path(__file__).resolve().parents[1] / "library" / "core",
                    library / "core")
    core = library / "core" / "module.mt"
    core.write_text(core.read_text() +
                    "\nfn reuse_helper(value: i32): i32 { value + 1 }\n"
                    "pub const fn reuse_constant(value: i32): i32 { value + 1 }\n"
                    "pub fn reuse_generic<T: Copy>(value: T): T { value }\n"
                    "pub fn reuse_value(value: i32): i32 { reuse_helper(value) }\n")
    first = directory / "first.mt"
    second = directory / "second.mt"
    first.write_text("const VALUE: i32 = core.reuse_constant(20)\n"
                     "fn main(): i32 {\n"
                     "    core.reuse_generic(core.reuse_value(VALUE)) - 22\n"
                     "}\n")
    second.write_text("const VALUE: i32 = core.reuse_constant(40)\n"
                      "fn main(): i32 {\n"
                      "    let wide = core.reuse_generic(42u64)\n"
                      "    if wide != 42u64 { return 1 }\n"
                      "    core.reuse_value(VALUE) - 42\n"
                      "}\n")
    arguments = ["--library-dir", library]
    cold, program = explained(first, *arguments)
    assert exit_code(program) == 0
    assert "checked library interface cache stored core " in cold, cold
    warm, program = explained(second, *arguments)
    assert exit_code(program) == 0
    assert "cache miss" in last_cache_event(warm), warm
    assert "checked library interface cache hit core " in warm, warm
    assert "library object cache hit core " in warm, warm
    prefix = next(line.rsplit(" ", 1)[-1] for line in cold.splitlines()
                  if "checked library interface cache stored core " in line)
    entry = next(path for path in cache_files("entries")
                 if path.name.startswith(prefix))
    digest = entry.read_text().split()[1]
    blob = next(path for path in cache_files("blobs") if path.name == digest)
    blob.chmod(0o644)
    blob.write_bytes(b"corrupted")
    recovered, program = explained(second, *arguments)
    assert exit_code(program) == 0
    assert "checked library interface cache corrupt core" in recovered, recovered
    assert "checked library interface cache stored core " in recovered, recovered
    clean, program = explained(second, *arguments, "--no-cache")
    assert exit_code(program) == 0
    assert "checked library interface cache " not in clean, clean
    if os.name != "nt":
        external = directory / "external.mt"
        external.write_text("pub fn external_value(): i32 { 42 }\n")
        (library / "core" / "external.mt").symlink_to(external)
        core.write_text(core.read_text() + "\npub module external\n")
        second.write_text("import core.external\n"
                          "fn main(): i32 { external.external_value() - 42 }\n")
        fallback, program = explained(second, *arguments)
        assert exit_code(program) == 0
        assert "checked library interface cache ineligible core:" in fallback, fallback
        assert "using source" in fallback, fallback


def checked_alloc_std_reuse(profile="debug"):
    directory = evidence / "checked-libraries"
    directory.mkdir()
    library = directory / "library"
    original = Path(__file__).resolve().parents[1] / "library"
    for root in ("core", "alloc", "std"):
        shutil.copytree(original / root, library / root)
    core = library / "core" / "module.mt"
    core.write_text(core.read_text() +
                    "\npub fn reuse_dependency(value: i32): i32 { value + 1 }\n")
    for root in ("alloc", "std"):
        module = library / root / "module.mt"
        module.write_text(module.read_text() +
                          "\nfn reuse_helper(value: i32): i32 { core.reuse_dependency(value) }\n"
                          "pub const fn reuse_constant(value: i32): i32 { value + 1 }\n"
                          "pub fn reuse_generic<T: Copy>(value: T): T { value }\n"
                          "pub fn reuse_value(value: i32): i32 { reuse_helper(value) }\n")
        if root == "std":
            module.write_text(module.read_text() +
                              "pub async fn reuse_async(value: i32): i32 { value + 1 }\n")
        first, second = directory / f"{root}-first.mt", directory / f"{root}-second.mt"
        first.write_text(f"const VALUE: i32 = {root}.reuse_constant(20)\n"
                         f"fn main(): i32 {{ {root}.reuse_generic({root}.reuse_value(VALUE)) - 22 }}\n")
        async_check = ("    if std.task.block_on(std.reuse_async(41)) != 42 { return 2 }\n"
                       if root == "std" else "")
        second.write_text("fn consumer_only(value: i32): i32 { value }\n"
                          f"const VALUE: i32 = {root}.reuse_constant(40)\n"
                          f"fn main(): i32 {{\n"
                          f"    let wide = {root}.reuse_generic(42u64)\n"
                          "    if wide != 42u64 { return 1 }\n"
                          f"{async_check}"
                          f"    consumer_only({root}.reuse_value(VALUE)) - 42\n"
                          "}\n")
        arguments = ["--library-dir", library, "--profile", profile]
        cold, program = explained(first, *arguments)
        assert exit_code(program) == 0
        assert f"checked library interface cache stored {root} " in cold, cold
        warm, program = explained(second, *arguments)
        assert exit_code(program) == 0
        assert "cache miss" in last_cache_event(warm), warm
        assert f"checked library interface cache hit {root} " in warm, warm
        assert f"library object cache hit {root} " in warm, warm
        assert "library object cache hit core " in warm, warm
        if root == "std":
            assert "library object cache hit alloc " in warm, warm
        if profile == "debug":
            edit(core, "value + 1", "value + 2")
            changed, program = explained(second, *arguments)
            assert exit_code(program) == 1
            assert f"checked library interface cache stored {root} " in changed, changed
            assert f"library object cache miss {root} " in changed, changed
            edit(core, "value + 2", "value + 1")
            if root == "std":
                _, program = explained(second, *arguments, "--no-cache")
                assert exit_code(program) == 0


def checked_alloc_std_release_reuse():
    checked_alloc_std_reuse("release")


def checked_native_macro_reuse():
    directory = evidence / "native-macros"
    library = directory / "library"
    for root in ("core", "alloc", "std"):
        module = library / root / "module.mt"
        module.parent.mkdir(parents=True)
        module.write_text("pub fn value(): i32 { 0 }\n")
    module = library / "std" / "module.mt"
    module.write_text(module.read_text() +
                      "pub module tokens\n"
                      "macro hidden { () => { 41 }; }\n"
                      "pub macro reuse { () => { hidden!() + 1 }; }\n")
    (module.parent / "tokens.mt").write_text(
        "pub macro suffix { () => { 1 }; }\n")
    first, second = directory / "first.mt", directory / "second.mt"
    first.write_text("fn main(): i32 { std.value() + std.reuse!() + "
                     "std.tokens.suffix!() - 43 }\n")
    second.write_text("macro hidden { () => { 7 }; }\n"
                      "fn extra(value: i32): i32 { value }\n"
                      "fn main(): i32 { extra(std.value() + std.reuse!() + "
                      "std.tokens.suffix!()) - 43 }\n")
    arguments = ["--library-dir", library]
    cold, program = explained(first, *arguments)
    assert exit_code(program) == 0
    assert "checked library interface cache stored std " in cold, cold
    warm, program = explained(second, *arguments)
    assert exit_code(program) == 0
    assert "cache miss" in last_cache_event(warm), warm
    assert "checked library interface cache hit std " in warm, warm
    assert "library object cache hit std " in warm, warm


def checked_library_diagnostics():
    directory = evidence / "library-diagnostics"
    module = directory / "library" / "core" / "module.mt"
    module.parent.mkdir(parents=True)
    consumer = directory / "main.mt"
    consumer.write_text("fn main(): i32 { core.broken() }\n")
    arguments = ["check", consumer, "--library-dir", directory / "library"]
    for source, line in (
            ("pub fn broken(): i32 { true }\n", 1),
            ("macro broken { () => { true }; }\n"
             "pub fn broken(): i32 { broken!() }\n", 2)):
        module.write_text(source)
        clean = invoke([*arguments, "--no-cache"], expected=1)
        cached = invoke([*arguments, "--explain"], expected=1)
        prefix = module.as_posix() + f":{line}:"
        expected = [item for item in clean.splitlines() if item.startswith(prefix)]
        actual = [item for item in cached.splitlines() if item.startswith(prefix)]
        assert expected and actual == expected, (clean, cached)
        assert any("error[type]" in item for item in actual), cached
        assert "error[metadata]" not in cached, cached
        assert "checked library interface cache stored core " not in cached, cached


def native_core_object_reuse():
    directory = evidence / "native-core"
    directory.mkdir()
    library = directory / "library"
    shutil.copytree(Path(__file__).resolve().parents[1] / "library" / "core",
                    library / "core")
    core = library / "core" / "module.mt"
    core.write_text(core.read_text() +
                    "\npub fn native_value(unused: i32, value: i32): i32 { value + 1 }\n"
                    "pub fn native_generic<T: Copy>(value: T): T { value }\n")
    first, second = directory / "first.mt", directory / "second.mt"
    first.write_text("fn main(): i32 {\n"
                     "    core.native_generic(core.native_value(99, 41)) - 42\n"
                     "}\n")
    second.write_text("fn main(): i32 {\n"
                      "    let wide = core.native_generic(42u64)\n"
                      "    if wide != 42u64 { return 1 }\n"
                      "    core.native_value(17, 81) - 82\n"
                      "}\n")
    for profile in ("debug", "release"):
        arguments = ["--library-dir", library, "--profile", profile]
        cold, program = explained(first, *arguments)
        assert exit_code(program) == 0
        assert "library object cache stored core " in cold, cold
        warm, program = explained(second, *arguments)
        assert exit_code(program) == 0
        assert "cache miss" in last_cache_event(warm), warm
        assert "library object cache hit core " in warm, warm
        edit(core, "value + 1", "value + 2")
        changed, program = explained(second, *arguments)
        assert exit_code(program) == 1
        assert "library object cache miss core " in changed, changed
        edit(core, "value + 2", "value + 1")


def linked_archive_changes_invalidate_executable():
    if os.name == "nt":
        return
    cxx = os.environ.get("CXX") or shutil.which("clang++")
    archiver = shutil.which("llvm-ar")
    assert cxx and archiver, "the pinned Clang and llvm-ar must be on PATH"
    directory = evidence / "native-link"
    directory.mkdir()
    native = directory / "probe.c"
    obj = directory / "probe.o"
    archive = directory / "libmettle_cache_probe.a"
    source = directory / "main.mt"
    source.write_text('@link("mettle_cache_probe")\n'
                      'extern "C" fn probe(): i32;\n'
                      'fn main(): i32 { unsafe { probe() } }\n')
    previous = os.environ.get("LIBRARY_PATH")
    os.environ["LIBRARY_PATH"] = os.pathsep.join(
        filter(None, (str(directory), previous)))
    try:
        for expected in (1, 2):
            native.write_text(f"int probe(void) {{ return {expected}; }}\n")
            processes.run([cxx, "-x", "c", "-c", str(native), "-o", str(obj)],
                          check=True)
            processes.run([archiver, "rcs", str(archive), str(obj)], check=True)
            _, program = explained(source)
            assert exit_code(program) == expected
    finally:
        if previous is None:
            os.environ.pop("LIBRARY_PATH", None)
        else:
            os.environ["LIBRARY_PATH"] = previous


def object_cache_integrity():
    app = packages("path-dependency/app")
    first, _ = explained(app)
    assert "package object cache stored" in first, first
    no_op, _ = explained(app)
    assert "cache hit" in no_op, no_op

    edit(app / "src/main.mt", "- 42", "- 41")
    root_edit, built = explained(app)
    assert "cache miss" in last_cache_event(root_edit), root_edit
    dependency_hit = next(
        line for line in root_edit.splitlines()
        if "package object cache hit" in line and "mathlib" in line)
    key_prefix = dependency_hit.rsplit(" ", 1)[-1]
    clean = evidence / "clean" / "out.bin"
    clean.parent.mkdir(exist_ok=True)
    invoke(["build", app, "-o", clean, "--no-cache"])
    assert built.read_bytes() == clean.read_bytes()
    assert exit_code(built) == exit_code(clean)

    # Damage that dependency object's blob. A second root-only edit misses the
    # whole-program entry but must verify and regenerate the dependency object.
    entry = next(path for path in cache_files("entries")
                 if path.name.startswith("pkg-" + key_prefix))
    blob_hash = entry.read_text().split()[1]
    blob = next(path for path in cache_files("blobs")
                if path.name == blob_hash)
    blob.chmod(0o644)
    blob.write_bytes(b"corrupted dependency object")
    edit(app / "src/main.mt", "- 41", "- 40")
    rebuilt, built = explained(app)
    assert "package object cache entry corrupt, rebuilding" in rebuilt, rebuilt
    assert "package object cache stored" in rebuilt, rebuilt
    clean_again = evidence / "clean-again" / "out.bin"
    clean_again.parent.mkdir(exist_ok=True)
    invoke(["build", app, "-o", clean_again, "--no-cache"])
    assert built.read_bytes() == clean_again.read_bytes()
    assert exit_code(built) == exit_code(clean_again)


def sanitizer_cache_key():
    app = packages("incremental/app")
    plain, _ = explained(app)
    assert "cache miss" in plain and "cache stored" in plain, plain
    sanitized, built = explained(app, "--sanitize", "address")
    assert "cache miss" in sanitized and "cache stored" in sanitized, sanitized
    assert exit_code(built) == 0
    reused, _ = explained(app, "--sanitize", "address")
    assert "cache hit" in reused, reused
    plain_again, _ = explained(app)
    assert "cache hit" in plain_again, plain_again
    invoke(["run", app, "--sanitize", "address"])
    invoke(["test", app, "--sanitize", "address"])


def edit_invalidation():
    app = packages("incremental/app")
    math = app / "src/math.mt"
    explained(app)
    # Comments, layout and files the program never loads are not inputs.
    edit(math, "pub fn answer", "// the answer\n\n\npub fn answer")
    text, _ = explained(app)
    assert "cache hit" in text, text
    edit(app / "src/unused.mt", "0", "1")
    text, _ = explained(app)
    assert "cache hit" in text, text
    # A token change recompiles, then reuses again.
    edit(math, "{ 42 }", "{ 40 + 2 }")
    text, built = explained(app)
    assert "cache miss" in text, text
    assert exit_code(built) == 0
    text, _ = explained(app)
    assert "cache hit" in text, text
    # A change in a dependency package invalidates the dependent build.
    path_app = packages("path-dependency/app")
    text, _ = explained(path_app)
    assert "cache miss" in text, text
    text, _ = explained(path_app, "--locked")
    assert "cache hit" in text, text
    edit(packages("path-dependency/units/src/main.mt"), "21", "20 + 1")
    text, built = explained(path_app)
    assert "cache miss" in text, text
    assert exit_code(built) == 0


def comment_newline_invalidates_cache():
    source = evidence / "comment-newline.mt"
    source.write_text("fn main(): i32 { return /* comment */ 7 }\n")
    text, output = explained(source)
    assert "cache stored" in text, text
    before = output.read_bytes()
    edit(source, "/* comment */", "/* changed */")
    text = invoke(["build", source, "-o", output, "--explain"])
    assert "cache hit" in text, text
    edit(source, "/* changed */", "/* changed\n */")
    text = invoke(["build", source, "-o", output, "--explain"], 1)
    assert "cache hit" not in text, text
    assert output.read_bytes() == before


def cache_dedup_and_bound():
    app = packages("incremental/app")
    explained(app)
    explained(app, "--features", "extra")
    # Different keys that produce the same bytes share one stored blob.
    assert len(cache_files("entries")) == 2, cache_files("entries")
    assert len(cache_files("blobs")) == 1, cache_files("blobs")
    blob = cache_files("blobs")[0].stat().st_size
    # With a budget that holds one artifact, the least recently used goes.
    edit(app / "src/math.mt", "pub fn answer(): i32 { 42 }",
         "pub fn answer(): i32 { 42 }\npub fn zero(): i32 { 0 }")
    edit(app / "src/main.mt", "- 42 }", "- 42 + math.zero() }")
    limit = (blob * 3 // 2) // 1024 + 1
    text, built = explained(app, "--cache-limit-kib", limit)
    assert "evicted" in text and "least recently used" in text, text
    assert cache_bytes() <= limit * 1024, (cache_bytes(), limit)
    assert exit_code(built) == 0
    assert len(cache_files("blobs")) == 1, cache_files("blobs")
    # A budget below a single artifact keeps nothing, yet builds still work.
    edit(app / "src/main.mt", "math.zero() }", "math.zero() + 0 }")
    text, built = explained(app, "--cache-limit-kib", 1)
    assert cache_bytes() <= 1024, cache_bytes()
    assert exit_code(built) == 0


def cache_corruption_and_clean():
    app = packages("incremental/app")
    explained(app)
    blob = cache_files("blobs")[0]
    blob.chmod(0o644)
    blob.write_bytes(b"corrupted")
    # Scratch and entry files that vanish while the store prunes have no age.
    cache = evidence / "cache"
    gone = [cache / "tmp" / "gone", cache_files("entries")[0].parent / "gone"]
    for link in gone:
        link.symlink_to(cache / "missing")
    text, built = explained(app)
    assert "entry corrupt" in text, text
    assert exit_code(built) == 0
    for link in gone:
        link.unlink()
    text, _ = explained(app)
    assert "cache hit" in text, text
    # `clean` reports, then empties, only a directory that is a store.
    text = invoke(["clean", "--dry-run"], contains="would remove 1 entries")
    assert cache.exists()
    invoke(["clean"], contains="removed 1 entries")
    assert not cache.exists()
    text, _ = explained(app)
    assert "cache miss" in text, text
    foreign = evidence / "foreign"
    foreign.mkdir()
    (foreign / "keep.txt").write_text("x")
    invoke(["clean", "--cache-dir", foreign], 1, "not a mettle store")
    assert (foreign / "keep.txt").exists()


def cache_corrupt_digest_preserves_other_files():
    app = packages("incremental/app")
    first, _ = explained(app)
    prefix = last_cache_event(first).split()[-1]
    entry = next(path for path in cache_files("entries")
                 if path.name.startswith(prefix))
    sentinel = evidence / "sentinel0"
    sentinel.write_text("keep")
    digest = "../" + "./" * 26 + sentinel.name
    assert len(digest) == 64
    entry.write_text(f"file {digest} 4 -\n")
    text, built = explained(app)
    assert "cache entry corrupt" in text, text
    assert sentinel.read_text() == "keep"
    assert exit_code(built) == 0


def cache_publication_failure_is_reported():
    app = packages("incremental/app")
    first, _ = explained(app)
    prefix = last_cache_event(first).split()[-1]
    entry = next(path for path in cache_files("entries")
                 if path.name.startswith(prefix))
    entry.unlink()
    entry.mkdir()
    sentinel = entry / "keep"
    sentinel.write_text("keep")
    text, built = explained(app)
    assert "cache could not store" in text, text
    assert sentinel.read_text() == "keep"
    assert exit_code(built) == 0


def cache_clean_failure():
    # Permission failures must leave a recognizable, retryable store.
    if os.geteuid() == 0:
        return  # Root bypasses directory permissions.
    app = packages("incremental/app")
    explained(app)
    cache = evidence / "cache"
    entries = cache / "entries"
    entries.chmod(0o500)
    try:
        invoke(["clean"], 1, "cannot remove")
        assert (cache / "VERSION").is_file()
    finally:
        entries.chmod(0o700)
    invoke(["clean"])
    assert not cache.exists()


def cache_clean_preserves_sources():
    explained(packages("incremental/app"))
    cache = evidence / "cache"
    checkout = cache / "sources" / "git" / "retained"
    checkout.mkdir(parents=True)
    source = checkout / "keep.mt"
    source.write_text("fn retained() {}\n")
    invoke(["clean"])
    assert source.read_text() == "fn retained() {}\n"
    assert (cache / "VERSION").is_file()
    invoke(["clean"])
    assert source.is_file()


def security_output_paths():
    sentinel = evidence / "sentinel.txt"
    sentinel.write_text("keep")
    source = evidence / "format.mt"
    source.write_text("fn main():i32{0}\n")
    temporary = Path(str(source) + ".mettle-fmt.tmp")
    temporary.symlink_to(sentinel)
    invoke(["fmt", source])
    assert sentinel.read_text() == "keep"
    assert temporary.is_symlink()

    output = evidence / "docs"
    output.mkdir()
    (output / "index.html").symlink_to(sentinel)
    invoke(["doc", source, "-o", output])
    assert sentinel.read_text() == "keep"
    assert not (output / "index.html").is_symlink()

    linked = evidence / "linked-docs"
    linked.symlink_to(output, target_is_directory=True)
    invoke(["doc", source, "-o", linked], 1, "contains a symlink")

    app = packages("build-script/app")
    target = app / "target"
    target.symlink_to(output, target_is_directory=True)
    invoke(["clean", app], 1, "package target is a symlink")
    assert sentinel.read_text() == "keep"


def cache_compiler_content_identity():
    # ELF permits inert trailing bytes, so alter identity without touching code.
    # Preserve path, size and timestamps to exclude metadata-based invalidation.
    if sys.platform != "linux":
        return
    compiler = evidence / "compiler-copy"
    shutil.copy2(mettle, compiler)
    with compiler.open("ab") as stream:
        stream.write(b"A")
    environment = {**os.environ, "METTLE_CACHE_DIR": str(evidence / "cache")}
    arguments = [str(compiler), "build", str(packages("incremental/app")),
                 "-o", str(evidence / "identity.bin"), "--explain"]

    def build():
        result = processes.run(arguments, text=True, capture_output=True, env=environment)
        assert result.returncode == 0, result.stderr
        return result.stderr

    assert "cache miss" in last_cache_event(build())
    assert "cache hit" in last_cache_event(build())
    stamp = compiler.stat()
    with compiler.open("r+b") as stream:
        stream.seek(-1, 2)
        stream.write(b"B")
    os.utime(compiler, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
    assert "cache miss" in last_cache_event(build())


def build_script():
    app = packages("build-script/app")
    text, built = explained(app)
    assert "rerun (no reproducible record)" in text, text
    assert exit_code(built) == 0, "generated module, feature or script output"
    text, built = explained(app)
    assert "reused (declared reproducible" in text, text
    assert "cache hit" in last_cache_event(text), text
    assert exit_code(built) == 0
    # A changed declared input reruns the script; unchanged generated tokens
    # still reuse the compiled program.
    edit(app / "spec.txt", "}\n", "} // annotated\n")
    text, built = explained(app)
    assert "rerun (input 'spec.txt' changed)" in text, text
    assert "cache hit" in last_cache_event(text), text
    edit(app / "spec.txt", "{ 7 }", "{ 3 + 4 }")
    text, built = explained(app)
    assert "cache miss" in last_cache_event(text), text
    assert exit_code(built) == 0
    # `clean PACKAGE` removes the generated outputs too.
    assert (app / "target/mettle/out/generated.mt").exists()
    invoke(["clean", app])
    assert not (app / "target/mettle").exists()


def build_script_untracked_inputs():
    app = packages("build-script/app")
    script = app / "build.mt"
    edit(script, '    std.io.print("mettle:reproducible\\n")\n', "")
    for _ in range(2):
        text, built = explained(app)
        assert "rerun (no reproducible record)" in text, text
        assert exit_code(built) == 0
    edit(script, '    0\n}', '    std.io.print("mettle:bogus=1\\n")\n    0\n}')
    explained(app, expected=1, contains="unknown or malformed declaration")


def procedural_macro():
    app = packages("proc-macro/app")
    macro = packages("proc-macro/genfn")
    # The macro program generates `answer`; main returns answer() - 41.
    text, built = explained(app)
    assert "procedural macro 'make_fn!': rerun (no reproducible record)" in text, text
    assert exit_code(built) == 0
    text, built = explained(app)
    assert "procedural macro 'make_fn!': reused (declared reproducible" in text, text
    assert "cache hit" in last_cache_event(text), text
    assert exit_code(built) == 0
    # Changing a declared external input reruns the program and changes the
    # expansion, so the compiled output must not be reused.
    edit(macro / "spec.txt", "41", "42")
    text, built = explained(app)
    assert "procedural macro 'make_fn!': rerun (input 'spec.txt' changed)" in text, text
    assert "cache miss" in last_cache_event(text), text
    assert exit_code(built) == 1


def procedural_macro_failure():
    app = packages("proc-macro/app")
    # A failure the program reports is a diagnostic at the invocation.
    (app / "src/main.mt").write_text("make_fn!()\n\nfn main(): i32 { 0 }\n")
    explained(app, expected=1,
              contains=["error[macro]", "procedural macro 'make_fn!': make_fn! "
                        "expects the name of the function"])
    # An unsupported API major version is rejected before any program runs.
    edit(packages("proc-macro/genfn/package.mettle"), "api: 1", "api: 2")
    explained(app, expected=1,
              contains="unsupported macro API major version 2")


def public_declarative_macro_dependency():
    app = packages("declarative-macro/app")
    dependency = packages("declarative-macro/units")
    (app / "src").mkdir(parents=True)
    (dependency / "src").mkdir(parents=True)
    (app / "package.mettle").write_text(
        'name: "macro-app"\nversion: "0.1.0"\n'
        'dependencies { units { path: "../units", features: ["enabled"] } }\n')
    (dependency / "package.mettle").write_text(
        'name: "units"\nversion: "0.1.0"\nkind: "library"\n'
        'features { enabled: [] }\n')
    (app / "src/main.mt").write_text(
        "import units.value\n"
        "fn main(): i32 { value!() - 42 }\n")
    (dependency / "src/main.mt").write_text(
        '@cfg(feature = "enabled")\n'
        "module macros {\n"
        "    pub macro value {\n"
        "        () => { 42 };\n"
        "    }\n"
        "}\n"
        '@cfg(feature = "enabled")\n'
        "pub import macros.value\n")
    build_and_run(app)


def cyclic_module_macro_definition():
    app = packages("cyclic-module-macro")
    (app / "src").mkdir(parents=True)
    (app / "package.mettle").write_text(
        'name: "cyclic-module-macro"\nversion: "0.1.0"\n')
    (app / "src/main.mt").write_text(
        "module first;\nmodule second;\n"
        "fn main(): i32 { first.value() - 42 }\n")
    (app / "src/first.mt").write_text(
        "import super.second\n"
        "macro make_value { () => { 42 }; }\n"
        "pub fn value(): i32 { make_value!() + second.extra() }\n")
    (app / "src/second.mt").write_text(
        "import super.first\n"
        "pub fn extra(): i32 { 0 }\n")
    build_and_run(app)


def multi_package_extension():
    app = packages("multi-package-extension/app")
    text, built = explained(app)
    assert "rerun (no reproducible record)" in text, text
    assert ("procedural macro 'make_fn!': rerun (no reproducible record)"
            in text), text
    assert exit_code(built) == 0

    text, built = explained(app)
    assert "reused (declared reproducible; inputs unchanged)" in text, text
    assert ("procedural macro 'make_fn!': reused (declared reproducible"
            in text), text
    assert "cache hit" in last_cache_event(text), text
    assert exit_code(built) == 0

    main = app / "src/main.mt"
    edit(main, "answer() - 41", "answer() - 40")
    text, built = explained(app)
    assert ("procedural macro 'make_fn!': reused (declared reproducible"
            in text), text
    assert "cache miss" in last_cache_event(text), text
    assert exit_code(built) == 1

    edit(main, "answer() - 40", "answer() - 41")
    edit(packages("multi-package-extension/mathlib/src/main.mt"),
         "{ 7 }", "{ 8 }")
    text, built = explained(app)
    assert "cache miss" in last_cache_event(text), text
    assert exit_code(built) == 1


def type_id_survives_public_reexport():
    app = packages("type-id-reexport/app")
    build_and_run(app)


def package_options_need_package():
    source = evidence / "plain.mt"
    source.write_text("fn main(): i32 { 0 }\n")
    invoke(["check", source, "--locked"], 2)


def fmt_normalizes_layout_only():
    # Indentation, spacing, trailing whitespace and blank runs change; the
    # comments, the multi-line raw text and the line structure do not.
    messy = (
        "// header comment   \n"
        "fn   double(value:i32):i32=>value  *  2\n"
        "interface   Twice {\n"
        "fn value():i32;\n"
        "fn twice():i32=>self.value()  *  2\n"
        "}\n"
        "type Number {\n"
        "fn twice():i32=>self.value  *  2\n"
        "}\n"
        "fn   add(a:i32,b: i32) : i32 {\n"
        "        a   +   b\n"
        "}\n"
        "\n\n\n\n"
        "/* block\n"
        "     comment */\n"
        "fn main(): i32 {\n"
        "  let text = r\"raw one\n"
        "   raw two  \"\n"
        "\tlet total = add( 1,2 )    // note  \n"
        "  let list = [1,\n"
        "  2,\n"
        "      3]\n"
        "    if total == 3 && list.len() == 3usize {\n"
        "   return  0\n"
        "      }\n"
        "  let sum = add(\n"
        "add(1, 2),\n"
        "         3\n"
        "    )\n"
        "    total  +  sum\n"
        "}   \n\n\n")
    expected = (
        "// header comment\n"
        "fn double(value: i32): i32 => value * 2\n"
        "interface Twice {\n"
        "    fn value(): i32;\n"
        "    fn twice(): i32 => self.value() * 2\n"
        "}\n"
        "type Number {\n"
        "    fn twice(): i32 => self.value * 2\n"
        "}\n"
        "fn add(a: i32, b: i32): i32 {\n"
        "    a + b\n"
        "}\n"
        "\n"
        "/* block\n"
        "     comment */\n"
        "fn main(): i32 {\n"
        "    let text = r\"raw one\n"
        "   raw two  \"\n"
        "    let total = add(1, 2) // note\n"
        "    let list = [1,\n"
        "        2,\n"
        "        3]\n"
        "    if total == 3 && list.len() == 3usize {\n"
        "        return 0\n"
        "    }\n"
        "    let sum = add(\n"
        "        add(1, 2),\n"
        "        3\n"
        "    )\n"
        "    total + sum\n"
        "}\n")
    source = evidence / "messy.mt"
    source.write_text(messy)
    invoke(["fmt", source, "--check"], 1,
           ["messy.mt", "would be reformatted", "line 1)"])
    assert source.read_text() == messy
    invoke(["fmt", source])
    assert source.read_text() == expected, source.read_text()
    text = invoke(["fmt", source])
    assert "formatted" not in text, text
    invoke(["fmt", source, "--check"])
    assert source.read_text() == expected
    broken = evidence / "broken.mt"
    broken.write_text("fn main(): i32 {  0\n")
    invoke(["fmt", broken], 1)
    assert broken.read_text() == "fn main(): i32 {  0\n"
    # Files that define declarative macros are checked after expansion.
    macro = evidence / "macro.mt"
    macro.write_text("macro square {\n    ($x:expr)  =>  { $x*$x };\n}\n"
                     "fn main(): i32 {\n  square!(3)  -  9\n}\n"
                     "fn compare(a: i32, b: i32): bool {\n"
                     "a>\nb\n}\n")
    invoke(["fmt", macro])
    assert macro.read_text() == ("macro square {\n    ($x:expr) => { $x*$x };\n}\n"
                                 "fn main(): i32 {\n    square!(3) - 9\n}\n"
                                 "fn compare(a: i32, b: i32): bool {\n"
                                 "    a>\n        b\n}\n"), \
        macro.read_text()
    wide_left = "left_" + "x" * 60
    wide_right = "right_" + "y" * 60
    before = (
        f"fn generic<{wide_left}, {wide_right}>() {{}}\n"
        f"fn parameters({wide_left}: i32, {wide_right}: i32) {{}}\n"
        "fn call_wrap() {\n"
        f"    call({wide_left}, {wide_right})\n"
        "}\n"
        "fn chain_wrap() {\n"
        f"    {wide_left}.first().long_method_name_that_is_long_enough()\n"
        "}\n"
        "fn binary_wrap() {\n"
        f"    let sum = {wide_left} + {wide_right} + 1\n"
        "}\n"
        "fn collection_wrap() {\n"
        f"    let values = [{wide_left}, {wide_right}]\n"
        "}\n"
        "fn record_wrap() {\n"
        f"    let value = Record({wide_left}, {wide_right})\n"
        "}\n"
        "fn match_wrap(input: i32) {\n"
        f"    match input {{ {wide_left} => 1, {wide_right} => 2 }}\n"
        "}\n")
    expected_after = (
        f"fn generic<{wide_left},\n"
        f"    {wide_right}>() {{}}\n"
        f"fn parameters({wide_left}: i32,\n"
        f"    {wide_right}: i32) {{}}\n"
        "fn call_wrap() {\n"
        f"    call({wide_left},\n"
        f"        {wide_right})\n"
        "}\n"
        "fn chain_wrap() {\n"
        f"    {wide_left}.first().long_method_name_that_is_long_enough()\n"
        "}\n"
        "fn binary_wrap() {\n"
        f"    let sum = {wide_left} +\n"
        f"        {wide_right} + 1\n"
        "}\n"
        "fn collection_wrap() {\n"
        f"    let values = [{wide_left},\n"
        f"        {wide_right}]\n"
        "}\n"
        "fn record_wrap() {\n"
        f"    let value = Record({wide_left},\n"
        f"        {wide_right})\n"
        "}\n"
        "fn match_wrap(input: i32) {\n"
        f"    match input {{ {wide_left} => 1,\n"
        f"        {wide_right} => 2 }}\n"
        "}\n")
    long = evidence / "long-layout.mt"
    long.write_text(before)
    expected = evidence / "long-layout.expected.mt"
    expected.write_text(expected_after)
    invoke(["fmt", long])
    formatted = long.read_text()
    assert formatted == expected.read_text(), formatted
    assert all(len(line) <= 100 for line in formatted.splitlines()
               if "long_method_name" not in line), formatted
    invoke(["fmt", long, "--check"])
    assert long.read_text() == formatted
    edges = evidence / "formatter-edges.mt"
    edges.write_text(
        "fn compare(left: i32, right: i32): bool {\n"
        "    left>\n"
        "right\n"
        "}\n"
        "type Item {\n"
        "    value: Box<core.sync.atomic.AtomicUsize>\n"
        "    enabled: bool\n"
        "}\n"
        "fn selected(): i32 {\n"
        "    let result = match 1 {\n"
        "0 => { 0 },\n"
        "1 => { 1 },\n"
        "}\n"
        "    result\n"
        "}\n"
        "fn returned(): i32 {\n"
        "    return match 1 {\n"
        "0 => 0,\n"
        "1 => 1,\n"
        "}\n"
        "}\n")
    invoke(["fmt", edges])
    assert edges.read_text() == (
        "fn compare(left: i32, right: i32): bool {\n"
        "    left>\n"
        "        right\n"
        "}\n"
        "type Item {\n"
        "    value: Box<core.sync.atomic.AtomicUsize>\n"
        "    enabled: bool\n"
        "}\n"
        "fn selected(): i32 {\n"
        "    let result = match 1 {\n"
        "        0 => { 0 },\n"
        "        1 => { 1 },\n"
        "    }\n"
        "    result\n"
        "}\n"
        "fn returned(): i32 {\n"
        "    return match 1 {\n"
        "        0 => 0,\n"
        "        1 => 1,\n"
        "    }\n"
        "}\n"), edges.read_text()
    invoke(["fmt", edges, "--check"])


def lint_reports_semantic_findings():
    source = evidence / "lint.mt"
    source.write_text(
        "import core.iter.{Iterator, Iterable};\n"
        "copy enum Error { Bad }\n"
        "fn value(input: i32): i32 throws Error {\n"
        "    if input < 0 { throw Error.Bad }\n"
        "    input\n"
        "}\n"
        "fn spare(): i32 {\n"
        "    let unused = 1\n"
        "    var counter = 2\n"
        "    return counter\n"
        "    3\n"
        "}\n"
        "@allow(unused-binding)\n"
        "fn quiet(): i32 {\n"
        "    let ignored = 1\n"
        "    0\n"
        "}\n"
        "fn main(): i32 {\n"
        "    capture value(1)\n"
        "    let _ = capture value(2)\n"
        "    0\n"
        "}\n")
    text = invoke(["lint", source], 0,
                  ["warning[unused-binding]", "binding 'unused'",
                   "warning[unused-mutability]", "'var counter'",
                   "warning[unused-import]", "core.iter.Iterator",
                   "core.iter.Iterable", "warning[unreachable-code]",
                   "warning[unused-outcome]"])
    # The function-level @allow wins; discarded results and `_` are fine.
    assert "'ignored'" not in text, text
    invoke(["lint", source, "--deny", "unused-outcome"], 1,
           ["error[unused-outcome]", "warning[unused-binding]"])
    findings = invoke_json(["lint", source, "--format", "json",
                            "--deny", "unused-outcome"], 1)
    outcome = next(item for item in findings
                   if item["code"] == "unused-outcome")
    assert outcome["level"] == "deny"
    span = outcome["span"]
    assert Path(span["file"]) == source
    assert "capture value(1)" in source.read_text()[span["begin"]:span["end"]]
    assert "Outcome" in outcome["message"]
    assert invoke_json(["lint", source, "--format", "json",
                        "--allow", "warnings"]) == []
    invoke(["lint", source, "--deny", "warnings", "--allow", "unused-import"], 1,
           ["error[unused-binding]"])
    text = invoke(["lint", source, "--allow", "warnings"])
    assert "warning[" not in text and "error[" not in text, text
    # Lint runs the whole front end: a type error is an ordinary error.
    broken = evidence / "broken-lint.mt"
    broken.write_text("fn main(): i32 {\n    true\n}\n")
    invoke(["lint", broken], 1, ["error[type]"])
    invoke(["lint", source, "--deny", "no-such-rule"], 2)


def run_forwards_args_and_exit_status():
    directory = evidence / "run-case"
    directory.mkdir()
    program = directory / "echo.mt"
    program.write_text(
        "fn main(): i32 {\n"
        "    let args = std.env.args()\n"
        "    std.io.print(\"hello from run\\n\")\n"
        "    if args.len() != 3usize { return 1 }\n"
        "    if !args[1usize].as_os_str().same(std.ffi.os_str_from_text(\"one\")) { return 2 }\n"
        "    if !args[2usize].as_os_str().same(std.ffi.os_str_from_text(\"--two\")) { return 3 }\n"
        "    42\n"
        "}\n")
    before = sorted(os.listdir(directory))
    invoke(["run", program, "--", "one", "--two"], 42, "hello from run")
    invoke(["run", program], 1, "hello from run")
    assert sorted(os.listdir(directory)) == before, "run left files behind"
    program.write_text('fn main(): i32 { panic("run panic") }\n')
    invoke(["run", program], 101, "run panic")


TEST_SOURCE = (
    "fn main(): i32 { 99 }\n"
    "fn add(a: i32, b: i32): i32 { a + b }\n"
    "@test\n"
    "fn passes() { if add(1, 2) != 3 { panic(\"bad add\") } }\n"
    "@test\n"
    "fn panics() { panic(\"boom\") }\n"
    "@test\n"
    "@ignore(\"slow\")\n"
    "fn skipped() { panic(\"must not run\") }\n"
    "@test\n"
    "@should_panic(\"expected boom\")\n"
    "fn expects_panic() { panic(\"expected boom\") }\n"
    "@test\n"
    "fn returns_failure(): Unit throws i32 { throw 5 }\n")


def test_reports_pass_fail_ignored_and_isolates_panics():
    source = evidence / "tests.mt"
    source.write_text(TEST_SOURCE)
    text = invoke(["test", source], 1, [
        "running 5 tests", "test passes ... ok", "test panics ... FAILED",
        "test skipped ... ignored, slow", "test expects_panic ... ok",
        "test returns_failure ... FAILED", "boom",
        "2 passed; 2 failed; 1 ignored"])
    assert "must not run" not in text, text
    invoke(["test", source, "--include-ignored", "--jobs", "1"], 1,
           ["test skipped ... FAILED", "2 passed; 3 failed; 0 ignored"])
    invoke(["test", source, "--ignored"], 1,
           ["test skipped ... FAILED", "0 passed; 1 failed; 0 ignored"])


def test_filter_exact():
    source = evidence / "tests.mt"
    source.write_text(TEST_SOURCE)
    invoke(["test", source, "pass"], 0,
           ["test passes ... ok", "1 passed; 0 failed; 0 ignored",
            "4 filtered out"])
    invoke(["test", source, "--exact", "pass"], 0,
           ["running 0 tests", "0 passed; 0 failed; 0 ignored"])
    invoke(["test", source, "--exact", "passes", "expects_panic"], 0,
           "2 passed; 0 failed; 0 ignored")


def harness_quoted_names():
    source = evidence / "quoted-tests.mt"
    source.write_text(
        '@test\nfn `if`() {}\n'
        'module `loop` {\n@test\nfn `while`() {}\n}\n'
        '@bench\nfn `else`() {}\n')
    invoke(["test", source], 0,
           ["test if ... ok", "test loop.while ... ok",
            "2 passed; 0 failed; 0 ignored"])
    invoke(["bench", source], 0, ["bench else ... ", "1 measured; 0 failed"])


def bench_reports_timing():
    source = evidence / "bench.mt"
    source.write_text(
        "@bench\n"
        "fn spin() {\n"
        "    var i = 0u32\n"
        "    while i < 100u32 { i += 1u32 }\n"
        "}\n"
        "@bench\n"
        "@ignore\n"
        "fn skipped() {}\n")
    invoke(["bench", source], 0,
           ["bench spin ... ", "ns/iter (median of 11 samples",
            "bench skipped ... ignored", "1 measured; 0 failed; 1 ignored"])
    invoke(["bench", source, "--exact", "other"], 0, "0 measured")
    # A result passes through core::hint::black_box, so returned work is kept.
    kept = evidence / "kept.mt"
    kept.write_text(
        "@bench\n"
        "fn total(): u64 {\n"
        "    var sum = 0u64\n"
        "    var i = core.hint.black_box(0u64)\n"
        "    while i < 1000u64 { sum = (sum ^ i) * 1099511628211u64; i += 1u64 }\n"
        "    sum\n"
        "}\n")
    text = invoke(["bench", kept], 0, "bench total ... ")
    median = float(re.search(r"total \.\.\. ([0-9.]+) ns/iter", text).group(1))
    # 1000 dependent multiplies cannot fold or vanish (~1 ns each).
    assert median > 100, text


def find_dwarfdump():
    for base in (mettle, Path(__file__).resolve()):
        for parent in base.parents:
            # Pinned toolchains of several hosts may sit side by side; take
            # the one that runs here.
            for tool in sorted(parent.glob(".tools/*/llvm/bin/llvm-dwarfdump")):
                try:
                    processes.run([str(tool), "--version"], check=True,
                                   capture_output=True)
                    return tool
                except (OSError, subprocess.SubprocessError):
                    continue
    return shutil.which("llvm-dwarfdump")


def debug_info():
    dwarfdump = find_dwarfdump()
    if dwarfdump is None:
        print("SKIP debug_info: llvm-dwarfdump not found")
        return
    source = evidence / "debuggee.mt"
    source.write_text(
        "macro twice { ($x:expr) => { $x * 2 }; }\n"
        "type Pair<T> { first: T; second: T }\n"
        "interface DebugReadable { fn read_value(): i32; }\n"
        "type DebugValue { value: i32 }\n"
        "extend DebugValue implements DebugReadable {\n"
        "    fn read_value(): i32 { self.value }\n"
        "}\n"
        "type DebugOwner { value: i32 }\n"
        "@layout(C,u8)\n"
        "copy enum Choice { Empty = 7; Value(i64) = 9 }\n"
        "fn add_up(base: i32): i32 {\n"
        "    let doubled: i32 = twice!(base)\n"
        "    doubled + 1\n"
        "}\n"
        "fn first(read values: [i32]): i32 { values[0] }\n"
        "async fn debug_inner(): i32 { 3 }\n"
        "async fn debug_coroutine(): i32 {\n"
        "    let saved: i32 = 4\n"
        "    let resumed = await debug_inner()\n"
        "    saved + resumed\n"
        "}\n"
        "fn scope_probe(): i32 {\n"
        "    let shadowed: i32 = 1\n"
        "    let inner: i32 = {\n"
        "        let shadowed: i32 = 2\n"
        "        shadowed\n"
        "    }\n"
        "    inner + shadowed\n"
        "}\n"
        "fn move_probe(): i32 {\n"
        "    let original = DebugOwner(3)\n"
        "    let moved = take original\n"
        "    moved.value\n"
        "}\n"
        "@inline(always)\n"
        "fn inline_increment(value: i32): i32 { value + 1 }\n"
        "@inline(never)\n"
        "fn inline_boundary(value: i32): i32 { inline_increment(value) }\n"
        "fn main(): i32 {\n"
        "    let pair: Pair<i64> = Pair<i64>(20i64, 22i64)\n"
        "    let data: [i32; 1] = [42; 1]\n"
        "    let data_view: read [i32] = read data\n"
        "    let seed: i32 = 7\n"
        "    let closure = fn(): i32 { seed }\n"
        "    let concrete = DebugValue(1)\n"
        "    let erased: read any DebugReadable = read concrete\n"
        "    let inline_result = inline_boundary(core.hint.black_box(40))\n"
        "    let pending = debug_coroutine()\n"
        "    let choice = Choice.Value(42i64)\n"
        "    match choice {\n"
        "        Choice.Empty => 1,\n"
        "        Choice.Value(_) => add_up(20) - 41 + closure() - 7 + "
        "first(data_view) - 42 + scope_probe() - 3 + move_probe() - 3 + "
        "inline_result - 41 + erased.read_value() - 1\n"
        "    }\n"
        "}\n")
    plain = [evidence / "plain1.o", evidence / "plain2.o"]
    debug = [evidence / "debug1.o", evidence / "debug2.o"]
    debug_ir = evidence / "debug.ll"
    release = evidence / "debug-release.o"
    for output in plain:
        invoke(["build", source, "-o", output, "--emit", "object"])
    for output in debug:
        invoke(["build", source, "-o", output, "--emit", "object", "-g"])
    invoke(["build", source, "-o", debug_ir, "--emit", "llvm", "-g"])
    invoke(["build", source, "-o", release, "--emit", "object", "-g",
            "--profile", "release"])
    assert plain[0].read_bytes() == plain[1].read_bytes()
    assert debug[0].read_bytes() == debug[1].read_bytes()
    assert plain[0].read_bytes() != debug[0].read_bytes()
    # Without -g no DWARF or source path may appear. ELF objects still carry
    # the standard STT_FILE symbol naming the source's basename; Mach-O has none.
    plain_bytes = plain[0].read_bytes()
    assert str(source.parent).encode() not in plain_bytes, "source path in plain object"
    plain_info = processes.run([str(dwarfdump), "--debug-info", str(plain[0])],
                                text=True, capture_output=True, check=True).stdout
    assert "DW_TAG_compile_unit" not in plain_info, plain_info
    if not plain_bytes.startswith(b"\x7fELF"):
        assert b"debuggee.mt" not in plain_bytes, "source name in plain object"
    processes.run([str(dwarfdump), "--verify", str(debug[0])],
                   text=True, capture_output=True, check=True)
    info = processes.run([str(dwarfdump), "--debug-info", str(debug[0])],
                          text=True, capture_output=True, check=True).stdout
    assert "DW_TAG_compile_unit" in info, info
    assert "DW_TAG_subprogram" in info and '"add_up"' in info, info
    assert "DW_TAG_variable" in info and '"doubled"' in info, info
    assert "DW_TAG_formal_parameter" in info and '"base"' in info, info
    assert '"Pair<i64>"' in info, info
    assert re.search(r'DW_TAG_member(?:(?!DW_TAG_).)*"seed"',
                     info, re.DOTALL), info
    assert '"read [i32]"' in info, info
    assert '"read any DebugReadable"' in info
    assert re.search(r'DW_TAG_member(?:(?!DW_TAG_).)*"data_ptr"',
                     info, re.DOTALL), info
    assert re.search(r'DW_TAG_member(?:(?!DW_TAG_).)*"length"',
                     info, re.DOTALL), info
    assert re.search(r'DW_TAG_member(?:(?!DW_TAG_).)*"witness"',
                     info, re.DOTALL), info
    assert re.search(r'DW_TAG_member(?:(?!DW_TAG_).)*"alignment"',
                     info, re.DOTALL), info
    assert "MettleWitness<" in info, info
    assert '"method.0"' in info, info
    assert "DW_TAG_lexical_block" in info and info.count('"shadowed"') >= 2, info
    assert "DW_TAG_variant_part" in info and '"Value"' in info, info
    assert '"discriminant"' in info, info
    assert '"state"' in info and "await #1 (line " in info, info
    assert re.search(r'DW_TAG_member(?:(?!DW_TAG_).)*"saved"',
                     info, re.DOTALL), info
    for discriminant in ("7", "9"):
        assert re.search(r"DW_AT_discr_value\s*\(\s*(?:0x0*)?" +
                         discriminant + r"\b", info), info
    assert "debuggee.mt" in info, info
    ir_text = debug_ir.read_text()
    moved = re.search(r'(!\d+) = !DILocalVariable\(name: "original"', ir_text)
    assert moved, ir_text
    # A variable is declared on an address slot; moving it nulls the slot.
    slot = re.search(r'#dbg_declare\(ptr (%\d+), ' +
                     re.escape(moved.group(1)) + r',', ir_text)
    assert slot, ir_text
    assert re.search(r'store ptr null, ptr ' + re.escape(slot.group(1)) +
                     r'\b', ir_text), ir_text
    release_info = processes.run(
        [str(dwarfdump), "--debug-info", str(release)],
        text=True, capture_output=True, check=True).stdout
    assert "DW_TAG_inlined_subroutine" in release_info, release_info
    assert '"inline_increment"' in release_info, release_info
    assert "DW_AT_call_file" in release_info and \
        "DW_AT_call_line" in release_info, release_info
    lines = processes.run([str(dwarfdump), "--debug-line", str(debug[0])],
                           text=True, capture_output=True, check=True).stdout
    invocation_line = next(i for i, line in enumerate(
        source.read_text().splitlines(), 1) if "twice!(base)" in line)
    assert any(row.split()[1:2] == [str(invocation_line)]
               for row in lines.splitlines()
               if row.startswith("0x")), lines
    return_line = next(i for i, line in enumerate(
        source.read_text().splitlines(), 1) if "doubled + 1" in line)
    assert any(row.split()[1:2] == [str(return_line)]
               for row in lines.splitlines()
               if row.startswith("0x")), lines


def find_lldb():
    candidates = []
    xcrun = shutil.which("xcrun")
    if xcrun:
        try:
            result = processes.run([xcrun, "--find", "lldb"], text=True,
                                    capture_output=True)
            if result.returncode == 0 and result.stdout.strip():
                candidates.append(result.stdout.strip())
        except (OSError, subprocess.SubprocessError):
            pass
    for base in (mettle, Path(__file__).resolve()):
        for parent in base.parents:
            candidates.extend(sorted(
                str(tool) for tool in
                parent.glob(".tools/*/llvm/bin/lldb")))
    if found := shutil.which("lldb"):
        candidates.append(found)
    for tool in dict.fromkeys(candidates):
        try:
            result = processes.run([tool, "--version"], capture_output=True)
            if result.returncode == 0:
                return tool
        except (OSError, subprocess.SubprocessError):
            continue
    return None


def debugger_workflow():
    lldb = find_lldb()
    if lldb is None:
        print("SKIP debugger_workflow: LLDB not found (xcrun or PATH/toolchain)")
        return

    source = evidence / "debuggee.mt"
    source.write_text(
        "import alloc.vec\nimport alloc.vec.List\n"
        "import core.future.{Context, Poll, noop_waker}\n"
        "import std.task\n"
        "interface DebugReadable { fn read_value(): i32; }\n"
        "type DebugValue { value: i32 }\n"
        "extend DebugValue implements DebugReadable {\n"
        "    fn read_value(): i32 { self.value }\n"
        "}\n"
        "@layout(C,u8)\n"
        "copy enum DebugChoice { Empty = 7; Value(i32) = 9 }\n"
        "async fn debug_coroutine(): i32 {\n"
        "    await task.yield_now();\n"
        "    42\n"
        "}\n"
        "fn inspect(base: i32): i32 {\n"
        "    let result = base + 1\n"
        "    result\n"
        "}\n"
        "fn main(): i32 {\n"
        "    var items = vec.new<i32>()\n"
        "    items.push(7)\n"
        "    let backing: [i32; 2] = [3; 2]\n"
        "    let slice: read [i32] = read backing\n"
        "    let choice = DebugChoice.Value(42)\n"
        "    let concrete = DebugValue(7)\n"
        "    let erased: read any DebugReadable = read concrete\n"
        "    var slot = core.pin.pin(debug_coroutine())\n"
        "    let waker = noop_waker()\n"
        "    var cx = Context.from_waker(read waker)\n"
        "    match take slot.as_mut().poll(mut cx) {\n"
        "        Poll.Pending => {},\n"
        "        Poll.Ready(_) => { return 1 }\n"
        "    }\n"
        "    let coroutine = unsafe { slot.as_mut().get_unchecked_mut() }\n"
        "    let result = inspect(41)\n"
        "    if result != 42 || items.len() != 1usize || "
        "slice.len() != 2usize { return 2 }\n"
        "    if erased.read_value() != 7 { return 3 }\n"
        "    match choice {\n"
        "        DebugChoice.Empty => 4,\n"
        "        DebugChoice.Value(value) => value - 42\n"
        "    }\n"
        "}\n")
    output = evidence / "debugger-workflow"
    invoke(["build", source, "-o", output, "-g", "--profile", "debug"])

    lines = source.read_text().splitlines()
    main_line = next(i for i, line in enumerate(lines, 1)
                     if "let result = inspect(41)" in line)
    inspect_line = next(i for i, line in enumerate(lines, 1)
                        if "let result = base + 1" in line)
    await_line = next(i for i, line in enumerate(lines, 1)
                      if "await task.yield_now()" in line)
    script = Path(__file__).resolve().parents[1] / "tools/debug/mettle_lldb.py"
    commands = [
        lldb, "--batch",
        "-o", f'command script import "{script}"',
        "-o", f"breakpoint set --file debuggee.mt --line {main_line}",
        "-o", f"breakpoint set --file debuggee.mt --line {inspect_line}",
        "-o", "run",
        "-o", "frame variable",
        "-o", "frame variable coroutine",
        "-o", "continue",
        "-o", "frame variable",
        "-o", "next",
        "-o", "frame variable",
        "-o", "continue",
        "--", str(output),
    ]
    result = processes.run(commands, text=True, capture_output=True)
    text = result.stdout + result.stderr
    assert result.returncode == 0, f"{commands}: {text}"
    assert "stop reason = breakpoint" in text, text
    assert f"debuggee.mt:{main_line}" in text, text
    assert f"debuggee.mt:{inspect_line}" in text, text
    assert "base" in text and "i32" in text, text
    assert "List len=1 cap=" in text, text
    assert "slice len=2" in text, text
    assert "DebugChoice" in text and "Value" in text, text
    assert "read any DebugReadable" in text and "erased data=" in text, text
    assert f"state = await #1 (line {await_line})" in text, text
    assert "exited with status = 0" in text, text


DOC_SOURCE = (
    "//! Arithmetic helpers.\n"
    "//!\n"
    "//! Use `add` to sum.\n"
    "\n"
    "/// Adds two numbers.\n"
    "///\n"
    "/// ```\n"
    "/// ~ let unused = 0\n"
    "/// if add(1, 2) != 3 { panic(\"bad add\") }\n"
    "/// ```\n"
    "pub fn add(a: i32, b: i32): i32 { a + b }\n"
    "\n"
    "/// Doubles a number.\n"
    "///\n"
    "/// ```\n"
    "/// if twice(2) != 5 { panic(\"doc boom\") }\n"
    "/// ```\n"
    "///\n"
    "/// ```compile_fail(type)\n"
    "/// let x: i32 = true\n"
    "/// ```\n"
    "///\n"
    "/// ```should_panic\n"
    "/// panic(\"expected\")\n"
    "/// ```\n"
    "///\n"
    "/// ```no_run\n"
    "/// loop {}\n"
    "/// ```\n"
    "///\n"
    "/// ```text\n"
    "/// not code\n"
    "/// ```\n"
    "pub fn twice(a: i32): i32 { add(a, a) }\n"
    "fn private_helper(): i32 { 1 }\n")


def doc_writes_deterministic_html():
    source = evidence / "maths.mt"
    source.write_text(DOC_SOURCE)
    first, second = evidence / "doc-a", evidence / "doc-b"
    invoke(["doc", source, "-o", first], 0, "documented 1 module")
    invoke(["doc", source, "-o", second], 0, "documented 1 module")
    names = sorted(path.name for path in first.iterdir())
    assert names == ["index.html", "maths.html", "search-index.js",
                     "search-index.json", "search.js", "style.css"], names
    for name in names:
        assert (first / name).read_bytes() == (second / name).read_bytes(), name
    page = (first / "maths.html").read_text()
    for needle in ["<h1>maths</h1>", "Use <code>add</code> to sum.",
                   "Adds two numbers.",
                   '<pre class="sig"><code>pub fn add(a: i32, b: i32): i32'
                   "</code></pre>", "<figcaption>compile_fail(type)"]:
        assert needle in page, needle
    # Non-Mettle fences are shown as text; hidden lines, bodies and private
    # items stay out of the page.
    assert "not code" in page
    for needle in ["unused", "a + b", "private_helper"]:
        assert needle not in page, needle
    assert "maths" in (first / "index.html").read_text()
    search = json.loads((first / "search-index.json").read_text())
    assert {"name": "maths.add", "href": "maths.html#add"} in search
    invoke(["doc", source, "-o", first, "--private"], 0)
    assert "private_helper" in (first / "maths.html").read_text()
    # A source that does not parse is reported, not documented.
    broken = evidence / "broken.mt"
    broken.write_text("pub fn (\n")
    invoke(["doc", broken, "-o", evidence / "doc-c"], 1, "error[parse]")


def doc_resolves_dependency_links_and_warns():
    app = packages("path-dependency/app")
    source = app / "src/main.mt"
    source.write_text(
        "/// Links: [mathlib.twice.double], `mathlib.answer`, and "
        "a missing [missing.item].\n" +
        source.read_text())
    mathlib_source = app.parent / "mathlib/src/main.mt"
    mathlib_text = mathlib_source.read_text()
    assert "pub fn answer" in mathlib_text
    # Cross-package links need a public path to the target.
    mathlib_source.write_text(mathlib_text.replace(
        "pub fn answer",
        "/// Transitive dependency link: [units.base].\npub fn answer").replace(
            "\nmodule twice", "\npub module twice"))
    output = evidence / "doc-package"
    text = invoke(["doc", app, "--offline", "--private", "-o", output],
                  0, "warning[doc-link]")
    assert "unresolved documentation reference 'missing.item'" in text, text
    page = (output / "main.html").read_text()
    assert '<a href="mathlib.twice.html#double">mathlib.twice.double</a>' in page
    assert '<a href="mathlib.html#answer">mathlib.answer</a>' in page
    math_page = (output / "mathlib.html").read_text()
    assert '<a href="units.html#base">units.base</a>' in math_page


def doctests_run_isolated_examples():
    source = evidence / "maths.mt"
    source.write_text(DOC_SOURCE)
    text = invoke(["test", source], 1, [
        "Doc-tests", "test maths - add (line 8) ... ok",
        "test maths - twice (line 16) ... FAILED", "doc boom",
        "test maths - twice (line 20) ... ok, failed to compile as declared",
        "test maths - twice (line 24) ... ok",
        "test maths - twice (line 28) ... ok, compiled, not run",
        "4 passed; 1 failed; 0 ignored"])
    assert "not code" not in text, text
    invoke(["test", source, "--doc", "add"], 0,
           ["test maths - add (line 8) ... ok", "1 passed; 0 failed",
            "4 filtered out"])
    # An example that is not valid Mettle fails alone; the others still run.
    source.write_text(DOC_SOURCE.replace("panic(\"expected\")",
                                         "let = ;"))
    invoke(["test", source, "--doc"], 1,
           ["test maths - add (line 8) ... ok",
            "test maths - twice (line 24) ... FAILED",
            "the example does not compile"])


class LanguageClient:
    """Drives `mettle lsp` with Content-Length framed JSON-RPC."""

    def __init__(self):
        self.process = subprocess.Popen(
            [str(mettle), "lsp"], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0,
            start_new_session=os.name == "posix")
        os.set_blocking(self.process.stdin.fileno(), False)
        self.buffer = bytearray()
        self.next_id = 0

    def __enter__(self):
        try:
            reply = self.request("initialize", {
                "processId": None, "rootUri": None, "capabilities": {}})
            assert "result" in reply, reply
            self.notify("initialized", {})
            return self
        except BaseException:
            processes.kill(self.process)
            self.process.communicate()
            raise

    def __exit__(self, kind, value, traceback):
        try:
            if kind is None:
                assert "result" in self.request("shutdown", None)
                self.notify("exit", None)
                assert self.process.wait() == 0
        finally:
            processes.kill(self.process)
            self.process.communicate()

    def checked(self, path, text=None):
        uri = path.as_uri()
        contents = path.read_text() if text is None else text
        self.open(uri, contents)
        published = self.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == uri)["params"]["diagnostics"]
        assert published == [], f"{path}: {published}\n{contents}"
        return {"uri": uri}

    def close(self, document):
        self.notify("textDocument/didClose", {"textDocument": document})
        published = self.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == document["uri"])["params"]["diagnostics"]
        assert published == [], (document, published)

    def ready(self, stream, writing=False):
        select.select([] if writing else [stream], [stream] if writing else [], [])

    def send(self, message):
        body = json.dumps({"jsonrpc": "2.0", **message}).encode()
        pending = memoryview(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        while pending:
            self.ready(self.process.stdin, writing=True)
            try:
                written = os.write(self.process.stdin.fileno(), pending)
            except BlockingIOError:
                continue
            pending = pending[written:]

    def read(self, count):
        while len(self.buffer) < count:
            self.ready(self.process.stdout)
            data = os.read(self.process.stdout.fileno(), 65536)
            if not data:
                raise AssertionError("language server closed its output")
            self.buffer.extend(data)
        result = bytes(self.buffer[:count])
        del self.buffer[:count]
        return result

    def receive(self):
        length = None
        while True:
            line = bytearray()
            while not line.endswith(b"\n"):
                line.extend(self.read(1))
            line = line.strip()
            if not line:
                break
            name, _, value = line.decode().partition(":")
            if name.lower() == "content-length":
                if length is not None:
                    raise AssertionError("duplicate language-server Content-Length")
                length = int(value)
        if length is None or length < 0:
            raise AssertionError("invalid language-server Content-Length")
        return json.loads(self.read(length))

    def notify(self, method, params):
        self.send({"method": method, "params": params})

    def request(self, method, params):
        self.next_id += 1
        self.send({"id": self.next_id, "method": method, "params": params})
        return self.wait(lambda m: m.get("id") == self.next_id)

    def wait(self, accept):
        for _ in range(100):
            message = self.receive()
            if accept(message):
                return message
        raise AssertionError("expected message never arrived")

    def open(self, uri, text):
        self.notify("textDocument/didOpen", {"textDocument": {
            "uri": uri, "languageId": "mettle", "version": 1, "text": text}})


def language_server():
    broken = "file:///workspace/broken.mt"
    clean = "file:///workspace/clean.mt"
    client = LanguageClient()
    try:
        reply = client.request("initialize", {"processId": None,
                                              "rootUri": None,
                                              "capabilities": {}})
        capabilities = reply["result"]["capabilities"]
        assert capabilities["definitionProvider"], capabilities
        assert capabilities["referencesProvider"], capabilities
        assert capabilities["completionProvider"], capabilities
        assert capabilities["signatureHelpProvider"], capabilities
        assert capabilities["renameProvider"], capabilities
        client.notify("initialized", {})

        # An unknown name on the second line is reported at that identifier.
        client.open(broken, "fn main(): i32 {\n    missing_name\n}\n")
        published = client.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == broken)["params"]["diagnostics"]
        assert published, "expected a diagnostic"
        diagnostic = published[0]
        assert diagnostic["severity"] == 1, diagnostic
        assert diagnostic["range"]["start"] == {"line": 1, "character": 4}, \
            diagnostic
        assert diagnostic["range"]["end"] == {"line": 1, "character": 16}, \
            diagnostic

        with_help = "file:///workspace/let-mut.mt"
        client.open(with_help, "fn main() { let mut value = 1 }\n")
        published = client.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == with_help)["params"]["diagnostics"]
        assert any("help: use `var` for a mutable local binding"
                   in item["message"] for item in published), published

        readable = "file:///workspace/readable-types.mt"
        client.open(readable,
                    "type Record<T> { value: T }\n"
                    "fn accepts(value: Record<i32>) {}\n"
                    "fn main() {\n"
                    "    let value: Record<bool> = Record(true)\n"
                    "    accepts(value)\n"
                    "}\n")
        published = client.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == readable)["params"]["diagnostics"]
        assert any("expected Record<i32>, found Record<bool>" in item["message"]
                   for item in published), published

        # Incomplete source still produces diagnostics and keeps serving.
        client.notify("textDocument/didChange", {
            "textDocument": {"uri": broken, "version": 2},
            "contentChanges": [{"text": "fn main(): i32 {\n    let x =\n"}]})
        client.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == broken and m["params"]["diagnostics"])

        client.open(clean, "fn double(x: i32): i32 { x + x }\n"
                           "fn main(): i32 {\n"
                           "    let total = double(21)\n"
                           "    total - 42\n"
                           "}\n")
        published = client.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == clean)["params"]["diagnostics"]
        assert published == [], published

        floating = "file:///workspace/floating-constants.mt"
        client.open(floating,
                    "const BITS: u64 = f64.from_bits(0xfff0123456789abcu64).to_bits()\n"
                    "fn main(): i32 { if BITS == 0xfff0123456789abcu64 { 0 } else { 1 } }\n")
        published = client.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == floating)["params"]["diagnostics"]
        assert published == [], published
        client.notify("textDocument/didChange", {
            "textDocument": {"uri": floating, "version": 2},
            "contentChanges": [{"text":
                "const VALUE: f32 = f32.from_bits(1u64)\nfn main(): i32 { 0 }\n"}]})
        published = client.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == floating)["params"]["diagnostics"]
        assert any("expected u32, found u64" in item["message"]
                   for item in published), published

        document = {"uri": clean}
        found = client.request("textDocument/definition", {
            "textDocument": document,
            "position": {"line": 2, "character": 17}})["result"]
        assert found == [{"uri": clean, "range": {
            "start": {"line": 0, "character": 3},
            "end": {"line": 0, "character": 9}}}], found

        changes = client.request("textDocument/rename", {
            "textDocument": document,
            "position": {"line": 3, "character": 5},
            "newName": "sum"})["result"]["changes"]
        assert [(e["range"]["start"], e["range"]["end"], e["newText"])
                for e in changes[clean]] == [
            ({"line": 2, "character": 8}, {"line": 2, "character": 13}, "sum"),
            ({"line": 3, "character": 4}, {"line": 3, "character": 9}, "sum"),
        ], changes

        references = client.request("textDocument/references", {
            "textDocument": document,
            "position": {"line": 3, "character": 5},
            "context": {"includeDeclaration": True}})["result"]
        assert [ref["range"]["start"] for ref in references] == [
            {"line": 2, "character": 8},
            {"line": 3, "character": 4},
        ], references

        completions = client.request("textDocument/completion", {
            "textDocument": document,
            "position": {"line": 2, "character": 19}})["result"]
        assert any(item["label"] == "double" for item in completions), \
            completions

        refused = client.request("textDocument/rename", {
            "textDocument": document,
            "position": {"line": 3, "character": 5},
            "newName": "fn"})
        assert "error" in refused, refused

        symbols = client.request("textDocument/documentSymbol",
                                 {"textDocument": document})["result"]
        assert [s["name"] for s in symbols] == ["double", "main"], symbols

        inferred = "file:///workspace/inferred.mt"
        client.open(inferred, "fn inferred(value: i32) { value }\n"
                             "fn main(): i32 { inferred(1) }\n")
        client.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == inferred)
        inferred_hover = client.request("textDocument/hover", {
            "textDocument": {"uri": inferred},
            "position": {"line": 0, "character": 5}})["result"]
        assert ": i32" in inferred_hover["contents"]["value"], inferred_hover

        signature = "file:///workspace/signature.mt"
        client.open(signature,
                    "fn add(left: i32, right: i32): i32 { left + right }\n"
                    "fn main(): i32 { add(1, ) }\n")
        client.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == signature)
        help_result = client.request("textDocument/signatureHelp", {
            "textDocument": {"uri": signature},
            "position": {"line": 1, "character": 24}})["result"]
        assert help_result["activeParameter"] == 1, help_result

        pattern = "file:///workspace/pattern.mt"
        client.open(pattern, "fn main(): i32 { match 1 { value => value } }\n")
        client.wait(
            lambda m: m.get("method") == "textDocument/publishDiagnostics"
            and m["params"]["uri"] == pattern)
        pattern_references = client.request("textDocument/references", {
            "textDocument": {"uri": pattern},
            "position": {"line": 0, "character": 30},
            "context": {"includeDeclaration": True}})["result"]
        assert len(pattern_references) == 2, pattern_references

        assert "result" in client.request("shutdown", None)
        client.notify("exit", None)
        assert client.process.wait() == 0
    finally:
        processes.kill(client.process)
        client.process.communicate()


def test_json_timeout_and_modules():
    source = evidence / "module-tests.mt"
    source.write_text(
        "module extras;\n"
        "module inline_tests {\n"
        "    @test\n"
        "    fn inline_passes() {}\n"
        "    @bench\n"
        "    fn inline_bench() {}\n"
        "}\n"
        "@test\n"
        "fn top_level() {}\n"
        "@test\n"
        "fn panic_report() { panic(\"json panic\") }\n"
        "@test\n"
        "fn hangs() { loop {} }\n"
        "@bench\n"
        "fn root_bench() {}\n")
    (evidence / "extras.mt").write_text(
        "/// Module docs.\n"
        "///\n"
        "/// ```\n"
        "/// if value() != 1 { panic(\"bad module doctest\") }\n"
        "/// ```\n"
        "fn value(): i32 { 1 }\n"
        "@test\n"
        "fn sub_passes() {}\n"
        "@bench\n"
        "fn sub_bench() {}\n")

    events = invoke_json(
        ["test", source, "--format", "json", "--timeout", "1", "--jobs", "2"],
        1)
    assert events[0]["event"] == "suite"
    assert events[-1]["event"] == "summary"
    expected_keys = {
        "suite": ["event", "name", "total", "filtered"],
        "test": ["event", "name", "outcome", "duration_ns", "output",
                  "message"],
        "summary": ["event", "passed", "failed", "ignored", "terminated",
                     "infrastructure_failures", "timed_out", "filtered"],
    }
    for event in events:
        assert list(event) == expected_keys[event["event"]], event
    outcomes = {event["name"]: event for event in events
                 if event["event"] == "test"}
    assert outcomes["inline_tests.inline_passes"]["outcome"] == "passed"
    assert outcomes["extras.sub_passes"]["outcome"] == "passed"
    assert outcomes["panic_report"]["output"].find("json panic") >= 0
    assert outcomes["hangs"]["outcome"] == "timed_out"
    assert any(event["event"] == "summary" and event["timed_out"] == 1
                for event in events), events

    benches = invoke_json([
        "bench", source, "--format", "json", "--exact",
        "inline_tests.inline_bench", "extras.sub_bench"])
    assert benches[0]["event"] == "suite"
    assert benches[-1]["event"] == "summary"
    measured = {event["name"] for event in benches
                if event.get("outcome") == "measured"}
    assert measured == {"inline_tests.inline_bench",
                        "extras.sub_bench"}, benches

    doctests = invoke_json(["test", source, "--doc", "--format", "json"])
    assert doctests[0]["event"] == "suite"
    assert doctests[-1]["event"] == "summary"
    assert any(
        event["event"] == "test" and event["name"].startswith("extras - ") and
        event["outcome"] == "passed" for event in doctests
    ), doctests


def driver_output_preserves_imports():
    directory = packages("driver-contracts/output-alias")
    main, helper = directory / "main.mt", directory / "helper.mt"
    original = helper.read_bytes()
    for flags in (["--no-cache"], []):
        if not flags:
            invoke(["build", main, "--emit", "object", "-o",
                    evidence / "warm.o"])
        invoke(["build", main, "--emit", "object", "-o", helper, *flags], 1,
               ["error[io]", "output would overwrite the source"])
        assert helper.read_bytes() == original
    linked, ir = directory / "helper.o", directory / "helper.ll"
    os.link(helper, linked)
    ir.write_bytes(b"preserved IR output\n")
    (directory / "package.mettle").write_text(
        'name: "output-alias"\nversion: "0.1.0"\nentry: "main.mt"\n'
        'emit: ["object", "llvm"]\n')
    invoke(["build", directory, "-o", directory / "helper"], 1,
           ["error[io]", "output would overwrite the source"])
    assert os.path.samefile(linked, helper)
    assert helper.read_bytes() == linked.read_bytes() == original
    assert ir.read_bytes() == b"preserved IR output\n"
    if os.name == "posix":
        alias = directory / "alias.o"
        alias.symlink_to(helper)
        target = os.readlink(alias)
        invoke(["build", main, "--emit", "object", "-o", alias], 1,
               ["error[io]", "output would overwrite the source"])
        assert alias.is_symlink() and os.readlink(alias) == target
        assert helper.read_bytes() == original
    if sys.platform == "darwin":
        bundle = directory / "preserved"
        tree = Path(str(bundle) + ".dSYM")
        tree.mkdir()
        for source in (main, helper):
            shutil.copy2(source, tree / source.name)
        saved = {p.name: p.read_bytes() for p in (tree / main.name,
                                                 tree / helper.name)}
        invoke(["build", tree / main.name, "-o", bundle, "-g"], 1,
               ["error[io]", "output would overwrite the source"])
        assert {name: (tree / name).read_bytes() for name in saved} == saved


def driver_panic_rejects_other_signals():
    if os.name != "posix":
        print("SKIP driver_panic_rejects_other_signals: hosted POSIX signals")
        return
    directory = packages("driver-contracts/panic-verdict")
    source = directory / "fatal-signal.mt"
    original = source.read_text()
    for number in (11, 4):
        source.write_text(original.replace("raise(11)", f"raise({number})"))
        events = invoke_json(["test", source, "--format", "json"], 1)
        tests = [e for e in events if e["event"] == "test"]
        assert len(tests) == 1 and tests[0]["outcome"] == "terminated", events
        assert events[-1]["event"] == "summary", events
        assert events[-1]["passed"] == 0 and events[-1]["terminated"] == 1
        assert events[-1]["infrastructure_failures"] == 0
    events = invoke_json(["test", directory / "expected-abort.mt",
                          "--format", "json"])
    assert [e["outcome"] for e in events if e["event"] == "test"] == ["passed"]
    assert events[-1]["passed"] == 1 and events[-1]["terminated"] == 0


def driver_compile_fail_requires_checking():
    source = packages("driver-contracts/compile-fail-link.mt")
    events = invoke_json(["test", source, "--doc", "--format", "json"], 1)
    tests = [e for e in events if e["event"] == "test"]
    assert len(tests) == 1 and tests[0]["outcome"] == "failed", events
    assert "expected phase" in tests[0]["message"], tests
    assert re.search(r"(?m)^[^\n]*error\[link\]:", tests[0]["output"]), tests
    assert "missing_doctest_symbol" in tests[0]["output"], tests
    assert "failed to compile as declared" not in tests[0]["message"]
    controls = evidence / "checking-doctests.mt"
    arch = os.uname().machine if os.name == "posix" else ""
    unsupported = ("_mm_aesenc_si128" if arch == "x86_64" else
                   "vaeseq_u8" if arch in ("aarch64", "arm64") else None)
    architecture = "x86_64" if arch == "x86_64" else "aarch64"
    controls_list = [
            ("compile_fail", "let value: i32 = true", 0),
            ("compile_fail(type)", 'let value: i32 = "error[internal]"', 0),
            ("compile_fail(lex)", 'let value = "', 0),
            ("compile_fail(parse)", "let = ;", 0),
            ("compile_fail", "let value: i32 = 42", 1)]
    if unsupported:
        controls_list.append(("compile_fail",
            f"unsafe {{ core.arch.{architecture}.{unsupported}() }};", 1))
    for fence, body, expected in controls_list:
        controls.write_text(
            f"/// ```{fence}\n/// {body}\n/// ```\npub fn documented() {{}}\n")
        events = invoke_json(["test", controls, "--doc", "--format", "json"],
                             expected)
        tests = [e for e in events if e["event"] == "test"]
        assert len(tests) == 1, events
        assert tests[0]["outcome"] == ("passed" if expected == 0 else "failed")
        if expected == 0:
            assert tests[0]["message"] == "failed to compile as declared"
        elif "core.arch" in body:
            assert re.search(r"(?m)^[^\n]*error\[feature\]: "
                             r"unsupported architecture operation",
                             tests[0]["output"]), tests


def driver_feature_backtracks():
    root = packages("driver-contracts/feature-backtracking")
    app = root / "app"
    build_and_run(app)
    lock = lock_of(app)
    assert re.search(r'name: "widget"\s+version: "1\.0\.0"', lock), lock
    assert not re.search(r'name: "widget"\s+version: "2\.0\.0"', lock), lock
    edit(root / "registry/widget/1.0.0/package.mettle",
         "features { old_api: [] }", "")
    (app / "lock.mettle").unlink()
    invoke(["check", app], 1, ["error[package]", "has no feature 'old_api'"])


def driver_git_host_outputs_preserve_package_paths():
    if os.name != "posix":
        print("SKIP driver_git_host_outputs_preserve_package_paths: POSIX views")
        return
    base = packages("driver-contracts/git-script")
    host = packages("driver-contracts/git-script-host")
    shutil.copytree(base, host)
    for root in (base, host):
        repository, app = root / "repository", root / "app"

        def git(directory, *arguments):
            return processes.run(["git", "-C", directory, *arguments],
                                 check=True, capture_output=True,
                                 text=True).stdout.strip()

        if root == host:
            manifest = repository / "package.mettle"
            manifest.write_text(manifest.read_text() +
                '"build-dependencies" {\n'
                ' helper { path: "nested/helper", features: ["host"], '
                'default_features: false }\n}\n')
            for name in ("build.mt", "macros/git_value.mt"):
                edit(repository / name, "fn run(): i32 throws Error {\n",
                     "fn run(): i32 throws Error {\n"
                     "    if helper.answer() != 7 { return 1 }\n")
            output_root = root / "tool-outputs"
            output_root.mkdir()
            (app / "target").symlink_to(output_root, target_is_directory=True)
        alias = root / "selected-checkout"
        (repository / "absolute-spec.txt").symlink_to(alias / "spec.txt")
        (repository / "namespace").symlink_to("nested", target_is_directory=True)
        (repository / "build.mt").chmod(0o755)
        git(repository, "init")
        git(repository, "checkout", "-b", "main")
        git(repository, "config", "user.name", "Mettle package test")
        git(repository, "config", "user.email", "packages-test@example.invalid")
        git(repository, "add", ".")
        git(repository, "commit", "-m", "script and macro inputs")
        revision = git(repository, "rev-parse", "HEAD")
        url = repository.as_uri()
        edit(app / "package.mettle", "__GIT_URL__", url)
        source_root = (evidence / "cache/sources/git/checkouts" /
                       hashlib.sha256(url.encode()).hexdigest())
        checkout = source_root / revision
        checkout.parent.mkdir(parents=True, exist_ok=True)
        processes.run(["git", "clone", "--no-hardlinks", "--", repository,
                       checkout], check=True, capture_output=True)
        git(checkout, "checkout", "--detach", revision)
        alias.symlink_to(checkout, target_is_directory=True)
        outside = source_root / "outside"
        shutil.copytree(root / "outside", outside)
        outside_bytes = (outside / "input.txt").read_bytes()
        names = git(checkout, "ls-files", "-z").rstrip("\0").split("\0")

        def snapshot():
            return {name: (os.readlink(checkout / name)
                           if (checkout / name).is_symlink()
                           else (checkout / name).read_bytes(),
                           (checkout / name).lstat().st_mode)
                    for name in names}

        original = snapshot()
        build_and_run(app)
        lock = lock_of(app)
        views = sorted(p.resolve() for p in
                       (app / "target/mettle/package-work").glob("*/tree"))
        copies = [view / checkout.relative_to(checkout.anchor)
                  for view in views]
        assert copies and all((copy / ".git").is_dir() for copy in copies)
        for copy in copies:
            assert Path(git(copy, "rev-parse", "--show-toplevel")).resolve() == copy
            assert git(copy, "rev-parse", "HEAD") == revision
            for name in names:
                selected, staged = checkout / name, copy / name
                if not selected.is_symlink():
                    assert staged.read_bytes() == selected.read_bytes(), name
                    assert staged.stat().st_mode == selected.stat().st_mode, name
                    assert not os.path.samefile(staged, selected), name
            assert (copy / "absolute-spec.txt").resolve() == copy / "spec.txt"
            assert (copy / "namespace").resolve() == copy / "nested"
        for _ in range(2):
            text, binary = explained(app, "--offline", "--locked")
            assert exit_code(binary) == 0
            for tool in ("build script of 'generated-git'",
                         "build script of 'helper'", "procedural macro 'git_value!'"):
                assert any(tool in line and "reused (declared reproducible" in line
                           for line in text.splitlines()), text
            assert lock_of(app) == lock
            assert sorted(p.resolve() for p in
                          (app / "target/mettle/package-work").glob("*/tree")) == views
        if root == host:
            generated = [p.read_text() for copy in copies
                         if (p := copy / "nested/helper/target/mettle/out/nested.mt").is_file()]
            assert "pub fn value(): i32 { 7 }\n" in generated, generated
            assert "pub fn value(): i32 { 42 }\n" in generated, generated
        copied_input = copies[0] / "spec.txt"
        copied_input.write_text("invalid private edit\n")
        build_and_run(app, "--offline", "--locked")
        assert copied_input.read_bytes() == (checkout / "spec.txt").read_bytes()
        generated = [p for copy in copies
                     if (p := copy / "target/mettle/out/generated.mt").is_file()]
        assert generated
        generated[0].write_text("invalid generated output\n")
        text, binary = explained(app, "--offline", "--locked")
        assert exit_code(binary) == 0
        assert any("build script of 'generated-git'" in line and "rerun (" in line
                   for line in text.splitlines()), text
        assert snapshot() == original and git(checkout, "rev-parse", "HEAD") == revision
        assert git(checkout, "status", "--porcelain", "--untracked-files=all") == ""
        assert (outside / "input.txt").read_bytes() == outside_bytes
        destination = checkout / "attempt.o"
        invoke(["build", app, "--emit", "object", "-o", destination], 1,
               ["error[io]", "output would overwrite the source"])
        assert not destination.exists() and snapshot() == original
        untracked = checkout / "untracked.mt"
        untracked.write_text("pub fn injected(): i32 { 0 }\n")
        invoke(["check", app, "--offline", "--locked"], 1,
               "cached checkout contains modified or untracked files")
        untracked.unlink()
        tracked = checkout / "spec.txt"
        saved = tracked.read_bytes()
        tracked.write_bytes(saved + b"// dirty\n")
        try:
            invoke(["check", app, "--offline", "--locked"], 1,
                   "cached checkout contains modified or untracked files")
        finally:
            tracked.write_bytes(saved)
        assert snapshot() == original
        edit(repository / "spec.txt", "{ 42 }", "{ 43 }")
        git(repository, "add", "spec.txt")
        git(repository, "commit", "-m", "changed declared input")
        changed = git(repository, "rev-parse", "HEAD")
        assert changed != revision
        alias.unlink()
        alias.symlink_to(source_root / changed, target_is_directory=True)
        text, binary = explained(app)
        assert exit_code(binary) == 2, text
        assert changed in lock_of(app) and lock_of(app) != lock
        assert snapshot() == original
        assert git(checkout, "rev-parse", "HEAD") == revision
        assert git(checkout, "status", "--porcelain", "--untracked-files=all") == ""
        assert (outside / "input.txt").read_bytes() == outside_bytes


def driver_host_scripts_consume_generated_context():
    root = packages("driver-contracts/host-script-order")
    app = root / "app"
    build_and_run(app)
    bridge = root / "bridge"
    (bridge / "src").mkdir(parents=True)
    (bridge / "package.mettle").write_text(
        'name: "bridge"\nversion: "0.1.0"\nkind: "library"\n'
        'dependencies { helper { path: "../helper" } }\n')
    (bridge / "src/main.mt").write_text(
        "pub fn answer(): i32 { helper.answer() }\n")
    edit(app / "package.mettle", 'helper { path: "../helper" }',
         'bridge { path: "../bridge" }')
    edit(app / "build.mt", "helper.answer()", "bridge.answer()")
    build_and_run(app)


def host_dependency_script_uses_host_target():
    if sys.platform != "linux" or os.uname().machine != "x86_64":
        return
    cross = "arm64-apple-macosx15.0"
    root = packages("driver-contracts/host-script-order")
    app = root / "app"
    helper = root / "helper"
    probe = (
        'fn main(): i32 {\n'
        '    match std.env.var_os(std.ffi.os_str_from_text("METTLE_TARGET")) {\n'
        f'        present(value) => {{ if value.as_os_str().same(std.ffi.os_str_from_text("{cross}")) '
        '{ return BAD } },\n'
        '        none => { return 9 }\n'
        '    }\n'
        '    std.io.print("mettle:feature=ready\\n")\n'
        '    0\n'
        '}\n')
    (helper / "build.mt").write_text(probe.replace("return BAD", "return 7"))
    (app / "build.mt").write_text(
        probe.replace("if value.as_os_str()", "if !value.as_os_str()")
             .replace("return BAD", "return 8"))
    invoke(["check", app, "--target", cross])


def driver_docs_preserve_target_cfg():
    app = packages("driver-contracts/doc-target-cfg")
    source = app / "src/main.mt"
    original = source.read_text()
    for index, predicate in enumerate((
            'target_os = "linux"', 'target_arch = "x86_64"',
            'target_pointer_width = "64"', 'target_endian = "little"',
            'target_feature = "sse2"')):
        source.write_text(original.replace('target_os = "linux"', predicate))
        flags = ["--target", "x86_64-unknown-linux-gnu"]
        invoke(["check", app, *flags])
        output = evidence / f"target-doc-{index}"
        invoke(["doc", app, *flags, "-o", output])
        entries = json.loads((output / "search-index.json").read_text())
        matches = [item for item in entries
                   if item["name"].split(".")[-2:] == ["platform", "answer"]]
        assert len(matches) == 1, (predicate, output, entries)
        entry = matches[0]
        filename, separator, anchor = entry["href"].partition("#")
        assert filename and separator and anchor, (predicate, entry)
        page = (output / filename).read_text()
        article = re.search(r'<article id="' + re.escape(anchor) +
                            r'">.*?</article>', page, re.S)
        assert article, (predicate, entry, page)
        assert "<pre class=\"sig\"><code>pub fn answer(): i32</code></pre>" in article[0], (
            predicate, entry, article[0])


def driver_inline_doctests_keep_scope():
    source = packages("driver-contracts/inline-module-doctest.mt")
    original = source.read_bytes()
    for selection, count in (([], 2), (["nested"], 1)):
        events = invoke_json(["test", source, "--doc", "--format", "json",
                              *selection])
        tests = [event for event in events if event["event"] == "test"]
        assert len(tests) == count and all(e["outcome"] == "passed" for e in tests)
        assert events[-1]["passed"] == count and events[-1]["failed"] == 0
        if selection:
            assert "nested" in tests[0]["name"] and events[-1]["filtered"] == 1
        assert source.read_bytes() == original


def package_ownership():
    app = packages("package-ownership/app")
    main = app / "src/main.mt"
    positive = main.read_bytes()
    invoke(["check", app])
    try:
        for name, message in (
                ("foreign-interface-on-primitive.mt",
                 "orphan interface implementation has no local owner"),
                ("foreign-alias-is-not-local.mt",
                 "orphan interface implementation has no local owner"),
                ("foreign-reexport-is-not-local.mt",
                 "orphan interface implementation has no local owner"),
                ("foreign-unpin-declaration.mt",
                 "Unpin implementation must belong to the type's package"),
                ("foreign-negative-transferable.mt",
                 "Transferable declaration must belong to the type's package")):
            contents = (app / "cases" / name).read_bytes()
            main.write_bytes(contents)
            line, column = next(
                (number, text.index("extend") + 1)
                for number, text in enumerate(contents.decode().splitlines(), 1)
                if text.startswith(("extend ", "unsafe extend ")))
            text = invoke(["check", app], 1)
            assert re.search(
                rf"(?m)^[^\n]*main\.mt:{line}:{column}: error\[type\]: "
                + re.escape(message) + r"$", text), text
    finally:
        main.write_bytes(positive)
    invoke(["check", app])


def lsp_position(text, offset):
    return {"line": text.count("\n", 0, offset),
            "character": offset - text.rfind("\n", 0, offset) - 1}


def lsp_word_ranges(text, word):
    return [{"start": lsp_position(text, match.start()),
             "end": lsp_position(text, match.end())}
            for match in re.finditer(r"\b" + re.escape(word) + r"\b", text)]


def checked_rename(client, path, text, position, ranges, new_name):
    document = client.checked(path, text)
    reply = client.request("textDocument/rename", {
        "textDocument": document, "position": position, "newName": new_name})
    context = f"{path}: rename at {position} to {new_name!r}\n{text}"
    assert "result" in reply and "error" not in reply, f"{context}\n{reply}"
    changes = reply["result"]["changes"]
    assert set(changes) == {document["uri"]}, changes
    edits = changes[document["uri"]]
    key = lambda item: (item["start"]["line"], item["start"]["character"])
    assert sorted((edit["range"] for edit in edits), key=key) == sorted(ranges, key=key), (
        context, ranges, edits)
    assert all(edit["newText"] == new_name for edit in edits), edits
    lines = text.splitlines(keepends=True)
    for item in sorted(edits, key=lambda e: key(e["range"]), reverse=True):
        start, end = item["range"]["start"], item["range"]["end"]
        first = sum(map(len, lines[:start["line"]])) + start["character"]
        last = sum(map(len, lines[:end["line"]])) + end["character"]
        text = text[:first] + item["newText"] + text[last:]
    renamed = evidence / "renamed.mt"
    renamed.write_text(text)
    invoke(["check", renamed])
    client.close(document)
    return text


def driver_rename_preserves_bindings():
    root = packages("driver-contracts")
    with LanguageClient() as client:
        for name, text in (
                ("rename-capture.mt", None),
                ("reverse-capture.mt",
                 "fn y(): i32 { 2 }\nfn choose(x: i32): i32 { x + y() }\n"
                 "fn main(): i32 { choose(1) }\n"),
                ("duplicate-parameter.mt",
                 "fn choose(x: i32, y: i32): i32 { x + y }\n"
                 "fn main(): i32 { choose(1, 2) }\n")):
            path = root / name
            text = path.read_text() if text is None else text
            document = client.checked(path, text)
            reply = client.request("textDocument/rename", {
                "textDocument": document,
                "position": lsp_word_ranges(text, "x")[0]["start"],
                "newName": "y"})
            assert "error" in reply and "result" not in reply, reply
            client.close(document)
        path = root / "rename-safe-shadow.mt"
        text = path.read_text()
        ranges = lsp_word_ranges(text, "x")
        renamed = checked_rename(client, path, text, ranges[0]["start"], ranges, "y")
        assert "{ let y = 2; y }" in renamed, renamed


def driver_conditional_pattern_rename():
    path = packages("driver-contracts/conditional-pattern-rename.mt")
    with LanguageClient() as client:
        for text in (
                path.read_text(),
                "fn main(): i32 { var result = 0; var next: i32? = present(42); "
                "while let present(value) = next { next = none; result = value }; "
                "result }\n",
                "fn main(): i32 { if let present(value) = present(42), "
                "value > 0 { value } else { 0 } }\n"):
            ranges = lsp_word_ranges(text, "value")
            checked_rename(client, path, text, ranges[-1]["start"], ranges, "item")


def driver_qualified_cross_file_rename():
    source = evidence / "main.mt"
    provider = evidence / "provider.mt"
    source.write_text("module provider;\nfn main(): i32 { provider.answer() - 42 }\n")
    provider.write_text("pub fn answer(): i32 { 42 }\n")
    paths = (source, provider)
    with LanguageClient() as client:
        documents = [client.checked(path) for path in paths]
        ranges = [lsp_word_ranges(path.read_text(), "answer")[0] for path in paths]
        expected = [{"uri": path.as_uri(), "range": span}
                    for path, span in zip(paths, ranges)]
        for document, span in zip(documents, ranges):
            params = {"textDocument": document, "position": span["start"]}
            refs = client.request("textDocument/references", {
                **params, "context": {"includeDeclaration": True}})["result"]
            assert len(refs) == 2 and all(site in refs for site in expected), refs
            reply = client.request("textDocument/rename", {
                **params, "newName": "result"})
            assert "result" in reply and "error" not in reply, reply
            changes = reply["result"]["changes"]
            assert set(changes) == {path.as_uri() for path in paths}, changes
            for path, span in zip(paths, ranges):
                assert changes[path.as_uri()] == [
                    {"range": span, "newText": "result"}], changes
    for path in paths:
        edit(path, "answer", "result")
    invoke(["check", source])


def driver_checked_methods_disambiguate():
    path = packages("driver-contracts/checked-method-identity.mt")
    text = path.read_text() + "fn other(): i32 { B().value() }\n"
    ranges = lsp_word_ranges(text, "value")
    with LanguageClient() as client:
        document = client.checked(path, text)
        for declaration, call in ((ranges[0], ranges[2]), (ranges[1], ranges[3])):
            found = client.request("textDocument/definition", {
                "textDocument": document, "position": call["start"]})["result"]
            assert found == [{"uri": path.as_uri(), "range": declaration}], found
            refs = client.request("textDocument/references", {
                "textDocument": document, "position": declaration["start"],
                "context": {"includeDeclaration": True}})["result"]
            expected = [{"uri": path.as_uri(), "range": r}
                        for r in (declaration, call)]
            assert len(refs) == len(expected) and all(r in refs for r in expected), refs
            hover = client.request("textDocument/hover", {
                "textDocument": document, "position": declaration["start"]})["result"]
            assert ": i32" in hover["contents"]["value"], hover
        other = evidence / "overlapping-method-spans.mt"
        other_text = text.replace("A().value()", "B().value()")
        client.checked(other, other_text)
        refs = client.request("textDocument/references", {
            "textDocument": document, "position": ranges[0]["start"],
            "context": {"includeDeclaration": True}})["result"]
        assert all({"uri": path.as_uri(), "range": r} in refs
                   for r in (ranges[0], ranges[2])), refs
        assert all({"uri": uri, "range": r} not in refs
                   for uri, sites in ((path.as_uri(), (ranges[1], ranges[3])),
                                      (other.as_uri(), ranges[2:]))
                   for r in sites), refs


def driver_generic_parameter_labels():
    path = packages("driver-contracts/generic-argument-label.mt")
    original = path.read_text()
    array = original.replace("identity<i32>(value: 42)",
                             "identity<[i32; 2]>(value: [21, 21])[0usize]")
    assert array != original
    with LanguageClient() as client:
        for text in (original, array):
            ranges = lsp_word_ranges(text, "value")
            checked_rename(client, path, text, ranges[0]["start"], ranges, "argument")


def driver_noop_changes_keep_checked_index():
    path = packages("driver-contracts/noop-checked-index.mt")
    text = path.read_text()
    ranges = lsp_word_ranges(text, "value")
    with LanguageClient() as client:
        document = client.checked(path, text)
        params = {"textDocument": document, "position": ranges[-1]["start"]}

        def facts():
            refs = client.request("textDocument/references", {
                **params, "context": {"includeDeclaration": True}})["result"]
            expected = [{"uri": path.as_uri(), "range": r} for r in ranges]
            assert len(refs) == len(expected) and all(r in refs for r in expected), refs
            hover = client.request("textDocument/hover", params)["result"]
            assert "i32" in hover["contents"]["value"], hover
            return expected, hover

        original = facts()
        for version, changes in enumerate((
                [{"text": text}],
                [{"range": ranges[-1], "text": "value"}],
                [{"range": ranges[-1], "text": "other"},
                 {"range": ranges[-1], "text": "value"}]), 2):
            client.notify("textDocument/didChange", {
                "textDocument": {**document, "version": version},
                "contentChanges": changes})
            assert facts() == original


CASES = [driver_output_preserves_imports, driver_panic_rejects_other_signals,
         driver_compile_fail_requires_checking, driver_feature_backtracks,
         driver_git_host_outputs_preserve_package_paths,
         driver_host_scripts_consume_generated_context,
         host_dependency_script_uses_host_target,
         driver_docs_preserve_target_cfg, driver_rename_preserves_bindings,
         driver_conditional_pattern_rename, driver_qualified_cross_file_rename,
         driver_checked_methods_disambiguate,
         driver_generic_parameter_labels, driver_inline_doctests_keep_scope,
         driver_noop_changes_keep_checked_index, package_ownership,
         cyclic_module_macro_definition,
         path_dependency, restricted_dependency_visibility, nested_dependency_imports,
         package_name_roots_own_modules, configured_entry, mettle_version, library_entries, development_dependencies,
         missing_lock_locked, lock_corruption,
         registry_resolution, version_conflict, wildcard_version_bounds,
         backtracking, cycle_backtracking, lock_publication_isolated, offline, features,
         coexisting_versions, git_source, git_concurrent_output, host_target_separation,
         manifest_diagnostics, data_format, lock_structure,
         package_options_need_package, incremental_reuse, checked_core_reuse,
         native_core_object_reuse, checked_alloc_std_reuse,
         checked_alloc_std_release_reuse,
         checked_native_macro_reuse,
         checked_library_diagnostics,
         linked_archive_changes_invalidate_executable,
         object_cache_integrity,
         sanitizer_cache_key, edit_invalidation, comment_newline_invalidates_cache,
         cache_dedup_and_bound,
         cache_corruption_and_clean, cache_corrupt_digest_preserves_other_files,
         cache_publication_failure_is_reported, cache_clean_failure, cache_clean_preserves_sources,
         security_output_paths,
         cache_compiler_content_identity,
         build_script, build_script_untracked_inputs,
         procedural_macro, procedural_macro_failure,
         public_declarative_macro_dependency,
         multi_package_extension,
         type_id_survives_public_reexport,
         run_forwards_args_and_exit_status,
         test_reports_pass_fail_ignored_and_isolates_panics,
         test_filter_exact, harness_quoted_names, bench_reports_timing,
         fmt_normalizes_layout_only,
         doc_writes_deterministic_html,
         doc_resolves_dependency_links_and_warns,
         doctests_run_isolated_examples,
         lint_reports_semantic_findings, debug_info, debugger_workflow,
         language_server,
         test_json_timeout_and_modules]

def main(argv=None):
    global mettle, evidence, fixtures
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("fixtures", type=Path)
    parser.add_argument("pattern", nargs="?")
    scheduling.arguments(parser, 4)
    parser.add_argument("--worker-case", choices=[case.__name__ for case in CASES],
                        help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    mettle, evidence, fixtures = (
        path.resolve() for path in (args.compiler, args.evidence, args.fixtures))
    if args.worker_case:
        os.environ["METTLE_CACHE_DIR"] = str(evidence / "cache")
        return run_case(next(case for case in CASES if case.__name__ == args.worker_case))
    selected = re.compile(args.pattern) if args.pattern else None
    chosen = [case.__name__ for case in CASES
              if selected is None or selected.search(case.__name__)]
    if not chosen:
        raise ValueError("no package cases selected")
    if args.shard_count > 1:
        evidence /= f"shard-{args.shard_index}"
    chosen = scheduling.select(chosen, str, args.shard_index, args.shard_count)

    def execute(name):
        command = [sys.executable, Path(__file__).resolve(), mettle,
                   evidence / name, fixtures, "--worker-case", name]
        result = processes.run(list(map(str, command)), text=True, capture_output=True)
        return {"name": name, "command": list(map(str, command)),
                "exit_status": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr}

    records = []
    for name, result, error, elapsed in scheduling.run(
            chosen, execute, evidence, args.jobs, str):
        record = result or {"name": name, "exit_status": 1, "stderr": error, "stdout": ""}
        record["elapsed_seconds"] = elapsed
        records.append(record)
        print(f"{'FAIL' if record['exit_status'] else 'PASS'} {name}")
        if record["exit_status"]:
            print(record["stdout"] + record["stderr"], file=sys.stderr)
    failed = any(record["exit_status"] for record in records)
    (evidence / "evidence.json").write_text(json.dumps({
        "status": "failed" if failed else "passed", "cases": records}, indent=2) + "\n")
    return int(failed)


def run_case(case):
    COMMANDS.clear()
    record = {"name": case.__name__, "status": "in_progress", "commands": COMMANDS}
    try:
        reset()
        os.chdir(evidence)
        case()
        record["status"] = "passed"
        return 0
    except Exception as error:
        record["status"] = "failed"
        record["error"] = str(error)
        print(f"FAIL {case.__name__}: {error}", file=sys.stderr)
        return 1
    finally:
        evidence.mkdir(parents=True, exist_ok=True)
        (evidence / "evidence.json").write_text(json.dumps(record, indent=2) + "\n")


if __name__ == "__main__":
    sys.exit(main())
