#!/usr/bin/env python3
"""Focused behavioral checks for maintained benchmark and debugger tooling."""

import ast
import hashlib
import importlib.util
import json
import os
import random
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import bench_compare as bench
import test_linux_target as linux
import unicode_tables as unicode

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests"))
import alloc as alloc_runner
import modules as module_runner
import packages as package_runner
import scheduling
import source as source_runner
import std as std_runner

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests" / "backend"))
import machine as machine_runner


def build_and_run(entry, directory):
    program = directory / "program"
    built = subprocess.run(
        [str(COMPILER), "build", str(entry), "-o", str(program),
         "--profile", "release", "--overflow-checks", "off",
         "--cache-dir", str(directory / "cache")],
        text=True, capture_output=True)
    if built.returncode:
        raise AssertionError(built.stdout + built.stderr)
    return subprocess.run([str(program)], capture_output=True)


class BenchmarkTests(unittest.TestCase):
    def test_scaling_sources_compile_and_run(self):
        for generic, expected in ((False, 61), (True, 105)):
            with self.subTest(generic=generic):
                directory = OUTPUT / ("generic" if generic else "plain")
                tree, _ = bench.generate_scale(directory, 1, 1, generic)
                result = build_and_run(tree, directory)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_imprecise_estimates_cannot_pass(self):
        for kind in ("runtime", "compile"):
            for samples in ([0.1, 0.2] * 15, [5.0, 10.0] * 15):
                with self.subTest(kind=kind, samples=samples[:2]):
                    result = bench.decide(samples, [1.0] * 30, 60, kind)
                    self.assertEqual(result["verdict"], "inconclusive")
                    self.assertEqual(result["gate"], "inconclusive")

    def test_precise_wins_ties_and_slowdowns_keep_their_gates(self):
        for ratio, kind, verdict, gate in (
                (0.5, "compile", "win", "pass"),
                (1.0, "compile", "tie", "fail"),
                (1.0, "runtime", "tie", "pass"),
                (2.0, "runtime", "slowdown", "fail")):
            with self.subTest(ratio=ratio, kind=kind):
                result = bench.decide([ratio] * 30, [1.0] * 30, 60, kind)
                self.assertEqual((result["verdict"], result["gate"]), (verdict, gate))

    def test_failed_runtime_or_warmup_is_not_a_checksum(self):
        class FakeRunner(bench.Runner):
            def __init__(self, status):
                self.status = status

            def run(self, *args, **kwargs):
                return {"returncode": self.status, "stdout": b"", "stderr": "",
                        "seconds": 1.0, "peak_rss_bytes": 1}

        for warmup in (0, 1):
            for status in (-11, -9, 128):
                with self.subTest(warmup=warmup, status=status):
                    with self.assertRaises(bench.Failure):
                        bench.measure_runtime(FakeRunner(status), {"mettle": "M", "rust": "R"},
                                              warmup, 2, 1, random.Random(0))
        samples, outputs, _ = bench.measure_runtime(
            FakeRunner(127), {"mettle": "M", "rust": "R"}, 1, 2, 1, random.Random(0))
        self.assertEqual(outputs["mettle"], (127, b""))
        self.assertEqual(samples["mettle"], [1.0, 1.0])


