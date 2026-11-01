import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import v1_operations as v1


def record(path, kind, parent=None, interface=None, **changes):
    value = {
        "rust_path": path, "kind": kind, "parent": parent,
        "implemented_interface": interface, "context": None,
        "interface_member": None,
        "canonical_id": path, "url": path, "contract": path,
        "runtime_stability": "stable", "deprecated": False,
        "availability": [], "signature": "",
    }
    value.update(changes)
    return value


class OperationSelectionTests(unittest.TestCase):
    def test_selects_inherent_and_trait_members_but_not_impl_members(self):
        owner = record("alloc::vec::Vec", "struct")
        trait = record("core::clone::Clone", "trait")
        implementation = record(
            "alloc::vec::Vec::impl-Clone", "implementation", owner["url"],
            trait["url"], signature="impl<T: Clone> Clone for Vec<T>")
        rows = [owner, trait, implementation,
                record("alloc::vec::Vec::retain", "method", owner["url"]),
                record("core::clone::Clone::clone", "tymethod", trait["url"]),
                record("alloc::vec::Vec::clone", "method", owner["url"],
                       context=implementation["url"],
                       interface_member="core::clone::Clone::clone"),
                record("alloc::vec::Vec::experimental", "method", owner["url"],
                       runtime_stability="unstable"),
                record("alloc::vec::Vec::deprecated", "method", owner["url"],
                       deprecated=True)]
        selected = {row["rust_path"] for row, _ in v1.select(rows)}
        self.assertEqual(selected, {owner["rust_path"], trait["rust_path"],
                                    implementation["rust_path"],
                                    "alloc::vec::Vec::retain",
                                    "core::clone::Clone::clone"})

    def test_scopes_selected_names_and_free_functions(self):
        rows = [record("std::net::SocketAddr", "enum"),
                record("std::os::unix::net::SocketAddr", "struct"),
                record("std::collections::linked_list::Iter", "struct"),
                record("core::iter::Map", "struct"),
                record("std::thread::spawn", "fn"),
                record("std::process::spawn", "fn"),
                record("std::fs::read", "fn"),
                record("std::print", "macro")]
        self.assertEqual({r["rust_path"] for r, _ in v1.select(rows)},
                         {"std::net::SocketAddr", "core::iter::Map",
                          "std::thread::spawn", "std::fs::read", "std::print"})

    def test_implementation_belongs_to_self_type_not_input_page(self):
        integer = record("core::primitive::i32", "primitive")
        trait = record("core::convert::From", "trait")
        unrelated = record(
            "core::primitive::i32::from-wrapping", "implementation",
            integer["url"], trait["url"],
            signature="impl From<i32> for Wrapping<i32>")
        own = record(
            "core::primitive::i32::from-i16", "implementation",
            integer["url"], trait["url"], signature="impl From<i16> for i32")
        self.assertEqual({r["url"] for r, _ in v1.select(
            [integer, trait, unrelated, own])},
            {integer["url"], trait["url"], own["url"]})

    def test_pair_folding_preserves_distinct_substitution_contracts(self):
        owner = record("alloc::vec::Vec", "struct")
        trait = record("core::convert::From", "trait")
        first = record("alloc::vec::Vec::from-array", "implementation",
                       owner["url"], trait["url"],
                       signature="impl<T> From<[T; 2]> for Vec<T>")
        second = record("alloc::vec::Vec::from-slice", "implementation",
                        owner["url"], trait["url"],
                        signature="impl<T: Clone> From<&[T]> for Vec<T>")
        generated = v1.generate([owner, trait, first, second], {})
        pairs = [row for row in generated if row["family"].startswith("impl:")]
        self.assertEqual(len(pairs), 2)
        self.assertEqual(pairs[0]["family"], pairs[1]["family"])
        self.assertNotEqual(pairs[0]["rust_contract"], pairs[1]["rust_contract"])

    def test_deduplicates_reexports_and_folds_widths_without_losing_rows(self):
        i32 = record("core::primitive::i32", "primitive")
        alias = record("std::primitive::i32", "primitive", canonical_id=i32["canonical_id"])
        u64 = record("core::primitive::u64", "primitive")
        rows = v1.generate([i32, alias, u64], {})
        self.assertEqual(len(rows), 2)
        self.assertEqual(len({r["family"] for r in rows}), 1)
        self.assertEqual(v1.fold_widths("AtomicI32"), v1.fold_widths("AtomicUsize"))
        self.assertNotEqual(v1.fold_widths("AtomicBool"), v1.fold_widths("AtomicPtr"))

    def test_preserves_reviewed_evidence_and_native_mapping(self):
        row = record("core::primitive::i32", "primitive")
        reviewed = {"status": "evidenced", "mettle_path": "core.i32",
                    "evidence_test": "tests/source/run/example.mt"}
        generated = v1.generate([row], {row["canonical_id"]: reviewed})[0]
        for key, value in reviewed.items():
            self.assertEqual(generated[key], value)
        with self.assertRaisesRegex(ValueError, "requires a test"):
            v1.generate([row], {row["canonical_id"]: {"status": "evidenced"}})

    def test_distinguishes_darwin_conditions_and_unknown_conditions(self):
        for conditions, expected in [
                ([], "missing"), (["Available on Unix only."], "missing"),
                (["Available on target_has_atomic=64 only."], "missing"),
                (["Available on Windows only."], "not-applicable"),
                (["Available on Unix only.", "Available on WASI only."],
                 "not-applicable"),
                (["Available on a new target condition only."], "blocked")]:
            with self.subTest(conditions=conditions):
                self.assertEqual(v1.target_status({"availability": conditions}), expected)
        self.assertEqual(v1.target_status({"availability": [
            "Available on a new target condition only.", "Available on Windows only.",
        ]}), "not-applicable")


if __name__ == "__main__":
    unittest.main()
