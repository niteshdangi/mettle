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

ROOT = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run_suite(mode, executable, directory, seed=None):
    executable = str(Path(executable).resolve())
    directory = Path(directory) / mode
    directory.mkdir(parents=True, exist_ok=True)
    evidence = {"scope": "Source regressions through the initial I06 machine boundary; not full language or release qualification",
                "status": "in_progress", "mode": mode, "compiler_sha256": digest(executable),
                "host": platform.platform(), "commands": [], "cases": []}

    def run(arguments, expected=0, timeout=30, env=None, input_text=None):
        begin = time.perf_counter()
        result = subprocess.run(arguments, text=True, capture_output=True,
                                timeout=timeout, env=env, input=input_text)
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
            "unicode-word": "x \u03bb y".encode(),
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
            if re.findall(r"(\d+) additional diagnostics suppressed", actual.stderr) != re.findall(r"(\d+) additional diagnostics suppressed", reference.stderr):
                raise AssertionError(f"{name}: diagnostic suppression count differs")
            evidence["cases"].append({"name": name, "source_sha256": digest(path),
                                      "tokens": len(found), "diagnostics": len(diagnostics)})

    def selfhost_parser():
        native = str(Path(seed).resolve())
        evidence["scope"] = "Self-hosted parser core shapes, lossless tokens, recovery and limits; extended grammar remains unsupported"
        evidence["seed_sha256"] = digest(native)
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
            if kind == "binding":
                text = data[nodes[children[0]][1]:nodes[children[0]][2]].decode().strip('`')
                children = [child for child in children[1:] if nodes[child][0] != "type"]
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
        }
        for name, body in accepted.items():
            path = source("parser-" + name, body if name == "declarations" else "fn main() {\n" + body + "\n}\n")
            reference = run([executable, "syntax", str(path)])
            actual = run([native, "syntax", str(path)])
            data = path.read_bytes()
            nodes, edges, tokens = inspect_native(actual, data)
            wanted = json.loads(reference.stdout)
            assert tokens == [(token["kind"], token["begin"], token["end"]) for token in wanted["tokens"]], name
            functions = [index for index, node in enumerate(nodes) if node[0] == "function"]
            assert len(functions) == len(wanted["functions"])
            for index, reference_function in zip(functions, wanted["functions"]):
                function = nodes[index]
                identifier = nodes[edges[function[3]]]
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
        }
        for name, text in rejected.items():
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
                           "unsupported": "type Product { value: i32 }\nfn after() { 7 }"}.items():
            path = source("parser-" + name, text)
            actual = run([native, "syntax", str(path)], 1)
            nodes, edges, tokens = inspect_native(actual, path.read_bytes())
            assert sum(node[0] == "function" for node in nodes) >= 1, actual.stdout
            assert sum(node[0] == "error" for node in nodes) >= (2 if name == "recovery" else 1), actual.stdout
            if name == "recovery":
                assert sum(node[0] == "function" for node in nodes) == 2
                assert any(node[0] == "integer" and path.read_bytes()[node[1]:node[2]] == b"42" for node in nodes)
            assert f"error[{'parse' if name == 'recovery' else 'feature'}]" in actual.stderr, actual.stderr
            evidence["cases"].append({"name": name, "source_sha256": digest(path)})

        for i, literal in enumerate(('"\\q"', '"\\x80"', '"\\u{}"', '"\\u{d800}"', '"\\u{110000}"',
                                     'b"\\u{41}"', 'b"\\xgg"', 'b"\u00e9"', 'br#"\u00e9"#')):
            path = source(f"parser-text-{i}", "fn main() { " + literal + " }\n")
            reference = run([executable, "check", str(path)], 1)
            actual = run([native, "syntax", str(path)], 1)
            wanted = re.search(r"error\[lex\]: ([^\n]*)", reference.stderr)
            found = re.search(r"error\[lex\] (\d+):(\d+) ([^\n]*)", actual.stderr)
            assert wanted and found and wanted[1] == found[3], (reference.stderr, actual.stderr)
            assert path.read_bytes()[int(found[1]):int(found[2])].decode() == literal
            evidence["cases"].append({"name": f"text-{i}", "source_sha256": digest(path)})

        for i, text in enumerate(("fn generic<T>() { 0 }", "fn slice(x: [u8]) { 0 }",
                                  "fn main() { if let present(x) = value { x } }",
                                  "fn defaults(x: i32 = 1) { x }", "fn main() { call(value: 1) }",
                                  "fn main() { object?.field }", "fn main() { T.(Trait).member }",
                                  "fn main() { factory<i32, Other>(value) }",
                                  "fn main() { factory<Outer<Inner>>(value) }")):
            path = source(f"parser-feature-{i}", text)
            actual = run([native, "syntax", str(path)], 1)
            assert "error[feature]" in actual.stderr, actual.stderr
            evidence["cases"].append({"name": f"feature-{i}", "source_sha256": digest(path)})

        for name, text, expected in (("empty-module", "", 0),
                                      ("parser-budget", "fn main() {\n" + "let x =;\n" * 140 + "}\n", 1)):
            path = source("parser-" + name, text)
            reference = run([executable, "syntax", str(path)], expected)
            actual = run([native, "syntax", str(path)], expected)
            inspect_native(actual, path.read_bytes())
            if expected:
                assert actual.stderr.count("error[parse]") == reference.stderr.count("error[parse]") == 100
                assert "40 additional diagnostics suppressed" in actual.stderr
            evidence["cases"].append({"name": name, "source_sha256": digest(path)})

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
        program = source("print-to-closed-pipe",
                         "import std.io;\nfn main(): i32 {\n"
                         "    var i = 0\n"
                         "    while i < 1000000 { io.print(f\"line {i}\\n\"); i += 1 }\n"
                         "    0\n}\n")
        binary = directory / "print-to-closed-pipe"
        run([executable, "build", str(program), "-o", str(binary)])
        for ignored, expected in ((False, -signal.SIGPIPE), (True, 141)):
            def disposition(ignored=ignored):
                signal.signal(signal.SIGPIPE, signal.SIG_IGN if ignored else signal.SIG_DFL)
            child = subprocess.Popen([str(binary)], stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, preexec_fn=disposition)
            child.stdout.read(16)
            child.stdout.close()
            stderr = child.stderr.read()
            status = child.wait(timeout=30)
            evidence["cases"].append({"sigpipe_ignored": ignored, "exit_status": status,
                                      "stderr": stderr.decode(errors="replace")})
            if status != expected or stderr:
                raise AssertionError(f"closed stdout (SIGPIPE ignored={ignored}): expected "
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
            capped = source("reported-diagnostic-cap",
                            "".join(f"fn f{i}() {{ 1+true }}\n" for i in range(140)) +
                            "fn main(){0}\n")
            result = run([executable, "check", str(capped)], 1)
            if result.stderr.count("error[") != 100 or "40 additional diagnostics suppressed (limit 100)" not in result.stderr:
                raise AssertionError("Diagnostic cap silently discarded failures")
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
            text = "// UTF-8 comment: café\r\nfn main()\r\n{\r\n /* a\r\n /* b */ c */\r\n(0)\r\n}\r\n"
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
                                         "sanitizers", "selfhost-lexer", "selfhost-parser"))
    parser.add_argument("executable")
    parser.add_argument("directory")
    parser.add_argument("--seed", help="compiled Mettle seed for selfhost probes")
    args = parser.parse_args()
    if args.mode.startswith("selfhost-") and not args.seed:
        parser.error(args.mode + " requires --seed")
    run_suite(args.mode, args.executable, args.directory, args.seed)
