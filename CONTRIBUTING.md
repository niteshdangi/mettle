# Contributing to Mettle

The [code quality standard](docs/process/code-quality.md) is normative.
The [compiler architecture](docs/process/compiler-architecture.md) defines responsibilities,
representations and future feature placement. CMake declares the current
component targets and dependencies.
The [language specifications](docs/spec/semantic-rules.md) define behavior;
implementation convenience does not override them.

Batch dependent shared-interface changes coherently and run focused checks for
the affected behavior. Until substantive self-hosting, limit C++ compiler changes
to V1-required features, correctness/soundness fixes and measured performance work.

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
The [quality standard](docs/process/code-quality.md#5-unsafe-memory-and-concurrency)
owns sanitizer requirements and the toolchain compatibility decision.
The gated compiler host and target are Linux x86-64, native or WSL2.
Historical macOS results do not qualify a Linux host.

Cross-target/backend changes also require the existing Linux source runner:

```sh
python3 tools/test_linux_target.py --source
```

Start the dedicated VM first and stop it after dependent work; see the
[README](README.md) for the complete runner commands.

## Changes

Use existing runners and the
[compiler test categories](docs/process/code-quality.md#6-diagnostics-and-behavioral-tests);
each regression must guard meaningful behavior.

- Explain the problem, changed behavior and affected compiler/library boundary.
- Include a regression that fails without the fix and tests the relevant edge.
- Record commands, configuration, target and actual results; identify skipped,
  unimplemented or unqualified work explicitly.
- Update affected specifications/examples when changing a contract.
- Check safety, cleanup, evaluation order, arithmetic policy and compatibility.

There is no selected project publication license and no hosted CI service is
configured by these instructions. No contribution instruction authorizes
publication, a license selection, or repository/registry access changes.
