#!/usr/bin/env python3
"""Focused multi-file module compile/run and diagnostic regressions."""

import subprocess
import sys
from pathlib import Path

TARGET_FILES = {
    "external-inline-alias-group-reexport": {
        "main.mt": "module math;\nimport math::{answer as result};\n"
                   "fn main() { result() - 42 }\n",
        "math.mt": "module detail { pub fn number() { 42 } }\n"
                   "pub import self::detail::number as answer;\n"},
    "directory-module-inline-child": {
        "main.mt": "module math;\nfn main() { math::answer() - 42 }\n",
        "math/module.mt": "module detail { pub module values; }\n"
                          "pub fn answer() { detail::values::answer() }\n",
        "math/detail/values.mt": "pub fn answer() { 42 }\n"},
}


def run(arguments, expected=0):
    result = subprocess.run(arguments, text=True, capture_output=True, timeout=30)
    if result.returncode != expected:
        raise AssertionError(
            f"{arguments!r}: expected {expected}, got {result.returncode}\n"
            f"{result.stdout}{result.stderr}")
    return result


def main(executable, directory):
    executable = str(Path(executable).resolve())
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)

    def case(name, files, message=None, diagnostic_file="main.mt"):
        root = directory / name
        root.mkdir(parents=True, exist_ok=True)
        for path, text in files.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        source = root / "main.mt"
        program = root / "program"
        if message:
            program.write_bytes(b"preserve prior output")
            result = run([executable, "build", str(source), "-o", str(program)], 1)
            if message not in result.stderr or f"{root / diagnostic_file}:" not in result.stderr:
                raise AssertionError(f"{name}: wrong diagnostic:\n{result.stderr}")
            if program.read_bytes() != b"preserve prior output":
                raise AssertionError(f"{name}: failed build damaged prior output")
        else:
            run([executable, "build", str(source), "-o", str(program)])
            run([str(program)])
        return root

    for name, files in TARGET_FILES.items():
        case(name, files)
    case("external-file-nested-child", {
        "main.mt": "module math;\nfn main() { math::answer() - 42 }\n",
        "math.mt": "module values;\n"
                   "pub fn answer() { values::answer() }\n",
        "math/values.mt": "pub fn answer() { 42 }\n"})
    case("private-parent-visible-to-descendant", {
        "main.mt": "fn answer() { 42 }\n"
                   "module child { pub fn result() { super::answer() } }\n"
                   "fn main() { child::result() - 42 }\n"})
    case("restricted-visible-siblings", {
        "main.mt": "module outer {\n"
                   "module a { pub(super) fn answer() { 42 } }\n"
                   "module b { pub fn answer() { super::a::answer() } }\n"
                   "pub fn result() { b::answer() }\n}\n"
                   "fn main() { outer::result() - 42 }\n"})
    case("same-declaration-two-globs", {
        "main.mt": "module base { pub fn answer() { 42 } }\n"
                   "module a { pub import package::base::answer; }\n"
                   "module b { pub import package::base::answer; }\n"
                   "import a::*;\nimport b::*;\nfn main() { answer() - 42 }\n"})
    case("explicit-before-globs-independent-of-order", {
        "main.mt": "module a { pub fn answer() { 1 } }\n"
                   "module b { pub fn answer() { 42 } }\n"
                   "import a::*;\nimport b::answer;\n"
                   "fn main() { answer() - 42 }\n"})
    case("nominal-alias-static-and-method", {
        "main.mt": "module geometry {\n"
                   "pub copy type Point { pub x: i32; pub y: i32;\n"
                   "pub static fn make(x: i32, y: i32): Self { Self(x, y) }\n"
                   "pub fn sum() { self.x + self.y }\n}\n"
                   "pub alias Position = Point;\n}\n"
                   "import geometry::Position as P;\n"
                   "fn inspect(value: read P) { value.sum() }\n"
                   "fn main() { let value = P::make(20, 22); inspect(value) - 42 }\n"})
    case("distinct-nominal-module-identities", {
        "main.mt": "module a { pub copy type Record { pub x: i32 }\n"
                   "pub fn make(): Record { Record(20) } }\n"
                   "module b { pub copy type Record { pub x: i32 }\n"
                   "pub fn make(): Record { Record(22) } }\n"
                   "fn main() { a::make().x + b::make().x - 42 }\n"})
    case("imported-enum-variants", {
        "main.mt": "module colors { pub enum Color { Red(i32), Blue } }\n"
                   "import colors::Color::{Red as R, Blue as B};\n"
                   "fn main() { let red = R(42); let blue = B;\n"
                   "let answer = match red {\n"
                   "colors::Color::Red(value) => value,\n"
                   "colors::Color::Blue => 1 };\n"
                   "match blue { colors::Color::Red(_) => 1,\n"
                   "colors::Color::Blue => answer - 42 } }\n"})
    case("distinct-type-and-value-namespaces", {
        "main.mt": "module model { pub enum Tag { Value }\n"
                   "pub fn Tag() { 42 } }\n"
                   "fn main() { let tag: model::Tag = model::Tag::Value;\n"
                   "model::Tag() - 42 }\n"})
    case("local-binding-and-method-precede-imported-variant", {
        "main.mt": "enum Token { UnitValue }\n"
                   "import Token::UnitValue as get;\n"
                   "copy type Value { fn get() { 42 } }\n"
                   "fn main() { let get = 0; let value = Value();\n"
                   "if value.get() == 42 && get == 0 { 0 } else { 1 } }\n"})
    case("public-custom-constructor-private-fields", {
        "main.mt": "module hidden { pub type Value { value: i32;\n"
                   "pub init(value: i32) { self.value = value }\n"
                   "pub fn get() { self.value } } }\n"
                   "fn main() { hidden::Value(42).get() - 42 }\n"})
    case("defaults-use-declaration-module-and-unique-symbols", {
        "main.mt": "module a { fn value() { 20 }\n"
                   "pub fn answer(input: i32 = value()) { input } }\n"
                   "module b { fn value() { 22 }\n"
                   "pub fn answer(input: i32 = value()) { input } }\n"
                   "fn main() { a::answer() + b::answer() - 42 }\n"})
    case("private-item", {
        "main.mt": "module child { fn hidden() { 42 } }\n"
                   "fn main() { child::hidden() }\n"}, "inaccessible")
    case("alias-destructor-call", {
        "main.mt": "type Guard { drop {} }\nalias Alias = Guard;\n"
                   "fn main() { var guard = Guard(); Alias::drop(guard); 0 }\n"},
         "error[ownership]: cannot invoke a destructor directly")
    case("module-qualified-destructor-call", {
        "main.mt": "module resource { pub type Guard { drop {} } }\n"
                   "fn main() { var guard = resource::Guard();\n"
                   "resource::Guard::drop(guard); 0 }\n"},
         "error[ownership]: cannot invoke a destructor directly")
    case("module-receiver-destructor-call", {
        "main.mt": "module resource { pub type Guard { drop {} } }\n"
                   "fn main() { var guard = resource::Guard(); guard.drop(); 0 }\n"},
         "error[ownership]: cannot invoke a destructor directly")
    case("enum-is-not-a-product-constructor", {
        "main.mt": "enum Choice { First(i32), Second }\n"
                   "fn main() { let forged = Choice(0, 42); 0 }\n"},
         "named variant")
    case("private-field-read", {
        "main.mt": "module hidden { pub type Value { value: i32 }\n"
                   "pub fn make(): Value { Value(42) } }\n"
                   "fn main() { hidden::make().value }\n"}, "inaccessible")
    case("private-field-constructor", {
        "main.mt": "module hidden { pub type Value { value: i32 } }\n"
                   "fn main() { let value = hidden::Value(42); 0 }\n"},
         "inaccessible")
    case("private-method", {
        "main.mt": "module hidden { pub type Value { pub value: i32;\n"
                   "fn get() { self.value } }\n"
                   "pub fn make(): Value { Value(42) } }\n"
                   "fn main() { hidden::make().get() }\n"}, "inaccessible")
    case("private-reexport", {
        "main.mt": "module child { fn hidden() { 42 }\n"
                   "pub import self::hidden as exposed; }\n"
                   "fn main() { 0 }\n"}, "cannot reexport")
    case("package-private-reexport", {
        "main.mt": "fn hidden() { 42 }\n"
                   "pub import self::hidden as exposed;\n"
                   "fn main() { 0 }\n"}, "cannot reexport")
    case("restriction-not-ancestor", {
        "main.mt": "module a {}\nmodule b { pub(package::a) fn bad() { 0 } }\n"
                   "fn main() { 0 }\n"}, "enclosing module")
    case("restricted-denied", {
        "main.mt": "module outer { pub(super) module child {\n"
                   "pub(super) fn hidden() { 42 } } }\n"
                   "fn main() { outer::child::hidden() }\n"}, "inaccessible")
    case("ambiguous-globs", {
        "main.mt": "module a { pub fn value() { 1 } }\n"
                   "module b { pub fn value() { 2 } }\n"
                   "import a::*;\nimport b::*;\nfn main() { 0 }\n"},
         "ambiguous glob")
    case("duplicate-explicit-imports", {
        "main.mt": "module a { pub fn value() { 1 } }\n"
                   "import a::value;\nimport a::value;\nfn main() { 0 }\n"},
         "duplicate explicit binding")
    case("cyclic-imports", {
        "main.mt": "import second as first;\nimport first as second;\n"
                   "fn main() { 0 }\n"}, "cyclic import")
    case("missing-external", {
        "main.mt": "module missing;\nfn main() { 0 }\n"}, "requires exactly one")
    case("two-external-candidates", {
        "main.mt": "module child;\nfn main() { 0 }\n",
        "child.mt": "fn unused() { 1 }\n",
        "child/module.mt": "fn unused() { 2 }\n"}, "matches both")
    case("external-file-diagnostic", {
        "main.mt": "module child;\nfn main() { 0 }\n",
        "child.mt": "fn broken() { missing() }\n"}, "missing", "child.mt")
    root = case("canonical-file-identity", {
        "main.mt": "module first;\nfn main() { 0 }\n",
        "first.mt": "fn unused() { 0 }\n"})
    (root / "second.mt").unlink(missing_ok=True)
    (root / "second.mt").symlink_to("first.mt")
    (root / "main.mt").write_text("module first;\nmodule second;\nfn main() { 0 }\n")
    result = run([executable, "check", str(root / "main.mt")], 1)
    if "more than one module identity" not in result.stderr:
        raise AssertionError(f"duplicate canonical source accepted:\n{result.stderr}")
    print("Module multi-file compile/run and diagnostic cases passed")


if __name__ == "__main__":
    main(*sys.argv[1:])