class CacheEnvironmentTests(unittest.TestCase):
    def test_budget_validation_pruning_and_cli_precedence(self):
        with tempfile.TemporaryDirectory(dir=OUTPUT) as temporary:
            root = Path(temporary)
            core = root / "library/core"
            core.mkdir(parents=True)
            (core / "module.mt").write_text("pub fn value(): i32 { 42 }\n")
            source, output = root / "main.mt", root / "main"
            source.write_text("fn main(): i32 { core.value() - 42 }\n")
            output.write_bytes(b"preserve existing artifact")
            cache = root / "cache"

            def build(limit, *extra, expected=0):
                result = subprocess.run(
                    [str(COMPILER), "build", str(source),
                     "-o", str(output), "--library-dir", str(root / "library"),
                     "--explain", *extra], text=True, capture_output=True,
                    env={**os.environ, "METTLE_CACHE_DIR": str(cache),
                         "METTLE_CACHE_LIMIT_KIB": limit})
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                return result.stdout + result.stderr

            def cache_bytes():
                return sum(path.stat().st_size for kind in ("entries", "blobs")
                           for path in (cache / kind).rglob("*") if path.is_file())

            rejected = build("invalid", expected=2)
            self.assertIn("METTLE_CACHE_LIMIT_KIB must be a non-negative integer", rejected)
            self.assertEqual(output.read_bytes(), b"preserve existing artifact")
            self.assertIn("mettle: cache miss", build("2097152"))
            populated = cache_bytes()
            self.assertGreater(populated, 0)
            source.write_text("fn main(): i32 { core.value() - 41 }\n")
            pruned = build("0")
            self.assertIn("mettle: cache miss", pruned)
            self.assertIn("mettle: cache evicted", pruned)
            self.assertIn("over the 0-byte budget", pruned)
            remaining = cache_bytes()
            self.assertLess(remaining, populated)
            source.write_text("fn main(): i32 { core.value() - 40 }\n")
            overridden = build("0", "--cache-limit-kib", "2097152")
            self.assertIn("mettle: cache miss", overridden)
            self.assertIn("mettle: cache stored", overridden)
            self.assertNotIn("over the 0-byte budget", overridden)
            self.assertGreater(cache_bytes(), remaining)


class LibraryRunnerTests(unittest.TestCase):
    def test_library_workers_preserve_filtered_profile_coverage(self):
        for runner in (alloc_runner, std_runner):
            with self.subTest(runner=runner.__name__), tempfile.TemporaryDirectory(dir=OUTPUT) as temporary:
                root = Path(temporary)
                for name in ("alpha", "beta", "gamma"):
                    (root / f"{name}.mt").write_text("fn main() { 0 }\n")
                barrier = threading.Barrier(2, timeout=5)
                lock = threading.Lock()
                active = peak = 0
                seen = []

                def check(executable, source, output, profile):
                    nonlocal active, peak
                    self.assertTrue(output.is_dir())
                    with lock:
                        active += 1
                        peak = max(peak, active)
                        seen.append((source.stem, profile))
                    barrier.wait()
                    with lock:
                        active -= 1

                with patch.object(runner, "check", side_effect=check):
                    runner.main("compiler", root / "out", root,
                                ("debug", "release", "debug"), jobs=2,
                                pattern="^(alpha|gamma)$")
                self.assertEqual(peak, 2)
                self.assertCountEqual(seen, [(name, profile)
                                            for name in ("alpha", "gamma")
                                            for profile in ("debug", "release")])

    def test_library_workers_report_failures_and_reject_invalid_selection(self):
        for runner in (alloc_runner, std_runner):
            with self.subTest(runner=runner.__name__), tempfile.TemporaryDirectory(dir=OUTPUT) as temporary:
                root = Path(temporary)
                (root / "alpha.mt").write_text("fn main() { 0 }\n")
                with patch.object(runner, "check", side_effect=AssertionError("broken")):
                    with self.assertRaisesRegex(AssertionError, "alpha.mt.*debug"):
                        runner.main("compiler", root / "out", root, jobs=2)
                with self.assertRaisesRegex(ValueError, "jobs"):
                    runner.main("compiler", root / "out", root, jobs=0)
                with self.assertRaisesRegex(ValueError, "no .* cases selected"):
                    runner.main("compiler", root / "out", root, pattern="^missing$")

    def test_core_file_cases_overlap_without_running_other_cases(self):
        with tempfile.TemporaryDirectory(dir=OUTPUT) as temporary:
            root = Path(temporary)
            library = root / "library"
            library.mkdir()
            for name in ("alpha", "beta", "gamma"):
                (library / f"{name}.mt").write_text("fn main() { 0 }\n")
            barrier = threading.Barrier(2, timeout=5)
            builds = []

            def run(arguments, **kwargs):
                if len(arguments) > 1 and arguments[1] == "build":
                    builds.append(Path(arguments[2]).parent.name)
                    barrier.wait()
                return subprocess.CompletedProcess(arguments, 0, "", "")

            with patch.object(module_runner, "__file__", str(root / "modules.py")), \
                    patch.object(module_runner.processes, "run", side_effect=run):
                module_runner.main("compiler", root / "out", "library", jobs=2,
                                   pattern="^(alpha|gamma)$")
            self.assertCountEqual(builds, ["library-core-alpha", "library-core-gamma"])


