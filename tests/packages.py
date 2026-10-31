#!/usr/bin/env python3
"""Package manifest, resolution, lock, feature and offline regressions.

Usage: packages.py MettleExecutable EvidenceDir FixturesDir
"""

import json
import os
import re
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


def invoke_json(arguments, expected=0):
    environment = {**os.environ, "METTLE_CACHE_DIR": str(evidence / "cache")}
    result = subprocess.run([str(mettle), *map(str, arguments)], text=True,
                            capture_output=True, timeout=600, env=environment)
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
    edit(app / "Mettle.lock", 'version = 2\n', 'version = 99\n')
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
    invoke(["check", app], 0)
    lock = lock_of(app)
    assert 'name = "util"\nversion = "1.3.0"' in lock, lock
    assert 'name = "util"\nversion = "2.0.0"' in lock, lock
    edit(packages("resolution/right/Mettle.toml"), "^2", "=1.0.0")
    (app / "Mettle.lock").unlink()


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
    edit(main, "@cfg(not(feature = \"fancy\"))\nfn main(): i32 { widget.base() - 100 }\n", "")
    edit(main, "@cfg(feature = \"fancy\")\n", "")
    invoke(["check", app, "--no-default-features"], 1, "unresolved value \'extra\'")


def coexisting_versions():
    app = packages("coexisting-versions/app")
    output = evidence / "out.bin"
    invoke(["build", app, "-o", output])
    result = subprocess.run([str(output)], capture_output=True, text=True,
                            timeout=60)
    assert result.returncode == 0, (
        f"{app}: program exited {result.returncode}")
    assert result.stdout == "alpha-1\nalpha-2\n", result.stdout
    lock = lock_of(app)
    assert 'name = "alpha"\nversion = "1.0.0"' in lock, lock
    assert 'name = "alpha"\nversion = "2.0.0"' in lock, lock


def git_source():
    app = packages("git-source/app")
    repository = packages("git-source/repository")
    repository.mkdir(parents=True)
    app.mkdir(parents=True)
    (repository / "src").mkdir()
    (app / "src").mkdir()
    (repository / "Mettle.toml").write_text(
        '[package]\nname = "gitlib"\nversion = "0.1.0"\n'
        'language = "mettle-1"\n')
    (repository / "src/lib.mt").write_text("pub fn value(): i32 { 7 }\n")
    (app / "src/main.mt").write_text(
        "fn main(): i32 { gitlib.value() - 7 }\n")
    subprocess.run(["git", "init", repository], check=True,
                   capture_output=True, text=True)
    subprocess.run(["git", "-C", repository, "checkout", "-b", "main"],
                   check=True, capture_output=True, text=True)
    subprocess.run(["git", "-C", repository, "config", "user.name",
                    "Mettle package test"], check=True, capture_output=True)
    subprocess.run(["git", "-C", repository, "config", "user.email",
                    "packages-test@example.invalid"], check=True,
                   capture_output=True)
    subprocess.run(["git", "-C", repository, "add", "Mettle.toml",
                    "src/lib.mt"], check=True, capture_output=True)
    subprocess.run(["git", "-C", repository, "commit", "-m", "first"],
                   check=True, capture_output=True)
    first = subprocess.run(
        ["git", "-C", repository, "rev-parse", "HEAD"], check=True,
        capture_output=True, text=True).stdout.strip()
    (app / "Mettle.toml").write_text(
        '[package]\nname = "git-app"\nversion = "0.1.0"\n'
        'language = "mettle-1"\n\n[dependencies]\n'
        f'gitlib = {{ git = "{repository.as_uri()}", branch = "main" }}\n')
    build_and_run(app)
    lock = lock_of(app)
    assert first in lock and "sha256:" in lock, lock
    invoke(["check", app, "--offline", "--locked"])
    edit(repository / "src/lib.mt", "{ 7 }", "{ 8 }")
    subprocess.run(["git", "-C", repository, "add", "src/lib.mt"],
                   check=True, capture_output=True)
    subprocess.run(["git", "-C", repository, "commit", "-m", "second"],
                   check=True, capture_output=True)
    invoke(["check", app, "--locked"], 1, "--locked forbids changing it")
    invoke(["check", app, "--offline", "--locked"])
    assert lock_of(app) == lock


