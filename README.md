# Mettle

An independent systems language implemented in C++20 with LLVM. V1 targets the
selected native language and library capabilities with simpler source structure, runtime parity,
faster compilation and less build-cache storage. These are acceptance goals;
runtime parity and release-platform qualification are not established.

The compiler builds Mettle programs with ownership checking, generics,
interfaces, machine/FFI facilities, native `core`/`alloc`/`std` libraries,
packages, macros, async and developer tools. Correctness repairs and library
completion remain open. The gated compiler host and target are Linux x86-64
(native or WSL2); historical macOS evidence does not qualify that host.
See the [implementation plan](docs/implementation-plan.md#8-delivery-milestones)
for current obligations and revision-scoped evidence.

`bootstrap/` contains the C++ seed/reference compiler; `compiler/` contains the
Mettle implementation in progress. Packages use optional `package.mettle`
configuration and generated `lock.mettle`, with `src/main.mt` as the default
entry for code and public APIs. See the
[package format](docs/tooling-and-packages.md#1-manifest-and-identity).

## Building the compiler

Requires Python 3.9+, curl and the pinned toolchain. Ubuntu needs
`build-essential`, `zlib1g-dev`, `libzstd-dev` and `libxml2-dev`. Under WSL2,
keep the checkout in the Linux filesystem rather than `/mnt/c` or `/mnt/d`.

```sh
python3 tools/bootstrap.py
python3 tools/build.py --configuration Debug
python3 tools/build.py --configuration Release
```

Bootstrap installs checksum-pinned tools in ignored `.tools/`; it refuses to
overwrite unknown installations. `build.py` builds, runs CTest and compares a
second clean build in the same environment. Commands, hashes and results are
recorded in `build/<platform>/<configuration>/foundation-evidence.json`.
Use a fresh build directory when the compiler version changes.

For an incremental Linux build:

```sh
P=$PWD/.tools/linux-x86_64
$P/cmake/bin/cmake -S . -B build/linux-x86_64/Release -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=$P/llvm/bin/clang \
  -DCMAKE_CXX_COMPILER=$P/llvm/bin/clang++ -DCMAKE_MAKE_PROGRAM=$P/ninja/ninja \
  -DLLVM_DIR=$P/llvm/lib/cmake/llvm -DBUILD_TESTING=ON
$P/cmake/bin/cmake --build build/linux-x86_64/Release
```

The pinned Linux LLVM archives use ThinLTO; subsequent links reuse
`build/linux-x86_64/llvm-thinlto-cache/`. macOS builds additionally require
the Command Line Tools SDK and zstd development library.

## Using the compiler

```sh
build/linux-x86_64/Release/mettle check examples/core/control-flow.mt
build/linux-x86_64/Release/mettle build examples/core/control-flow.mt -o build/count
./build/count
build/linux-x86_64/Release/mettle build tests/packages/path-dependency/app \
  -o build/app --locked
```

Hosted entry functions return `i32`, explicitly or by body inference.
`--profile debug` checks ordinary integer overflow; `release` wraps it and
optimizes output. Division/remainder failure checks stay enabled in both.
`--overflow-checks on|off` overrides ordinary overflow policy.
`--emit object|llvm|ir` selects non-executable output; executables require the
compiler's runtime target. `--library-dir DIR` selects native library sources.
See [commands and packages](docs/tooling-and-packages.md) for other operations.

## Contributor checks

Read [CONTRIBUTING.md](CONTRIBUTING.md), the
[quality standard](docs/code-quality.md) and
[compiler architecture](docs/compiler-architecture.md).
Use focused fixtures during implementation and the required frozen-source
gates for qualification. Source cases use the existing runner:

```sh
python3 tests/source.py run BUILD/mettle OUTDIR -j 2 --filter REGEX
python3 tests/source.py fail BUILD/mettle OUTDIR -j 2 --filter REGEX
```

For cross-target Linux execution from an ARM Mac, the optional runner needs
Lima, QEMU and Lima's x86-64 guest agents:

```sh
python3 tools/bootstrap.py --platform linux-x86_64
export LIMA_HOME="$PWD/.tools/lima"
limactl --tty=false start --name=mettle-linux-x64 --mount-only="$PWD:w" \
  --timeout=10m tools/linux-vm.yaml
python3 tools/test_linux_target.py --source --libraries
limactl --tty=false stop mettle-linux-x64
```

This checks target execution under emulation, not Linux-host qualification or
performance. Stop the VM after dependent work.

## Selected source syntax

```text
fn double(value: i32): i32 { value * 2 }
fn inferred_double(value: i32) { value * 2 }
fn completed(): Unit { () }
```

Result inference uses the body, not callers. Callable types and bodyless
declarations require explicit results. `Unit` has value `()`; `Never` has no
values. Use `let _ = expression` for intentional discards.

## Planning map

- [Implementation and delivery gates](docs/implementation-plan.md)
- [Architecture](docs/compiler-architecture.md) and [decisions](docs/decisions.md)
- [Core semantics](docs/core-semantics.md) and [detailed rules](docs/semantic-rules.md)
- [Core grammar](docs/core-grammar.md) and [full grammar](docs/language-grammar.md)
- [Advanced contracts](docs/advanced-contracts.md), [annex](docs/specification-annex.md)
  and [memory model](docs/memory-and-concurrency.md)
- [Library/ABI](docs/library-and-abi.md), [native surface](docs/library-surface.md)
  and [baseline mapping](docs/baseline-mapping.md)
- [Capability coverage](docs/capability-coverage.md) and [I13 work](docs/i13-library.md)
- [Packages/tools](docs/tooling-and-packages.md) and [VS Code support](tools/vscode/README.md)
- [Platforms](docs/platform-contracts.md), [profiles](docs/reference-profiles.md)
  and [toolchain pins](docs/toolchain-pins.json)
- [Baseline reproduction](docs/baseline/README.md) and [documentation gate](docs/specification-status.md)
- [Performance protocol](docs/performance.md) and [adoption rationale](docs/adoption-rationale.md)
- [Core example expectations](examples/core/expectations.json)
  and [extended expectations](examples/spec/expectations.json)

V1 uses C++/LLVM; V1.1 is substantively self-hosted with LLVM; V1.2 uses an
independent production backend. Development subsets are not reduced V1 releases.
No project publication license has been selected; dependency licenses remain
separate.