class SchedulingTests(unittest.TestCase):
    def test_source_receipts_track_shared_helper_changes(self):
        with tempfile.TemporaryDirectory(dir=OUTPUT) as temporary:
            root = Path(temporary)
            helpers = root / "source_helpers"
            helpers.mkdir()
            module, child = helpers / "module.mt", helpers / "poll.mt"
            module.write_text("module poll;\n")
            child.write_text("pub fn value(): i32 { 1 }\n")
            source = root / "case.mt"
            source.write_text("module source_helpers;\nfn main(): i32 { 0 }\n")

            def run(command, **kwargs):
                if command[0] == "compiler":
                    if kind == "run":
                        Path(command[command.index("-o") + 1]).write_bytes(b"program")
                    else:
                        return subprocess.CompletedProcess(
                            command, 1, "", f"{source}:2:1: error[name]: rejection\n")
                return subprocess.CompletedProcess(command, 0, "", "")

            for kind in ("run", "fail"):
                case = source_runner.Case(
                    "case", source, kind, ("debug",), [], None,
                    exits={"debug": 0}, errors=[("name", 2, 1, "rejection")])
                records = []
                with patch.object(source_runner.processes, "run", side_effect=run):
                    for changed in (None, module, child):
                        if changed:
                            changed.write_text(changed.read_text() + "// changed\n")
                        runner = source_runner.Runner("compiler", case)
                        getattr(runner, f"execute_{kind}")(root)
                        records.append(runner.records[0])
                self.assertEqual(len({record["source_sha256"] for record in records}), 1)
                self.assertNotEqual(records[0]["helper_sha256"], records[1]["helper_sha256"])
                self.assertNotEqual(records[1]["helper_sha256"], records[2]["helper_sha256"])
                self.assertEqual(records[2]["helper_sha256"],
                                 {str(path): source_runner.digest(path) for path in (module, child)})
                if kind == "run":
                    self.assertEqual(len({record["program_sha256"] for record in records}), 1)

    def test_longest_first_keeps_failed_work_and_stable_results(self):
        with tempfile.TemporaryDirectory(dir=OUTPUT) as temporary:
            root = Path(temporary)
            (root / "durations.json").write_text(
                json.dumps({"short": 1, "long": 20, "failed": 10, "bad": "invalid"}))
            seen = []

            def execute(name):
                seen.append(name)
                if name == "failed":
                    raise AssertionError
                return name

            results = scheduling.run(["short", "failed", "long"], execute, root, 1, str)
            self.assertEqual(seen, ["long", "failed", "short"])
            self.assertEqual([item for item, *_ in results], ["failed", "long", "short"])
            self.assertEqual(results[0][2], "AssertionError")
            timings = json.loads((root / "durations.json").read_text())
            self.assertEqual(set(timings), {"short", "failed", "long"})
            self.assertTrue(all(value >= 0 for value in timings.values()))
            with self.assertRaisesRegex(ValueError, "jobs"):
                scheduling.run([], execute, root, 0, str)

    def test_shards_cover_each_unit_once_independent_of_submission_order(self):
        units = [f"case-{index}:{profile}" for index in range(25)
                 for profile in ("debug", "release")]
        selected = []
        for index in range(7):
            shard = scheduling.select(units, str, index, 7)
            self.assertEqual(set(shard),
                             set(scheduling.select(reversed(units), str, index, 7)))
            selected += shard
        self.assertCountEqual(selected, units)
        for index, count in ((0, 0), (-1, 2), (2, 2)):
            with self.assertRaisesRegex(ValueError, "shard"):
                scheduling.select(units, str, index, count)

    def test_source_profiles_overlap_and_failed_diagnostics_keep_artifacts_and_evidence(self):
        with tempfile.TemporaryDirectory(dir=OUTPUT) as temporary:
            root = Path(temporary)
            compiler = root / "compiler"
            compiler.write_bytes(b"compiler")
            repeated = root / "repeated.mt"
            repeated.write_text("// profiles: debug release debug\nfn main() { 0 }\n")
            self.assertEqual(source_runner.parse_case(repeated, "run").profiles,
                             ("debug", "release"))
            cases = []
            for name in ("alpha", "beta"):
                path = root / f"{name}.mt"
                path.write_text("invalid\n")
                cases.append(source_runner.Case(
                    name, path, "fail", ("debug", "release"), [], None,
                    errors=[("name", 1, 1, "expected rejection")], count=1))
            barrier = threading.Barrier(4, timeout=5)
            history = root / "out/fail"
            history.mkdir(parents=True)
            (history / "evidence.json").write_text(json.dumps({"commands": [
                {"command": [str(compiler), "build", str(cases[1].path),
                             "--profile", "release"], "elapsed_seconds": 30},
                {"command": ["malformed", "build", "source.mt", "--profile"]}]}))

            def run(command, **kwargs):
                barrier.wait()
                path = Path(command[2])
                profile = command[command.index("--profile") + 1]
                message = ("wrong rejection" if path.stem == "beta" and profile == "release"
                           else "expected rejection")
                return subprocess.CompletedProcess(
                    command, 1, "", f"{path}:1:1: error[name]: {message}\n")

            with patch.object(source_runner, "load_cases", return_value=cases), \
                    patch.object(source_runner.processes, "run", side_effect=run), \
                    patch.object(source_runner.scheduling, "run", wraps=scheduling.run) as schedule:
                with self.assertRaisesRegex(SystemExit, "1 of 4"):
                    source_runner.run_suite("fail", compiler, root / "out", 4, None)
            self.assertEqual(schedule.call_args.kwargs["initial"], {"beta:release": 30})
            evidence = json.loads((root / "out/fail/evidence.json").read_text())
            self.assertEqual(evidence["status"], "failed")
            self.assertEqual(len(evidence["commands"]), 4)
            self.assertEqual(len(evidence["cases"]), 3)
            for profile in ("debug", "release"):
                for name in ("alpha", "beta"):
                    self.assertEqual((root / "out/fail" / profile / f"{name}.out").read_bytes(),
                                     source_runner.PRESERVED)

    def test_package_workers_isolate_resets_environments_and_failed_logs(self):
        with tempfile.TemporaryDirectory(dir=OUTPUT) as temporary:
            root = Path(temporary)
            fixtures = root / "fixtures"
            (fixtures / "path-dependency/app").mkdir(parents=True)
            compiler = root / "compiler"
            compiler.write_text("""#!/usr/bin/env python3
import os, sys, time
from pathlib import Path
owner = Path(os.environ["METTLE_CACHE_DIR"]).parent
if Path.cwd() != owner:
    sys.exit("working directory escaped case")
(owner / "owner").write_text(str(os.getppid()))
arrivals = Path(__file__).parent / "arrivals"
arrivals.mkdir(exist_ok=True)
(arrivals / owner.name).touch()
end = time.monotonic() + 5
while len(list(arrivals.iterdir())) < 2:
    if time.monotonic() > end:
        sys.exit("workers did not overlap")
    time.sleep(0.01)
if (Path(__file__).parent / "fail").exists():
    sys.exit("intentional worker failure")
lock = Path(sys.argv[2]) / "lock.mettle"
if "--locked" in sys.argv or (lock.exists() and lock.read_text() != "version: 3\\n"):
    sys.exit("lock.mettle")
lock.write_text("version: 3\\n")
""")
            compiler.chmod(0o755)
            selection = "^(missing_lock_locked|lock_corruption)$"
            output = root / "out"
            self.assertEqual(package_runner.main(
                [str(compiler), str(output), str(fixtures), selection, "-j", "2"]), 0)
            names = ("missing_lock_locked", "lock_corruption")
            self.assertEqual(len({(output / name / "owner").read_text() for name in names}), 2)
            self.assertFalse((fixtures / "path-dependency/app/lock.mettle").exists())
            self.assertFalse((output / names[0] / "path-dependency/app/lock.mettle").exists())
            self.assertEqual((output / names[1] / "path-dependency/app/lock.mettle").read_text(),
                             "version: 99\n")
            (root / "fail").touch()
            self.assertEqual(package_runner.main(
                [str(compiler), str(output), str(fixtures), selection, "-j", "2"]), 1)
            evidence = json.loads((output / "evidence.json").read_text())
            self.assertEqual(evidence["status"], "failed")
            self.assertEqual([case["name"] for case in evidence["cases"]], sorted(names))
            for name in names:
                child = json.loads((output / name / "evidence.json").read_text())
                self.assertEqual(child["status"], "failed")
                self.assertIn("intentional worker failure", child["commands"][0]["stderr"])


