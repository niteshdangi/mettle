# Mettle

An independent systems language targeting Rust-level capabilities with simpler
source structure and measured runtime parity. Mettle must not read like a Rust
copy: it aims for better readability, runtime at least equal to Rust, faster
compilation and less build-cache storage (decisions D16-D17).

Status: correctness repairs are in progress after the `c485aa1` re-review.
Historical green gates missed confirmed crashes, soundness/ABI defects and
validation gaps; they are not current completion approval. The recorded scope is
macOS ARM64 compiler-host / Linux x86-64 target execution. The compiler checks and builds
Mettle programs with functions, result inference and control
flow. I03 includes concrete products, projected initialization and
moves, stored/returned views, receiver borrowing and native destructor/unwind
cleanup. Native `core`, `alloc` and hosted `std` libraries (I/O, files, paths,
processes, networking, threads and synchronization) exist in initial form; a
package manager, macros/derives, async and release-qualified targets remain
later work. No Rust-runtime parity
is claimed.
I04 adds multi-file modules/imports/reexports/visibility,
transparent aliases, concrete enums and ownership-sensitive patterns, nested
optionals/outcomes, typed propagation/capture, defaults/custom constructors,
tuples/fixed arrays, integer ranges/iteration, scalar/byte literals and labeled
value-producing loops.
I05 adds declaration-checked type/const generics and specialization, interfaces
and associated families, coherence, named/higher-ranked regions, operators,
receiver projections, closures/function pointers, slices, borrowed erased
dispatch and opaque returns. I05 qualification passed on 2026-10-29:
Debug/Release 14/14 CTest suites each, ASan/UBSan 15/15, static analysis and
byte-identical clean rebuilds, plus 632 Linux source/profile cases and twelve
cleanup cases. The aggregate receipt is `build/i05-qualification.json`; the
[implementation plan](docs/implementation-plan.md) records its scope and limits.
This is not release-platform qualification or a Rust-runtime parity claim.

I06's implemented initial machine boundary includes
wide integers/floats, raw pointers and memory operations, manual/uninitialized
storage, interior mutability, inline pinning, atomics, C layout/calls and
freestanding object emission. Combined C/integer enum representations,
transparent enum/payload ABI forwarding and unions pass native and target probes.
Packed-field destruction relocates to aligned unwind-frame storage. Full-width
constant composition, checked conversions, explicit floating policies, safe
Cell/RefCell guards, conditional Unpin, statics/linkage and physical-entry
variadic definitions are integrated. Inline/global/naked assembly and initial
architecture-specific SIMD/feature dispatch are also integrated. Historical I06 gates
passed on 2026-10-29 but the completion claim is reopened. Those receipts record
Debug coverage through a documented focused
continuation, Release 16/16 CTest suites, ASan/UBSan 17/17, selected static analysis
and byte-identical clean rebuilds, plus 1,240 Linux source/profile cases and twelve
cleanup cases. The aggregate receipt is `build/i06-qualification.json`.
This is initial-profile qualification, not I13's complete per-operation/profile
closure, Linux compiler-host qualification or a runtime-parity claim.
I05 receipts remain unchanged historical evidence.

## Contributor quality gate

The [compiler architecture](docs/compiler-architecture.md) defines component
responsibilities, phase-owned representations and the full-language growth map.
`compiler/modules.json` drives independent CMake targets and enforces source
ownership, public headers and a dependency DAG. Future responsibilities are
specified without pretending the corresponding features are implemented.

Read [CONTRIBUTING.md](CONTRIBUTING.md) and the
[compiler/library standard](docs/code-quality.md) before changing the implementation.

```sh
python3 tools/check_quality.py
python3 tools/check_quality.py --build-dir build/macos-arm64/Debug
```

Pinned formatting, safety-focused static analysis, warnings-as-errors and
behavioral tests are required as applicable. A separate
`python3 tools/build.py --configuration Debug --sanitizers` build instruments
project C++ with ASan/UBSan. These checks do not prove a safety model or replace
target execution/reproducibility gates.

## Building the compiler

From this directory, using Python 3.9+ and curl. The native macOS ARM64 build is
validated; full Ubuntu x86-64 compiler-host linking remains unverified.
macOS also needs the Command Line Tools SDK and zstd development library.
Ubuntu needs `build-essential`, `zlib1g-dev`, `libzstd-dev` and `libxml2-dev`;
the optional VM provisions these automatically:

```sh
python3 tools/bootstrap.py
python3 tools/build.py --configuration Debug
python3 tools/build.py --configuration Release
```

