#!/usr/bin/env python3
"""Package manifest, resolution, lock, feature and offline regressions.

Usage: packages.py MettleExecutable EvidenceDir FixturesDir
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

mettle, evidence, fixtures = (Path(a).resolve() for a in sys.argv[1:4])


def reset():
    shutil.rmtree(evidence, ignore_errors=True)
    shutil.copytree(fixtures, evidence)


def invoke(arguments, expected=0, contains=()):
    # Every case owns its build cache so runs never touch the user's.
    environment = {**os.environ, "METTLE_CACHE_DIR": str(evidence / "cache")}
    result = subprocess.run([str(mettle), *map(str, arguments)], text=True,
                            capture_output=True, timeout=600, env=environment)
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
    return subprocess.run([str(program)], timeout=60).returncode


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
    # Root and dependency `@cfg` test their own resolved feature sets.
    build_and_run(app)
    build_and_run(app, "--features", "fancy")
    assert 'name = "extra"' in lock_of(app)
    invoke(["check", app, "--features", "nope"], 1, "no feature 'nope'")
    edit(app / "Mettle.toml", "default = []", 'default = ["fancy"]')
    build_and_run(app)
    build_and_run(app, "--no-default-features")
    main = app / "src/main.mt"
    edit(main, "@cfg(not(feature = \"fancy\"))\nfn main(): i32 { widget::base() - 100 }\n", "")
    edit(main, "@cfg(feature = \"fancy\")\n", "")
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
    assert not os.access(cache_files("blobs")[0], os.W_OK), "shared blob is writable"
    # An incremental result equals a clean build without any cache.
    # The linker embeds the output's file name, so compare like names.
    clean = evidence / "clean" / "out.bin"
    clean.parent.mkdir(exist_ok=True)
    invoke(["build", app, "-o", clean, "--no-cache"])
    assert clean.read_bytes() == bytes_built


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
    edit(packages("path-dependency/units/src/lib.mt"), "21", "20 + 1")
    text, built = explained(path_app)
    assert "cache miss" in text, text
    assert exit_code(built) == 0


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
    edit(app / "src/main.mt", "- 42 }", "- 42 + math::zero() }")
    limit = (blob * 3 // 2) // 1024 + 1
    text, built = explained(app, "--cache-limit-kib", limit)
    assert "evicted" in text and "least recently used" in text, text
    assert cache_bytes() <= limit * 1024, (cache_bytes(), limit)
    assert exit_code(built) == 0
    assert len(cache_files("blobs")) == 1, cache_files("blobs")
    # A budget below a single artifact keeps nothing, yet builds still work.
    edit(app / "src/main.mt", "math::zero() }", "math::zero() + 0 }")
    text, built = explained(app, "--cache-limit-kib", 1)
    assert cache_bytes() <= 1024, cache_bytes()
    assert exit_code(built) == 0


def cache_corruption_and_clean():
    app = packages("incremental/app")
    explained(app)
    blob = cache_files("blobs")[0]
    blob.chmod(0o644)
    blob.write_bytes(b"corrupted")
    text, built = explained(app)
    assert "entry corrupt" in text, text
    assert exit_code(built) == 0
    text, _ = explained(app)
    assert "cache hit" in text, text
    # `clean` reports, then empties, only a directory that is a store.
    cache = evidence / "cache"
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
    edit(script, '    std::io::print("mettle:reproducible\\n")\n', "")
    for _ in range(2):
        text, built = explained(app)
        assert "rerun (no reproducible record)" in text, text
        assert exit_code(built) == 0
    edit(script, '    0\n}', '    std::io::print("mettle:bogus=1\\n")\n    0\n}')
    explained(app, expected=1, contains="unknown or malformed declaration")


def package_options_need_package():
    source = evidence / "plain.mt"
    source.write_text("fn main(): i32 { 0 }\n")
    invoke(["check", source, "--locked"], 2)


def migrate_preserves_syntax_tree():
    # Generic arguments move between a `::` path and a dotted chain; the
    # syntax-tree check must accept that and the result must be a fixed point.
    source = evidence / "old.mt"
    source.write_text(
        "enum Opt<T> { Some(T), Nothing }\n"
        "type Slot<K> { v: K? }\n"
        "impl<K> Slot<K> {\n"
        "    static fn empty(): Slot<K> { Slot(none) }\n"
        "}\n"
        "fn main(): i32 {\n"
        "    let t: Opt<i32> = Opt::<i32>::Nothing\n"
        "    let e: Slot<i32> = Slot::empty()\n"
        "    match t { Opt::Nothing => 0, Opt::Some(_) => 1 }\n"
        "}\n")
    expected = (
        "enum Opt<T> { Some(T), Nothing }\n"
        "type Slot<K> { v: K? }\n"
        "extend<K> Slot<K> {\n"
        "    static fn empty(): Slot<K> { Slot(none) }\n"
        "}\n"
        "fn main(): i32 {\n"
        "    let t: Opt<i32> = Opt<i32>.Nothing\n"
        "    let e: Slot<i32> = Slot.empty()\n"
        "    match t { Opt.Nothing => 0, Opt.Some(_) => 1 }\n"
        "}\n")
    migrated = evidence / "new.mt"
    invoke(["migrate", source, "-o", migrated])
    assert migrated.read_text() == expected, migrated.read_text()
    again = evidence / "again.mt"
    invoke(["migrate", migrated, "-o", again])
    assert again.read_text() == expected, again.read_text()
    shadow = evidence / "shadow.mt"
    shadow.write_text("module m { pub fn f(): i32 { 1 } }\n"
                      "fn main(): i32 { let m = 2; m::f() + m }\n")
    kept = invoke(["migrate", shadow])
    assert "m::f()" in kept and "local name" in kept, kept
    broken = evidence / "broken.mt"
    broken.write_text("fn main(): i32 { 0\n")
    invoke(["migrate", broken], 1)


def fmt_normalizes_layout_only():
    # Indentation, spacing, trailing whitespace and blank runs change; the
    # comments, the multi-line raw text and the line structure do not.
    messy = (
        "// header comment   \n"
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
                     "fn main(): i32 {\n  square!(3)  -  9\n}\n")
    invoke(["fmt", macro])
    assert macro.read_text() == ("macro square {\n    ($x:expr) => { $x*$x };\n}\n"
                                 "fn main(): i32 {\n    square!(3) - 9\n}\n"), \
        macro.read_text()


CASES = [path_dependency, missing_lock_locked, lock_corruption,
         registry_resolution, version_conflict, backtracking, offline, features,
         manifest_diagnostics, package_options_need_package, incremental_reuse,
         edit_invalidation, cache_dedup_and_bound, cache_corruption_and_clean,
         build_script, build_script_untracked_inputs,
         migrate_preserves_syntax_tree, fmt_normalizes_layout_only]

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