def host_target_separation():
    app = packages("host-target-separation/app")
    build_and_run(app)
    lock = lock_of(app)
    assert ('name = "helper"' in lock and '"host"' in lock and
            '"target"' in lock), lock


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
    invoke(["check", app], 1, "mathlib 0.3.1 -> units 0.1.4 -> mathlib 0.3.1")


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
    edit(packages("proc-macro/genfn/Mettle.toml"), "api = 1", "api = 2")
    explained(app, expected=1,
              contains="unsupported macro API major version 2")


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
    edit(packages("multi-package-extension/mathlib/src/lib.mt"),
         "{ 7 }", "{ 8 }")
    text, built = explained(app)
    assert "cache miss" in last_cache_event(text), text
    assert exit_code(built) == 1


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
                     "fn main(): i32 {\n  square!(3)  -  9\n}\n")
    invoke(["fmt", macro])
    assert macro.read_text() == ("macro square {\n    ($x:expr) => { $x*$x };\n}\n"
                                 "fn main(): i32 {\n    square!(3) - 9\n}\n"), \
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
        f"            {wide_right} => 2 }}\n"
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
                    subprocess.run([str(tool), "--version"], check=True,
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
        "fn first(values: read [i32]): i32 { values[0] }\n"
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
    assert b"debuggee.mt" not in plain[0].read_bytes()
    subprocess.run([str(dwarfdump), "--verify", str(debug[0])],
                   text=True, capture_output=True, check=True)
    info = subprocess.run([str(dwarfdump), "--debug-info", str(debug[0])],
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
    assert re.search(r'(?:@llvm\.dbg\.value\(metadata |#dbg_value\()'
                     r'ptr undef, (?:metadata )?' +
                     re.escape(moved.group(1)) + r'\b', ir_text), ir_text
    release_info = subprocess.run(
        [str(dwarfdump), "--debug-info", str(release)],
        text=True, capture_output=True, check=True).stdout
    assert "DW_TAG_inlined_subroutine" in release_info, release_info
    assert '"inline_increment"' in release_info, release_info
    assert "DW_AT_call_file" in release_info and \
        "DW_AT_call_line" in release_info, release_info
    lines = subprocess.run([str(dwarfdump), "--debug-line", str(debug[0])],
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
    mathlib_source = app.parent / "mathlib/src/lib.mt"
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
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.next_id = 0

    def send(self, message):
        body = json.dumps({"jsonrpc": "2.0", **message}).encode()
        self.process.stdin.write(
            b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.process.stdin.flush()

    def receive(self):
        length = None
        while True:
            line = self.process.stdout.readline()
            if not line:
                raise AssertionError("language server closed its output")
            line = line.strip()
            if not line:
                break
            name, _, value = line.decode().partition(":")
            if name.lower() == "content-length":
                length = int(value)
        return json.loads(self.process.stdout.read(length))

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

        refused = client.request("textDocument/rename", {
            "textDocument": document,
            "position": {"line": 3, "character": 5},
            "newName": "fn"})
        assert "error" in refused, refused

        symbols = client.request("textDocument/documentSymbol",
                                 {"textDocument": document})["result"]
        assert [s["name"] for s in symbols] == ["double", "main"], symbols

        assert "result" in client.request("shutdown", None)
        client.notify("exit", None)
        assert client.process.wait(timeout=30) == 0
    finally:
        if client.process.poll() is None:
            client.process.kill()
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


CASES = [path_dependency, missing_lock_locked, lock_corruption,
         registry_resolution, version_conflict, backtracking, offline, features,
         coexisting_versions, git_source, host_target_separation,
         manifest_diagnostics, package_options_need_package, incremental_reuse,
         sanitizer_cache_key, edit_invalidation, cache_dedup_and_bound,
         cache_corruption_and_clean,
         build_script, build_script_untracked_inputs,
         procedural_macro, procedural_macro_failure,
         multi_package_extension,
         run_forwards_args_and_exit_status,
         test_reports_pass_fail_ignored_and_isolates_panics,
         test_filter_exact, bench_reports_timing, fmt_normalizes_layout_only,
         doc_writes_deterministic_html,
         doc_resolves_dependency_links_and_warns,
         doctests_run_isolated_examples,
         lint_reports_semantic_findings, debug_info, language_server,
         test_json_timeout_and_modules]

# Optional fourth argument: a regular expression selecting cases by name.
selected = re.compile(sys.argv[4]) if len(sys.argv) > 4 else None
failures = []
for case in CASES:
    if selected and not selected.search(case.__name__):
        continue
    reset()
    try:
        case()
        print(f"PASS {case.__name__}")
    except (AssertionError, subprocess.SubprocessError) as error:
        failures.append(case.__name__)
        print(f"FAIL {case.__name__}: {error}")
sys.exit(1 if failures else 0)