The bootstrap installs checksum-pinned tools into ignored `.tools/`, without
replacing system compilers. The build script configures CMake/Ninja, performs a clean build, runs CTest,
then requires a second clean build to have byte-identical compiler artifacts in the same
environment. Logs, source/tool/sysroot hashes, commands and results remain under
`build/<platform>/<configuration>/foundation-evidence.json`. This is not a
cross-machine hermetic-build or release reproducibility claim.
The Linux LLVM archives contain ThinLTO bitcode. Their first native link can be
slow under emulation; subsequent links reuse the ignored, content-keyed
`build/linux-x86_64/llvm-thinlto-cache/` dependency cache.

LLVM/Clang/LLD/compiler-rt are pinned together to 22.1.3 to fix Darwin sanitizer
startup with the former 21.1.8 runtime. CMake/Ninja versions are unchanged.
Existing installations must preserve the old `.tools/<platform>/llvm` cache
under a versioned name before bootstrapping the new selection; the bootstrap
deliberately refuses to overwrite an unrecognized cache. Use a fresh CMake
build directory when the compiler version changes. The superseded LLVM 21.1.8
tools and their `-llvm21` builds were retired on 2026-10-30 after an audit
found no remaining consumers.
See the [compatibility record](docs/code-quality.md#5-unsafe-memory-and-concurrency).

The three foundation checks retain their constructed-LLVM smoke test. Four
source suites additionally compile actual Mettle programs, execute native code,
check arithmetic traps/wrapping, and reject invalid or unsupported source.
Evidence and retained programs live under each build's `scalar-evidence/`.
Runtime and native cleanup integration suites additionally check exact drop
traces, unwinding, replacement restoration and double-panic abort.

```sh
build/macos-arm64/Debug/mettle check examples/core/control-flow.mt
build/macos-arm64/Debug/mettle build examples/core/control-flow.mt -o build/count
./build/count
```

A directory with a `Mettle.toml` builds as a package (dependencies, features,
`Mettle.lock`; see `docs/tooling-and-packages.md`):

```sh
build/macos-arm64/Debug/mettle build tests/packages/path-dependency/app -o build/app --locked
```

The example returns process status 0 on success. Hosted programs can print
through `std::io` (see `tests/std/`).
`--profile debug` checks integer overflow; `--profile release` wraps ordinary
overflow and optimizes object/executable output. Division/remainder failure
checks remain enabled in both. `--overflow-checks on|off` overrides that policy.
`--emit object|llvm|ir` selects an object, pre-optimization LLVM or compiler-owned
CFG instead of an executable. `tokens` and `syntax` expose lossless token text
and span-bearing syntax as prototype JSON. These inspection formats are not
stable tooling APIs.

The default target is the host architecture; on macOS ARM64 it is
`arm64-apple-macosx15.0` (CMake `METTLE_MACOS_DEPLOYMENT_TARGET`, the macOS 15
baseline shared by emitted objects, the runtime and the link), not the host
kernel version. `--emit executable` requires that runtime target and is
rejected before code generation otherwise; use `--emit object` for another
supported target. The module data layout comes from the LLVM target machine,
and the compiler checks that its own scalar/pointer layout agrees with it.
Output is written to a temporary file beside `-o` and renamed only on success,
so an unwritable or missing output location reports `error[io]` and leaves no
partial file.

The compiler supports concrete methods with read/mut/take receivers, eligible
two-phase mutable receivers, `drop { ... }`, first-class read/mut views and basic
region declarations/result-source contracts. Generic bodies are checked before
specialization; a Copy instantiation cannot grant undeclared ownership rights.
Slice views expose `len()` using element-count metadata; erased slice receivers
retain that metadata, and opaque values expose only
declared bounds. Erasing a witness-metadata implementor itself still needs an
explicit sized adapter; structural tail unsizing and interface upcasts are
supported. Owning library handles and the remaining numeric/foreign-machine
surface remain later milestones. This is
not a reduction of the full V1 specification.

```sh
build/macos-arm64/Debug/mettle build examples/core/values.mt -o build/values
./build/values
```

Named product types have compilation-owned nominal identities, not LLVM type
identities. Checked syntax and CFG share an immutable type-store owner.
Copy eligibility, duplicate fields, recursive by-value layouts and constructor
arguments are checked before emission. Projected-place analysis checks partial
initialization, partial moves/reinitialization, immutable assignment and conflicting
live loans before LLVM lowering. Origin analysis follows copied/stored views,
returned source dependencies and view-storage writes through calls/destructors.
Direct borrowed initializers extend their owning temporary to the binding block;
ordinary calls do not extend temporary lifetimes.

Loops use the selected `label name` syntax. Unlabeled control targets the nearest
loop; labels are lexical and select the nearest matching enclosing loop.
`loop` joins its break value types, while `while` remains `Unit`:

```text
fn answer() {
    label done: loop {
        loop { break label done 42 }
    }
}
```

`continue label name` cleans up the exited scopes before restarting its target.
Break values finish evaluation before scope cleanup; owned results remain
protected during that cleanup and transfer once to the loop result.

Aliases preserve the underlying type's nominal identity, Copy eligibility, view
access and cleanup behavior. Forward alias references resolve before bodies;
cycles diagnose. Static functions have no implicit `self`:

```text
alias Coordinate = Point
copy type Point {
    x: i32
    static fn make(x: i32): Self { Self(x) }
}
fn main() { if Coordinate::make(42).x == 42 { 0 } else { 1 } }
```

`Type::method(receiver, arguments)` also supports an explicit receiver using its
declared access mode. Only object-style eligible mutable receivers receive the
two-phase reservation behavior; qualifying an ordinary call does not weaken it.

The private native panic runtime uses C++ unwinding and compiler-owned cleanup
plans with per-frame initialization flags. It is not a per-object runtime registry.
Checked-IR catch probes establish replacement recovery; source panic-catching APIs,
generic payloads, C-unwind interoperability and freestanding support remain later
milestones, not additional source syntax.

Typed failure is separate: `throws Error` stays explicit, `try` propagates only
that declared error, and `capture` produces an ordinary success/failure outcome
without catching panic. Matching retains alternative identity even when both
payload types are equal. `none`, `present`, `??` and optional chaining preserve
nested presence and skip unselected operands.

Defaults are checked in declaration scope, including unused defaults. Supplied
arguments evaluate in source order before omitted defaults in parameter order.
Custom `init` replaces generated construction, establishes every field on success,
and cleans initialized fields without invoking the unestablished whole-value
destructor on failure. Fixed-array rest bindings preserve disjoint borrowed
subarrays; consuming matches transfer only selected initialized fields.

```sh
build/macos-arm64/Debug/mettle build examples/core/ownership.mt -o build/ownership
./build/ownership
```

For Linux execution on an ARM Mac, the optional isolated runner requires Lima,
QEMU and Lima's additional x86-64 guest agents. It mounts this project, not the
host home directory:

```sh
python3 tools/bootstrap.py --platform linux-x86_64
export LIMA_HOME="$PWD/.tools/lima"
limactl --tty=false start --name=mettle-linux-x64 --mount-only="$PWD:w" --timeout=10m tools/linux-vm.yaml
python3 tools/test_linux_target.py --source --libraries
limactl --tty=false stop mettle-linux-x64
```

The VM image is digest-pinned Ubuntu 24.04 AMD64. Guest packages are recorded in
build evidence rather than claimed to be an immutable apt repository. Execution
uses an actual Linux kernel under x86-64 emulation, not native x86 hardware or
valid performance-comparison evidence.
The target test uses the verified macOS Debug/Release object emitters and scalar
compilers, then the pinned Linux Clang/LLD and Linux kernel. Its evidence is retained under
`build/linux-target/`; it does not claim that a Linux-hosted LLVM compiler was
built. An earlier emulated full compiler-host link was interrupted when its VM
was killed before completing.

Ordinary builds register twelve CTest suites; ASan/UBSan adds a thirteenth suite
with actual sanitizer detector probes. Per compiler build, the source suites retain run-pass, compile-fail,
arithmetic/profile and syntax/inspection cases with their actual counts/commands
in the evidence receipts. The Linux runner additionally links and executes selected source cases
across both compiler builds and source profiles, both foundation smokes and the
native cleanup/recovery probes.
The component-boundary suite additionally checks parsed/checked data ownership,
in-memory compilation, malformed IR, SSA and independent initialization analysis.
At I03 closure, Debug/Release passed all twelve suites and ASan/UBSan all thirteen,
with byte-identical clean rebuilds. Each compiler build executed 112 run-pass profile
cases, rejects 104 invalid programs, and checks 24 arithmetic/profile cases.
Linux execution passed 134 source/profile cases and six native cleanup probes per
ordinary compiler configuration, plus both foundation smokes. Evidence is retained
under the build/quality/target paths above; the dedicated VM is stopped.
That gate qualifies I03's concrete ownership subset, not generic ownership, source
panic-catching APIs, a Linux compiler host or a release platform.
The source suites now additionally cover I04 modules, sums, effects, defaults,
constructors, literals, patterns and aggregate/control-flow composition;
their revision-bound receipts contain the current counts and target results.
The Linux runner also executes external multi-file module fixtures. I04's native
gate passes fourteen ordinary suites and fifteen under ASan/UBSan, with
byte-identical clean rebuilds; current quality/target receipts complete the
revision-specific qualification record.

## Selected source syntax

These function forms are accepted by the scalar compiler; a buildable hosted
file also needs `fn main(): i32` or an inferred i32 entry result:

```text
fn double(value: i32): i32 {
    value * 2
}

fn inferred_double(value: i32) {
    value * 2
}

fn completed(): Unit {
    ()
}
```

An optional `: Type` declares a checked result; omission infers from body returns
and tail values, not from callers. `Unit` is the type and `()` its sole value.
`Never` names the type with no values, used for non-returning results.
Prefer `let _ = expression` to make intentional non-Unit discards explicit.
Callable types and bodyless declarations require explicit results. Parameter
types, error effects and ambiguous borrow-source contracts stay explicit.
The compiler does not yet implement callable types or bodyless interface/foreign
declarations; those contracts remain requirements for later milestones.

An early integer-reduction experiment is available with an installed Rust
compiler as an optional comparator:

```sh
python3 tools/run_p01.py --compiler build/macos-arm64/Release/mettle
```

It records paired process timings, compiler time/memory and source/binary hashes
under `build/p01/`. It is one uncontrolled engineering session, not the registered
pilot or release protocol. The installed comparator may differ from frozen
Rust 1.99.1; its actual version and that mismatch are recorded.

## Planning map

- [Adoption rationale](docs/adoption-rationale.md): documented problems,
  existing alternatives, and the new-language justification test.
- [Core semantics](docs/core-semantics.md): ownership and execution rules.
- [Semantic rules](docs/semantic-rules.md): typing/state judgments, arithmetic,
  loans, region variance, temporary scopes and unwind restoration.
- [Core grammar](docs/core-grammar.md): initial syntax subset and limitations.
- [Extended grammar](docs/language-grammar.md): working full-language forms.
- [Advanced contracts](docs/advanced-contracts.md): pinning, async scope
  containment, compile-time execution and macros.
- [Specification annex](docs/specification-annex.md): numeric conversions,
  higher-ranked solving, closure destruction, macros, attributes and assembly.
- [Memory and concurrency](docs/memory-and-concurrency.md): validity, provenance,
  aliasing, atomics and poll-scoped borrowed-task execution.
- [Examples](examples/core/expectations.json): full core expectations; the
  I02 scalar corpus in `tests/scalars.py` is qualified separately.
- [Extended examples](examples/spec/expectations.json): optional/outcome and
  method/default-argument composition.
- [Capability coverage](docs/capability-coverage.md): baseline inventory method
  and [tracking matrix](docs/capabilities.csv).
- [Native baseline mapping](docs/baseline-mapping.md): contract-preserving
  translation rules and explicit native replacements.
- Native libraries live in [library/](library/) (`core`, `alloc`, `std`); the
  compiler mounts a root on demand when a program names it, `--library-dir`
  selects another tree, and text literals use `core::text::Text`. Core names (`Text`, `Iterator`,
  `panic`, ...) and `String` come from an implicit lowest-priority prelude.
  `alloc` provides collections, `String`, `Box`/`Rc`/`Arc`; `std` provides
  hosted I/O, filesystem, process, environment, time, networking and threads.
- [Native library surface](docs/library-surface.md): per-signature translation
  rules, derives/compiler facilities, unsized types and foreign completion.
- [Reproducible baseline audit](docs/baseline/README.md): verified source/docs
  inputs, complete archived operation inventory and validation boundaries.
- [Toolchain source pins](docs/toolchain-pins.json): immutable upstream source
  identities and the separate binary archive/build-evidence policy.
- [Implementation plan](docs/implementation-plan.md): dependency-ordered
  milestones, compiler boundaries, and first executable-core exit criteria.
- [Delivery milestones](docs/implementation-plan.md#8-delivery-milestones):
  fourteen gates to V1, then self-hosting and the independent backend.
- [Packages and development tools](docs/tooling-and-packages.md): manifests,
  resolution/locks, build inputs, tests/doctests, editors and debugging.
- [Platform and runtime contracts](docs/platform-contracts.md): target profiles
  and feature-specific design gates.
- [Reference profiles](docs/reference-profiles.md): selected deployment/SDK,
  CPU/ABI, linker, Wasm and freestanding reference environments.
- [Library and ABI](docs/library-and-abi.md): ownership-bearing APIs, storage,
  foreign calls, package contracts and target lock schema.
- [Performance protocol](docs/performance.md): Rust comparison and runtime gate.
- [Decision register](docs/decisions.md): accepted choices and unresolved work.
- [Documentation gate](docs/specification-status.md): current coverage and
  completion checks, evidence and separate implementation/product gates.

V1 is the full agreed capability release, implemented in C++ using LLVM.
V1.1 is substantively self-hosted using LLVM. V1.2 uses Mettle's own production
backend. Development subsets are not reduced V1 releases.

No license has been selected. This repository does not yet grant a project
open-source license. Dependency licenses remain separate.