class MachineOracleTests(unittest.TestCase):
    def test_machine_cases_and_profiles_overlap_with_private_fixture_objects(self):
        with tempfile.TemporaryDirectory(dir=OUTPUT) as temporary:
            root = Path(temporary)
            compiler, cxx, runtime, callbacks = [root / name for name in
                                                ("mettle", "clang++", "runtime.a", "callbacks.a")]
            for path in (compiler, cxx, runtime, callbacks):
                path.write_bytes(b"fixture")
            names = ("machine-target-guarded-wide-vector-c-physical-abi",
                     "machine-target-wide-vector-aggregate-c-abi")
            barrier = threading.Barrier(4, timeout=5)
            fixtures = []
            failing = False

            def run(command, **kwargs):
                command = list(map(str, command))
                if command[0] == sys.executable:
                    try:
                        machine_runner.main(command[2:])
                    except AssertionError as error:
                        return subprocess.CompletedProcess(command, 1, "", str(error))
                elif "-o" in command:
                    output = Path(command[command.index("-o") + 1])
                    output.write_bytes(" ".join(command).encode())
                    if "-std=c11" in command:
                        fixtures.append(output)
                        barrier.wait()
                    if failing and command[0] == str(compiler) and names[0] in command[2] and \
                            command[-1] == "debug":
                        return subprocess.CompletedProcess(command, 1, "", "intentional build failure")
                return subprocess.CompletedProcess(command, 0, "", "")

            with patch.object(machine_runner, "SOURCES", dict.fromkeys(names, "fn main() { 0 }\n")), \
                    patch.object(machine_runner.processes, "run", side_effect=run):
                machine_runner.main([*map(str, (compiler, cxx, runtime, callbacks, root / "out")),
                                     "--case", names[0], "--case", names[1], "-j", "4"])
            self.assertEqual(len(set(fixtures)), 4)
            evidence = json.loads((root / "out/evidence.json").read_text())
            self.assertEqual(evidence["status"], "passed")
            self.assertEqual([(case["name"], case["profile"]) for case in evidence["cases"]],
                             [(name, profile) for name in names
                              for profile in ("debug", "release")])
            self.assertTrue(all(path.is_file() for path in fixtures))
            failing = True
            with patch.object(machine_runner, "SOURCES", dict.fromkeys(names, "fn main() { 0 }\n")), \
                    patch.object(machine_runner.processes, "run", side_effect=run):
                with self.assertRaisesRegex(AssertionError, "intentional build failure"):
                    machine_runner.main([*map(str, (compiler, cxx, runtime, callbacks, root / "out")),
                                         "--case", names[0], "--case", names[1], "-j", "4"])
            evidence = json.loads((root / "out/evidence.json").read_text())
            self.assertEqual(evidence["status"], "failed")
            self.assertEqual(len(evidence["workers"]), 4)
            self.assertEqual(len(evidence["cases"]), 3)
            self.assertTrue(any("intentional build failure" in command["stderr"]
                                for command in evidence["commands"]))

    def test_large_volatile_probe_tracks_pointer_loaded_from_cleanup_frame(self):
        body = """
  %1 = getelementptr inbounds nuw %frame, ptr %0, i32 0, i32 0
  %2 = load ptr, ptr %1, align 8
  call void @llvm.memmove.p0.p0.i64(ptr align 1 %2, ptr %source, i64 1025, i1 true)
  call void @llvm.memcpy.p0.p0.i64(ptr %destination, ptr align 1 %2, i64 1025, i1 true)
"""
        self.assertEqual(machine_runner.large_volatile_accesses("ptr %0", body), (True, True))
        self.assertEqual(machine_runner.large_volatile_accesses(
            "ptr %0", body.replace("i1 true", "i1 false")), (False, False))
        self.assertEqual(machine_runner.large_volatile_accesses(
            "ptr %0", body.replace("ptr align 1 %2", "ptr %unrelated")), (False, False))


