import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import v1_operations as v1
import audit


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


class AuditStabilityTests(unittest.TestCase):
    def test_variant_stability_in_sibling_info_does_not_leak_to_neighbors(self):
        document = audit.Document(
            '<div class="variants">'
            '<section id="variant.Stable"><h3 class="code-header">Stable</h3></section>'
            '<div class="docblock">Stable variant.</div>'
            '<section id="variant.Nightly"><h3 class="code-header">Nightly</h3></section>'
            '<span class="item-info"><div class="stab unstable">Nightly API.</div></span>'
            '<div class="docblock">Nightly variant.</div>'
            '<section id="variant.Other"><h3 class="code-header">Other</h3></section>'
            '</div>')
        variants = {node.attrs["id"]: node for node in document.root.walk()
                    if node.attrs.get("id", "").startswith("variant.")}
        for name, unstable in (("Stable", False), ("Nightly", True), ("Other", False)):
            with self.subTest(name=name):
                metadata = audit.summary_nodes(variants["variant." + name])
                self.assertEqual(audit.signals(metadata)["unstable"], unstable)
                self.assertEqual(audit.header(metadata), name)


class RemainingWorkTests(unittest.TestCase):
    def reconcile(self, records):
        previous = {row["canonical_id"]: row for row in v1.generate(records, {})}
        return {row["canonical_id"]: row for row in v1.worklist(records, previous)}

    def test_excludes_deprecated_but_preserves_live_alias_contract(self):
        old = record("core::old", "fn", deprecated=True)
        alias = record("std::old", "fn", canonical_id=old["canonical_id"])
        rows = self.reconcile([old])
        self.assertEqual(rows[old["canonical_id"]]["disposition"], "excluded-deprecated")
        rows = self.reconcile([old, alias])
        self.assertEqual(rows[old["canonical_id"]]["disposition"], "post-v1-obligation")
        self.assertEqual(rows[old["canonical_id"]]["rust_contract"], alias["contract"])

    def test_preserves_platform_contracts_and_distinct_signatures(self):
        windows = record("std::os::windows::first", "fn",
                         availability=["Available on Windows only."])
        second = record("std::os::windows::second", "fn")
        i32 = record("core::other_i32", "fn")
        u64 = record("core::other_u64", "fn")
        rows = self.reconcile([windows, second, i32, u64])
        self.assertEqual(len(rows), 4)
        self.assertTrue(all(row["disposition"] == "post-v1-obligation"
                            for row in rows.values()))
        self.assertEqual(rows[windows["canonical_id"]]["category"], "os-extension")
        self.assertIn("Windows", rows[windows["canonical_id"]]["availability"])

    def test_impl_members_remain_traceable_under_one_obligation(self):
        owner = record("alloc::vec::Vec", "struct")
        trait = record("core::clone::Clone", "trait")
        implementation = record(
            "alloc::vec::Vec::impl-Clone", "implementation", owner["url"],
            trait["url"], signature="impl<T: Clone> Clone for Vec<T>")
        member = record("alloc::vec::Vec::clone", "method", owner["url"],
                        context=implementation["url"],
                        interface_member="core::clone::Clone::clone")
        rows = self.reconcile([owner, trait, implementation, member])
        self.assertEqual(rows[implementation["canonical_id"]]["disposition"],
                         "v1-obligation")
        self.assertEqual(rows[member["canonical_id"]]["disposition"],
                         "covered-by-implementation")
        self.assertIn(implementation["canonical_id"],
                      rows[member["canonical_id"]]["covered_by"])
        self.assertEqual(rows[member["canonical_id"]]["milestone"], "I13/I14")
        # Scope membership must not invent execution evidence.
        self.assertEqual(rows[member["canonical_id"]]["recorded_v1_status"], "")

    def test_inherent_blocks_attach_to_owner_but_methods_remain_work(self):
        owner = record("core::extra::Extra", "struct")
        block = record("core::extra::Extra::impl", "implementation", owner["url"])
        method = record("core::extra::Extra::run", "method", owner["url"],
                        context=block["url"])
        rows = self.reconcile([owner, block, method])
        self.assertEqual(rows[block["canonical_id"]]["disposition"], "covered-by-owner")
        self.assertEqual(rows[method["canonical_id"]]["disposition"], "post-v1-obligation")

    def test_shared_source_groups_code_but_keeps_type_contexts(self):
        first = record("core::extra::First", "struct")
        second = record("core::extra::Second", "struct")
        trait = record("core::extra::Trait", "trait")
        implementations = [
            record(owner["rust_path"] + "::impl", "implementation", owner["url"],
                   trait["url"], signature="impl<T> Trait for T",
                   source_file="core/src/extra.rs",
                   source="https://example.invalid/extra.rs.html#10-12")
            for owner in [first, second]]
        rows = self.reconcile([first, second, trait] + implementations)
        a, b = [rows[item["canonical_id"]] for item in implementations]
        self.assertEqual(a["work_unit"], b["work_unit"])
        self.assertNotEqual(a["canonical_id"], b["canonical_id"])
        self.assertEqual(a["disposition"], "post-v1-obligation")
        self.assertEqual(b["disposition"], "post-v1-obligation")
        implementations[1]["signature"] = "impl<T: Clone> Trait for T"
        rows = self.reconcile([first, second, trait] + implementations)
        self.assertNotEqual(*(rows[item["canonical_id"]]["work_unit"]
                              for item in implementations))
        implementations[1]["signature"] = implementations[0]["signature"]
        implementations[1]["source"] = None
        rows = self.reconcile([first, second, trait] + implementations)
        self.assertNotEqual(*(rows[item["canonical_id"]]["work_unit"]
                              for item in implementations))

    def test_rejects_stale_membership_and_uncovered_members(self):
        owner = record("alloc::vec::Vec", "struct")
        with self.assertRaisesRegex(ValueError, "selector differ"):
            v1.worklist([owner], {})
        extra = record("core::extra::Extra", "struct", deprecated=True)
        block = record("core::extra::Extra::impl", "implementation", extra["url"])
        with self.assertRaisesRegex(ValueError, "uncovered dependency"):
            self.reconcile([extra, block])

    def test_copies_evidence_without_accepting_invalid_receipts(self):
        owner = record("alloc::vec::Vec", "struct")
        previous = {owner["canonical_id"]: {
            "status": "evidenced", "mettle_path": "alloc.vec.List",
            "evidence_test": "tests/source/run/example.mt"}}
        row = v1.worklist([owner], previous)[0]
        self.assertEqual(row["recorded_v1_status"], "evidenced")
        self.assertEqual(row["evidence_test"], previous[owner["canonical_id"]]["evidence_test"])
        previous[owner["canonical_id"]]["evidence_test"] = ""
        with self.assertRaisesRegex(ValueError, "requires a test"):
            v1.worklist([owner], previous)


if __name__ == "__main__":
    unittest.main()
