#!/usr/bin/env python3
"""Package manifest, resolution, lock, feature and offline regressions.

Usage: packages.py MettleExecutable EvidenceDir FixturesDir
"""

import shutil
import subprocess
import sys
from pathlib import Path

mettle, evidence, fixtures = (Path(a).resolve() for a in sys.argv[1:4])


def reset():
    shutil.rmtree(evidence, ignore_errors=True)
    shutil.copytree(fixtures, evidence)


def invoke(arguments, expected=0, contains=()):
    result = subprocess.run([str(mettle), *map(str, arguments)], text=True,
                            capture_output=True, timeout=600)
    text = result.stdout + result.stderr
    if result.returncode != expected:
        raise AssertionError(f"{arguments}: expected {expected}, got "
                             f"{result.returncode}\n{text}")
    for needle in ([contains] if isinstance(contains, str) else contains):
        if needle not in text:
            raise AssertionError(f"{arguments}: missing {needle!r}\n{text}")
    return text


def build_and_run(directory, *extra):
    output = evidence / "out.bin"
    output.unlink(missing_ok=True)
    invoke(["build", directory, "-o", output, *extra])
    result = subprocess.run([str(output)], timeout=60)
    assert result.returncode == 0, f"{directory}: program exited {result.returncode}"


def edit(path, old, new):
    text = path.read_text()
    assert old in text, (path, old)
    path.write_text(text.replace(old, new))


def packages(name):
    return evidence / name


def lock_of(directory):
    return (directory / "Mettle.lock").read_text()


def path_dependency():
    app = packages("path-dependency/app")
    build_and_run(app)
    lock = lock_of(app)
    assert 'name = "units"' in lock and "sha256:" in lock, lock
    build_and_run(app, "--locked")
    assert lock_of(app) == lock, "an unchanged build rewrote the lock"
    invoke(["check", app, "--frozen"])
    edit(packages("path-dependency/units/src/lib.mt"), "21", "21 + 0")
    invoke(["build", app, "--locked", "-o", evidence / "x"], 1,
           ["--locked", "units"])
    invoke(["check", app])
    assert lock_of(app) != lock, "the lock was not refreshed"
    invoke(["check", app, "--locked"])


def missing_lock_locked():
    app = packages("path-dependency/app")
    invoke(["check", app, "--locked"], 1, "Mettle.lock")
    assert not (app / "Mettle.lock").exists()


def lock_corruption():
    app = packages("path-dependency/app")
    invoke(["check", app])
    lock = lock_of(app)
    (app / "Mettle.lock").write_text(lock + "[[package\n")
    invoke(["check", app], 1, "Mettle.lock")
    (app / "Mettle.lock").write_text(lock)
    edit(app / "Mettle.lock", 'version = 1\n', 'version = 99\n')
    invoke(["check", app], 1, "Mettle.lock")


def registry_resolution():
    app = packages("registry-resolution/app")
    build_and_run(app)
    lock = lock_of(app)
    assert 'version = "1.2.0"' in lock and 'version = "1.3.0"' in lock, lock
    assert "1.4.0" not in lock, "a yanked version was selected"
    # A new release does not move a locked package.
    new = packages("registry/util/1.3.5")
    shutil.copytree(packages("registry/util/1.3.0"), new)
    edit(new / "Mettle.toml", "1.3.0", "1.3.5")
    edit(new / "src/lib.mt", "13", "99")
    build_and_run(app, "--locked")
    assert lock_of(app) == lock
    # Tampering with a locked registry package is always rejected.
    edit(packages("registry/util/1.3.0/src/lib.mt"), "13", "13 + 0")
    invoke(["check", app], 1, "checksum mismatch")
    invoke(["check", app, "--locked"], 1, "checksum mismatch")


def version_conflict():
    app = packages("resolution/app")
    edit(packages("resolution/right/Mettle.toml"), "=1.0.0", "^2")
    invoke(["check", app], 1, ["no version of 'util' satisfies all requirements",
                               "'^1' (required by 'left 0.1.0')",
                               "'^2' (required by 'right 0.1.0')"])


def backtracking():
    app = packages("resolution/app")
    build_and_run(app)
    lock = lock_of(app)
    assert 'name = "util"\nversion = "1.0.0"' in lock, lock


def offline():
    app = packages("registry-resolution/app")
    edit(app / "Mettle.toml", '[registry]\npath = "../../registry"\n\n', "")
    invoke(["check", app], 1, "no registry is configured")
    invoke(["check", app, "--offline"], 1, "no registry is configured")
    invoke(["check", app, "--offline", "--registry", evidence / "registry"], 0)
    app = packages("registry-resolution/app")
    edit(app / "Mettle.toml", 'shapes = "^1"', 'shapes = "^1"\nmissing = "^1"')
    invoke(["check", app, "--offline", "--registry", evidence / "registry"], 1,
           ["missing", "offline mode never fetches"])


def features():
    app = packages("features/app")
    invoke(["check", app], 1, "extra::value")
    build_and_run(app, "--features", "fancy")
    assert 'name = "extra"' in lock_of(app)
    invoke(["check", app, "--features", "nope"], 1, "no feature 'nope'")
    edit(app / "Mettle.toml", "default = []", 'default = ["fancy"]')
    build_and_run(app)
    invoke(["check", app, "--no-default-features"], 1, "extra::value")


def manifest_diagnostics():
    app = packages("path-dependency/app")
    manifest = app / "Mettle.toml"
    original = manifest.read_text()
    manifest.write_text(original.replace("[package]\n", "[package\n", 1))
    invoke(["check", app], 1, "Mettle.toml:1")
    manifest.write_text(original.replace('name = "path-app"',
                                         'name = "path-app"\nbogus = 1'))
    invoke(["check", app], 1, "bogus")
    manifest.write_text(original.replace(
        'mathlib = { path = "../mathlib" }',
        'mathlib = { git = "https://example.invalid/x.git" }'))
    invoke(["check", app], 1, "git")
    manifest.write_text(original.replace(
        'mathlib = { path = "../mathlib" }',
        'mathlib = { path = "../mathlib", version = "^1.q" }'))
    invoke(["check", app], 1, "version")
    manifest.write_text(original.replace('"../mathlib"', '"../nowhere"'))
    invoke(["check", app], 1, "nowhere")
    manifest.write_text(original)
    # A dependency cycle names the path.
    edit(packages("path-dependency/units/Mettle.toml"),
         'language = "mettle-1"\n',
         'language = "mettle-1"\n\n[dependencies]\n'
         'mathlib = { path = "../mathlib" }\n')
    invoke(["check", app], 1, "mathlib -> units -> mathlib")


def package_options_need_package():
    source = evidence / "plain.mt"
    source.write_text("fn main(): i32 { 0 }\n")
    invoke(["check", source, "--locked"], 2)


CASES = [path_dependency, missing_lock_locked, lock_corruption,
         registry_resolution, version_conflict, backtracking, offline, features,
         manifest_diagnostics, package_options_need_package]

failures = []
for case in CASES:
    reset()
    try:
        case()
        print(f"PASS {case.__name__}")
    except (AssertionError, subprocess.SubprocessError) as error:
        failures.append(case.__name__)
        print(f"FAIL {case.__name__}: {error}")
sys.exit(1 if failures else 0)