class DebuggerTests(unittest.TestCase):
    def test_registered_sum_summaries_render_native_variants(self):
        fake_lldb = SimpleNamespace(SBError=Mock())
        fake_lldb.SBError.return_value.Success.return_value = True
        path = Path(__file__).parent / "debug" / "mettle_lldb.py"
        spec = importlib.util.spec_from_file_location("mettle_lldb", path)
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"lldb": fake_lldb}):
            spec.loader.exec_module(module)
        commands = []
        getattr(module, "__lldb_init_module")(SimpleNamespace(HandleCommand=commands.append), {})
        registrations = []
        for command in commands:
            parts = shlex.split(command)
            if "-x" in parts:
                registrations.append((parts[parts.index("-x") + 1],
                                      parts[parts.index("-F") + 1].rsplit(".", 1)[-1]))
        for name, labels in (
                ("Outcome<i32, ParseError>", ("success", "failure")),
                ("Outcome<(i32)?, Outcome<bool, ParseError>>", ("success", "failure")),
                ("(i32)?", ("none", "present"))):
            for tag, expected in enumerate(labels):
                with self.subTest(name=name, tag=tag):
                    callbacks = [getattr(module, callback) for regex, callback in registrations
                                 if re.search(regex, name)]
                    self.assertEqual(len(callbacks), 1)
                    value = Mock()
                    value.GetTypeName.return_value = name
                    value.GetChildMemberWithName.return_value.GetValueAsUnsigned.return_value = tag
                    self.assertEqual(callbacks[0](value, {}), expected)


