# Contributing to Mettle

The [code quality standard](docs/code-quality.md) is normative.
The [compiler architecture](docs/compiler-architecture.md) defines responsibilities,
representations and future feature placement. CMake declares the current
component targets and dependencies.
The [language specifications](docs/core-semantics.md) define behavior;
implementation convenience does not override them.

For milestone work, follow the
[execution gates](AGENTS.md#milestone-execution-gates): inventory the complete
scope before compiler edits, batch shared-interface changes, and separate
focused implementation checks from frozen-source qualification.

Until self-hosting (I15), limit C++ compiler changes to what V1 requires; see
the [C++ compiler scope](docs/implementation-plan.md#8-delivery-milestones).

## Local checks

Run from the project root with the selected local toolchain installed:

```sh
cmake --build build/linux-x86_64/Debug
ctest --test-dir build/linux-x86_64/Debug --output-on-failure
```

Format C++ with the pinned `clang-format`. CMake builds independent component
targets with explicit link dependencies.

For a new build configuration use the existing reproducibility workflow:

```sh
python3 tools/build.py --configuration Debug --quality
python3 tools/build.py --configuration Release
python3 tools/build.py --configuration Debug --sanitizers
```

`--quality` replaces the standalone CTest step with the build-directory quality
gate, which includes CTest. This runs each configuration's tests once while
retaining static analysis and clean-rebuild reproducibility checks.
Run full static analysis in the selected build configuration; additionally use
`--quality` for another configuration when its changed compiler definitions or
sources require separate analysis, rather than repeating identical analysis.

The selected LLVM 22.1.3 replaces 21.1.8 to resolve the Darwin sanitizer
startup failure. The instrumented corpus and both detector probes pass; see the
[compatibility decision](docs/code-quality.md#5-unsafe-memory-and-concurrency).
Do not silently substitute runtimes or disable instrumentation.

The gated compiler host is Linux x86-64 from 2026-11-08 (owner decision;
implementation-plan section 8.0). Earlier closures were qualified on a macOS
ARM64 host; their evidence does not establish Linux compiler-host
qualification until LNX completes.

Cross-target/backend changes also require the existing Linux source runner:

```sh
python3 tools/test_linux_target.py --source
```

Start the dedicated VM first and stop it after dependent work; see the
[README](README.md) for the complete runner commands.

## Change checklist

Tests follow the [conventional compiler categories](docs/code-quality.md#6-diagnostics-and-behavioral-tests):
source compile/run pass/fail cases, diagnostics, focused algorithm unit tests
and applicable codegen/link/ABI or library tests. Use the existing CTest/Python
and C++ runners. Do not create a framework or a new directory hierarchy merely
to resemble Rust; every additional test must guard meaningful behavior.

- Explain the problem, changed behavior and affected compiler/library boundary.
- Include a regression that fails without the fix and tests the relevant edge.
- Record commands, configuration, target and actual results; identify skipped,
  unimplemented or unqualified work explicitly.
- Update affected specifications/examples when changing a contract.
- Check safety, cleanup, evaluation order, arithmetic policy and compatibility.
- Keep generated baseline data separate from authored/native implementation.
  Regenerate only through its mapping/audit logic; preserve reference provenance.
- Do not claim runtime parity from the engineering P01 experiment.

There is no selected project publication license and no hosted CI service is
configured by these instructions. No contribution instruction authorizes
publication, a license selection, or repository/registry access changes.
