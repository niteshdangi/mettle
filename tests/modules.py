#!/usr/bin/env python3
"""Focused multi-file module compile/run and diagnostic regressions."""

import re
import resource
import shutil
import subprocess
import sys
from pathlib import Path

TARGET_FILES = {
    "external-inline-alias-group-reexport": {
        "main.mt": "module math;\nimport math.{answer as result};\n"
                   "fn main() { result() - 42 }\n",
        "math.mt": "module detail { pub fn number() { 42 } }\n"
                   "pub import detail.number as answer;\n"},
    "directory-module-inline-child": {
        "main.mt": "module math;\nfn main() { math.answer() - 42 }\n",
        "math/module.mt": "module detail { pub module values; }\n"
                          "pub fn answer() { detail.values.answer() }\n",
        "math/detail/values.mt": "pub fn answer() { 42 }\n"},
}

RAW_PARTS_PROGRAM = 'fn tail<region r>(read v: [u8] from r): read [u8] from r {\n    let p = core.slice.data(v)\n    unsafe { core.slice.from_raw_parts(p.add(1usize), v.len() - 1usize) }\n}\nfn main(): i32 {\n    var a: [u8; 4] = [1u8, 2u8, 3u8, 4u8]\n    let all: read [u8] = read a\n    let t = tail(all)\n    if t.len() != 3usize || t[0] != 2u8 { return 1 }\n    let p = core.ptr.from_mut(a).cast<u8>()\n    let m: mut [u8] = unsafe { core.slice.from_raw_parts_mut(p, 2usize) }\n    m[1] = 9u8\n    if a[1] != 9u8 { return 2 }\n    0\n}\n'
TEXT_SLICE_PROGRAM = """fn main(): i32 {
    let a = "h\\u{e9}llo"
    let b: read core.text.Text = read a[1..3]
    if !(b == "\\u{e9}") { return 1 }
    if a[..1].len() != 1usize || a[3..].len() != 3usize || a[..].len() != 6usize || a[..=0].len() != 1usize { return 2 }
    0
}
"""
TEXT_STATIC_PROGRAM = """static GREETING: read core.text.Text from static = "hi\\u{e9}";
static BYTES: read [u8; 2] from static = b"ab";
fn main(): i32 {
    if GREETING.len() != 4usize { return 1 }
    if BYTES[1] != 98u8 { return 2 }
    let raw = r#"a\\n"b"#
    if raw.len() != 5usize { return 3 }
    0
}
"""
TEXT_PROGRAM = 'import core.iter.Iterator;\nfn code(read text: core.text.Text): usize {\n    var chars = text.chars()\n    var count = 0usize\n    while true {\n        match chars.next() {\n            present(c) => { count += 1usize },\n            none => { break }\n        }\n    }\n    count\n}\nfn valid(read bytes: [u8]): bool {\n    match core.text.from_utf8(bytes) { present(t) => true, none => false }\n}\nfn two(a: u8, b: u8): bool { let v = [a, b]\n    valid(read v) }\nfn three(a: u8, b: u8, c: u8): bool { let v = [a, b, c]\n    valid(read v) }\nfn four(a: u8, b: u8, c: u8, d: u8): bool { let v = [a, b, c, d]\n    valid(read v) }\nfn main(): i32 {\n    let a = "h\\u{e9}llo\\n"\n    if a.len() != 7usize || code(a) != 6usize { return 1 }\n    if !(a == "h\\u{e9}llo\\n") || a != "h\\u{e9}llo\\n" || a == "hello\\n" { return 2 }\n    if !"".is_empty() || "a\\u{1F600}\\x41\\t\\\\\\"".len() != 9usize { return 3 }\n    if a.as_bytes()[1usize] != 0xc3u8 { return 4 }\n    match a.get(0usize, 2usize) { present(t) => { return 5 }, none => {} }\n    match a.get(0usize, 3usize) { present(t) => { if !(t == "h\\u{e9}") { return 6 } }, none => { return 7 } }\n    if !a.is_char_boundary(3usize) || a.is_char_boundary(2usize) { return 8 }\n    if !a.starts_with("h\\u{e9}l") || a.starts_with("hel") { return 9 }\n    match a.find_byte(0x6cu8) { present(i) => { if i != 3usize { return 10 } }, none => { return 11 } }\n    if two(0xc0u8, 0x80u8) || !two(0xc2u8, 0xa9u8) || two(0xe2u8, 0x82u8) { return 12 }\n    if two(0x80u8, 0x41u8) || two(0xffu8, 0x41u8) { return 13 }\n    if three(0xe0u8, 0x80u8, 0x80u8) || three(0xedu8, 0xa0u8, 0x80u8) { return 14 }\n    if !three(0xe2u8, 0x82u8, 0xacu8) || three(0xe2u8, 0x82u8, 0x41u8) { return 15 }\n    if four(0xf4u8, 0x90u8, 0x80u8, 0x80u8) || four(0xf0u8, 0x80u8, 0x80u8, 0x80u8) { return 16 }\n    if !four(0xf0u8, 0x9fu8, 0x98u8, 0x80u8) { return 17 }\n    0\n}\n'