class LinuxOracleTests(unittest.TestCase):
    def test_unwrap_probe_requires_the_selected_panic(self):
        expectations = next(expectations for group, name, text, expectations
                            in linux.library_cases(OUTPUT) if name == "unwrap-none-aborts")
        execute = next(node for node in ast.parse(linux.LIBRARY_EXECUTION).body
                       if isinstance(node, ast.FunctionDef) and node.name == "execute")
        program = OUTPUT / "mock-library-program"
        program.write_bytes(b"mock linked artifact")
        case = {"name": "unwrap", "object": "source.o", "program": str(program),
                **expectations}
        message = b"panicked: called `unwrap` on an absent value\n"
        for status, stderr, accepted in (
                (-11, message, False), (1, message, False),
                (101, b"", False), (101, message, True)):
            with self.subTest(status=status, stderr=stderr):
                process = SimpleNamespace(run=Mock(side_effect=[
                    subprocess.CompletedProcess([], 0, "", ""),
                    subprocess.CompletedProcess([], status, b"", stderr)]))
                namespace = {"Path": Path, "os": os, "shutil": shutil,
                             "subprocess": process, "hashlib": hashlib,
                             "cxx": "clang++", "runtime": "runtime.a"}
                exec(compile(ast.Module(body=[execute], type_ignores=[]),
                             "<linux-library-execution>", "exec"), namespace)
                if accepted:
                    self.assertEqual(namespace["execute"](case)["exit_status"], 101)
                else:
                    with self.assertRaises(RuntimeError):
                        namespace["execute"](case)


