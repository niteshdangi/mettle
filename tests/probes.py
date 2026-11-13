#!/usr/bin/env python3
"""Bespoke compiler probes that are not plain run/fail programs.

  syntax      lexer/syntax-tree/recovery/diagnostic-budget checks through `mettle tokens|syntax|check`
  fast-math   LLVM floating-point flag inspection of
              tests/source/run/machine-numeric-explicit-function-and-module-relaxations.mt
  broken-pipe `print` to a closed stdout: SIGPIPE under the default disposition,
              a quiet exit status 141 when SIGPIPE is ignored
  sanitizers  ASan heap-overflow and TSan data-race checks on emitted Mettle
              programs
  selfhost-lexer  compare a compiled Mettle lexer (--seed) with bootstrap tokens
  selfhost-parser  compare the Mettle parser core with bootstrap syntax
  selfhost-unicode  Unicode 16.0 NFC/XID conformance through the native fixture
"""

import argparse
import hashlib
import json
import os
import platform
import re
import resource
import signal
import subprocess
import time
from pathlib import Path

import processes

ROOT = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run_suite(mode, executable, directory, seed=None, case_filter=None, ucd_dir=None):
    executable = str(Path(executable).resolve())
    directory = Path(directory) / mode
    directory.mkdir(parents=True, exist_ok=True)
    evidence = {"scope": "Source regressions through the initial I06 machine boundary; not full language or release qualification",
                "status": "in_progress", "mode": mode, "compiler_sha256": digest(executable),
                "host": platform.platform(), "commands": [], "cases": []}
    if case_filter:
        evidence["case_filter"] = case_filter

    def selected(name):
        return not case_filter or re.search(case_filter, name)

    def run(arguments, expected=0, env=None, input_text=None, memory_limit=None):
        def constrain_memory():
            resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))

        begin = time.perf_counter()
        result = processes.run(arguments, text=True, capture_output=True, env=env, input=input_text,
                                preexec_fn=constrain_memory if memory_limit else None)
        evidence["commands"].append({"command": list(map(str, arguments)),
                                    "exit_status": result.returncode,
                                    "elapsed_seconds": time.perf_counter() - begin,
                                    "stdout": result.stdout, "stderr": result.stderr})
        if (expected == "trap" and result.returncode != -signal.SIGABRT) or (
                expected != "trap" and result.returncode != expected):
            raise AssertionError(f"{arguments!r}: expected {expected}, got {result.returncode}\n"
                                 f"{result.stdout}{result.stderr}")
        return result

    def source(name, text):
        path = directory / (name + ".mt")
        path.write_text(text)
        return path

    def selfhost_lexer():
        import random

        native = str(Path(seed).resolve())
        evidence["scope"] = "Self-hosted lexer token/diagnostic parity; not parser or compiler qualification"
        evidence["seed_sha256"] = digest(native)
        valid = {
            "empty": b"",
            "trivia": b" \t\v\f\r\n// cafe\xc3\xa9\r/* outer /* inner */ done */\n",
            "numbers": b"1..3 1..=3 1.5e+3 2f32 3.25 1e-9 0xff 0o77 0b10 tuple.0.1 tuple. /*x*/ 0.1",
            "symbols": b"... ..= >>= <<= == != <= >= && || += -= *= /= %= &= |= ^= << >> -> => ?. ?? (){}[],;:+-*/%!=<>&|^.?@$",
            "text": b'"" "a\\\"b\\\\c" b"hello" r#"a"b"# br##"one\ntwo"## `type`',
            "format": b'f"plain" f"{{x}} {value}" f"{ { 1 } }" f"{f"{2}"}" f"{r#"}"#}"',
            "characters": "'a' '\\n' '\\u{10ffff}' '\\u{0}' '\\u{d7ff}' '\\u{e000}' '\u00e9' '\U0001f600' b'a' b'\\xFF' b'\\0'".encode(),
        }
        invalid = {
            "utf8-leading": b"\xff",
            "utf8-truncated": b"//\n\xf0\x9f",
            "utf8-overlong": b"\xe0\x80\x80",
            "utf8-surrogate": b"\xed\xa0\x80",
            "utf8-range": b"\xf4\x90\x80\x80",
            "comment-eof": b"/* outer /* inner */",
            "raw-eof": b'r##"text"#',
            "text-newline": b'"text\r\nnext',
            "backtick-eof": b"`bad",
            "backtick-empty": b"``",
            "backtick-contents": b"`two words`",
            "format-brace": b'f"text } tail"',
            "format-hole-eof": b'f"{value',
            "format-newline": b'f"{value\nnext',
            "diagnostic-budget": b"~" * 140,
        }
        bad_characters = (b"''", b"'ab'", b"'\\q'", b"'\\u{}'", b"'\\u{gg}'",
                          b"'\\u{1234567}'", b"'\\u{d800}'", b"'\\u{110000}'",
                          b"'\\u1234'", b"'\\x41'", b"'\\'", b"'abc\n",
                          b"b''", b"b'\\x0'", b"b'\\xgg'", b"b'\\u{41}'",
                          "b'\u00e9'".encode())
        for i, literal in enumerate(bad_characters):
            invalid[f"character-{i}"] = literal
        cases = [(name, data, 0) for name, data in valid.items()]
        cases += [(name, data, 1) for name, data in invalid.items()]
        rng = random.Random(0)
        for i in range(64):
            cases.append((f"mixed-{i}", b"\x00" + bytes(rng.randrange(128) for _ in range(128)), 1))
        for path in sorted((ROOT.parent / "compiler").rglob("*.mt")):
            cases.append(("compiler-" + "-".join(path.relative_to(ROOT.parent / "compiler").parts),
                          path.read_bytes(), 0))
        for name, data, expected in cases:
            if not selected(name):
                continue
            path = directory / (name + ".mt")
            path.write_bytes(data)
            reference = run([executable, "tokens", str(path)], expected)
            actual = run([native, str(path)], expected)
            wanted = [(token["kind"], token["begin"], token["end"])
                      for token in json.loads(reference.stdout)["tokens"]]
            found = [tuple(map(int, line.split())) for line in actual.stdout.splitlines()]
            if found != wanted:
                mismatch = next((i for i, pair in enumerate(zip(found, wanted)) if pair[0] != pair[1]),
                                min(len(found), len(wanted)))
                raise AssertionError(f"{name}: token {mismatch}: {found[mismatch:mismatch + 1]} != {wanted[mismatch:mismatch + 1]}")
            native_diagnostics = re.findall(r"error\[(\w+)\] (\d+):(\d+) ([^\n]*)", actual.stderr)
            diagnostics = []
            for phase, begin, end, message in native_diagnostics:
                begin, end = int(begin), int(end)
                if not 0 <= begin <= end <= len(data):
                    raise AssertionError(f"{name}: invalid diagnostic span {begin}:{end}")
                line = data[:begin].count(b"\n") + 1
                start = data.rfind(b"\n", 0, begin) + 1
                column = sum(byte & 0xc0 != 0x80 for byte in data[start:begin]) + 1
                diagnostics.append((str(line), str(column), phase, message))
            reference_diagnostics = re.findall(r":(\d+):(\d+): error\[(\w+)\]: ([^\n]*)", reference.stderr)
            if diagnostics != reference_diagnostics:
                raise AssertionError(f"{name}: diagnostics differ\n{diagnostics}\n{reference_diagnostics}")
            if name.startswith("character-") and any(int(end) != len(data.rstrip(b"\n")) for _, _, end, _ in native_diagnostics):
                raise AssertionError(f"{name}: character diagnostic lost its full token span")
            evidence["cases"].append({"name": name, "source_sha256": digest(path),
                                      "tokens": len(found), "diagnostics": len(diagnostics)})

        unicode_words = {
            "unicode-scripts": ["αβ", "cafe\u0301", "_नमस्ते", "变量", "𐐀𐐨", "𮯰"],
            "unicode-quoted": ["`λ`", "`cafe\u0301`", "`type`"],
            "unicode-mixed": ["asciiλ123", "a\u0301_９", "\u2118x", "a\u200cx"],
        }
        for name, words in unicode_words.items():
            if not selected(name):
                continue
            data = " ".join(words).encode()
            wanted, at = [], 0
            for index, word in enumerate(words):
                encoded = word.encode()
                wanted.append((10 if word.startswith("`") else 0, at, at + len(encoded)))
                at += len(encoded)
                if index + 1 < len(words):
                    wanted.append((3, at, at + 1))
                    at += 1
            wanted.append((6, at, at))
            path = directory / (name + ".mt")
            path.write_bytes(data)
            actual = run([native, str(path)])
            assert [tuple(map(int, line.split())) for line in actual.stdout.splitlines()] == wanted, actual.stdout
            assert not actual.stderr, actual.stderr
            evidence["cases"].append({"name": name, "source_sha256": digest(path), "tokens": len(wanted)})
        for name, text, spans in (("unicode-leading-mark", "\u0301name", [(0, 2)]),
                                   ("unicode-symbol", "α😀β", [(2, 6)]),
                                   ("unicode-17", "\U00011db0", [(0, 4)]),
                                   ("unicode-quoted-mark", "`\u0301name`", [(0, 8)]),
                                   ("unicode-quoted-space", "`λ name`", [(0, 9)])):
            if not selected(name):
                continue
            path = source(name, text)
            actual = run([native, str(path)], 1)
            found = re.findall(r"error\[lex\] (\d+):(\d+) ([^\n]*)", actual.stderr)
            assert [(int(begin), int(end)) for begin, end, _ in found] == spans, (name, actual.stderr)
            message = "backtick contents must be an identifier" if "quoted" in name else "character is not permitted at the start of an identifier"
            assert all(item[2] == message for item in found), actual.stderr
            evidence["cases"].append({"name": name, "source_sha256": digest(path), "diagnostics": len(found)})

    def selfhost_unicode():
        native = str(Path(seed).resolve())
        evidence["scope"] = "Unicode 16.0 NFC conformance, exhaustive XID scalar comparison and token/parser identity integration"
        evidence["seed_sha256"] = digest(native)
        data = Path(ucd_dir).resolve()
        inputs = {"NormalizationTest.txt": "d811971453e7075e1ad56fb1b301eece5aa80757b81f6156e74a1bfb3ae5ceb1",
                  "DerivedCoreProperties.txt": "39d35161f2954497f69e08bdb9e701493f476a3d30222de20028feda36c1dabd"}
        for name, expected in inputs.items():
            assert digest(data / name) == expected, name + ": not the pinned Unicode 16.0 input"
        actual = run([native, str(data / "NormalizationTest.txt"), str(data / "DerivedCoreProperties.txt")])
        match = re.fullmatch(r"normalization (\d+)\nxid 1114112\nnfc-singletons 1112064\nintegration passed\n", actual.stdout)
        assert match and int(match[1]) == 19965, actual.stdout
        assert not actual.stderr, actual.stderr
        evidence["cases"].append({"name": "unicode-conformance", "normalization_rows": int(match[1]),
                                  "xid_codepoints": 1114112, "nfc_scalar_coverage": 1112064, "inputs": inputs})

    def selfhost_parser():
        native = str(Path(seed).resolve())
        evidence["scope"] = "Self-hosted selected grammar: structural syntax, lossless tokens, recovery and limits; no semantic or expansion qualification"
        evidence["seed_sha256"] = digest(native)
        if selected("source-limit"):
            path = directory / "source-limit.mt"
            with path.open("wb") as file:
                file.truncate(1 << 32)
            try:
                memory_limit = None if os.environ.get("ASAN_OPTIONS") else 96 * 1024 * 1024
                control = source("source-limit-control", "fn main() { 0 }\n")
                for command in ([], ["syntax"]):
                    run([native, *command, str(control)], memory_limit=memory_limit)
                    result = run([native, *command, str(path)], 1, memory_limit=memory_limit)
                    assert not result.stdout, result.stdout
                    assert result.stderr == "error[limit] 0:0 source file must be smaller than 4 GiB\n", result.stderr
                evidence["cases"].append({"name": "source-limit", "source_bytes": path.stat().st_size,
                                          "memory_limit": memory_limit})
            finally:
                path.unlink()
        kinds = {0: "integer", 1: "boolean", 2: "unit", 3: "name", 4: "group",
                 5: "unary", 6: "binary", 7: "call", 8: "block", 9: "if",
                 10: "binding", 11: "assign", 12: "return", 13: "while",
                 14: "loop", 15: "break", 16: "continue", 17: "field",
                 25: "tuple", 26: "array", 27: "index", 28: "range",
                 30: "coalesce", 31: "character", 32: "text", 34: "floating", 35: "cast"}
        textual = {"integer", "floating", "boolean", "character", "text", "name", "unary", "binary", "coalesce", "range", "assign", "binding", "field"}

        def inspect_native(result, data):
            nodes, edges, tokens = [], [], []
            for line in result.stdout.splitlines():
                fields = line.split()
                if fields[0] == "node":
                    index, kind, begin, end, first, last, operation, semicolon = fields[1:]
                    assert int(index) == len(nodes), line
                    nodes.append((kind, *map(int, (begin, end, first, last, operation, semicolon))))
                elif fields[0] == "edge":
                    edges.append(int(fields[1]))
                elif fields[0] == "token":
                    tokens.append(tuple(map(int, fields[1:])))
                else:
                    raise AssertionError(line)
            for index, (kind, begin, end, first, last, operation, semicolon) in enumerate(nodes):
                assert 0 <= begin <= end <= len(data), (kind, begin, end)
                assert 0 <= first <= last <= len(edges), (kind, first, last)
                assert operation == -1 or 0 <= operation < len(tokens), (kind, operation)
                for child in edges[first:last]:
                    assert 0 <= child < index, (kind, child, index)
                    assert begin <= nodes[child][1] <= nodes[child][2] <= end, (kind, nodes[child])
            if nodes:
                assert nodes[-1][0] == "module", nodes[-1]
                seen, work = set(), [len(nodes) - 1]
                while work:
                    index = work.pop()
                    assert index not in seen, "syntax nodes have multiple parents"
                    seen.add(index)
                    work.extend(edges[nodes[index][3]:nodes[index][4]])
                assert len(seen) == len(nodes), "orphaned syntax nodes"
            return nodes, edges, tokens

        def native_shape(index, nodes, edges, tokens, data):
            kind, begin, end, first, last, operation, semicolon = nodes[index]
            children = edges[first:last]
            text = data[begin:end].decode()
            if kind == "generic-apply":
                base = native_shape(children[0], nodes, edges, tokens, data)
                return (base[0], base[1], bool(semicolon), base[3])
            if kind == "binding":
                text = data[nodes[children[0]][1]:nodes[children[0]][2]].decode().strip('`')
                children = [child for child in children[1:] if nodes[child][0] != "type" and not nodes[child][0].startswith("type-")]
            elif kind == "field":
                text = data[nodes[children[-1]][1]:nodes[children[-1]][2]].decode().strip('`')
                children = children[:-1]
            elif kind == "call":
                children = children[:1] + edges[nodes[children[1]][3]:nodes[children[1]][4]]
            elif kind == "cast":
                children = children[:1]
            elif kind in {"unary", "binary", "coalesce", "range", "assign"}:
                token = tokens[operation]
                text = data[token[1]:token[2]].decode()
            if kind == "repeat":
                kind = "array"
            if kind == "byte":
                kind = "character"
            if kind == "name":
                text = text.strip('`')
            return (kind, text if kind in textual else "", bool(semicolon),
                    [native_shape(child, nodes, edges, tokens, data) for child in children])

        def reference_shape(node):
            kind = kinds[node["kind"]]
            if kind == "name" and "::" in node["text"]:
                parts = node["text"].split("::")
                shape = ("name", parts[0], False, [])
                for part in parts[1:]:
                    shape = ("field", part, False, [shape])
                return (shape[0], shape[1], node["semicolon"], shape[3])
            return (kind, node["text"] if kind in textual else "", node["semicolon"],
                    [reference_shape(child) for child in node["children"]])

        accepted = {
            "declarations": "fn add(read a: i32, mut b: Other,): i32\n{ a + b }\nfn main() { add(first, second) }\n",
            "precedence": "1 + 2 * 3 << 1 == 14 && !false || true",
            "association": "a - b - c ?? d ?? e",
            "unary-cast": "-value as i32 + *read other",
            "group": "(1 + 2) * (3 - 4)",
            "tuple-index": "(1, 2,).0 + values[2]",
            "calls": "object.method(1, other(2, 3),)[index].field",
            "array": "[1, 2, 3,][0]",
            "repeat": "[42; count]",
            "ranges": "(1..3, ..4, 5.., .., 1..=3)",
            "literals": "(1.25e+3, 'x', b'\\xff', \"a\\n\", r#\"raw\\n\"#, br#\"bytes\"#)",
            "bindings": "let value: i32 = 2\nvar count = value\ncount += 3\nlet _ = other()\ncount",
            "tail-newline": "42 // tail\n",
            "tail-semicolon": "42\n;\n",
            "call-newline": "one()\ntwo()\n42",
            "group-newline": "(1)\n2",
            "comment-separator": "1 /* a\r\n b */ 2",
            "rhs-newline": "1 +\n /* x */ 2",
            "block-in-call": "accept({ 1\n2 },\n 3)",
            "if-else": "if enabled { 1 }\n/*x*/ else if other { 2 } else { 3 }",
            "if-no-else": "if enabled { one() }\n42",
            "loops": "while enabled { if done { break }; continue }\nloop { break 42 }",
            "return-newline": "return\n(42)",
            "return-group": "return (\n42\n)",
            "quoted-name": "`type`(1)",
            "pointer-binding": "var value: ptr<read ptr<mut i32>>=other\nvalue",
            "structural-binding": "let value: (read [u8] from r)? = other\nvalue",
            "structural-cast": "value as ptr<read i32>",
            "comparison-arguments": "call(" + ", ".join(["a < b"] * 256) + ")",
            "generic-call": "factory<i32, Other>(value)",
            "generic-nested-call": "factory<Outer<Inner>>(value)",
            "generic-mixed-comparison": "call(a < b, factory<T>(x))",
            "generic-mixed-nested": "call(a < b, factory<Outer<Inner>>(x))",
            "generic-value": "let convert = parse<i32>\nconvert(value)",
            "generic-semicolon": "factory<T>;\n42",
            "generic-member": "object.convert<T>(value).field",
            "generic-projection-member": "factory<T>.member(value)",
            "generic-drop-member": "factory<T>.drop(value)",
            "contextual-drop-member": "core.mem.drop(value)",
            "generic-compound-types": "factory<[u8; N], ptr<read T>, fn(): U>(value)",
            "generic-constant-comparisons": "factory<{a < b && c > d}>(value)",
            "generic-block-shift": "outer(call<4 + { factory<[i32; 8 >> 1]>(0) }>())",
            "generic-block-boundary-restore": "outer(factory<Buffer<4 + { inner<[i32; 8 >> 1]>(0) } + 2>>())",
            "generic-comment-newline": "let convert = parse<T> /* newline\n */ next()",
            "generic-quirk": "assert(a < b, c > (d))",
            "generic-parenthesized-comparison": "assert((a < b), c > (d))",
            "declaration-generic": "fn identity<T, region r, const N: usize = 4>(read value: T): T { value }",
            "declaration-defaults": "fn defaults<T = i32>(value: T = 42): T { value }",
            "declaration-constraints": "fn convert<T: Trait + ?Sized, U>(value: T): U\nwhere T: Other, U = Result<T> { other(value) }",
            "declaration-public": "pub(package) unsafe const fn identity<T>(value: T): T => value",
            "declaration-effect": "fn load<T>(value: T): T throws Error where T: Trait { value }",
            "declaration-generic-value": "fn main() => factory<T>",
            "declaration-contextual-format": "fn format(format: format, value: format.Message) { format }",
            "declaration-imports": "pub import dep.api as renamed\nimport core.text.{Text, Other as Alias,}\nimport external.api.*\nfn main() { 42 }",
            "declaration-modules": "pub module tools\n{\nimport dep.api\nmodule child\nfn inspect() { 42 }\nmodule nested { fn inner() { 7 } }\n}\nmodule remote\nfn main() { 0 }",
            "declaration-module-comments": "module one /* a\r\n b */ { import dep\nfn inside() { 1 } }\nmodule two /* c\n d */\nfn main() { 2 }",
            "generic-binding": "var value: Outer<Inner<i32>>=other\nvalue",
        }
        for name, body in accepted.items():
            if not selected(name):
                continue
            path = source("parser-" + name, body if name == "declarations" or name.startswith("declaration-") else "fn main() {\n" + body + "\n}\n")
            reference = run([executable, "syntax", str(path)])
            actual = run([native, "syntax", str(path)])
            data = path.read_bytes()
            nodes, edges, tokens = inspect_native(actual, data)
            wanted = json.loads(reference.stdout)
            lexical = json.loads(run([executable, "tokens", str(path)]).stdout)
            assert tokens == [(token["kind"], token["begin"], token["end"]) for token in lexical["tokens"]], name
            functions = [index for index, node in enumerate(nodes) if node[0] == "function"]
            assert len(functions) == len(wanted["functions"])
            for index, reference_function in zip(functions, wanted["functions"]):
                function = nodes[index]
                identifier = next(nodes[child] for child in edges[function[3]:function[4]] if nodes[child][0] == "name")
                assert data[identifier[1]:identifier[2]].decode().strip('`') == reference_function["name"]
                block = edges[function[4] - 1]
                found = native_shape(block, nodes, edges, tokens, data)
                expected = reference_shape(reference_function["body"])
                assert found == expected, f"{name}: shape differs\n{found}\n{expected}"
            evidence["cases"].append({"name": name, "source_sha256": digest(path), "nodes": len(nodes)})

        rejected = {
            "missing-rhs": "fn main() { 1 + }",
            "same-line": "fn main() { 1 2 }",
            "comparison-chain": "fn main() { a < b < c }",
            "range-chain": "fn main() { 1..2..3 }",
            "inclusive-bound": "fn main() { 1..= }",
            "let-mut": "fn main() { let mut x = 1 }",
            "missing-initializer": "fn main() { let x }",
            "continue-value": "fn main() { continue 2 }",
            "unclosed-call": "fn main() { call(1 }",
            "unclosed-block": "fn main() { 42",
            "depth": "fn main() { " + "!" * 300 + "true }",
            "depth-block": "fn main() { " + "{" * 300 + "0" + "}" * 300 + " }",
            "depth-else": "fn main() { " + "if true { 0 } else " * 300 + "{ 1 } }",
            "type-unit": "fn inspect(value: ()) { 0 }",
            "type-pointer-access": "fn inspect(value: ptr<i32>) { 0 }",
            "type-pointer-close": "fn inspect(value: ptr<read i32) { 0 }",
            "type-local-owner": "fn inspect(value: local i32) { 0 }",
            "type-array-count": "fn inspect(value: [u8;]) { 0 }",
            "type-array-close": "fn inspect(value: [u8) { 0 }",
            "type-tuple-element": "fn inspect(value: (u8,,i32)) { 0 }",
            "type-empty-sources": "fn inspect(value: read Text from ()) { 0 }",
            "type-source-tail": "fn inspect(value: read Text from (a,)) { 0 }",
            "depth-type-array": "fn inspect(value: " + "[" * 300 + "u8" + "]" * 300 + ") { 0 }",
            "depth-type-owner": "fn inspect(value: " + "heap " * 300 + "u8) { 0 }",
            "generic-missing-type": "fn inspect(value: List<type Item = >) { 0 }",
            "generic-missing-region": "fn inspect(value: View<region>) { 0 }",
            "generic-missing-close": "fn inspect(value: List<T) { 0 }",
            "outcome-bare": "fn inspect(value: Outcome) { 0 }",
            "outcome-quoted-bare": "fn inspect(value: `Outcome`) { 0 }",
            "outcome-arity": "fn inspect(value: Outcome<T>) { 0 }",
            "outcome-extra": "fn inspect(value: Outcome<T, E, U>) { 0 }",
            "outcome-region": "fn inspect(value: Outcome<T, region r>) { 0 }",
            "outcome-associated": "fn inspect(value: Outcome<Item = T, E>) { 0 }",
            "callable-result": "fn inspect(value: fn()) { 0 }",
            "callable-parameter": "fn inspect(value: fn(,): T) { 0 }",
            "callable-abi": "fn inspect(value: extern C fn(): T) { 0 }",
            "callable-effect-type": "fn inspect(value: fn(): T throws ) { 0 }",
            "stored-effect": "fn inspect(value: T throws E) { 0 }",
            "generic-const-no-type": "fn inspect<const N>() { 0 }",
            "generic-region-default": "fn inspect<region r = T>() { 0 }",
            "generic-default-missing": "fn inspect<T = >() { 0 }",
            "generic-declaration-close": "fn inspect<T(value: T) { 0 }",
            "constraint-missing-bound": "fn inspect<T>() where T: { 0 }",
            "parameter-default-missing": "fn inspect(value: T = ) { 0 }",
            "function-arrow-result": "fn inspect() -> T { 0 }",
            "generic-speculation-rollback": "fn main() { a < (b + c) > (d) }",
            "generic-suppressed-newline": "fn main() { (factory<T>\n + other) }",
            "generic-empty-application": "fn main() { factory<>(value) }",
            "generic-after-call": "fn main() { factory<T>() < U > (value) }",
            "import-path-missing": "import",
            "import-alias-missing": "import dep as",
            "import-empty-group": "import dep.{}",
            "import-group-comma": "import dep.{A B}",
            "import-group-close": "import dep.{A",
            "import-item-separator": "import dep fn main() { 0 }",
            "module-name-missing": "module {}",
            "module-item-separator": "module dep fn main() { 0 }",
            "module-close": "module dep { fn inside() { 0 }",
            "depth-module": "module nested { " * 300 + "}" * 300,
            "projection-member": "fn inspect(value: T.(Trait).) { 0 }",
            "depth-type-generic": "fn inspect(value: " + "Outer<" * 300 + "T" + ">" * 300 + ") { 0 }",
            "depth-type-callable": "fn inspect(value: " + "fn(): " * 300 + "T) { 0 }",
        }
        for name, text in rejected.items():
            if not selected(name):
                continue
            path = source("parser-" + name, text)
            reference = run([executable, "syntax", str(path)], 1)
            actual = run([native, "syntax", str(path)], 1)
            inspect_native(actual, path.read_bytes())
            wanted = re.search(r":(\d+):(\d+): error\[(\w+)\]: ([^\n]*)", reference.stderr)
            found = re.search(r"error\[(\w+)\] (\d+):(\d+) ([^\n]*)", actual.stderr)
            assert wanted and found, (name, reference.stderr, actual.stderr)
            begin = int(found[2])
            data = path.read_bytes()
            line = data[:begin].count(b"\n") + 1
            column = len(data[data.rfind(b"\n", 0, begin) + 1:begin].decode()) + 1
            assert found[1] == wanted[3], (name, found[0], wanted[0])
            if not name.startswith("depth"):
                assert (str(line), str(column)) == wanted.group(1, 2), (name, found[0], wanted[0])
            evidence["cases"].append({"name": name, "phase": found[1], "source_sha256": digest(path)})

        for name, text in {"recovery": "fn main() {\nlet a =\n;\nlet b =\n;\n42\n}\nfn after() { 7 }",
                           "recovery-type": "fn main() {\nlet a: [u8;] = x;\nlet b: ptr<i32> = x;\n42\n}\nfn after() { 7 }",
                           "recovery-generic": "fn main() {\nlet a: List<region> = x;\nlet b: fn(): = x;\n42\n}\nfn after() { 7 }",
                           "recovery-application": "fn main() {\nlet a = factory<type Item = >();\nlet b = (factory<T>\n + other);\n42\n}\nfn after() { 7 }",
                           "recovery-module": "module broken { import dep as; import missing fn inside() { 42 } }\nfn after() { 7 }",
                           "recovery-product": "type Product { one: ; two: }\nfn after() { 42 }"}.items():
            if not selected(name):
                continue
            path = source("parser-" + name, text)
            actual = run([native, "syntax", str(path)], 1)
            nodes, edges, tokens = inspect_native(actual, path.read_bytes())
            assert sum(node[0] == "function" for node in nodes) >= 1, actual.stdout
            assert sum(node[0] == "error" for node in nodes) >= (2 if name.startswith("recovery") else 1), actual.stdout
            if name.startswith("recovery"):
                assert sum(node[0] == "function" for node in nodes) == (1 if name == "recovery-product" else 2)
                assert any(node[0] == "integer" and path.read_bytes()[node[1]:node[2]] == b"42" for node in nodes)
            assert f"error[{'parse' if name.startswith('recovery') else 'feature'}]" in actual.stderr, actual.stderr
            evidence["cases"].append({"name": name, "source_sha256": digest(path)})

        bad_text = (('"\\q"', "invalid text escape"),
                    ('"\\x80"', "text byte escape requires two hexadecimal digits no greater than 7f"),
                    ('"\\u{}"', "invalid Unicode scalar escape"),
                    ('"\\u{d800}"', "invalid Unicode scalar escape"),
                    ('"\\u{110000}"', "invalid Unicode scalar escape"),
                    ('b"\\u{41}"', "invalid text escape"),
                    ('b"\\xgg"', "byte escape requires two hexadecimal digits"),
                    ('b"\u00e9"', "byte text must contain only ASCII characters"),
                    ('br#"\u00e9"#', "byte text must contain only ASCII characters"))
        for i, (literal, message) in enumerate(bad_text):
            if not selected(f"text-{i}"):
                continue
            path = source(f"parser-text-{i}", "fn main() { " + literal + " }\n")
            actual = run([native, "syntax", str(path)], 1)
            found = re.search(r"error\[lex\] (\d+):(\d+) ([^\n]*)", actual.stderr)
            assert found and message == found[3], (message, actual.stderr)
            assert path.read_bytes()[int(found[1]):int(found[2])].decode() == literal
            evidence["cases"].append({"name": f"text-{i}", "source_sha256": digest(path)})

        grammar = {
            "products": ("@derive(Clone) copy type Pair<T> { @pinned pub first: T; second: T; init(value: T) { self.first = value }; drop {} ; mut unsafe fn reset(): Unit {} }", {"product": 1, "field-declaration": 2, "constructor": 1, "destructor": 1, "attribute": 2}),
            "contextual-extend": ("fn extend() {} fn inspect() { let extend = callback; extend(items); extend(take items); extend.extend(items); extend + 1; extend<T>(items) }", {"function": 2, "call": 4}),
            "nested-extension": ("fn inspect() { extend<T> Pair<T> { fn method() {} }; extend (Pair<i32>) { fn other() {} } }", {"extension": 2, "function": 3}),
            "extension-lifecycle": ("type Resource {} extend Resource { init(value: i32) {} drop {} }", {"constructor": 1, "destructor": 1, "extension": 1}),
            "union": ("union Bits<T> { integer: u32, other: T }", {"union": 1, "field-declaration": 2}),
            "enum": ("copy enum Event<T> { Empty, Value(T), Record { value: T }, Code = 4 }", {"enumeration": 1, "variant-declaration": 4, "members": 1}),
            "interface": ("unsafe interface Source<T>: Base { type Item<U>: Bound where U: Copy = List<U>; const COUNT: usize = 2; fn next(): T\nasync(heap) mut fn total(): i32\nfn defaulted(): T { other() } }", {"interface": 1, "associated-type": 1, "constant": 1, "function": 3}),
            "extension": ("unsafe extend<T> Pair<T> implements Source<T> where T: Copy { type Item = T; const COUNT: usize = 2; static unsafe fn empty(): Unit {} }\nextend Pair<i32> not Send", {"extension": 1, "negative-extension": 1, "associated-type": 1}),
            "values": ("alias Names<T> = List<T>\nconst COUNT: usize = 4\nstatic mut TOTAL: i32 = 0", {"alias": 1, "constant": 1, "static": 1}),
            "foreign": ('extern "C" { unsafe fn call(value: i32, ...): i32; static mut COUNT: i32 }\nextern "C" fn exported(value: i32, args: ...): i32 { value }', {"foreign": 2, "function": 2, "type-variadic": 2}),
            "macros": ("macro select { ($value:expr) => { nested!([$value]) }; }\nselect!{ item }\nfn apply() { let callback: api.selector!(r) = take fn(value) { value }; callback(1) }", {"macro-definition": 1, "macro-invocation": 2, "closure": 1}),
            "patterns": ("fn inspect((a, b): (i32, i32)) { let [first, rest @ ..] = values; let Pair { first: value, .. } = pair; let present(found) = optional else { return }; match take found { -3..=0 | 2 => 1, Event.Value(x) if x > 0 => x, _ => 0 } }", {"pattern-tuple": 1, "pattern-array": 1, "pattern-at": 1, "pattern-product": 1, "let-else": 1, "match": 1, "arm": 3, "guard": 1, "pattern-range": 1, "pattern-or": 1}),
            "conditions": ("fn inspect() { if let present(x) = value, x > 0 { x } else { 0 }; while let success(x) = next(), x > 0 { break }; label outer: for (a, b) in pairs { if a { continue label outer }; break label outer b } }", {"conditions": 2, "condition": 2, "for": 1, "label": 3}),
            "closures": ("fn inspect() { (async take fn(read x: T): T throws Error => x, fn((a, b)) { a }, async { await work() }) }", {"closure": 3, "await": 1, "type-effect": 1}),
            "postfix": ("fn inspect() { call(value: 1, other: 2); object?.field; T.(Trait).member; [T; 4].(Trait).member }", {"named-argument": 2, "optional-field": 1, "projection": 1, "type-projection": 1, "type-array": 1}),
            "errors-owners": ("fn inspect() { unsafe { (try call(), capture other(), none, present(1), success(2), failure(3), heap value, shared value, local shared value, weak owner, pinned heap value) }; throw error }", {"unsafe": 1, "try": 1, "capture": 1, "none": 1, "present": 1, "success": 1, "failure": 1, "owner": 5, "throw": 1}),
            "interpolation": ('fn inspect() { f"head {{literal}} {call(1)} middle {f"nested {value}"} tail" }', {"interpolation": 2, "format-hole": 3}),
            "async-callable": ("fn inspect(value: async fn(): i32) {}", {"type-callable": 1, "type-modifier": 1}),
            "callable-bound": ("fn inspect(value: any for<region r> fn(read T from r): Unit) {}", {"type-erased": 1, "type-callable": 1, "type-binders": 1}),
            "nested-items": ("fn inspect() { type Local {} fn inner() {} const VALUE: i32 = 2; inner() }", {"product": 1, "function": 2, "constant": 1}),
            "signature-newline": ("interface Source { fn first(): i32\nfn second():\n i32\n}\nfn inspect():\nmut [i32; 4] from values {}", {"interface": 1, "function": 3}),
            "grouped-projection": ("fn inspect() { (read T from r).(Trait).member; ([T; N]).(Trait).member }", {"type-projection": 2, "type-group": 2, "type-borrow": 1}),
            "header-range": ("fn inspect() { match 1.. { _ => 0 }; for x in 1.. {} }", {"match": 1, "for": 1, "range": 2}),
            "nested-async": ("fn inspect() { async fn inner() { await work() }; async fn(x) => x }", {"function": 2, "closure": 1}),
            "sources-path": ("fn inspect(value: read T from package.region_name) {}", {"type-sources": 1}),
            "contextual-copy": ("fn inspect() { core.ptr.copy(a, b, n) }", {"field": 2}),
        }
        for name, (text, required) in grammar.items():
            if not selected("grammar-" + name):
                continue
            path = source("parser-grammar-" + name, text)
            actual = run([native, "syntax", str(path)])
            data = path.read_bytes()
            nodes, edges, tokens = inspect_native(actual, data)
            lexical = json.loads(run([executable, "tokens", str(path)]).stdout)
            assert tokens == [(token["kind"], token["begin"], token["end"]) for token in lexical["tokens"]], name
            for kind, count in required.items():
                assert sum(node[0] == kind for node in nodes) == count, (name, kind, count, actual.stdout)
            evidence["cases"].append({"name": "grammar-" + name, "source_sha256": digest(path), "nodes": len(nodes)})

        invalid_grammar = {
            "union-method": "union Bad { fn method() {} }",
            "optional-index": "fn bad() { value?.0 }",
            "optional-projection": "fn bad() { T?.(Trait).member }",
            "standalone-rest": "fn bad() { let .. = value }",
            "tuple-rest": "fn bad() { let (a, ..) = value }",
            "pinned-constructor": "fn bad() { pinned value }",
            "callable-varargs": "fn bad(value: fn(i32, ...): Unit) {}",
            "callable-empty-varargs": 'fn bad(value: extern "C" fn(...): Unit) {}',
            "pattern-escape": r'fn bad() { match value { "\q" => 0 } }',
            "foreign-body": 'extern "C" { fn bad(): Unit {} }',
            "foreign-default": 'extern "C" { fn bad(value: i32 = 0): Unit; }',
            "foreign-pattern": 'extern "C" { fn bad((a, b): (i32, i32)): Unit; }',
            "foreign-varargs": 'extern "C" { fn bad(...): Unit; }',
            "native-varargs": "fn bad(value: i32, ...): Unit {}",
            "native-cursor": "fn bad(value: i32, args: ...): Unit {}",
            "foreign-item": 'extern "C" { type Bad {} }',
            "interface-result": "interface Bad { fn method(); }",
            "duplicate-rest": "fn bad() { let [.., ..] = values }",
            "rest-tail": "fn bad() { let Pair { .., value } = pair }",
            "pattern-range": "fn bad() { match value { 1..other => 0 } }",
            "condition-tail": "fn bad() { if true, {} }",
            "arm-arrow": "fn bad() { match value { _ 0 } }",
            "named-order": "fn bad() { call(value: 1, 2) }",
            "token-tree": "macro bad { ([)] }",
            "macro-close": "fn bad() { call!([) }",
            "constructor-body": "type Bad { init() => 1 }",
            "constructor-file": "init() {}",
            "destructor-file": "drop {}",
            "interpolation-escape": r'fn bad() { f"bad \q {value}" }',
            "depth-pattern": "fn bad() { let " + "[" * 300 + "x" + "]" * 300 + " = values }",
            "depth-macro": "macro bad { " + "(" * 300 + ")" * 300 + " }",
        }
        for name, text in invalid_grammar.items():
            if not selected("grammar-invalid-" + name):
                continue
            path = source("parser-grammar-invalid-" + name, text)
            actual = run([native, "syntax", str(path)], 1)
            inspect_native(actual, path.read_bytes())
            phase = "limit" if name.startswith("depth-") else "lex" if name in {"interpolation-escape", "pattern-escape"} else "parse"
            assert "error[" + phase + "]" in actual.stderr, (name, actual.stderr)
            evidence["cases"].append({"name": "grammar-invalid-" + name, "source_sha256": digest(path), "phase": phase})

        if selected("import-dotted-group"):
            path = source("parser-import-dotted-group", "import dep.{nested.Name}")
            actual = run([native, "syntax", str(path)], 1)
            assert "error[parse]" in actual.stderr, actual.stderr
            evidence["cases"].append({"name": "import-dotted-group", "source_sha256": digest(path)})

        for name, text, expected in (("empty-module", "", 0),
                                      ("parser-budget", "fn main() {\n" + "let x =;\n" * 140 + "}\n", 1),
                                      ("speculation-budget", "fn main() {\n" + "let x = f<(a + b)>(c);\n" * 140 + "}\n", 1)):
            if not selected(name):
                continue
            path = source("parser-" + name, text)
            reference = run([executable, "syntax", str(path)], expected)
            actual = run([native, "syntax", str(path)], expected)
            inspect_native(actual, path.read_bytes())
            if expected:
                assert actual.stderr.count("error[parse]") == reference.stderr.count("error[parse]") == 140
            evidence["cases"].append({"name": name, "source_sha256": digest(path)})

        def type_shape(index, nodes, edges, tokens, data):
            kind, begin, end, first, last, operation, _ = nodes[index]
            children = edges[first:last]
            if kind == "default-value":
                assert len(children) == 1 and not nodes[children[0]][0].startswith("type"), (kind, children)
                expression = nodes[children[0]]
                return "default-value(expr[" + data[expression[1]:expression[2]].decode() + "])"
            if kind == "name":
                return data[begin:end].decode().strip('`')
            if kind == "type":
                if all(nodes[child][0] == "name" for child in children):
                    return ".".join(type_shape(child, nodes, edges, tokens, data) for child in children)
                assert len(children) == 1, (kind, children)
                return type_shape(children[0], nodes, edges, tokens, data)
            structural = {"generic-apply", "generic-parameters", "generic-parameter", "bounds", "constraints", "constraint", "default-type", "default-value", "visibility", "modifier", "parameters", "parameter", "module", "module-declaration", "module-body", "import", "import-path", "import-alias", "import-group", "import-name", "import-glob", "function", "block"}
            if not kind.startswith("type-") and kind not in structural:
                return "expr[" + data[begin:end].decode() + "]"
            label = kind.removeprefix("type-")
            if kind in {"type-owner", "type-pointer", "type-borrow", "type-modifier", "type-parameter", "generic-parameter", "constraint", "modifier", "parameter"} and operation != -1:
                token = tokens[operation]
                qualifier = data[token[1]:token[2]].decode()
                if kind == "type-owner" and qualifier == "local":
                    qualifier = " ".join(data[begin:end].decode().split()[:2])
                label += "[" + qualifier + "]"
            return label + "(" + ",".join(type_shape(child, nodes, edges, tokens, data) for child in children) + ")"

        structural_types = {
            "qualified": ("core.text.Text", "core.text.Text"),
            "inferred": ("_", "_"),
            "slice": ("[u8]", "slice(u8)"),
            "array": ("[i32; 2 + 3]", "array(i32,expr[2 + 3])"),
            "nested-array": ("[[u8; 4]; 2]", "array(array(u8,expr[4]),expr[2])"),
            "group": ("(i32)", "group(i32)"),
            "tuple": ("(i32, [u8],)", "tuple(i32,slice(u8))"),
            "single-tuple": ("(i32,)", "tuple(i32)"),
            "borrow": ("read [u8] from r", "sources(borrow[read](slice(u8)),r)"),
            "mutable": ("mut i32 from static", "sources(borrow[mut](i32),static)"),
            "sources": ("read Text from (a, static, b)", "sources(borrow[read](Text),a,static,b)"),
            "borrow-optional": ("read i32? from r", "sources(borrow[read](optional(i32)),r)"),
            "optional-borrow": ("(read i32 from r)?", "optional(group(sources(borrow[read](i32),r)))"),
            "double-optional": ("i32??", "optional(optional(i32))"),
            "heap": ("heap [u8]", "owner[heap](slice(u8))"),
            "shared": ("shared Item", "owner[shared](Item)"),
            "weak": ("weak Item", "owner[weak](Item)"),
            "local-shared": ("local shared Item", "owner[local shared](Item)"),
            "local-weak": ("local weak Item", "owner[local weak](Item)"),
            "pinned": ("pinned heap Item", "pinned(owner[heap](Item))"),
            "pinned-view": ("pinned read Item from r", "pinned(sources(borrow[read](Item),r))"),
            "pointer": ("ptr<read i32>", "pointer[read](i32)"),
            "nested-pointer": ("ptr<read ptr<mut i32>>", "pointer[read](pointer[mut](i32))"),
            "pointer-optional": ("ptr<mut i32>?", "optional(pointer[mut](i32))"),
            "multiline": ("[\n(read Text from (\na, b\n), u8)\n]", "slice(tuple(sources(borrow[read](Text),a,b),u8))"),
            "generic": ("List<u8>", "apply(List,arguments(argument(u8)))"),
            "generic-nested": ("Outer<Inner<i32>>", "apply(Outer,arguments(argument(apply(Inner,arguments(argument(i32))))))"),
            "generic-region": ("View<region r, region static, T,>", "apply(View,arguments(region-argument(r),region-argument(static),argument(T)))"),
            "generic-const": ("Buffer<4, true, b'x'>", "apply(Buffer,arguments(const-argument(expr[4]),const-argument(expr[true]),const-argument(expr[b'x'])))"),
            "generic-const-name": ("Buffer<N + 1>", "apply(Buffer,arguments(const-argument(expr[N + 1])))"),
            "generic-const-nested": ("Outer<Buffer<4>>", "apply(Outer,arguments(argument(apply(Buffer,arguments(const-argument(expr[4]))))))"),
            "generic-const-shift": ("Buffer<{N >> 1}>", "apply(Buffer,arguments(const-argument(expr[N >> 1])))"),
            "generic-explicit-const": ("Buffer<const {N + 1}>", "apply(Buffer,arguments(const-argument(expr[N + 1])))"),
            "generic-associated": ("Future<Output = i32>", "apply(Future,arguments(argument(Output,i32)))"),
            "generic-explicit-associated": ("Future<type Output = i32>", "apply(Future,arguments(argument(Output,i32)))"),
            "generic-associated-const": ("Buffer<const N = 2 + 3>", "apply(Buffer,arguments(const-argument(N,expr[2 + 3])))"),
            "outcome": ("Outcome<T, Error>", "outcome(Outcome,arguments(argument(T),argument(Error)))"),
            "outcome-quoted": ("`Outcome`<T, Error>", "outcome(Outcome,arguments(argument(T),argument(Error)))"),
            "erased": ("any Trait + Other<T>", "erased(Trait,apply(Other,arguments(argument(T))))"),
            "opaque": ("some Trait<Item = T>", "opaque(apply(Trait,arguments(argument(Item,T))))"),
            "ranked-bound": ("any for<region r> Trait<region r>", "erased(for(binders(r),apply(Trait,arguments(region-argument(r)))))"),
            "projection": ("T.(Trait).Item", "projection(T,Trait,Item)"),
            "slice-projection": ("[u8].(Trait).Item", "projection(slice(u8),Trait,Item)"),
            "generic-projection": ("Container<T>.(Trait<U>).Item<V>", "projection(apply(Container,arguments(argument(T))),apply(Trait,arguments(argument(U))),Item,arguments(argument(V)))"),
            "chained-projection": ("T.(Trait).Item.(Other).Value?", "optional(projection(projection(T,Trait,Item),Other,Value))"),
            "callable": ("fn(): Unit", "callable(parameters(),Unit)"),
            "callable-modes": ("mut fn(read i32, take T,): bool", "callable(modifier[mut](),parameters(parameter[read](i32),parameter[take](T)),bool)"),
            "callable-consuming": ("take fn(T): U", "callable(modifier[take](),parameters(parameter(T)),U)"),
            "callable-foreign": ('unsafe extern "C" fn(ptr<read u8>, ...): i32', 'callable(modifier[unsafe](),modifier[extern](expr["C"]),parameters(parameter(pointer[read](u8)),variadic()),i32)'),
            "callable-effect": ("fn(T): U throws Error", "callable(parameters(parameter(T)),U,effect(Error))"),
            "callable-ranked": ("for<region r> fn(read Text from r): read Text from r", "callable(binders(r),parameters(parameter[read](sources(Text,r))),sources(borrow[read](Text),r))"),
            "callable-nested-effect": ("fn(): fn(): T throws Error", "callable(parameters(),callable(parameters(),T,effect(Error)))"),
            "callable-grouped-effect": ("fn(): (fn(): T) throws Error", "callable(parameters(),group(callable(parameters(),T)),effect(Error))"),
        }
        for name, (text, expected) in structural_types.items():
            if not selected("type-" + name):
                continue
            path = source("parser-type-" + name, f"fn inspect(value: {text}): {text} {{ 0 }}\n")
            if name != "generic-explicit-const":
                run([executable, "syntax", str(path)])
            reference = run([executable, "tokens", str(path)])
            actual = run([native, "syntax", str(path)])
            data = path.read_bytes()
            nodes, edges, tokens = inspect_native(actual, data)
            assert tokens == [(token["kind"], token["begin"], token["end"]) for token in json.loads(reference.stdout)["tokens"]], name
            function = nodes[-2]
            assert function[0] == "function", function
            children = edges[function[3]:function[4]]
            parameter = edges[nodes[children[1]][3]]
            annotation = edges[nodes[parameter][4] - 1]
            for index in (annotation, children[2]):
                found = type_shape(index, nodes, edges, tokens, data)
                assert found == expected, (name, found, expected)
            if name == "double-optional":
                assert [data[node[1]:node[2]].decode() for node in nodes if node[0] == "type-optional"] == ["i32?", "i32??"] * 2
            evidence["cases"].append({"name": "type-" + name, "source_sha256": digest(path)})

        signatures = {
            "full": (
                "pub(package) unsafe const fn select<region r: static, T: Trait + ?Sized = Other, const N: usize = 4>(read value: T = input): T throws Error\nwhere T: Other + ?Sized, region r: static, T = Result<T> => value",
                ["visibility(package)", "modifier[unsafe]()", "modifier[const]()", "select",
                 "generic-parameters(generic-parameter[region](r,bounds(static)),generic-parameter(T,bounds(Trait,modifier[?](Sized)),default-type(Other)),generic-parameter[const](N,usize,default-value(expr[4])))",
                 "parameters(parameter[read](value,T,default-value(expr[input])))", "T", "effect(Error)",
                 "constraints(constraint[:](T,bounds(Other,modifier[?](Sized))),constraint[:](modifier[region](r),bounds(static)),constraint[=](T,apply(Result,arguments(argument(T)))))"]),
            "callable-bound": (
                "fn invoke<F: for<region r> fn(read Text from r): Unit>(take operation: F): Unit { operation(value) }",
                ["invoke", "generic-parameters(generic-parameter(F,bounds(callable(binders(r),parameters(parameter[read](sources(Text,r))),Unit))))", "parameters(parameter[take](operation,F))", "Unit"]),
            "outer-effect": (
                "fn make(): (fn(): T) throws Error => factory<T>",
                ["make", "parameters()", "group(callable(parameters(),T))", "effect(Error)"]),
            "inner-effect": (
                "fn make(): fn(): T throws Error => factory<T>",
                ["make", "parameters()", "callable(parameters(),T,effect(Error))"]),
            "format-parameters": (
                "fn inspect(value: format core.fmt.Message, other: format Message) { 0 }",
                ["inspect", "parameters(parameter(value,modifier[format](),core.fmt.Message),parameter(other,modifier[format](),Message))"]),
        }
        for name, (text, expected) in signatures.items():
            if not selected("signature-" + name):
                continue
            path = source("parser-signature-" + name, text)
            run([executable, "syntax", str(path)])
            actual = run([native, "syntax", str(path)])
            data = path.read_bytes()
            nodes, edges, tokens = inspect_native(actual, data)
            function = nodes[-2]
            children = edges[function[3]:function[4] - 1]
            found = [type_shape(child, nodes, edges, tokens, data) for child in children]
            assert found == expected, (name, found, expected)
            evidence["cases"].append({"name": "signature-" + name, "source_sha256": digest(path)})

        if selected("application-structure"):
            path = source("parser-generic-application-structure", "fn main() { factory<[u8], region r, const N = 4>(value) }")
            run([executable, "syntax", str(path)])
            actual = run([native, "syntax", str(path)])
            data = path.read_bytes()
            nodes, edges, tokens = inspect_native(actual, data)
            applications = [index for index, node in enumerate(nodes) if node[0] == "generic-apply"]
            assert len(applications) == 1, applications
            found = type_shape(applications[0], nodes, edges, tokens, data)
            assert found == "generic-apply(factory,arguments(argument(slice(u8)),region-argument(r),const-argument(N,expr[4])))", found
            evidence["cases"].append({"name": "application-structure", "source_sha256": digest(path)})

        module_cases = {
            "imports": (
                "pub(package) import dep.api as selected;\nimport dep.{A, B as C,}\nimport dep.*",
                "module(import(visibility(package),import-path(dep,api),import-alias(selected)),import(import-path(dep),import-group(import-name(A),import-name(B,import-alias(C)))),import(import-path(dep),import-glob()))",
                ["pub(package) import dep.api as selected"]),
            "inline": (
                "pub module api {\nimport dep\nmodule child;\nfn entry() { 42 }\n}",
                "module(module-declaration(visibility(),api,module-body(import(import-path(dep)),module-declaration(child),function(entry,parameters(),block(expr[42])))))",
                ["module child"]),
            "external-and-nested": (
                "module one\n{\nmodule two {}\n}\nmodule three\nfn after() { 0 }",
                "module(module-declaration(one,module-body(module-declaration(two,module-body()))),module-declaration(three),function(after,parameters(),block(expr[0])))",
                []),
            "quoted": (
                "import `type`.`module`.{`fn` as escaped,}\nmodule `type`;",
                "module(import(import-path(type,module),import-group(import-name(fn,import-alias(escaped)))),module-declaration(type))",
                ["module `type`"]),
            "comment-lookahead": (
                "module outer /* c\n */ { import dep }\nmodule remote /* c\n */\nfn after() { 0 }",
                "module(module-declaration(outer,module-body(import(import-path(dep)))),module-declaration(remote),function(after,parameters(),block(expr[0])))",
                []),
        }
        for name, (text, expected, terminated) in module_cases.items():
            if not selected("module-" + name):
                continue
            path = source("parser-module-" + name, text)
            run([executable, "syntax", str(path)])
            reference = run([executable, "tokens", str(path)])
            actual = run([native, "syntax", str(path)])
            data = path.read_bytes()
            nodes, edges, tokens = inspect_native(actual, data)
            assert tokens == [(token["kind"], token["begin"], token["end"]) for token in json.loads(reference.stdout)["tokens"]], name
            found = type_shape(len(nodes) - 1, nodes, edges, tokens, data)
            assert found == expected, (name, found, expected)
            marked = [data[node[1]:node[2]].decode() for node in nodes if node[0] in {"import", "module-declaration"} and node[6]]
            assert sorted(marked) == sorted(terminated), (name, marked, terminated)
            if name == "comment-lookahead":
                assert any(node[0] == "module-declaration" and data[node[1]:node[2]] == b"module remote" for node in nodes)
            evidence["cases"].append({"name": "module-" + name, "source_sha256": digest(path)})
        if not evidence["cases"]:
            raise ValueError("no parser cases match --filter")

    def inspect_fast_math():
        name = "machine-numeric-explicit-function-and-module-relaxations"
        path = ROOT / "source" / "run" / (name + ".mt")
        profile = "debug"
        output = directory / (name + ".ll")
        run([executable, "build", str(path), "--emit", "llvm",
             "--profile", profile, "-o", str(output)])
        bodies = {}
        for body in re.findall(r"^define [^\n]*\n.*?^}", output.read_text(), re.M | re.S):
            symbol = re.search(r'@(?:"([^"]+)"|([^ (]+))\(', body)
            bodies[symbol[1] or symbol[2]] = body
        flags = {"reassoc", "nnan", "ninf", "nsz", "arcp", "contract", "afn", "fast"}
        for owner, operations, selected in (
                ("multiply_add", {"fmul", "fadd"}, {"contract"}),
                ("<closure-", {"fmul", "fadd"}, {"contract"}),
                ("defaulted.<default.", {"fmul", "fadd"}, {"contract"}),
                ("relaxed.calculate", {"fadd"}, {"reassoc", "arcp", "afn"}),
                ("separate", {"fmul", "fadd"}, set()),
                ("checked", {"fcmp"}, set())):
            matches = [body for symbol, body in bodies.items()
                       if symbol == "mettle." + owner + ".body" or
                       (owner.endswith(("-", ".")) and symbol.startswith("mettle." + owner)
                        and symbol.endswith(".body"))]
            if len(matches) != 1:
                raise AssertionError(f"{owner}: expected one lowered arithmetic body")
            body = matches[0]
            found = set()
            for operation, operands in re.findall(r"\b(fmul|fadd|fcmp)\s+([^\n]+)", body):
                if operation in operations:
                    found.add(operation)
                    actual = set(operands.split()) & flags
                    if actual != selected:
                        raise AssertionError(f"{owner}: expected floating flags {selected}, got {actual}")
            if found != operations:
                raise AssertionError(f"{owner}: missing floating operations {operations - found}")
        evidence["cases"].append({"file": str(path), "source_sha256": digest(path),
                                  "profile": profile, "llvm_sha256": digest(output)})
        path = ROOT / "source" / "run" / "i13-numeric-float-to-int-unchecked.mt"
        output = directory / (path.stem + ".ll")
        run([executable, "build", str(path), "--emit", "llvm",
             "--profile", profile, "-o", str(output)])
        bodies = {}
        for body in re.findall(r"^define [^\n]*\n.*?^}", output.read_text(), re.M | re.S):
            symbol = re.search(r'@(?:"([^"]+)"|([^ (]+))\(', body)
            bodies[symbol[1] or symbol[2]] = body
        expected = {(operation, width) for operation in ("fptosi", "fptoui")
                    for width in (8, 16, 32, 64, 128)}
        for owner, floating in (("every_f32_target", "float"),
                                ("every_f64_target", "double")):
            body = bodies["mettle." + owner + ".body"]
            found = {(operation, int(width)) for operation, width in
                     re.findall(rf"\b(fptosi|fptoui)\s+{floating}\b[^\n]*\bto i(\d+)\b", body)}
            if found != expected or "fptosi.sat" in body or "fptoui.sat" in body:
                raise AssertionError(f"{owner}: missing unchecked conversion or saturating lowering")
        evidence["cases"].append({"file": str(path), "source_sha256": digest(path),
                                  "profile": profile, "llvm_sha256": digest(output)})
    def broken_pipe():
        programs = (
            ("print-to-closed-pipe", "import std.io;", 'io.print(f"line {i}\\n")'),
            ("println-to-closed-pipe", "import std.macros.println;", 'println(f"line {i}")'),
        )
        for name, imports, output in programs:
            program = source(name, f"{imports}\nfn main(): i32 {{\n"
                             "    var i = 0\n"
                             f"    while i < 1000000 {{ {output}; i += 1 }}\n"
                             "    0\n}\n")
            binary = directory / name
            run([executable, "build", str(program), "-o", str(binary)])
            for ignored, expected in ((False, -signal.SIGPIPE), (True, 141)):
                def disposition(ignored=ignored):
                    signal.signal(signal.SIGPIPE, signal.SIG_IGN if ignored else signal.SIG_DFL)
                child = subprocess.Popen([str(binary)], stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, preexec_fn=disposition)
                child.stdout.read(16)
                child.stdout.close()
                stderr = child.stderr.read()
                status = child.wait()
                evidence["cases"].append({"file": str(program), "sigpipe_ignored": ignored,
                                          "exit_status": status, "stderr": stderr.decode(errors="replace")})
                if status != expected or stderr:
                    raise AssertionError(f"{name}, closed stdout (SIGPIPE ignored={ignored}): expected "
                                         f"{expected} and no output, got {status}: {stderr!r}")

    def sanitizer_probes():
        address = source(
            "asan-heap-overflow",
            "import alloc.boxed\n"
            "fn main(): i32 {\n"
            "    let raw = alloc.boxed.new([42i32; 1]).into_raw()\n"
            "    let value = unsafe { *raw.0.cast<i32>().add(1usize) }\n"
            "    value\n"
            "}\n")
        address_binary = directory / "asan-heap-overflow"
        run([executable, "build", str(address), "-o", str(address_binary),
             "--sanitize", "address"])
        address_env = {**os.environ,
                       "ASAN_OPTIONS": "halt_on_error=1:abort_on_error=0:exitcode=99"}
        report = run([str(address_binary)], expected=99, env=address_env)
        if "AddressSanitizer: heap-buffer-overflow" not in report.stderr:
            raise AssertionError("ASan did not report the emitted heap overflow")
        evidence["cases"].append({
            "file": str(address), "source_sha256": digest(address),
            "sanitizer": "address", "exit_status": report.returncode})

        # Zero-sized values (here the Global allocator) emit no checked access.
        zero_sized = source(
            "asan-zero-sized",
            "import alloc.vec_deque\n"
            "fn main(): i32 {\n"
            "    let queue = vec_deque.new<i32>()\n"
            "    queue.len() as i32\n"
            "}\n")
        zero_sized_binary = directory / "asan-zero-sized"
        run([executable, "build", str(zero_sized), "-o", str(zero_sized_binary),
             "--sanitize", "address"])
        report = run([str(zero_sized_binary)], env=address_env)
        if report.stderr:
            raise AssertionError(f"ASan zero-sized access: {report.stderr!r}")
        evidence["cases"].append({
            "file": str(zero_sized), "source_sha256": digest(zero_sized),
            "sanitizer": "address", "exit_status": report.returncode})

        race = source(
            "tsan-data-race",
            "import std.thread\n"
            "static READY: core.sync.atomic.AtomicUsize = "
            "core.sync.atomic.AtomicUsize.new(0usize)\n"
            "static mut VALUE: i32 = 0\n"
            "fn worker(): i32 {\n"
            "    READY.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)\n"
            "    while READY.load(core.sync.atomic.Ordering.SeqCst) < 2usize "
            "{ thread.yield_now() }\n"
            "    unsafe { VALUE = 1 }\n"
            "    0\n"
            "}\n"
            "fn main(): i32 {\n"
            "    let first = thread.spawn(take worker)\n"
            "    let second = thread.spawn(take worker)\n"
            "    let a = capture first.join()\n"
            "    let b = capture second.join()\n"
            "    match take a { success(_) => {}, failure(_) => { return 1 } }\n"
            "    match take b { success(_) => {}, failure(_) => { return 2 } }\n"
            "    0\n"
            "}\n")
        race_binary = directory / "tsan-data-race"
        run([executable, "build", str(race), "-o", str(race_binary),
             "--sanitize", "thread"])
        race_env = {**os.environ,
                    "TSAN_OPTIONS": "halt_on_error=1:abort_on_error=0:exitcode=99"}
        report = run([str(race_binary)], expected=99, env=race_env)
        if "ThreadSanitizer: data race" not in report.stderr:
            raise AssertionError("TSan did not report the emitted data race")
        evidence["cases"].append({
            "file": str(race), "source_sha256": digest(race),
            "sanitizer": "thread", "exit_status": report.returncode})

        incompatible = run(
            [executable, "build", str(race), "-o", str(directory / "bad"),
             "--sanitize", "address,thread"], expected=1)
        if "error[feature]" not in incompatible.stderr:
            raise AssertionError("address+thread was not rejected diagnostically")
        unsupported = run(
            [executable, "build", str(race), "-o", str(directory / "bad"),
             "--sanitize", "undefined"], expected=1)
        if "error[feature]" not in unsupported.stderr or \
                "Mettle already checks integer overflow" not in unsupported.stderr:
            raise AssertionError("undefined sanitization was not explained")

    try:
        if mode == "selfhost-lexer":
            selfhost_lexer()
        elif mode == "selfhost-unicode":
            selfhost_unicode()
        elif mode == "selfhost-parser":
            selfhost_parser()
        elif mode == "fast-math":
            inspect_fast_math()
        elif mode == "broken-pipe":
            broken_pipe()
        elif mode == "sanitizers":
            sanitizer_probes()
        elif mode == "syntax":
            for name in ("syntax-composition-values", "syntax-composition-conditions",
                         "syntax-composition-cleanup"):
                formatted = source(name, (ROOT / "source" / "run" / (name + ".mt")).read_text())
                run([executable, "fmt", str(formatted)])
                run([executable, "fmt", str(formatted), "--check"])
                run([executable, "check", str(formatted)])
            text = ("fn get(read input: i32): i32 { input }\n"
                    "fn main(): i32 {\n"
                    "    let value = 9\n"
                    "    if let present(value) = present(value),\n"
                    "       value > 0 { value } else { value }\n"
                    "    value\n"
                    "}\n")
            document = source("condition-binding-navigation", text)
            uri = document.resolve().as_uri()
            lines = text.splitlines()
            requests = [
                {"id": 1, "method": "initialize", "params": {}},
                {"method": "initialized", "params": {}},
                {"method": "textDocument/didOpen", "params": {"textDocument": {
                    "uri": uri, "languageId": "mettle", "version": 1, "text": text}}},
            ]
            positions = [(0, lines[0].rindex("input")),
                         (3, lines[3].rindex("value")),
                         (4, lines[4].index("value")),
                         (4, lines[4].index("value", lines[4].index("{"))),
                         (4, lines[4].rindex("value")),
                         (5, lines[5].index("value"))]
            for identity, (line, character) in enumerate(positions, 2):
                requests.append({"id": identity, "method": "textDocument/definition",
                                 "params": {"textDocument": {"uri": uri},
                                            "position": {"line": line, "character": character}}})
            requests.extend([
                {"id": 8, "method": "textDocument/hover", "params": {
                    "textDocument": {"uri": uri},
                    "position": {"line": 0, "character": lines[0].index("input")}}},
                {"id": 9, "method": "shutdown"},
                {"method": "exit"},
            ])
            wire = ""
            for request in requests:
                body = json.dumps({"jsonrpc": "2.0", **request})
                wire += f"Content-Length: {len(body.encode())}\r\n\r\n{body}"
            response = run([executable, "lsp"], input_text=wire).stdout
            messages = [json.loads(response[match.end():match.end() + int(match[1])])
                        for match in re.finditer(r"Content-Length: (\d+)\r?\n\r?\n", response)]
            replies = {message["id"]: message for message in messages if "id" in message}
            for identity, expected in enumerate(
                    [(0, lines[0].index("input")), (2, lines[2].index("value")),
                     (3, lines[3].index("value")), (3, lines[3].index("value")),
                     (2, lines[2].index("value")), (2, lines[2].index("value"))], 2):
                definitions = replies[identity]["result"]
                if len(definitions) != 1 or definitions[0]["range"]["start"] != {
                        "line": expected[0], "character": expected[1]}:
                    raise AssertionError(f"Conditional binding resolved outside its scope: {identity}: {definitions}")
            if "read input: i32" not in replies[8]["result"]["contents"]["value"]:
                raise AssertionError("Parameter hover lost its prefix access mode")
            pure = source("no-cleanup-trampoline",
                          "fn add(a:i32,b:i32):i32 {a+b}\nfn main(){add(20,22)-42}\n")
            pure_ir = directory / "no-cleanup-trampoline.ll"
            run([executable, "build", str(pure), "--emit", "llvm", "-o", str(pure_ir)])
            if "@mettle_rt_run(" in pure_ir.read_text():
                raise AssertionError("A function without cleanup still uses the unwind trampoline")
            prefix_path = source("try-prefix-precedence",
                                 "fn f():i32 throws i32 {1}\n"
                                 "fn g():i32 throws i32 { try f() + 1 }\nfn main(){0}\n")
            prefix = json.loads(run([executable, "syntax", str(prefix_path)]).stdout)
            body = next(item for item in prefix["functions"] if item["name"] == "g")["body"]
            if body["children"][0]["text"] != "+":
                raise AssertionError("try consumed a lower-precedence binary expression")
            recovery = source("recovery-state",
                              "fn f():i32 {\n" + "let x = -------------------;\n" * 14 +
                              "let valid=1\nreturn valid\n}\nfn main(){0}\n")
            recovered = run([executable, "syntax", str(recovery)], 1)
            if "nesting limit" in recovered.stderr or recovered.stderr.count("error[") != 14:
                raise AssertionError("Parser recovery leaked nesting state")
            cascade = source("no-inference-cascade", "fn f(){1+true}\nfn main(){0}\n")
            result = run([executable, "check", str(cascade)], 1)
            if result.stderr.count("error[") != 1 or "cannot infer recursive" in result.stderr:
                raise AssertionError("An independent type error poisoned later result inference")
            pattern_cascade = source(
                "no-generic-pattern-cascade",
                "enum Slot<K, V> { Empty, Full(K, V) }\n"
                "type M<K, V> { s: Slot<K, V> }\n"
                "extend<K, V> M<K, V> {\n"
                "    fn a(): (read V from self)? {\n"
                "        let s = self.s.missing(1)\n"
                "        match s { Slot.Full(_, v) => present(read v), _ => none }\n"
                "    }\n"
                "}\nfn main(){0}\n")
            result = run([executable, "check", str(pattern_cascade)], 1)
            if result.stderr.count("error[") != 1:
                raise AssertionError("A failed scrutinee cascaded into its generic pattern")
            every = source("every-diagnostic-reported",
                           "".join(f"fn f{i}() {{ 1+true }}\n" for i in range(140)) +
                           "fn main(){0}\n")
            result = run([executable, "check", str(every)], 1)
            if result.stderr.count("error[") != 140:
                raise AssertionError("Diagnostics were discarded")
            visibility = source("one-visibility-diagnostic",
                                "pub(nowhere) fn f(){}\nfn main(){0}\n")
            result = run([executable, "check", str(visibility)], 1)
            if result.stderr.count("restricted visibility must name an enclosing module") != 1:
                raise AssertionError("One visibility restriction was diagnosed repeatedly")
            independent = source(
                "independent-exhaustiveness-budgets",
                "".join(f"fn f{i}(x:i32):i32 {{ match x {{\n" +
                        "".join(f"{j} => {j},\n" for j in range(128)) +
                        "_ => 0\n} }\n" for i in range(200)) + "fn main(){0}\n")
            run([executable, "check", str(independent)])
            unsupported = source("unsupported-target", "fn main(){0}\n")
            for target in ("wasm32-unknown-unknown", "armv7-unknown-linux-gnueabihf"):
                for emission in ("ir", "llvm"):
                    destination = directory / "unsupported.out"
                    destination.write_bytes(b"preserve unsupported output")
                    result = run([executable, "build", str(unsupported), "--target",
                                  target, "--emit", emission, "-o", str(destination)], 1)
                    if "error[feature]" not in result.stderr or destination.read_bytes() != b"preserve unsupported output":
                        raise AssertionError("Unsupported target escaped source admission")
            lexical = ('extern "C" { unsafe fn `type`():Unit; }\n'
                       'fn main() { unsafe { asm!("/* quoted \\"text\\" */") }; 0 }\n')
            lexical_path = source("text-and-quoted-identifiers", lexical)
            for command in ("tokens", "syntax"):
                result = run([executable, command, str(lexical_path)])
                tokens = json.loads(result.stdout)["tokens"]
                if "".join(token["text"] for token in tokens) != lexical:
                    raise AssertionError("Text/backtick tokens lost source bytes")
                for token in tokens:
                    if lexical.encode()[token["begin"]:token["end"]].decode() != token["text"]:
                        raise AssertionError("Text/backtick token has wrong byte span")
                quoted = next(token for token in tokens if token["text"] == "`type`")
                word = next(token for token in tokens if token["text"] == "extern")
                literal = next(token for token in tokens if token["text"] == '"C"')
                if len({quoted["kind"], word["kind"], literal["kind"]}) != 3:
                    raise AssertionError("Quoted identifiers/text were classified as ordinary words")
            literals = ('fn main() { let a = \'x\'; let b = \'\\u{41}\'; let c = b\'a\'; let d = b\'\\x41\';\n'
                        'let e = 1.5e+3; let f = 2f32; let g = 3.25; let h = 42; let i = 0x2a; let `type` = 1;\n'
                        'unsafe { asm!("a\\"b\\\\n\\x41", "") }; 0 }\n')
            literal_path = source("literal-token-kinds", literals)
            for command in ("tokens", "syntax"):
                tokens = json.loads(run([executable, command, str(literal_path)]).stdout)["tokens"]
                if "".join(token["text"] for token in tokens) != literals:
                    raise AssertionError("Literal tokens lost source bytes")
                kinds = {}
                for category, spellings in (
                        ("word", ("fn", "main", "let")), ("symbol", ("{", "=", ";")),
                        ("character", ("'x'", "'\\u{41}'")), ("byte", ("b'a'", "b'\\x41'")),
                        ("floating", ("1.5e+3", "2f32", "3.25")), ("integer", ("42", "0x2a")),
                        ("quoted", ("`type`",)), ("text", ('"a\\"b\\\\n\\x41"', '""'))):
                    found = {token["kind"] for token in tokens if token["text"] in spellings}
                    if len(found) != 1:
                        raise AssertionError(f"{category} tokens have inconsistent kinds {found}")
                    kinds[category] = found.pop()
                if len(set(kinds.values())) != len(kinds):
                    raise AssertionError(f"Distinct literal categories share a token kind: {kinds}")
            text = "// UTF-8 comment: cafÃ©\r\nfn main()\r\n{\r\n /* a\r\n /* b */ c */\r\n(0)\r\n}\r\n"
            path = source("lossless", text)
            for command in ("tokens", "syntax"):
                result = run([executable, command, str(path)])
                tree = json.loads(result.stdout)
                if "".join(token["text"] for token in tree["tokens"]) != text:
                    raise AssertionError("Tokens did not preserve source bytes/trivia")
                for token in tree["tokens"]:
                    if text.encode()[token["begin"]:token["end"]].decode() != token["text"]:
                        raise AssertionError("Token span does not select its original bytes")
            run([executable, "check", str(path)])
            for emit, marker in (("ir", "fn main: i32"), ("llvm", "define i32 @main")):
                output = directory / emit
                run([executable, "build", str(path), "--emit", emit, "-o", str(output)])
                if marker not in output.read_text():
                    raise AssertionError(f"Missing {emit} representation")
            bad = source("recovery", "fn main() {\nlet x =\n;\nlet y =\n;\n0\n}\n")
            result = run([executable, "check", str(bad)], 1)
            if result.stderr.count("error[parse]") < 2:
                raise AssertionError("Parser did not recover to report separate malformed statements")
            bad.write_bytes(b"// invalid UTF-8: \xff\nfn main() { 0 }\n")
            if "error[lex]" not in run([executable, "check", str(bad)], 1).stderr:
                raise AssertionError("Invalid UTF-8 was accepted")
            for text in ("fn main() { " + "!" * 1000 + "true }\n",
                         "fn main() { " + "(" * 1000 + "0" + ")" * 1000 + " }\n"):
                bad.write_text(text)
                if "error[limit]" not in run([executable, "check", str(bad)], 1).stderr:
                    raise AssertionError("Deep syntax did not produce a bounded limit diagnostic")
            bad.write_text("fn main() { 0 }\n")
            run([executable, "build", str(bad), "-o", str(bad)], 1)
            output = directory / "unknown-target.o"
            run([executable, "build", str(bad), "-o", str(output), "--emit", "object",
                 "--target", "unknown-mettle-target"], 1)
            if output.exists():
                raise AssertionError("Unknown target created a published output")
        else:
            raise ValueError(mode)
        if case_filter and not evidence["cases"]:
            raise ValueError("no cases match --filter")
        evidence["status"] = "passed"
    except Exception as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
        raise
    finally:
        evidence["child_peak_rss_high_water"] = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        evidence["rss_units"] = "bytes" if platform.system() == "Darwin" else "KiB"
        evidence["rss_scope"] = "cumulative child high-water mark, not isolated per-command memory"
        (directory / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"{mode}: passed; {len(evidence['cases'])} retained cases, {len(evidence['commands'])} commands")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("syntax", "fast-math", "broken-pipe",
                                         "sanitizers", "selfhost-lexer", "selfhost-parser", "selfhost-unicode"))
    parser.add_argument("executable")
    parser.add_argument("directory")
    parser.add_argument("--seed", help="compiled Mettle seed for selfhost probes")
    parser.add_argument("--filter", help="only selfhost lexer/parser cases whose name matches this regular expression")
    parser.add_argument("--ucd-dir", help="pinned Unicode 16.0.0 UCD directory for selfhost-unicode")
    args = parser.parse_args()
    if args.mode.startswith("selfhost-") and not args.seed:
        parser.error(args.mode + " requires --seed")
    if args.filter and args.mode not in {"selfhost-parser", "selfhost-lexer"}:
        parser.error("--filter requires selfhost-parser or selfhost-lexer")
    if args.mode == "selfhost-unicode" and not args.ucd_dir:
        parser.error("selfhost-unicode requires --ucd-dir")
    run_suite(args.mode, args.executable, args.directory, args.seed, args.filter, args.ucd_dir)
