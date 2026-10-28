import re
import unittest
from pathlib import Path

from audit import native_path
from validate import function_grammar_checks


class FunctionGrammarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grammars = {}
        for filename in ("core-grammar.md", "language-grammar.md"):
            text = (Path(__file__).parent.parent / filename).read_text()
            body = "\n".join(re.findall(r"```ebnf\n(.*?)```", text, re.S))
            cls.grammars[filename] = dict(re.findall(
                r"^([a-z_]\w*)\s*=\s*(.*?)(?=^[a-z_]\w*\s*=|\Z)",
                body, re.M | re.S))

    def test_selected_grammars(self):
        for filename, rules in self.grammars.items():
            with self.subTest(filename=filename):
                self.assertEqual(function_grammar_checks(rules, filename), [])

    def test_rejects_obsolete_or_inconsistent_result_rules(self):
        cases = (
            ("core-grammar.md", "result_annotation", '":"', '"->"', "arrow"),
            ("core-grammar.md", "function", "[ result_annotation ]",
             "result_annotation", "inference"),
            ("language-grammar.md", "callable_type", "result_annotation",
             "[ result_annotation ]", "explicit result"),
            ("language-grammar.md", "foreign_declaration", "result_annotation",
             "[ result_annotation ]", "explicit result"),
            ("language-grammar.md", "closure", "[ result_annotation ]",
             "result_annotation", "inference"),
        )
        self.assert_rejected(cases)

    def test_rejects_unit_type_value_confusion(self):
        cases = (
            ("language-grammar.md", "type_atom", "path, [ generic_args ]",
             'path, [ generic_args ] | "(", ")"', "only a value"),
            ("core-grammar.md", "primary", "unit_value", "INTEGER", "unit value"),
            ("core-grammar.md", "unit_value", '"(", ")"', '"Unit"', "empty parentheses"),
        )
        self.assert_rejected(cases)

    def test_rejects_old_never_keyword_and_missing_discard_contract(self):
        cases = (
            ("language-grammar.md", "type_atom", '| "_"',
             '| "never" | "_"', "Never"),
            ("core-grammar.md", "binding", "| discard_binding", "", "explicit discard"),
            ("core-grammar.md", "discard_binding", '"=", expression',
             '[ "=", expression ]', "explicit discard"),
        )
        self.assert_rejected(cases)

    def assert_rejected(self, cases):
        for filename, name, old, new, expected in cases:
            with self.subTest(filename=filename, production=name, replacement=new):
                rules = self.grammars[filename].copy()
                self.assertIn(old, rules[name])
                rules[name] = rules[name].replace(old, new, 1)
                failures = function_grammar_checks(rules, filename)
                self.assertTrue(any(expected in failure["problem"] for failure in failures),
                                failures)


class BuiltinMappingTests(unittest.TestCase):
    def test_builtin_exposures_and_members_share_native_type(self):
        for source, target in (("unit", "Unit"), ("never", "Never")):
            for crate in ("core", "std"):
                for kind, suffix, expected_suffix in (
                        ("primitive", "", ""),
                        ("method", "::clone-1", "::clone"),
                        ("associatedtype", "::Error-1", "::Error"),
                        ("implementation", "::impl-Any-for-T", "::impl-Any-for-T")):
                    with self.subTest(source=source, crate=crate, kind=kind):
                        record = {"kind": kind,
                                  "rust_path": crate + "::primitive::" + source + suffix}
                        self.assertEqual(native_path(record), "core::" + target + expected_suffix)

    def test_does_not_rename_unrelated_operations(self):
        self.assertEqual(native_path({"kind": "primitive", "rust_path": "core::primitive::i32"}),
                         "core::i32")
        self.assertEqual(native_path({"kind": "fn", "rust_path": "core::primitive::unit_test"}),
                         "core::primitive::unit_test")
        self.assertEqual(native_path({"kind": "fn", "rust_path": "core::primitive::never_test"}),
                         "core::primitive::never_test")


if __name__ == "__main__":
    unittest.main()