class UnicodeGeneratorTests(unittest.TestCase):
    def test_selected_release_debug_categories_and_full_case_mapping(self):
        directory = OUTPUT / "unicode"
        ucd = directory / "ucd"
        (ucd / "extracted").mkdir(parents=True, exist_ok=True)
        records = []
        for scalar, category, upper, lower in (
                ("0030", "Nd", "", ""), ("0041", "Lu", "", "0061"),
                ("0061", "Ll", "0041", "")):
            fields = [scalar, "SYNTHETIC", category] + [""] * 12
            fields[12], fields[13] = upper, lower
            records.append(";".join(fields))
        files = {
            "UnicodeData.txt": "\n".join(records),
            "DerivedCoreProperties.txt": (
                "# DerivedCoreProperties-17.0.0.txt\n"
                "0041; Alphabetic\n0061; Lowercase\n0041; Uppercase\n"
                "0041; Cased\n0027; Case_Ignorable\n"
                "0300; Grapheme_Extend\n2060; Default_Ignorable_Code_Point\n"),
            "PropList.txt": "# PropList-17.0.0.txt\n0020; White_Space\n",
            "SpecialCasing.txt": "# SpecialCasing-17.0.0.txt\n0130;0069 0307;0130;0130;;\n",
            "CaseFolding.txt": "# CaseFolding-17.0.0.txt\n",
            "DerivedGeneralCategory.txt": (
                "# DerivedGeneralCategory-17.0.0.txt\n"
                "0000..001F; Cc\n200B; Cf\n0378; Cn\nE000..F8FF; Co\n"),
        }
        for name, text in files.items():
            path = ucd / "extracted" / name if name == "DerivedGeneralCategory.txt" else ucd / name
            path.write_text(text, encoding="utf-8")
        generated = unicode.render_module(unicode.read_inputs(ucd))
        (directory / "data.mt").write_text(generated, encoding="utf-8")
        entry = directory / "main.mt"
        entry.write_text("""module data
fn main(): i32 {
    if !data.is_debug_escape(0u32, false) { return 1 }
    if !data.is_debug_escape(0x200bu32, false) { return 2 }
    if !data.is_debug_escape(0x0378u32, false) { return 3 }
    if !data.is_debug_escape(0xe000u32, false) { return 4 }
    if !data.is_debug_escape(0xf8ffu32, false) { return 5 }
    if !data.is_debug_escape(0x20u32, false) { return 6 }
    if !data.is_debug_escape(0x2060u32, false) { return 7 }
    if data.is_debug_escape(0x300u32, false) { return 8 }
    if !data.is_debug_escape(0x300u32, true) { return 9 }
    if data.is_debug_escape(0x41u32, true) { return 10 }
    let lower = data.lowercase(0x130u32)
    if lower[0] != 2u32 || lower[1] != 0x69u32 || lower[2] != 0x307u32 { return 11 }
    0
}
""", encoding="utf-8")
        result = build_and_run(entry, directory)
        self.assertEqual(result.returncode, 0, result.stderr)
        (ucd / "DerivedCoreProperties.txt").write_text(
            files["DerivedCoreProperties.txt"].replace("17.0.0", "16.0.0"), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "expected a 17.0.0 UCD header"):
            unicode.read_inputs(ucd)


if __name__ == "__main__":
    COMPILER, OUTPUT = map(lambda value: Path(value).resolve(), sys.argv[1:3])
    OUTPUT.mkdir(parents=True, exist_ok=True)
    del sys.argv[1:3]
    unittest.main()
