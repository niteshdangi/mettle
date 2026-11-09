import unittest

from audit import native_path


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
