import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from check_quality import include_failures, owned_files, text_failures
from check_modules import module_failures


class QualityRulesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mettle-quality-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_rejects_bad_authored_text(self):
        for data, expected in ((b"x \n", "trailing whitespace"),
                               (b"x\r\n", "LF line endings"),
                               (b"x", "final newline"),
                               (b"\tx\n", "spaces for indentation"),
                               (b"\xff\n", "UTF-8")):
            with self.subTest(data=data):
                path = self.write("compiler/source/sample.cpp", data)
                self.assertTrue(any(expected in error for error in text_failures(path, self.root)))

    def test_enforces_direct_compiler_layer_boundaries(self):
        modules = [
            {"name": name, "files": files, "dependencies": dependencies,
             "public_headers": files, "llvm": name in {"backend_llvm", "driver"}}
            for name, files, dependencies in (
                ("source", ["source/a.h"], []),
                ("syntax", ["syntax/syntax.h"], ["source"]),
                ("semantics", ["semantics/a.cpp"], ["syntax"]),
                ("ir", ["ir/a.h"], []),
                ("backend_llvm", ["backend/llvm/lower.h"], ["ir"]),
                ("driver", ["driver/a.cpp"], ["backend_llvm"]),
            )]
        cases = (
            ("compiler/source/a.h", '#include "syntax/syntax.h"\n', True),
            ("compiler/semantics/a.cpp", '#include "llvm/IR/Module.h"\n', True),
            ("compiler/ir/a.h", '#include "../backend/llvm/lower.h"\n', True),
            ("compiler/semantics/a.cpp", '#include "syntax/syntax.h"\n', False),
            ("compiler/driver/a.cpp", '#include "llvm/IR/Module.h"\n', False),
            ("runtime/a.cpp", '#include "llvm/IR/Module.h"\n', True),
            ("compiler/source/a.h", '// #include "llvm/IR/Module.h"\n', False),
        )
        for name, text, rejected in cases:
            with self.subTest(name=name, text=text):
                path = self.write(name, text.encode())
                self.assertEqual(bool(include_failures(path, self.root, modules)), rejected)

    def test_dependency_does_not_expose_private_headers(self):
        modules = [
            {"name": "syntax", "files": ["syntax/ast.h", "syntax/parser/detail.h"],
             "dependencies": [], "public_headers": ["syntax/ast.h"]},
            {"name": "semantics", "files": ["semantics/check.cpp"],
             "dependencies": ["syntax"], "public_headers": []}]
        path = self.write("compiler/semantics/check.cpp", b'#include "syntax/parser/detail.h"\n')
        self.assertTrue(any("private header" in error for error in include_failures(path, self.root, modules)))
        path.write_text('#include "syntax/ast.h"\n')
        self.assertEqual(include_failures(path, self.root, modules), [])

    def test_graph_rejects_cycles_unknown_edges_and_unowned_sources(self):
        modules = [
            {"name": "source", "directory": "source", "kind": "STATIC",
             "files": ["source/a.cpp"], "dependencies": [], "public_headers": []},
            {"name": "syntax", "directory": "syntax", "kind": "STATIC",
             "files": ["syntax/a.cpp"], "dependencies": ["source"], "public_headers": []},
            {"name": "driver", "directory": "driver", "kind": "EXECUTABLE",
             "files": ["driver/main.cpp"], "dependencies": ["syntax"], "public_headers": []}]
        for module in modules:
            for member in module["files"]:
                self.write("compiler/" + member, b"// owned source\n")
        def save():
            self.write("compiler/modules.json", (json.dumps({"schema": 1, "modules": modules}) + "\n").encode())
        save()
        self.assertEqual(module_failures(self.root), [])
        modules[0]["dependencies"] = ["syntax"]
        save()
        self.assertTrue(any("cycle" in error for error in module_failures(self.root)))
        modules[0]["dependencies"] = ["missing"]
        save()
        self.assertTrue(any("unknown component" in error for error in module_failures(self.root)))
        modules[0]["dependencies"] = []
        save()
        self.write("compiler/source/orphan.cpp", b"// no declared owner\n")
        self.assertTrue(any("no component owner" in error for error in module_failures(self.root)))

    def test_does_not_scan_tool_build_or_vendor_trees(self):
        expected = self.write("compiler/source/owned.cpp", b"owned\n")
        for directory in (".tools", "build", ".git", "__pycache__", "vendor", "third_party"):
            self.write(directory + "/ignored.cpp", b"invalid \r\n")
        self.write("docs/baseline/generated.csv", b"generated\r\n")
        self.assertEqual(list(owned_files(self.root)), [expected])

    def test_rejects_source_symlink_outside_project(self):
        with tempfile.TemporaryDirectory(prefix="mettle-quality-external-") as directory:
            external = Path(directory) / "external.cpp"
            external.write_text("external\n")
            link = self.root / "source.cpp"
            link.symlink_to(external)
            self.assertTrue(any("escapes" in error for error in text_failures(link, self.root)))


if __name__ == "__main__":
    unittest.main()