def run(arguments, expected=0):
    result = subprocess.run(arguments, text=True, capture_output=True, timeout=900)
    if result.returncode != expected:
        raise AssertionError(
            f"{arguments!r}: expected {expected}, got {result.returncode}\n"
            f"{result.stdout}{result.stderr}")
    return result


def main(executable, directory, only=None):
    executable = str(Path(executable).resolve())
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)

    def case(name, files, phase=None, message=None, location=None, diagnostic_file="main.mt", options=(), trap=False, count=None, build_only=False):
        root = directory / name
        shutil.rmtree(root, ignore_errors=True)
        root.mkdir(parents=True)
        for path, text in files.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        source = root / "main.mt"
        program = root / "program"
        if message:
            program.write_bytes(b"preserve prior output")
            result = run([executable, "build", str(source), "-o", str(program), *options], 1)
            line, column = location
            intended = (re.escape(f"{root / diagnostic_file}:{line}:{column}: error[{phase}]:") +
                        r"[^\n]*" + re.escape(message))
            if not re.search(intended, result.stderr):
                raise AssertionError(f"{name}: wrong diagnostic:\n{result.stderr}")
            if count is not None and result.stderr.count("error[") != count:
                raise AssertionError(f"{name}: expected {count} diagnostics:\n{result.stderr}")
            if program.read_bytes() != b"preserve prior output":
                raise AssertionError(f"{name}: failed build damaged prior output")
        else:
            run([executable, "build", str(source), "-o", str(program), *options])
            if trap:
                if subprocess.run([str(program)], timeout=30).returncode == 0:
                    raise AssertionError(f"{name}: expected a trap")
            elif not build_only:
                run([str(program)])
        return root

    def library_cases():
        # Native `core` library behavior: each program returns 0 when every check holds.
        for program in sorted((Path(__file__).parent / "library").glob("*.mt")):
            case("library-core-" + program.stem.replace("_", "-"), {"main.mt": program.read_text()})
        case("library-builtin-pointer-does-not-load-core", {
            "lib/core/module.mt": "pub module ptr;\n"
                                 "pub fn broken(): i32 { missing() }\n",
            "main.mt": "fn main(): i32 {\n"
                       "    let pointer = core.ptr.null_mut<i32>()\n"
                       "    0\n"
                       "}\n"},
             options=["--library-dir", str(
                 directory / "library-builtin-pointer-does-not-load-core" / "lib")])
        absent = case("library-core-unwrap-none-aborts", {
            "main.mt": "import core.option;\nfn nothing(): i32? { none }\n"
                       "fn main(): i32 { nothing().unwrap() }\n"}, build_only=True)
        aborted = subprocess.run([str(absent / "program")], capture_output=True, timeout=60)
        if aborted.returncode == 0:
            raise AssertionError("unwrap of an absent value must abort")
        case("library-prelude-names-need-no-import", {
            "main.mt": "fn order(a: i32, b: i32): Ordering { a.cmp(b) }\n"
                       "fn size(read t: Text): usize { t.len() }\n"
                       "module inner { pub fn text_len(read t: Text): usize { t.len() } }\n"
                       "fn main(): i32 {\n"
                       "    assert(size(\"abc\") == 3usize && inner.text_len(\"hi\") == 2usize, \"lengths\")\n"
                       "    match order(1, 2) { Ordering.Less => 0, _ => 1 }\n}\n"})
        case("library-prelude-is-shadowed-by-declarations-and-imports", {
            "main.mt": "type Ordering { rank: i32 }\n"
                       "import core.text.Text as Words;\n"
                       "fn assert(flag: bool, rank: i32): i32 { if flag { rank } else { 1 } }\n"
                       "fn size(read t: Words): usize { t.len() }\n"
                       "fn main(): i32 { let order = Ordering(assert(true, 0)); order.rank + (size(\"\") as i32) }\n"})
        case("library-prelude-absent-when-core-is-user-defined", {
            "main.mt": "module core { pub fn answer(): i32 { 42 } }\n"
                       "fn size(read t: Text): i32 { 0 }\nfn main(): i32 { core.answer() - 42 }\n"},
             "name", "unresolved or inaccessible type 'Text'", (2, 9))
        panicked = case("library-panic-reports-message-and-exits-101", {
            "main.mt": "fn nothing(): i32? { none }\n"
                       "fn main(): i32 { let guard = nothing()\n guard.expect(\"value was required\") }\n"},
             build_only=True)
        exited = subprocess.run([str(panicked / "program")], capture_output=True, text=True, timeout=60)
        if exited.returncode != 101 or "panicked: value was required" not in exited.stderr:
            raise AssertionError(f"panic status/message: {exited.returncode} {exited.stderr!r}")
        explicit = case("library-panic-function-unwinds-and-exits-101", {
            "main.mt": "fn check(ok: bool) { if !ok { panic(\"check failed\") } }\n"
                       "fn main(): i32 { check(false)\n 0 }\n"}, build_only=True)
        exited = subprocess.run([str(explicit / "program")], capture_output=True, text=True, timeout=60)
        if exited.returncode != 101 or "panicked: check failed" not in exited.stderr:
            raise AssertionError(f"panic status/message: {exited.returncode} {exited.stderr!r}")
        freestanding = case("library-panic-freestanding-traps", {
            "main.mt": "fn main(): i32 { panic(\"no sink\") }\n"},
             options=["--freestanding", "--emit", "llvm"], build_only=True)
        listing = (freestanding / "program").read_text()
        if "llvm.trap" not in listing or "mettle_rt_panic_message" in listing:
            raise AssertionError("freestanding panic must lower to a trap without the hosted hook")

    def library_check_scales():
        # Checking cost must stay near-linear in the calls of a core generic
        # method; compare CPU time, which machine load does not inflate.
        calls = "".join(f"    let _v{i} = \"ab\".lines().next()\n" for i in range(80))
        root = directory / "library-core-check-scales"
        shutil.rmtree(root, ignore_errors=True)
        root.mkdir(parents=True)
        (root / "main.mt").write_text(
            "import core.text;\nimport core.iter.Iterator;\nimport core.option;\n"
            f"fn main(): i32 {{\n{calls}    0\n}}\n")
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        run([executable, "check", str(root / "main.mt")])
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        used = after.ru_utime - before.ru_utime
        if used > 20:
            raise AssertionError(f"checking core generic calls used {used:.1f}s CPU")

    if only == "library":
        library_cases()
        library_check_scales()
        print("Native core library programs passed")
        return
    for name, files in TARGET_FILES.items():
        case(name, files)
    case("external-file-nested-child", {
        "main.mt": "module math;\nfn main() { math.answer() - 42 }\n",
        "math.mt": "module values;\n"
                   "pub fn answer() { values.answer() }\n",
        "math/values.mt": "pub fn answer() { 42 }\n"})
    case("private-parent-visible-to-descendant", {
        "main.mt": "fn answer() { 42 }\n"
                   "module child { pub fn result() { super.answer() } }\n"
                   "fn main() { child.result() - 42 }\n"})
    case("restricted-visible-siblings", {
        "main.mt": "module outer {\n"
                   "module a { pub(super) fn answer() { 42 } }\n"
                   "module b { pub fn answer() { super.a.answer() } }\n"
                   "pub fn result() { b.answer() }\n}\n"
                   "fn main() { outer.result() - 42 }\n"})
    case("same-declaration-two-globs", {
        "main.mt": "module base { pub fn answer() { 42 } }\n"
                   "module a { pub import package.base.answer; }\n"
                   "module b { pub import package.base.answer; }\n"
                   "import a.*;\nimport b.*;\nfn main() { answer() - 42 }\n"})
    case("explicit-before-globs-independent-of-order", {
        "main.mt": "module a { pub fn answer() { 1 } }\n"
                   "module b { pub fn answer() { 42 } }\n"
                   "import a.*;\nimport b.answer;\n"
                   "fn main() { answer() - 42 }\n"})
    case("nominal-alias-static-and-method", {
        "main.mt": "module geometry {\n"
                   "pub copy type Point { pub x: i32; pub y: i32;\n"
                   "pub static fn make(x: i32, y: i32): Self { Self(x, y) }\n"
                   "pub fn sum() { self.x + self.y }\n}\n"
                   "pub alias Position = Point;\n}\n"
                   "import geometry.Position as P;\n"
                   "fn inspect(read value: P) { value.sum() }\n"
                   "fn main() { let value = P.make(20, 22); inspect(value) - 42 }\n"})
    case("distinct-nominal-module-identities", {
        "main.mt": "module a { pub copy type Record { pub x: i32 }\n"
                   "pub fn make(): Record { Record(20) } }\n"
                   "module b { pub copy type Record { pub x: i32 }\n"
                   "pub fn make(): Record { Record(22) } }\n"
                   "fn main() { a.make().x + b.make().x - 42 }\n"})
    case("imported-enum-variants", {
        "main.mt": "module colors { pub enum Color { Red(i32), Blue } }\n"
                   "import colors.Color.{Red as R, Blue as B};\n"
                   "fn main() { let red = R(42); let blue = B;\n"
                   "let answer = match red {\n"
                   "colors.Color.Red(value) => value,\n"
                   "colors.Color.Blue => 1 };\n"
                   "match blue { colors.Color.Red(_) => 1,\n"
                   "colors.Color.Blue => answer - 42 } }\n"})
    case("distinct-type-and-value-namespaces", {
        "main.mt": "module model { pub enum Tag { Value }\n"
                   "pub fn Tag() { 42 } }\n"
                   "fn main() { let tag: model.Tag = model.Tag.Value;\n"
                   "model.Tag() - 42 }\n"})
    case("local-binding-and-method-precede-imported-variant", {
        "main.mt": "enum Token { UnitValue }\n"
                   "import Token.UnitValue as get;\n"
                   "copy type Value { fn get() { 42 } }\n"
                   "fn main() { let get = 0; let value = Value();\n"
                   "if value.get() == 42 && get == 0 { 0 } else { 1 } }\n"})
    case("public-custom-constructor-private-fields", {
        "main.mt": "module hidden { pub type Value { value: i32;\n"
                   "pub init(value: i32) { self.value = value }\n"
                   "pub fn get() { self.value } } }\n"
                   "fn main() { hidden.Value(42).get() - 42 }\n"})
    case("defaults-use-declaration-module-and-unique-symbols", {
        "main.mt": "module a { fn value() { 20 }\n"
                   "pub fn answer(input: i32 = value()) { input } }\n"
                   "module b { fn value() { 22 }\n"
                   "pub fn answer(input: i32 = value()) { input } }\n"
                   "fn main() { a.answer() + b.answer() - 42 }\n"})
    case("private-item", {
        "main.mt": "module child { fn hidden() { 42 } }\n"
                   "fn main() { child.hidden() }\n"},
         "name", "unresolved or inaccessible function 'child.hidden'", (2, 13))
    case("alias-destructor-call", {
        "main.mt": "type Guard { drop {} }\nalias Alias = Guard;\n"
                   "fn main() { var guard = Guard(); Alias.drop(guard); 0 }\n"},
         "ownership", "cannot invoke a destructor directly", (3, 34))
    case("module-qualified-destructor-call", {
        "main.mt": "module resource { pub type Guard { drop {} } }\n"
                   "fn main() { var guard = resource.Guard();\n"
                   "resource.Guard.drop(guard); 0 }\n"},
         "ownership", "cannot invoke a destructor directly", (3, 1))
    case("module-receiver-destructor-call", {
        "main.mt": "module resource { pub type Guard { drop {} } }\n"
                   "fn main() { var guard = resource.Guard(); guard.drop(); 0 }\n"},
         "ownership", "cannot invoke a destructor directly", (2, 43))
    case("enum-is-not-a-product-constructor", {
        "main.mt": "enum Choice { First(i32), Second }\n"
                   "fn main() { let forged = Choice(0, 42); 0 }\n"},
         "type", "enum construction requires a named variant", (2, 26))
    case("private-field-read", {
        "main.mt": "module hidden { pub type Value { value: i32 }\n"
                   "pub fn make(): Value { Value(42) } }\n"
                   "fn main() { hidden.make().value }\n"},
         "name", "private or restricted field 'value' is inaccessible", (3, 13))
    case("private-field-constructor", {
        "main.mt": "module hidden { pub type Value { value: i32 } }\n"
                   "fn main() { let value = hidden.Value(42); 0 }\n"},
         "name", "private or restricted field 'value' is inaccessible", (2, 25))
    case("private-method", {
        "main.mt": "module hidden { pub type Value { pub value: i32;\n"
                   "fn get() { self.value } }\n"
                   "pub fn make(): Value { Value(42) } }\n"
                   "fn main() { hidden.make().get() }\n"},
         "name", "private or restricted function 'Value.get' is inaccessible", (4, 13))
    case("private-reexport", {
        "main.mt": "module child { fn hidden() { 42 }\n"
                   "pub import hidden as exposed; }\n"
                   "fn main() { 0 }\n"},
         "name", "cannot reexport private or restricted item 'exposed'", (2, 5))
    case("package-private-reexport", {
        "main.mt": "fn hidden() { 42 }\n"
                   "pub import hidden as exposed;\n"
                   "fn main() { 0 }\n"},
         "name", "cannot reexport private or restricted item 'exposed'", (2, 5))
    case("restriction-not-ancestor", {
        "main.mt": "module a {}\nmodule b { pub(package.a) fn bad() { 0 } }\n"
                   "fn main() { 0 }\n"},
         "name", "restricted visibility must name an enclosing module", (2, 12))
    case("restricted-denied", {
        "main.mt": "module outer { pub(super) module child {\n"
                   "pub(super) fn hidden() { 42 } } }\n"
                   "fn main() { outer.child.hidden() }\n"},
         "name", "unresolved or inaccessible function 'outer.child.hidden'", (3, 13))
    case("ambiguous-globs", {
        "main.mt": "module a { pub fn value() { 1 } }\n"
                   "module b { pub fn value() { 2 } }\n"
                   "import a.*;\nimport b.*;\nfn main() { 0 }\n"},
         "name", "ambiguous glob imports for 'value'", (4, 1))
    case("duplicate-explicit-imports", {
        "main.mt": "module a { pub fn value() { 1 } }\n"
                   "import a.value;\nimport a.value;\nfn main() { 0 }\n"},
         "name", "duplicate explicit binding 'value'", (3, 1))
    case("cyclic-imports", {
        "main.mt": "import second as first;\nimport first as second;\n"
                   "fn main() { 0 }\n"},
         "name", "unresolved, inaccessible, ambiguous or cyclic import 'second'", (1, 1))
    case("missing-external", {
        "main.mt": "module missing;\nfn main() { 0 }\n"},
         "name", "external module 'missing' requires exactly one of", (1, 1))
    case("two-external-candidates", {
        "main.mt": "module child;\nfn main() { 0 }\n",
        "child.mt": "fn unused() { 1 }\n",
        "child/module.mt": "fn unused() { 2 }\n"},
         "name", "external module 'child' matches both", (1, 1))
    case("external-file-diagnostic", {
        "main.mt": "module child;\nfn main() { 0 }\n",
        "child.mt": "fn broken() { missing() }\n"},
         "name", "unresolved or inaccessible function 'missing'", (1, 15), "child.mt")
    # Native library mounting and text literals.
    case("library-text-literals", {"main.mt": TEXT_PROGRAM})
    case("library-text-invalid-escape", {
        "main.mt": "fn main(): i32 { let t: read core.text.Text from static = \"a\\q\"\n 0 }\n"},
         "lex", "invalid text escape", (1, 59), count=1)
    case("library-text-invalid-escape-no-cascade", {
        "main.mt": "fn main(): i32 { let n = \"a\\q\".len()\n 0 }\n"},
         "lex", "invalid text escape", (1, 26), count=1)
    case("library-text-range-slicing", {"main.mt": TEXT_SLICE_PROGRAM})
    case("library-text-range-slicing-non-boundary-traps", {
        "main.mt": "fn main(): i32 { let a = \"h\\u{e9}llo\"\n let b = read a[1..2]\n if b.len() == 9usize { return 1 }\n 0 }\n"},
         trap=True)
    case("library-text-range-slicing-out-of-bounds-traps", {
        "main.mt": "fn main(): i32 { let a = \"hello\"\n let b = read a[2..9]\n if b.len() == 9usize { return 1 }\n 0 }\n"},
         trap=True)
    case("library-text-static-and-raw-literals", {"main.mt": TEXT_STATIC_PROGRAM})
    case("library-slice-from-raw-parts", {"main.mt": RAW_PARTS_PROGRAM})
    case("library-subslice-keeps-source-region", {
        "main.mt": "fn pick<region a, region b>(read v: [u8] from a, read w: [u8] from b): read [u8] from a {\n    read w[0..1]\n}\nfn main(): i32 { 0 }\n"},
         "region", "view region or invariant payload does not satisfy its declared relationship", (1, 89))
    library = {"lib/core/module.mt": "pub module text;\npub fn answer(): i32 { 42 }\n",
               "lib/core/text.mt": "pub type Text { bytes: [u8] }\n",
               "lib/alloc/module.mt": "pub fn broken(): i32 { missing() }\n",
               "lib/std/module.mt": "pub fn broken(): i32 { missing() }\n"}
    custom = ["--library-dir", str(directory / "library-custom-dir-item" / "lib")]
    case("library-custom-dir-item", {
        **library, "main.mt": "fn main(): i32 { core.answer() - 42 }\n"}, options=custom)
    case("library-alloc-reaches-core-by-package-path", {
        "lib/core/module.mt": "pub fn answer(): i32 { 42 }\n",
        "lib/alloc/module.mt": "pub fn via_core(): i32 { package.core.answer() }\n",
        "lib/std/module.mt": "",
        "main.mt": "fn main(): i32 { alloc.via_core() - 42 }\n"},
         options=["--library-dir", str(directory / "library-alloc-reaches-core-by-package-path" / "lib")])
    case("library-diagnostic-in-library-file", {
        **library, "main.mt": "fn main(): i32 { std.broken() }\n"},
         "name", "unresolved or inaccessible function 'missing'", (1, 24),
         "lib/std/module.mt", ["--library-dir", str(directory / "library-diagnostic-in-library-file" / "lib")])
    case("library-user-root-shadows", {
        "main.mt": "module core { pub fn answer(): i32 { 42 } }\n"
                   "fn main(): i32 { core.answer() - 42 }\n"})
    layering = {"lib/core/module.mt": "pub fn up(): i32 { alloc.broken() }\n",
                "lib/alloc/module.mt": "pub fn broken(): i32 { 0 }\n",
                "lib/std/module.mt": "pub fn broken(): i32 { 0 }\n"}
    case("library-core-depends-on-alloc", {
        **layering, "main.mt": "fn main(): i32 { core.up() }\n"},
         "name", "library module 'core' may not depend on 'alloc'", (1, 20),
         "lib/core/module.mt", ["--library-dir", str(directory / "library-core-depends-on-alloc" / "lib")])
    case("library-std-freestanding", {
        "main.mt": "fn main(): i32 { std.answer() }\n"},
         "name", "library module 'std' is not available in a freestanding build", (1, 18),
         options=["--freestanding", "--emit", "object"])
    case("library-missing-file", {
        "lib/other/module.mt": "", "main.mt": "fn main(): i32 { alloc.x() }\n"},
         "name", "library module 'alloc'", (1, 18),
         options=["--library-dir", str(directory / "library-missing-file" / "lib")])
    root = directory / "library-freestanding-object"
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    (root / "main.mt").write_text(
        'fn size(): usize { let t = "h\\u{e9}llo"\n t.len() }\n')
    run([executable, "build", str(root / "main.mt"), "--freestanding",
         "--emit", "object", "-o", str(root / "main.o")])
    root = case("canonical-file-identity", {
        "main.mt": "module first;\nfn main() { 0 }\n",
        "first.mt": "fn unused() { 0 }\n"})
    (root / "second.mt").unlink(missing_ok=True)
    (root / "second.mt").symlink_to("first.mt")
    (root / "main.mt").write_text("module first;\nmodule second;\nfn main() { 0 }\n")
    result = run([executable, "check", str(root / "main.mt")], 1)
    if f"{root / 'main.mt'}:2:1: error[name]:" not in result.stderr or \
            "more than one module identity" not in result.stderr:
        raise AssertionError(f"duplicate canonical source accepted:\n{result.stderr}")
    print("Module multi-file compile/run and diagnostic cases passed")


if __name__ == "__main__":
    main(*sys.argv[1:])
