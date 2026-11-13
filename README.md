# Mettle

An independent systems language implemented in C++20 with LLVM. V1 targets the
selected native language and library capabilities with simpler source structure, runtime parity,
faster compilation and less build-cache storage. These are acceptance goals;
runtime parity and release-platform qualification are not established.

The compiler builds Mettle programs with ownership checking, generics,
interfaces, machine/FFI facilities, native `core`/`alloc`/`std` libraries,
packages, macros, async and developer tools. The owner accepted the main-branch
stabilization batch on 2026-11-11; library delivery follows the milestone plan.
The gated compiler host and target are Linux x86-64
(native or WSL2); historical macOS evidence does not qualify that host.
See the [implementation plan](docs/process/implementation-plan.md#8-delivery-milestones)
for current obligations and revision-scoped evidence.

`bootstrap/` contains the C++ seed/reference compiler; `compiler/` contains the
Mettle implementation in progress. Packages use optional `package.mettle`
configuration and generated `lock.mettle`, with `src/main.mt` as the default
entry. Library packages declare `kind: "library"` and expose their public APIs
from that entry. See the
[package format](docs/spec/tooling-and-packages.md#1-manifest-and-identity).

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
See [commands and packages](docs/spec/tooling-and-packages.md) for other operations.

## Contributor checks

Read [CONTRIBUTING.md](CONTRIBUTING.md), the
[quality standard](docs/process/code-quality.md) and
[compiler architecture](docs/process/compiler-architecture.md).
Use focused fixtures during implementation and the required frozen-source
gates for qualification. Source cases use the existing runner:

```sh
python3 tests/source.py run BUILD/mettle OUTDIR -j 2 --filter REGEX
python3 tests/source.py fail BUILD/mettle OUTDIR -j 2 --filter REGEX
```

Library runners also accept `-j N` and `--filter REGEX` (source stems):

```sh
python3 tests/alloc.py BUILD/mettle OUTDIR tests/alloc -j 4 --filter REGEX
python3 tests/std.py BUILD/mettle OUTDIR tests/std debug -j 4 --filter REGEX
python3 tests/modules.py BUILD/mettle OUTDIR library -j 4 --filter REGEX
```

Alloc/std run both profiles unless selected explicitly. Machine/ABI cases and
profiles also run independently (`tests/backend/machine.py -j N`). Package cases
use separate worker processes, fixture copies and private caches
(`tests/packages.py COMPILER OUTDIR tests/packages [REGEX] -j N`); cold-cache and
eviction checks still run unchanged within each case. Without a filter, core
also runs its supplemental module/panic cases once.

CTest splits these suites into single-worker shards, rather than reserving all
cores for an entire suite. `METTLE_TEST_SHARDS` (default twice the logical CPU
count) controls granularity, not concurrency; it replaces the previous
`METTLE_LIBRARY_TEST_JOBS` and `METTLE_SOURCE_TEST_JOBS` settings. Use `ctest -j N`
for the global CPU/memory budget. `tools/build.py --test-jobs N` passes the same
budget (default at most four); lower it for memory-heavy or sanitized compilers.
`METTLE_TEST_CACHE_LIMIT_KIB` sets the shared suite cache budget (default 2097152,
2 GiB). Six checked interfaces alone (core/alloc/std, debug/release) occupied
794,493,268 bytes in a private baseline cache, exceeding the compiler's default
512 MiB before objects or sanitizer variants. The suite budget adds headroom;
it is not a measured full-suite working set. Package workers do not receive this
override, so cold-cache and eviction tests retain their existing budgets.
Standalone runners retain `-j N` and accept zero-based `--shard-index I
--shard-count N`. Each shard writes separate artifacts and evidence.

Running the suite quickly: checked-library interfaces and library objects are cache
entries keyed by every flag the harnesses pass (profile, overflow checks,
sanitizers, target, library path), and a cold build of `core` alone takes ~26 s,
more for `alloc` and `std`. Concurrent cold shards each rebuild them, so the
`cache.prime.*` fixture tests build `tests/cache_prime/{core,alloc,std}.mt` once per
configuration the source and library shards use before those shards start. CTest adds
them for any selected dependent test (`ctest -j 3 -R '^library\.std\.'` primes only
`std`); `-FA mettle-cache` skips them. A source case whose `flags` change the
checked-library key needs a matching `mettle_add_cache_prime` line in
`CMakeLists.txt`. Package shards assert cold caches and keep private ones. Keep the
build directory between runs: `test-cache`, `durations.json` and CTest's cost data
all make later runs faster. For one case or file, run the standalone runner with
`--filter REGEX` (or `ctest -R '^source\.run\.3$'` for one shard) instead of a suite.

Runners retain `durations.json` beside their evidence and submit previously
long-running work first; source runners can also seed estimates from existing
per-command evidence. Timing history affects order only, never selection or
pass/fail checks. CTest additionally reuses its own recorded test costs. Keep
the evidence directories between runs to retain these estimates.

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

- [Implementation and delivery gates](docs/process/implementation-plan.md)
- [Architecture](docs/process/compiler-architecture.md) and [decisions](docs/spec/decisions.md)
- [Semantic rules](docs/spec/semantic-rules.md)
- [Grammar](docs/spec/language-grammar.md)
- [Advanced contracts](docs/spec/advanced-contracts.md), [annex](docs/spec/specification-annex.md)
  and [memory model](docs/spec/memory-and-concurrency.md)
- [Library/ABI](docs/library/library-and-abi.md), [native surface](docs/library/library-surface.md)
  and [baseline mapping](docs/process/baseline-mapping.md)
- [Capability coverage](docs/process/status.md) and [I13 work](docs/process/i13-library.md)
- [Packages/tools](docs/spec/tooling-and-packages.md) and [VS Code support](tools/vscode/README.md)
- [Platforms and profiles](docs/spec/platform-contracts.md)
  and [toolchain pins](docs/toolchain-pins.json)
- [Baseline reproduction](docs/baseline/README.md) and [documentation gate](docs/process/status.md)
- [Performance protocol](docs/process/performance.md)
- [Core example expectations](examples/core/expectations.json)
  and [extended expectations](examples/spec/expectations.json)

V1 uses C++/LLVM; V1.1 is substantively self-hosted with LLVM; V1.2 uses an
independent production backend. Development subsets are not reduced V1 releases.
No project publication license has been selected; dependency licenses remain
separate.
