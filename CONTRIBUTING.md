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

`--quality` includes CTest, static analysis and clean-rebuild checks; do not
also run standalone CTest. Repeat static analysis in another configuration only
when its changed definitions or sources require it.
The [quality standard](docs/code-quality.md#5-unsafe-memory-and-concurrency)
owns sanitizer requirements and the toolchain compatibility decision.
The Linux host qualification gate and historical macOS evidence scopes are in
[implementation-plan section 8.0](docs/implementation-plan.md).

Cross-target/backend changes also require the existing Linux source runner:

```sh
python3 tools/test_linux_target.py --source
```

Start the dedicated VM first and stop it after dependent work; see the
[README](README.md) for the complete runner commands.

## Change checklist

Use existing runners and the
[compiler test categories](docs/code-quality.md#6-diagnostics-and-behavioral-tests);
each regression must guard meaningful behavior.

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
