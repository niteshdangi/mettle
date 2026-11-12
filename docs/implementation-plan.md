# Compiler implementation plan

Gated profile: `linux-x64` from 2026-11-08 (owner decision). LNX (section 8.0)
precedes further I13 area closure. Earlier macOS ARM64/Darwin evidence does not
transfer to a Linux compiler host.

I01-I06 are closed within their recorded scopes; I06 re-review `c485aa1` was
repaired/requalified at `ff1daa3`. I07-I12 closed on macOS ARM64/Darwin
2026-10-31 (closure commit parent `c6fe28c`): Release CTest 24/24, both source
suites, emitted ASan owner/collection/async and TSan thread/sync/async cases.
Owner moves: S003 pinned owners to I13; I09 front-end dependency separation and
compile/storage measurements, P08/P09/P10 to I14. I13's capability inventory is
not V1 operation qualification; eighteen library areas remain partial. I14-I17
implementation/qualification are not started. I17's 2026-11-09 inventory
reconciliation is recorded in [post-v1-worklist.md](post-v1-worklist.md);
source-cfg and native-state review remain open. Standalone operation
specification migration is partial: [native contract assignments](baseline-mapping.md#7-native-operation-authority)
own their listed operations and retain explicit fallback for unassigned contracts.
This changes documentation authority, not implementation/qualification status.
Per-item scope and outstanding work follow.

## 1. Development phases

| Phase | Deliverable | Exit evidence |
| --- | --- | --- |
| M0 | Grammar/semantic closure for first subset | Separator cases, typing rules and ownership examples have unambiguous expected outcomes |
| M1 | Lexer, lossless tree, resolution, scalar checker, executable scalar subset | Scalar program produces exit status; syntax/type negatives fail with source spans |
| M2 | Product values, access modes, initialization, borrows, drop elaboration | Ownership corpus accepts/rejects correctly; cleanup traces agree on exceptional edges supported by the subset |
| M3 | Generic core, modules, containers, text, outcomes, interfaces and C integration | CLI/parser/collection programs and C ABI probes run end to end |
| M4 | Constants, macros, packages, incremental builds and harnesses | Build-input invalidation, cross-package instantiation and reproducible diagnostics |
| M5 | Unsafe model, concurrency, async, pinning, no-OS operation | Memory-model and cancellation counterexamples; stress and target probes |
| M6 | Complete inventory, supported profiles, libraries and user tooling | Every committed capability has evidence; release and performance gates pass |

M0-M6 are development phases, not V1 versions. Some work can overlap, but a
dependent feature cannot claim correctness before its prerequisite contract.
V1 includes every agreed baseline capability. V1.1 and V1.2 retain the blueprint's
self-hosting and own-backend requirements; neither has a calendar estimate.

M0's documentation gate is closed; I01's foundation gate has passed.
The delivery milestones in section 8 subdivide these phases without renumbering
the capability register's existing M1-M6 references. Those references identify
earliest development phases, not release/completion claims.

## 2. First executable milestone

Target: Linux x86-64 hosted, single file, no dependencies or heap. Begin with i32,
bool, `Unit`/`()`, `Never`, local let/var and explicit discard, arithmetic,
comparisons, short circuit,
explicit parameter types, optional `: Type` results and body-based result
inference, calls, blocks, if, while, return, and main exit status.
The first observable artifact is a native executable, not an LLVM IR screenshot.

M1 does not pretend to validate resources: products, ownership modes, generics,
closures, user destructors, stored views, or async are diagnosed as unsupported
until their phase. Such diagnostics mean compiler incompleteness, not invalid
Mettle language. Do not silently reinterpret them as scalar operations.

For M1, use aborting arithmetic panic paths; unwinding and catch are not required
to establish scalar execution and remain explicit later obligations. Both profile
overflow modes must behave as specified for the supported integer operations.
Avoid claiming the complete arithmetic matrix until every operation is
covered. Do not allow divide-by-zero or signed division overflow to become LLVM UB.

M1 exit:

- Deterministic tokenization and parsing, including malformed/incomplete input.
- Separate syntax, name, type, and internal-compiler diagnostics.
- Scalar functions and branch/loop control flow lower and execute correctly.
- Appropriate development/release arithmetic behavior and side-effect order.
- Debug and optimized code give equivalent defined results.
- Program source, command, target, compiler version, and exit status are captured.
- Unsupported core fixture features fail explicitly; no false success totals.

The full existing core fixture set becomes the M2/M3 acceptance input as product,
ownership, and generic checking arrive. Add a smaller scalar fixture at M1 rather
than weakening existing examples to make an early compiler appear complete.

## 3. Repository boundaries

[compiler-architecture.md](compiler-architecture.md) owns components, phase
representations and future placement; CMake owns actual targets/dependencies and
discovers their sources. Create components with implementations, not empty
markers. The architecture correction gate precedes I03. Use typed internal
APIs, not separate services/processes; public extension APIs stay distinct from
unstable internals. Internal validator failures are compiler defects.

## 4. IR contracts

Compiler-architecture.md sections 2-4 own representation invariants and phase
admission. Initial operations: constants, projection, load/copy, move, borrow,
initialize/replace, call, branch, return and cleanup. Add exceptional successors
before resource unwind. Preserve addressable places/cleanup through SSA lowering;
LLVM types cannot define language semantics. Establish correctness/end-to-end
execution before an elaborate optimizer.

## 5. Toolchain and build decisions

Select C++20, CMake, Ninja, and Clang for the initial implementation workflow.
Use ordinary CTest orchestration plus fixture-driven compiler/runtime tests.
Avoid adding a third-party test framework until a concrete testing need warrants
it. C++ implementation choices do not leak into Mettle source contracts.

LLVM is the production backend through V1.1. toolchain-pins.json selects exact
upstream source identities and reference-profiles.md selects target environments.
Before the first backend build, capture installed artifact hashes and perform
object/link/debug probes. Source selection is fixed; joint build compatibility
and platform execution are not claimed before those probes.

Use checksum-pinned project-local tools, not host substitutes. A Linux kernel
runner must link/execute cross-emitted ELF; macOS emission alone does not
qualify Linux execution or a Linux-hosted compiler. Lima/QEMU guest agents are
runner dependencies, not compiler dependencies. Rust is optional comparison/
interop tooling, never an ordinary compiler prerequisite.

Current foundation workflow, from the project root:

```text
python3 tools/bootstrap.py
python3 tools/build.py --configuration Debug
python3 tools/build.py --configuration Release
```

The script selects the locked tools, invokes CMake/Ninja/CTest, records installed
tool and SDK/sysroot hashes, and checks a same-environment clean rebuild.
See the README for isolated Linux execution and evidence locations. Emulation
establishes execution, not native-hardware performance or release qualification.

## 6. Validation strategy

Use fixture manifests with accept/reject category and relevant diagnostics, not
fragile whole-output snapshots for every test. Compare runtime results and
ordered cleanup traces. Add source-span checks where diagnostics are the feature.

Parser testing covers tokens, operator prefixes, parentheses/tuples, generic
closing angles, newline continuations, comments, tail expressions, and recovery.
Result tests cover explicit/inferred colon results, Unit type versus unit value,
Never/diverging paths, explicit discard, conflicting returns, unresolved recursion
and independence from call-site types.
Ownership testing covers branch joins, loops, partial initialization, reborrows,
explicit consumption, and indirect calls. Unsafe/runtime tests need sanitizers
and independent model checks where applicable.

Differential tests must translate equivalent semantics, not copy Mettle's
borrow-by-default spelling into Rust by-value arguments. A reference interpreter
must be independently specified rather than another path through the same buggy
lowering. Shared assumptions remain limitations even when both outputs agree.

## 7. Start gate

The technical minimum for a lexer/parser prototype is determinate grammar cases,
but the user selected a stronger project gate: finish documentation before
implementation, not on the strength of the subset alone.
`specification-status.md` defines the documentation completion evidence and its
limits. That gate has closed and the user authorized I01 implementation; source/build
files are now permitted. Documentation validation
excludes tool caches and build output without relaxing the frozen API audit.

Borrow checking and resource lowering must wait for precise CFG/loan/drop
contracts. Unwind recovery, borrowed spawned tasks, and strong backend aliasing
metadata must wait for their soundness-critical rules.

Before external source publication/distribution, resolve the project license.
No release date, staffing commitment, package installation, repository publishing,
or CI infrastructure purchase is implied by this plan.

## 8. Delivery milestones

Completion requires an executable/inspectable artifact, positive/negative
checks and retained evidence, not directories, unchecked LLVM, API mappings or
line counts. Historical receipts qualify only their recorded inputs/profiles.

C++ compiler scope until I15 (owner decision, 2026-10-31): the C++ compiler is
the bootstrap and reference implementation for the self-hosted compiler, not a
long-term product. Until I15, change it only for what a V1 milestone (I07-I14)
requires: language features and diagnostics selected for V1, correctness and
soundness fixes, and changes needed to pass a measured I14 gate. Do not spend
effort on C++-only performance tuning, internal refactors, architectural
rework or tooling polish beyond those requirements; record such ideas for the
Mettle implementation instead. Library work (`library/`) is unaffected because
the self-hosted compiler reuses it. I16's LLVM-free backend is written in
Mettle, not C++.

| ID | Milestone | Exit artifact / decisive check | Prerequisites |
| --- | --- | --- | --- |
| I01 | Reproducible compiler foundation | Pinned C++/LLVM build, CTest fixture harness and an object/link/run smoke test on actual Linux x86-64 | Documentation gate |
| I02 | First executable Mettle programs | `.mt` scalar programs compile, link and execute; invalid syntax/names/types fail at the right phase | I01 |
| I03 | Ownership and resource cleanup | Products, access modes, moves/Copy, loans and destruction produce correct accept/reject results and cleanup traces | I02 |
| I04 | Composable language forms | Multi-module programs use enums, patterns, optionals/outcomes, methods/defaults and structured control flow | I03 |
| I05 | Generic type system and dispatch | Declaration-checked generics, regions, interfaces, associated families and concrete/erased/opaque calls execute correctly | I04 |
| I06 | Low-level core and C interoperability | Full scalar operations, raw storage, pinning and Linux C/layout/unwind probes pass; no-OS core emits no hosted dependencies | I05 |
| I07 | Native core and allocation libraries | Owners, UTF-8, collections, iterators, formatting and allocator contracts work in real programs | I06 |
| I08 | Hosted operating-system services | A file-processing CLI, loopback socket program and child-process round trip exercise native std services | I07 |
| I09 | Compile-time programming and package builds | Constants, macros/derives and locked multi-package builds pass invalidation, checksum and offline tests | I08 |
| I10 | Threads and synchronization | Scoped/owned threads, shared ownership, locks, atomics and channels pass race/failure stress cases | I07 |
| I11 | Async and scoped tasks | Optional executor drives async I/O; owned/direct-borrowed/scoped tasks pass wake, cancellation, panic and forgetting cases | I08, I10 |
| I12 | Complete developer workflow | Native build/run/test/bench/doc/fmt/lint commands, LSP and debugger workflows pass end to end | I09, I11 |
| I13 | Platform and capability closure | All 107 capability requirements and the V1 operation subset (library-surface.md section 6.1) have checked declarations and evidence across selected profiles | I12 |
| I14 | V1 release qualification | Reproducible installable C++/LLVM toolchain passes safety, capability, target and Rust runtime, compile-time and build-storage gates | I13 |
| I15 | V1.1 substantive self-hosting | Mettle compiler builds itself through repeatable bootstrap stages and preserves V1 capability/performance gates | I14 |
| I16 | V1.2 independent production backend | LLVM-free code generation covers every accepted profile/capability and passes Rust/LLVM-path comparisons | I15 |
| I17 | Complete stable-operation closure | Every applicable non-deprecated stable obligation outside the V1 subset, including architecture intrinsics and OS extensions, has checked declarations and evidence across all reference profiles | I14 |

This is fourteen delivery milestones to V1, followed by two architectural
evolution milestones and I17's post-V1 completion of the operation inventory. I02 is the first useful native compiler, not a reduced V1.
Dependencies are completion gates; a component's preparatory work may start once
its own contracts/inputs exist, without marking the enclosing milestone complete.
The experience track of section 8.7 runs alongside these milestones and is
delivered by its own gates.

### 8.0. Linux x86-64 profile transition (2026-11-08)

Owner decision (2026-11-08): with the macOS ARM64 machine unavailable, the
remaining V1 milestones gate on `linux-x64` from reference-profiles.md: a
Linux x86-64 compiler host producing x86_64-unknown-linux-gnu executables on
the installed maintained Linux userland. The owner's working environment is WSL2
on Windows. Owner amendment (2026-11-09): no Ubuntu release or glibc version is
mandated; each qualification run records the actual OS, libc, kernel and sysroot
identities. Windows x64 (MSVC ABI, PE/COFF, CodeView/PDB) stays
ungated for V1; the 2026-11-09 worklist amendment retains all reference profiles
for post-V1 applicability/qualification. Selecting Windows as a V1 gate would
still require a separate owner decision.

Consequences:

- I01-I12 stay closed for their recorded macOS ARM64 scope. That evidence does
  not transfer, so their behavior is reopened for the Linux profile through
  LNX below. I01-I06 already have Linux x86-64 target execution receipts, but
  with a macOS host; a Linux-hosted compiler build was never qualified.
- LNX, Linux host requalification, precedes any further I13 area closure:
  1. Bootstrap the pinned `linux-x86_64` CMake/Ninja/LLVM 22.1.3 artifacts.
     The upstream LLVM Linux release links `zstd::libzstd_static`, so the host
     needs a static zstd: Ubuntu's `libzstd-dev` (already a README
     prerequisite). Where the package archive is unreachable, a static zstd
     built from the checksum-verified upstream 1.5.7 release and passed with
     `CMAKE_PREFIX_PATH` is equivalent; it is a host build prerequisite of the
     pinned LLVM artifact, not a compiler or library dependency.
  2. Build Debug and Release, then run CTest, `tests/source.py` run/fail,
     `tests/std.py` and the package cases on Linux.
  3. Classify each failure as a Darwin-only assumption in tests or tools, a
     genuine Linux runtime/ABI defect, or an inapplicable record. Fix the first
     two under the normal gates; never relabel a failure as inapplicable.
  4. Re-run the I07-I12 decisive checks on Linux, including emitted ASan/TSan
     cases and the LLDB `debugger_workflow`, and record per-item Linux status
     beside the macOS status in sections 8.3-8.5.
- I13: the S031 per-item target/cfg audit and every `not applicable` record
  are re-evaluated for Linux. Records marked Darwin-inapplicable are no longer
  excluded automatically, and Linux-only std services (for example epoll and
  `/proc`-backed queries, where selected) become applicable.
- I14 qualifies `linux-x64`. Correctness, sanitizer and reproducibility checks
  may run under WSL2 or the container. Runtime, compile-time and storage gates
  need a qualified runner; virtualized WSL2/container timings count only as
  pilot evidence until that runner is recorded.

#### LNX status

Partial. Historical 2026-11-08 base `fd4f46a` plus LNX changes: Ubuntu 24.04
x86-64 container, glibc 2.39, 2 vCPU/7 GB; Release qualification scope only.
Pinned tools/checksum-verified zstd 1.5.7 bootstrap and Debug build passed.
Linux compile repairs: explicit uint64 timer clamp (`runtime/sys.cpp`), complete
recursive TOML Value special members (`packages/toml.h`), unambiguous Source
arguments (`tests/ir/verify.cpp`) and no-RTTI flags matching LLVM (CMake).

| Receipt | Actual scope / remaining limitation |
| --- | --- |
| Thread-name spawn repair | `thread_name_visible_at_spawn.mt`: old runtime fails 5/5, repaired passes 5/5; it and `threads_basic` pass emitted TSan. Original 15-byte OS-name truncation is addressed by owned names in the 2026-11-09 repair batch below; full qualification pending. |
| Test portability repairs | Blob mode bits instead of root-sensitive os.access; ELF STT_FILE basename allowed without DWARF/source path; five x86_64 fail spans corrected; float min/max equal-zero sign remains unspecified; text/CString cases use current range/is_present/empty-product/to_bytes contracts. |
| Initial serial Release | 21/22; source.run 1/548 fails known Any identity. Alloc 46/std 86 pass with two workers; LLDB debugger_workflow and emitted ASan/TSan probes pass. Parallel ~1.6 GB compiles OOM; not code-failure evidence. |
| After Any identity repair | Serial Release 22/22, source.run 549/549; alloc 46/std 86 pass. Not a complete LNX matrix. |

Remaining LNX gates: clean-build reproducibility, complete compiler ASan/UBSan,
repository clang-tidy, full Debug CTest and per-item I07-I12 Linux status.
The 2026-11-09 WSL focused repairs and pending consolidated qualification are
recorded in section 8.4; they supersede the earlier "WSL not run" snapshot,
not these outstanding gates.

### 8.1. Foundation and first executable: I01-I02

I01 establishes source/build identities and installed artifact hashes for the
selected compiler, LLVM, linker and sysroot, plus host/target configuration.
Build the skeleton in debug/optimized configurations and prove object emission,
linking and execution on Linux x86-64. The backend smoke test is not a claim that
Mettle source already compiles. Keep the fixture harness small and CTest-driven;
no public registry, hosted CI purchase or extra framework is required.
`tools/test_linux_target.py` checks the native macOS build identities, cross-emits
x86-64 ELF objects from both configurations, and requires real Linux linking and
exit status. The emulated target is not native-hardware performance evidence.

I01 evidence (2026-10-28, macOS ARM64 host): Debug/Release each pass three
CTest fixtures and byte-identical CLI/backend/smoke-emitter clean rebuilds;
Debug object DWARF passes. Both emitters' x86-64 ELF objects link with
Clang/LLD 21.1.8 and exit 37 on Ubuntu 24.04/glibc 2.39. Locks/logs/artifacts:
`build/macos-arm64/`, `build/linux-target/`. The interrupted Linux-host link
(VM killed) is not qualification.

I02 implements the vertical slice in section 2: source buffers/spans, tokens,
lossless parsing, resolution, scalar types, compiler-owned IR, LLVM lowering,
linking and native exit status. Include the separator/precedence recovery corpus
and arithmetic failure paths. Reject unsupported features explicitly.
Begin P01 runtime comparisons and retain compiler time/memory measurements;
these early measurements are engineering signals, not the V1 verdict.

Historical I02 evidence (2026-10-28, macOS ARM64 host):

| Snapshot | Native checks | Linux x86-64 target / retained scope |
| --- | --- | --- |
| Scalar | Debug/Release seven suites, byte-identical rebuilds; Debug DWARF; each 34 positive, 44 invalid/unsupported, 24 arithmetic/profile, 11 inspection cases. Token reconstruction, UTF-8/CRLF/comments, recovery/limits, phase/spans and output preservation. | `foundation-evidence.json`: 28 source cases across both compilers/profiles, both smokes. `scalar-evidence/` under each configuration. |
| LLVM 22.1.3 compatibility | Replaces LLVM/Clang/LLD/compiler-rt 21.1.8 for Darwin sanitizer startup; source/archive locks updated together, CMake/Ninja unchanged. Triple-taking lookup replaces deprecated string API. Debug/Release seven suites; ASan/UBSan eight including detector exits; all three byte-identical rebuilds; instrumented quality/static analysis. | Both compilers repeat 28 cases/smokes. Old `llvm-21.1.8`/`-llvm21` evidence retained; no language/check weakening. |
| Architecture correction | Twelve actual components, syntax/facts/verified-CFG owners, independent LLVM-free boundary tests. Debug/Release eight suites; ASan/UBSan nine; three byte-identical rebuilds. Gate precedes I03. | Both compilers repeat 28 cases. Production contract: compiler-architecture.md. |

`build/p01/evidence.json`: three reduction sizes, six randomized pairs/size,
independent checksums, compiler time/RSS; Rust **1.94.1**, not frozen 1.99.1,
shared-host/startup noise and one session. Historical engineering evidence only,
not pilot/release parity or requalification for LLVM 22.1.3.

I02 does not qualify ownership/generics/libraries, other numeric widths,
uninhabited parameters, stable inspection API, source DWARF, Linux compiler
host or release/platform/performance. Unsupported remains distinct from invalid.

### 8.2. Ownership and type-system foundation: I03-I05

I03 implements compilation-owned nominal/Copy products, finite layouts and
construction; canonical places and sparse field-sensitive initialization/moves;
value/read/mut/take, first-class stored/returned views, region-only sources,
concrete methods, reborrows and two-phase receivers; scope/temporary/drop plans,
partial cleanup and pending arguments/results. Origin/effect summaries include
implicit-destructor writes. `examples/core/values.mt` and `ownership.mt` execute
unchanged; original move/take negatives reject for ownership reasons.
Implement exceptional cleanup before unwinding through resources: outer catch
must see valid replacement after the old destructor panics, and second panic
must abort before installation. Use ordered traces and ownership negatives.

Historical I03 qualification (2026-10-29, macOS ARM64 host): Debug/Release
12 suites, ASan/UBSan 13; all three byte-identical compiler/runtime/test
rebuilds; ordinary/instrumented quality. Per build: 112 run-pass profiles,
104 intended rejections, 24 arithmetic/profile cases. IR rejects duplicate
non-Copy consumption/lost cleanup/live redeclaration and accepts exclusive phi
transfers. Cleanup traces cover local/field/temporary order, partial moves,
exits, pending values and first/second panic. Linux per ordinary compiler:
134 source profiles, six cleanup/recovery probes, foundation smoke; checked
source/compiler/runtime/generator identities, VM stopped. Receipts:
`build/macos-arm64/`, `build/quality/`, `build/linux-target/`.
I03 closes only the concrete single-file subset: I05 generic/variance/higher-
ranked checking, source panic APIs and Linux-host/release qualification remain
separate.

I04 adds complete product/enum/pattern composition, nested presence and outcomes,
typed propagation/capture, modules/reexports/aliases, methods/default arguments,
labels/ranges/arrays and exhaustive control flow. Consume all applicable existing
example fixtures without weakening their expectations. A malformed program
must not satisfy a fixture intended to reject ownership or generic-body use.

I04 implementation contracts are owned by compiler-architecture.md sections
2-4: transparent aliases preserve identity/Copy/access/drop, explicit qualified
methods retain modes without implicit two-phase access, target-aware labeled
exits protect owned results through cleanup, and declaration-owned default/
constructor plans preserve evaluation order and partial initialization.
The source/module/cleanup corpus covers enums/active alternatives, nested
coverage/guards, defaults, destructured parameters, typed failures and array/rest
borrows; existing option/outcome/default examples execute unchanged. Generic/
callable fixtures retain their I05 contracts.

Required array lengths use checked arithmetic in every profile; general const
functions remain I09. Compact non-droppable arrays use one place and memory
lowering; droppable arrays stay expanded, capped at 2^16. Array patterns,
constant-index projection of large static arrays and large droppable by-value
iteration remain unsupported. Large extern C value snapshots use physical
object storage, not pointer-valued SSA storage. The focused
`c-memory-represented-aggregate-snapshots` probe passes Linux x86-64
Debug/Release imports, exports, callbacks and varargs with independent C
controls, including ASan/UBSan on the C fixture; this is not compiler or emitted
Mettle sanitizer qualification, nor Darwin ABI evidence. Large local
storage is bounded by the 8 MB thread stack. Earlier `[u8; 1_000_000]` timings
are engineering observations, not qualified speed evidence.

I04 native qualification (2026-10-29): Debug/Release pass fourteen CTest suites
each, including in-memory and multi-file module checks; ASan/UBSan passes fifteen.
All three clean rebuilds are byte-identical, including the module-test executable
and resolution archive. Each configuration executes 216 run-pass profile cases,
168 intended compile-fail cases and 28 arithmetic/profile cases. The native source
trace verifies sixty ordered drops, including active variants, consuming array
rest bindings and constructor failure that must not invoke the whole destructor.
The target runner selects 246 source/profile cases per ordinary compiler build,
including external multi-file fixtures, plus six native cleanup probes and the
foundation smoke. Completion requires that runner's passed, current-identity
receipt as well as the ordinary/instrumented quality receipts; all are retained
under `build/macos-arm64/`, `build/quality/` and `build/linux-target/`.

I05 implements declaration-based generic bodies and specialization, named and
higher-ranked regions, variance, const parameters, associated types/constants
and GATs, coherence, lookup, operators, closures and callable modes. It includes
unsized constraints, explicit erased dispatch and opaque return identities.
Negative cases check that a Copy instantiation grants no undeclared ownership
rights, overlap cannot be selected by order and a region cannot escape its binder.
The core constant expressions needed by const parameters precede the expanded
const-function evaluator in I09.

I05 acceptance includes generic declaration rights/defaults, coherent explicit
lookup, once-only receiver/deref paths, higher-ranked callable modes, slice/tail
metadata, erased mutation/upcasts, opaque Self/associated results, and loans
through erased results/unknown mutable writebacks. Erasing a witness-metadata
implementor requires the explicit sized adapter in compiler-architecture.md;
never add silent allocation.

Closure requires current Debug/Release and ASan/UBSan CTest, byte-identical
rebuilds, fast/build-directory quality and Linux source/module/cleanup execution.
Receipts, not historical counts, qualify scope; libraries/I06/stable foreign ABI,
Linux compiler host and runtime parity remain separate.

I05 qualification passed on 2026-10-29: Debug/Release pass fourteen CTest suites
each and ASan/UBSan passes fifteen, including detector probes. Each configuration
executes 286 positive source/profile cases, 204 intended rejections and 28
arithmetic/profile cases. Fast quality and ordinary/instrumented build-directory
quality pass, including static analysis; all three clean rebuilds are
byte-identical. Linux Debug/Release each execute 316 source/profile cases,
including modules and arithmetic, six cleanup cases and the foundation smoke.
The source execution uses two bounded lanes while retaining the original
600-second whole-request deadline and per-link/program limits. All source,
tool, sysroot, compiler and output identities were verified; the VM was stopped.
`build/i05-qualification.json` records the underlying receipts. Documentation-only
completion records are checked by the fast gate without rerunning unchanged
compiler matrices; the aggregate receipt distinguishes those updates from the
qualified compiler snapshot.

### 8.3. Native libraries and machine boundary: I06-I08

I06 completes integer/float/conversion behavior, raw-pointer provenance,
initialization/manual destruction, interior mutability, atomics, pinned storage,
layout, symbol/linkage, C callbacks/varargs and compatible unwind. Provide
volatile, assembly/intrinsic and freestanding mechanisms, initially demonstrated
on their applicable first execution/reference environments. Never substitute
an unsafe caller workaround for an unimplemented safe operation.
Use C round trips, layout/calling probes and independent memory-model cases;
sanitizer success alone is not a safety proof.

Implemented initial mechanisms include scalars/conversions, raw memory,
manual/uninitialized/interior storage, atomics, inline/structural pinning,
representations, C callbacks/varargs/unwind, assembly/SIMD and freestanding
objects. Contracts and shared interfaces: compiler-architecture.md section 4.
Re-review qualification and historical evidence are distinct below.

#### I06 acceptance inventory

Reconciled 2026-10-29 against section 8.3, the 24 I06-owned capability rows,
specifications and receipts. **Partial** means an implementation gap;
**implemented** is not verified. The re-review exposed missed obligations:
affected rows need regression revalidation. Initial delivery and I13 operation/
profile closure remain separate (section 9); resolve ambiguous scope explicitly.

| ID | Contract and implementation state | Implementation/evidence | Qualified acceptance scope and later limits |
| --- | --- | --- | --- |
| L001 | Integer widths/literals: implemented initial composition | Full-width typed constants, patterns/ranges and substitutions; checked array-count narrowing, usize inference/indexing and pointer-width slice iteration have focused evidence | Frozen-input qualification of boundaries and composition. Bounded const execution is not general I09 const programming. |
| L002 | Overflow profiles: implemented | LLVM checked operations and focused debug/release arithmetic cases | Consolidated boundary/exception cases on the frozen compiler and qualified target. |
| L003 | Explicit arithmetic families: implemented initial families | `types/machine.cpp`, LLVM numeric operations | Declared initial-family width/exception acceptance cases; I13 retains complete stable-operation inventory closure. |
| L004 | Boolean/short-circuit behavior: implemented | Existing scalar corpus; boolean memory/atomic cases | Current-input short-circuit and byte-storage regressions; no effects from an unevaluated branch. |
| L005 | Floating/conversion policy: implemented initial mechanisms | Direct rounding, strict defaults, checked integer-destination conversions and explicit inherited floating relaxations | Frozen-input NaN/signed-zero/rounding/conversion and policy qualification; no implicit relaxed release mode. |
| L012 | Unsafe unions: implemented | `syntax/parser/declarations.cpp`, typed overlap checks, C union round trips | Current sanitizer/target validity, overlapping-loan, initialization and manual-destruction evidence. |
| L014 | Raw pointers/provenance: implemented | Pointer signatures/lowering and focused raw-memory cases | Consolidated alignment, extent, provenance, validity and ownership cases; no inferred aliasing guarantees. |
| L015 | Unsized metadata: implemented mechanisms | I05 metadata paths plus I06 pointer/cast lowering; raw slice/address/reborrow case passes in both source profiles | Frozen-input metadata-preserving target qualification; older I05 qualification is not current I06 evidence. |
| L016 | Zero-sized values: implemented; focused cases pass | Zero-size owned-array iteration drops each element once; zero-size wrapping pointer extremes pass | Frozen-input sanitizer/target coverage of layout, iteration, arithmetic and destruction. |
| L018 | Coercions/conversions: implemented initial composition | I05 coercions, I06 scalar/pointer/checked casts and typed integer contexts | Frozen-input qualification without hidden retain, erasure, lossy count narrowing or ownership upgrades. |
| L031 | Interior mutability: implemented initial facilities | Safe Cell/RefCell exchange/guards and compiler-owned UnsafeCell, including view-writeback and native cleanup | Frozen-input safety, panic/forgetting and target qualification; raw access is not a replacement for a safe interface. |
| L032 | Manual destruction/forgetting: implemented | Storage operations, in-place drop and aligned unwind-frame cleanup | Current sanitizer and failure/forgetting cases, including no repeated destruction after panic. |
| L033 | Pinning: implemented initial contracts | Inline pinning/projections/destructors/receivers and solver-backed conditional Unpin; proof context is retained without shared assumption flags | Frozen-input generic/region/projection/writeback/destruction qualification. Heap-owner libraries remain I07 and future state machines I11. |
| S015 | Cell/RefCell/UnsafeCell: implemented initial facilities | Safe cell operations, dynamic borrow/try-borrow guards, native release and conflict/forget/unwind cases | Frozen-input sanitizer/target and applicable operation qualification; native thread libraries remain I10. |
| S016 | Uninitialized/manual-drop storage: implemented | `MaybeUninit`/`ManuallyDrop` signatures and focused ownership cases | Current partial-initialization, validity, explicit-drop, alignment and unwind evidence. |
| S017 | Atomics/fences: implemented initial scalar mechanisms | Ordering validation, RMW/CAS/fences; C++ thread publication case | Independent memory-model/race evidence and applicable target width/order cases. A publication example or ASan alone is insufficient; native thread libraries remain I10. |
| S018 | Transferable/Shareable/Static: implemented initial contracts | Structural derivation in `interface_solver.cpp` (raw pointers, cells and `Ref`/`RefMut` opt out; atomics and plain data opt in), `unsafe extend`/negative `extend X not P` declarations, bounds enforced at call sites; Static additionally requires `static` regions | Frozen-input generic/region/projection qualification. Immutable statics must be Shareable (raw pointers and a bare `UnsafeCell` are exempt; `static mut` needs unsafe). Scoped spawns require `F: Within<region s>`, checked in `regions.cpp` (`withinBounds`), so closures cannot capture locals declared inside the scope body. Method-level bounds bind extension-owner regions from the receiver's nominal region arguments before covariant view shortening; the short-capture regression is verified on macOS arm64 (`neg_async_scope_mut_receiver_short_borrow.mt`). `fs.ReadDir` is an `Iterator`; `mpsc.sync_channel(n)` has capacity `n`, including rendezvous at zero. A panic in a spawned thread is caught per thread and `join()` reports a Panicked result with code 101. Extension-level region names are now resolved from the current function's region scope when a callee's annotation scope is active (`regionReference`); verified on macOS arm64 (`impl-region-method-call-on-other-type.mt`), and `Scope.spawn` no longer needs its private `register` workaround. |
| S019 | Thread spawn and scope: implemented initial library | `std.thread` (`spawn`, `JoinHandle.join` reporting `Panicked`, `scope` joining on panic) over `runtime/thread.cpp`; owned threads require Transferable + Static, scoped ones Transferable | Linux target execution of `library.std`, sanitizer/TSan evidence of the shim, stress on the target. Race freedom is not a fairness or deadlock-freedom claim. |
| S020 | Mutex and RwLock: implemented initial library | `std.sync.{mutex,rwlock}` with poisoning, thread-affine guards (`not Transferable`) and an error-checking mutex that reports relock | Target stress and applicable poison/failure-policy cases. |
| S021 | Condition variables, barriers, once: implemented initial library | `std.sync.{condvar,barrier,once}`; a panicking initialiser re-arms `Once` | Target stress. |
| S022 | Channels: implemented, verified on macOS arm64 (`tests/std/channel_rendezvous_select_timeouts_iterator.mt`) | `std.sync.mpsc` unbounded FIFO, bounded/zero-capacity rendezvous, try/timed operations, blocking iteration, condvar-backed multi-receiver Select | Remaining Linux-target/stress/TSan qualification; recorded macOS receipts do not transfer. |
| S023 | TLS: implemented, verified on macOS arm64 (`tests/std/tls_static_init_and_exit_order.mt`) | Static LocalKey aggregates/lazy native keys and owned dynamic keys; per-thread initialization, reverse first-installation destruction at thread/main exit | Qualify initializer/destructor iteration/order on remaining target profiles. |
| A001 | Initial C ABIs/callbacks/varargs: implemented mechanisms | Darwin ARM64/Linux x86-64 adapters, physical-entry cursor capture, independent copies, promoted/aggregate reads and cleanup | Frozen-input C round trips/cursor/cleanup qualification on Linux. Cursor transfers outside the represented initial contract are explicitly diagnosed; no new target ABI is implied. |
| A002 | Layout/alignment: implemented initial combinations | Combined C/integer tags, transparent single-variant enums/products, unions and packed/aligned storage; exact transparent scalar ABI/callback/vararg forwarding has focused C evidence | Frozen-input sanitizer and Linux calling/layout/validity qualification; additional profile/operation closure remains I13. |
| A003 | Symbols/linkage: implemented mechanisms | Function/static imports/exports/library selection, stable storage identities, full-width required initializers and relocations | Frozen-input symbol/link/lifetime/initialization and freestanding qualification. |
| A004 | Compatible unwind: implemented initial boundary | Ordinary-C abort and compatible C-unwind cleanup probes | Current direct/indirect ABI rejection and cross-language cleanup/escape cases on the target. |
| A005 | Assembly: implemented initial mechanisms | Inline/global/naked variants, typed full-width/generic constants, function/static symbols, operands/registers/clobbers/options and compiler-owned verification | Frozen-input execution, unwind/evaluation and rejection qualification; naked entries must remain physical non-inlined ABI entries. |
| A006 | SIMD/target operations: implemented initial mechanisms | Native vector identity/layout/ABI, initial operation tables, explicit target facts, recognized feature contracts and guarded dispatch | Frozen-input sanitizer and Linux execution; distinguish unavailable optional instructions from baseline execution. Complete per-operation/profile closure remains I13. |
| A007 | Volatile access: implemented | Explicit volatile loads/stores and raw-pointer cases | Preserve accesses under optimization without treating volatile as synchronization. |
| A008 | Freestanding core: implemented mechanisms and fixture selection | No-entry abort, assembly/SIMD objects and undefined-symbol checks; Linux selection omits the hosted runtime | Frozen-input Linux execution and no accidental hosted dependencies for the delivered core boundary. |

#### Focused integration history before qualification

Historical 2026-10-29 integration, superseded by requalification below:

| Retained evidence | Scope / failures preserved |
| --- | --- |
| `build/i06-focused/memory-layout/evidence.json`, `pin-layout/` | Native/sanitized memory and native pin/layout/union cases; 35-unit static analysis predates later representations. |
| `build/i06-focused/representation-closure/` | Six positive profiles, three rejections, 22 C/profile round trips, three ABI rejections; native Debug only. |
| Session `files/i06-parallel/results/numeric/` | 74 positive profiles, 39 rejections, 16 arithmetic/override cases plus parent wide-count/usize/zero-array fixes. |
| `ffi-ownership-integrated-evidence.json` in that results directory | 94 positive profiles/51 rejections; two fixture/one diagnostic corrections have explicit follow-ups, not relabeled raw receipts. Eight traps, IR boundaries, 44 C/profile round trips/three ABI rejections. |
| Assembly/SIMD integration and `build/i06-focused/target-integration/` | Recovered cancelled worker source; 32 negatives, 20 C/profile round trips/assembler rejection. 91 Linux cross-emission cases are **not execution**. Naked physical entries need no-inline; guarded vector register ABI needs storage bridges in both directions. Old compiler fails independent AVX ABI C case. Four affected profiles/two C follow-ups; final native 38 profiles, 20 C round trips, assembler rejection and IR boundaries. |
| First frozen Debug gate | Static analysis passed, CTest 14/16: Unit-result bridge returned null LLVM value; constructed cleanup fixture lacked typed destructor descriptors. Reopened freeze; six source profiles, cleanup-frame and both changed units' analysis pass after repairs. Original failures retained. |

Four worker deltas/parent fixes remain in the session results; worktrees removed
after checked integration. Linux fixtures explicitly select x86-64 templates
and both freestanding cases. Source freeze depends on complete inventory,
implementations, fixtures and docs; qualification depends on freeze and milestone
completion on qualification. Later source changes reopen affected gates and
invalidate dependent evidence, not unrelated passing groups.

#### I06 requalification result (2026-10-31)

Frozen commit `ff1daa3` on the native macOS ARM64 host and Darwin target:

- The `c485aa1` re-review corpus (crash, soundness, ABI, limit and diagnostic
  findings) produces its expected acceptances and located rejections; the
  doubling-specialization case now stops at `error[limit]` in about a second.
- `tools/build.py --configuration Release --quality` on `ec000dd`: clean
  build, static analysis of every owned translation unit, full CTest and a
  byte-identical second clean build. The only later change (`ff1daa3`) is the
  package-store fix below; for it the Release build, static analysis of
  `store.cpp` and full CTest were rerun on `ff1daa3`.
- The ASan/UBSan qualification exposed undefined behavior in package-store
  pruning: an entry deleted by a concurrent build reported the minimum file
  time, overflowing the age computation, and one shared error code silently
  ended directory walks. `ff1daa3` skips vanished entries with per-entry error
  codes; `tests/packages.py` (cache corruption and clean) adds dangling entries
  that fail the old sanitized compiler.
- ASan/UBSan on `ff1daa3`: sanitized build and full CTest. Two suites exceed
  their wall-clock bounds only because the sanitized compiler is slow (a hosted
  std program compiles in about 37s versus the 30s probe bound and 2.7s in
  Release); `packages.resolution` (all 29 cases, sharded) and
  `probe.broken-pipe` were rerun without the bound under halting ASan/UBSan and
  passed. Front-end compile time is a recorded follow-up.
- Not claimed: Linux/Windows execution (owner decision 2026-10-31: run on a
  separate machine, excluded from gates here), emitted-code TSan, a complete
  memory-model proof, or I13 complete stable-operation/profile closure.

#### Earlier I06 qualification result (before the re-review)

Historical 2026-10-29 macOS ARM64-host/Linux x86-64-target receipt, **not
current approval** after `c485aa1`: `build/i06-qualification.json` binds source,
tools, sysroots, artifacts, raw receipts and documentation-only delta;
`build/i05-qualification.json` is unchanged.

- Debug: all 247 source cases/494 profiles via explicit continuation; fourteen
  original passing suites retained, three repaired cases pass both profiles,
  constructed cleanup passes. Failed receipts retained.
- Static analysis 127 units, two affected units refreshed; Release 16/16,
  ASan/UBSan 17/17 with detectors; all three byte-identical rebuilds.
- Each ordinary compiler: Linux 620 source profiles/six cleanup cases/object
  smoke; storage and assembly/SIMD freestanding probes have no undefined
  symbols and link without Mettle runtime. Selected emitted TSan/race/model
  checks pass, not complete memory-model or operation/profile qualification.
- No Linux compiler-host/release/runtime-parity claim. Worktrees removed and
  Linux VM verified stopped.

I07 implements core/alloc operation families against the pinned inventory:
unique/local-shared/weak owners, allocator identity/failure, optional/outcome
operations, UTF-8, slices/collections, iteration, hashing, formatting/parsing and
type identity/downcast. Native atomic-shared ownership lands here as needed,
but its concurrent safety closes in I10. Test allocation failure, partial
initialization, invalidation and panic, not only happy-path values.
I07 integration (macOS ARM64 evidence; full selected-operation closure remains
I13):

| Surface | Required behavior / implementation | Focused evidence |
| --- | --- | --- |
| Loading/prelude | Native core/alloc/std mounted on demand via --library-dir or in-memory catalog; layering/freestanding/user-shadow rules in architecture section 6. Core prelude is lowest priority; explicit imports/declarations/globs shadow it. No specified opt-out. | `library.core` via `tests/modules.py`; `library.alloc`. |
| Core values | UTF-8 validate/slice/search/trim/split/lines/chars/bytes/char_indices; nested option/outcome; comparison/Reverse, hash and iterator/range protocols; parsing, formatting and Any/downcast. Text literals are static validated Text; byte/raw literals retain static storage. Const items reuse required evaluation for expressions/array lengths/patterns/associated values. | `tests/library/*.mt`; inherent-associated-constant run/fail cases. |
| Panic/exit | core panic/assert/unreachable -> panic_message: freestanding trap, hosted hook/stderr `panicked: msg` and code 101; builtin arithmetic/index traps abort. Only hosted std.process.exit, not core.process.exit. Catch returns owned code/message after cleanup. | `tests/std/process_exit.mt`, panic fixtures below. |
| Optimization barrier | core.hint.black_box round-trips memory through empty sideeffect asm with memory clobber. | Existing compiler/library cases; no runtime comparison claim. |
| Ranges | Non-for bounded/open ranges become native range values when core is mounted; direct-for ranges retain structural counted loops. Local iterator consumed by for. RangeFrom follows integer-overflow policy; char stepping skips surrogates and panics beyond its maximum. Inclusive endpoints exhaust without overflow; end-bounded ranges are not iterators. | `range_value.mt`, `open-ended-range-values`, `end-bounded-range-is-not-an-iterator`; historical maximum-exhaustion expectations are superseded by `review-sequence-range-overflow` and `review-sequence-char-range-overflow`. |
| Sorting | Core unstable sort: allocation-free introsort (median-of-three, short insertion, heap fallback, fixed pending stack). Alloc stable slice/List sort uses two Global index buffers and swaps initialized elements only after comparisons; alloc.vec must be mounted. | `tests/alloc/stable_sort.mt`, `tests/library/range_value.mt`. |
| Unicode | Unicode 16.0.0 properties/case iterators and alloc text case conversion, including final sigma. Generator/table: tools/unicode_tables.py, core/unicode_data.mt. | `unicode_whitespace.mt`, `unicode_properties.mt`, `tests/alloc/unicode_case.mt`. |
| Slice/text safety | Checked range slicing for arrays/slices; IndexRange/Mut for Text/user types (Text bounds and scalar boundaries panic). Unsafe from_raw_parts[_mut]/from_utf8_unchecked[_mut] leave result-region proof to caller. char.from_u32 returns optional; direct u32-as-char invalid. | Historical `char_from_u32` and `char-from-u32-is-checked`; retired library boundary checks now in `tests/source/run/i13-char-operations.mt`, not new qualification. |
| Allocator/owners | Checked Layout and allocate/deallocate/grow/shrink/AllocError; Global allocation-error abort. Each allocator-generic owner/collection retains its allocator for every owned block; hosted alloc hooks, freestanding supplied symbols. heap/shared/local-shared/weak syntax calls native Box/Arc/Rc/Weak. Unsizing transfers allocator/allocation and preserves slice/witness metadata. Shared payload/header and exact padded layout survive last-strong/last-weak drops; Text copies accept validated Text only. | `native-heap-unsized-slice.mt`, `native-heap-erased-owner-drop.mt`, `native-heap-unsized-owner-use-after-move.mt`, `native-shared-unsized-{slice-weak-drop,erased-weak-drop,weak-dealloc-layout}.mt`, `native-unsized-structural-tail-drops.mt`, `native-unsized-text-owner-copy.mt`; moved-owner/non-Text/pinned negatives. |
| Collections | List, String, Map/Set, SortedMap/Set, deque, heap, linked list: failure/growth/collisions/drops/invalidation and no-std parser workload. B-tree minimum degree 6, allocator nodes/parent links, split-down/borrow-merge removal, key-order iterators rather than contiguous entries. | `tests/alloc` including `map_entry`, `map_entry_blocks_map_use`, `btree_stress`, `btree_heap`, `sorted_entry`, `btree_alloc_failure`. |
| Panic safety | Hosted catches restore valid collection state/exactly-once drops where cleanup proceeds; unvisited leaks permitted, second unwind panic aborts. | `tests/std/collection_panic_safety_{vec,maps,heap}.mt`. |
| Traits | Core Clone; region-family Iterable/MutableIterable; List owns/derefs/indexes/clones/compares/hashes; String writes/compares/hashes like Text. Box/Rc deref/value traits, Box mutable deref/Clone. Collection Debug/pretty Debug, Clone/Eq where selected; ordered containers lexicographic/hash, Map/Set order-independent Eq and deliberately no Hash. BinaryHeap deliberately lacks Eq/MutableIterable; collections lack Display. Mutable map iteration exposes values, never keys. FromItems/ExtendItems/collect accept OwnedIterable; Debug covers options/outcomes/tuples 1-12/arrays. | `library.alloc`; nested Debug and callable-bound cases at Release CTest 24/24, `749854f`. |

Source-prepared correctness repairs (baseline `883eda1`, native verification
pending) restore `RangeFrom`'s ordinary integer-overflow policy and panic beyond
`char.MAX`, and consuming receivers for whole-stream iterator consumers;
historical I07 receipts above do not verify these repairs.
The complete Linux Release run exposed stale `range_value.mt` expectations
that open ranges exhaust at integer/char maxima. Native panic-entry debugging
confirmed ordinary checked integer overflow, as specified by the current
contract. The finite-endpoint checks now use inclusive bounds, preserving
their value/exhaustion assertions; separate profile-specific open-range
panic/wrap checks remain unchanged. The core rerun passed these range checks
and exposed a stale prelude diagnostic column, now corrected from 9 to 14.
The same qualification run found `collection_remaining.mt` expecting none for
overlapping mutable map lookups, contrary to the selected panic contract.
Its absence check now uses a missing key; the existing
`review-ordered-algebra-heap-and-disjoint` regression retains duplicate-key
panic coverage. The repaired collection case passes both profiles.
Nineteen alloc/std rejection fixtures still used phase-only directives;
their replacements identify the observed intended diagnostic's phase,
message and exact location. Four borrowed-future/closure fixtures correctly
report a region failure rather than a type failure. All 38 exact
diagnostic/profile rechecks pass. Native debugging also confirmed `sync_primitives.mt`
blocked in its second `Once.wait_force`, before same-thread forced recovery.
That wait now follows successful recovery and its completion assertion,
matching the existing concurrent poison-wait regression; both profiles pass.
These fixture repairs do not change production library behavior. The full
Release run and complete sanitizer qualification are not yet passing receipts.

The same run exposed an I06 A008 debug-object defect: unreachable internal
core definitions introduced integer-division, libm and memory-service references
into the assembly/SIMD freestanding probe. Debug object emission now removes
unreachable globals before machine lowering, preserving exported and
assembly-retained symbols; live function bodies remain unoptimized. The existing
no-undefined-symbol/link/run probe passes both profiles, as do six global-assembly
and naked-entry round trips. Continuing the machine suite exposed a stale
volatile-access oracle: it treated the cleanup-frame pointer as the source
pointer. The oracle now follows the frame's first pointer slot, with positive
and nonvolatile/unrelated-pointer negative controls. The remaining machine
checks pass eight profile round trips and ten intended rejections.

Library runners now accept bounded worker counts and source-stem filters;
independent core files run concurrently, joined before supplemental checks and
the child-CPU scaling probe. Alloc/std retain both profiles by default, and CTest
reserves each library pool's worker count. Source worker counts are configurable
for memory-heavy sanitizer runs. Four focused runner/oracle tests pass; the
complete core rerun passes. Full qualification remains incomplete.

The completed hosted suite exposed stale callers of Clone/Writer, unsafe
environment mutation, throwing filesystem/path APIs, explicit copies from
borrowed elements and optional text comparison; their assertions are preserved
while updating the callers. All sixteen repaired programs now pass both
profiles (32 source/profile cases), including an explicit caught-panic
assertion for invalid environment names. Two compiler defects were isolated: direct-call
region inference discarded the normalized associated error, and wildcard
writeback retained a temporary same-container access loan. Both reduced
compile checks now accept; six focused source programs pass both profiles
and seven retained-source/escape rejection cases pass their exact diagnostics.

The preserved package-suite log also exposes two integration defects:
generated modules lack an alias inside their owning dependency package, and
the root test harness cannot reach tests through private nested modules.
Same-instance generated-module aliases and harness-only ancestor visibility
address these without broadening ordinary source lookup or visibility.
The nested doctest, complete Git-host regression, two dependency
visibility/import checks and affected module-memory CTest pass.
The original qualification was interrupted
by an owner-approved Ubuntu restart after WSL became unavailable; completed
receipts are retained, but neither a complete Release nor sanitizer pass is
claimed. The sanitizer configuration has no compiled objects or executable;
its full rebuild remains separate qualification work, not a focused-test
receipt.

The subsequently authorized unfinished rejection suite passes 684 applicable
cases (698 compiler invocations). Runtime qualification was stopped at the
owner's ten-minute deadline: reexecuting existing artifacts recovered 453
passing source/profile checks and one stale reversed-set-range assertion.
That assertion now checks equal-bound emptiness and catches the required
reversed-bound panic; both profiles pass. Disambiguating the String Borrow
target also passes both profiles. Repairing a malformed multiline result in
`compact-array-symbolic-element-and-unpin` exposed compact counts being inferred
with their canonical storage type instead of the formal const parameter type.
Concrete lengths now infer in the formal type with a range check; symbolic
counts retain their declared types. Five focused programs pass both profiles,
including the original failure and expanded/compact boundary cases; overflow
and symbolic-type rejection controls and the target-width CTest pass.
The complete runtime suite and sanitizer qualification remain unfinished;
earlier full-suite receipts do not qualify this compiler revision.

2026-11-10: inclusive `usize.MAX` List indexing traps with overflow checks off.
A finite exclusive `usize.MAX` collided with the public `IndexRange`
unbounded-end sentinel: an empty `List` indexed with `[..usize.MAX]` returned an
empty view. The owner approved changing the public protocol; its `RangeEnd`
represents unbounded, exclusive and inclusive ends, including `..=usize.MAX`
for custom indexers. Eight focused run cases passed Debug and Release, three
negative cases passed, and the custom-indexing case passed emitted ASan. These
used a temporary link against the preceding semantics components because the
shared region-solver header changed concurrently; current-tree integration
remains unverified. Prior sentinel-based receipts do not cover this protocol.

Compiler/library seam obligations:
- Borrowed slices use element-count len metadata; Text literals are validated
  static storage. Mounting all core costs seconds in Debug; lazy per-module
  loading remains work, not permission to skip symbolic-body checking.
- Interface equality can determine generic parameters (`I: Iterator<Item=T>`);
  generic callable constructors and region-bearing bounds preserve declared
  argument/result sources. Source-less callable access is call-local, not
  retained (`generic-callable-bound-*`).
- Blanket coherence rules out only impossible requirements, not potentially
  downstream implementations. Bodyless method calls through an interface name
  diagnose; use method syntax or T.(I).m. Raw-pointer region comparison is
  structural/coinductive through recursive nominals.
- List Index on view elements preserves element region separately from the
  temporary receiver loan; accepted/escape regressions pass at `749854f`.
  Generic `read K` arguments contribute carried views, not their temporary
  parameter borrow (`generic-read-argument-*`).
- Region-family iteration carries Item regions; live loop/items block mutation
  and escape. Read items from stored shared views can outlive the iterator;
  exclusive items remain tied while its storage is live (Loan::borrowed).
  Erased mutable formatting calls do not retain the formatter's call borrow.
  `match` through mut still needs explicit `match mut`; no default binding mode.
- Take consumes Copy too; use a fresh binding/expression for independent use.

S003 safe pinned owning handles moved from I07 to I13 by owner decision
2026-10-31. The historical `native-unsized-owner-payload.mt` pinned-owner
feature diagnostic records that boundary, not a declaration that V1 forbids it.
Run a structured parser/collection workload without Rust/OS/executor in core/
alloc and start applicable P02-P06/P08/P11 comparisons; complete measurements
remain I14.

I08 adds files/paths/OS strings, synchronous networking, processes/environment,
time and hosted panic handling. Demonstrate partial I/O, non-Unicode names,
timeouts, child failure and raw OS-error round trips. Core/alloc must still
build without these hosted services. Record the initial profile's actual
behavior; other profile implementations close in I13.

Stored exclusive-view contracts: results from a Cursor's stored mut view keep
referent loans even through raw-pointer derivation (summary paths truncate at
the last view deref and retain from-parameter backing). Borrowing stored mut
storage freezes its referent (Loan::frozen); mixed safe/raw results keep both
safe targets and declared backing. Generic mut callable results require an
unambiguous from contract. Existing stored/nested/returned/escaping-closure
probes found no hole; that is bounded evidence, not proof.

I08 macOS ARM64 integration: native std io/buffering/raw errno, OsStr/OsString,
path/fs, processes/env/time, IPv4/IPv6 TCP/UDP/timeouts/timed connect/DNS and
hosted panic. POSIX calls live in std.sys with runtime/sys.cpp shims. Tests:
`cli_wordcount`, `net_loopback`, `net_process`, `process_roundtrip`; partial I/O,
non-Unicode paths, timeouts, child failure/signals and OS errors. Nonreserved
API names include read_some/write_some/read_bytes/var_os/set_*.

Historical Linux Debug cross-target run (`tools/test_linux_target.py
--libraries`): 12 core/19 alloc/14 std programs plus 740 source profiles/six
cleanup probes passed with cross-built panic/alloc/sys runtimes under the Linux
kernel. `fs_nonunicode` asserts real on-disk bytes and accepts EILSEQ 84/92;
macOS may reject such names. Official both-configuration
`build/linux-target/foundation-evidence.json` remained pending a fresh
`tools/build.py` identity receipt. This is not Linux-host qualification.

S028 macOS Release `library.std`: `panic_catch.mt` covers owned code/message,
nested catches/replacement; `panic_hook_abort.mt` covers hook take/reset and
abort-on-hook-panic. Abort/freestanding cannot recover; spawned panic reports
through join. ReadDir terminal EOF/error is verified by fs_basic. Remaining
thread/sync target work is S019-S023; Windows-native paths/networking and other
profiles are unqualified, not implementations inferred from POSIX evidence.

### 8.4. Builds, concurrency and async: I09-I11

Main stabilization accepted by the owner on 2026-11-11. The owner requested
closure of the final eight-group Linux-host behavior run after these groups
passed: `library.core` (192.82 seconds), `compiler.modules-source`
(318.06 seconds), `library.alloc` (719.59 seconds) and
`backend.machine-interop` (1681.48 seconds). The run was stopped at the owner's
request with `packages.resolution`, `library.std` and `source.run` in progress;
`source.fail` had not started. The final input comparison recorded only
`AGENTS.md` as changed during the run. Existing focused ordinary and ASan/UBSan
receipts below are retained.

The stabilization repairs cover constant expansion/indexing/target widths; region coercion,
array/replacement/projection regions and interface obligations; throwing/default
call lowering and conditional cleanup; parser/macro/harness correctness;
native-link/cache identity, Git locking/path identity and cross-file rename.
The evaluator now consumes checked shapes and inferred function results.
Lazy static expressions receive ordinary semantic checking without executing
their dead branches or emitting validation functions.
Git lock format 3 records selectors; the owner approved the one-time unlocked
migration from readable version 2 locks. Nested Git path identities no longer
depend on the cache location.
Pinned WSL Release incremental checks passed the reproduced regional defects,
Git selector/cache relocation and rename cases, cfg source/import/generated
cases, 70 constant/static rejection cases, and focused constant execution
controls. After the latest constants changes, the incremental compiler build,
all three focused compiler CTests, and eight cross-boundary/static compatibility
controls (16 executions across both profiles) passed. The checker translation unit
also passed ASan/UBSan lazy-initializer success and rejection controls.
The early inferred-result gap was reproduced in an array header and repaired
with demand-driven ordinary function inference, predeclared identities and
cycle-checked lazy static headers. Existing inferred-result execution now covers
aliases, product fields, function parameters/results, static and local headers,
forward callees, branch/return joins and referenced constants. Early overflow
and static-type cycles have focused rejection cases. Pinned WSL Release
validation passed 18 execution cases across both profiles (36 executions),
78 rejection cases (82 executions), and all three focused compiler CTests.
ASan/UBSan instrumentation of the five changed implementation units passed two
acceptance and six rejection controls, including inference inside a live caller
scope. Later fixture strengthening reran only its affected profile pair and
sanitized check; compiler inputs and the other passing controls were unchanged.
These receipts do not qualify the entire dirty tree, all targets, compiler
sanitizer coverage or a milestone.
Translation-unit sanitizer receipts are not full-compiler sanitizer evidence.

2026-11-10 stability repairs on the uncommitted working tree: I09 cache entry
validation and publication (`bootstrap/packages/store.cpp`, focused cases in
`tests/packages.py`); macro path/async fragments and generated await bindings
(`bootstrap/expansion/macros.cpp`, `bootstrap/syntax/parser.cpp`,
`bootstrap/syntax/parser/async.cpp`, focused source run/fail cases); and I10
spawned thread names and attribute cleanup (`runtime/thread.cpp`,
`library/std/thread.mt`, `tests/std/thread_current_name.mt` and
`tests/std/thread_builder.mt`). Linux socket and process-pipe descriptors are
created close-on-exec atomically (`runtime/sys.cpp`, `tests/runtime/thread.cpp`).
The macOS fallback still creates descriptors before setting close-on-exec and
is not covered by this Linux repair.
Implemented; focused Linux cache, scoped thread and descriptor cases passed.
The thread runtime test passed ASan/UBSan, and emitted thread-name cases passed
ASan/TSan. Compiler cases used temporary links against preceding compiler
components; concurrent semantics edits prevent treating these receipts as
qualification of the whole tree. Rebuild and rerun affected cases after inputs
are stable; this is not a milestone source freeze.

Source-review repair batch (2026-11-09; base `d8dbc580`, qualification pending):
these are correctness repairs to existing obligations, not milestone closure.
The owner authorized execution on 2026-11-09. Focused validation was completed
in an isolated WSL Ubuntu 26.04 snapshot with the pinned LLVM 22.1.3 tools;
these are focused receipts rather than complete LNX qualification.

| Existing obligation | Starting state and owning source | Implemented repair / regression |
| --- | --- | --- |
| I09 cache input identity | Partial: `driver/cache.cpp` uses binary metadata | Bind compiler/runtime bytes; same-size/same-time replacement fixture in `tests/packages.py` |
| I09 cache clean | Partial: `packages/store.cpp` ignores deletion errors | Preserve marker/report failure; permission-denied cleanup fixture |
| I10 thread lifecycle | Partial: `runtime/thread.cpp` reuses pthread identities | Unique runtime tokens and lifecycle-safe lookup; native thread lifecycle regression |
| I11 executor retention | Partial: `std/task.mt` retains finished registrations | Reclaim quiescent finished entries; repeated completion and stale-waker regression |
| I13 time/process/fs/net operations | Partial: overflow, reaping and filesystem/timeout edge cases | Bounds, cached child status, directory type and finite deadline regressions in `tests/std` |
| Quality workflow and panic fixtures | Partial: `tools/build.py` lacks documented quality mode; alloc traps accept any failure | Restore format/static-analysis gate and require SIGABRT |

All rows are implemented with focused fixtures, not full LNX qualification.
Thread-name handles own clones; nonrecycled tokens and live-name/unpark lookup
serialize with exit. Executor sweeps release only finished/disposed payloads;
handles/wakers retain independent Arc owners. Retained-memory bounds remain open.
Quality runs pinned formatting/compilation-database clang-tidy before CTest;
Linux-target alloc panic checks require SIGABRT.

| 2026-11-09 receipt | Passing scope / limitation |
| --- | --- |
| `3ccd407` plus follow-ups | Debug build/modules; five CTests (`runtime.panic`, `runtime.thread`, `compiler.boundaries`, `compiler.consteval-target`, `compiler.modules-memory`); four cache cases, exact-SIGABRT alloc, changed-file format/tidy. Native thread ASan/UBSan/TSan; nine std programs after socket capture was corrected to clone inside worker (original failure retained). |
| Emitted probes | Release-profile time bounds/long socket wait/retained names; task_reclamation ASan with leak detection and TSan; task_owned TSan. Its two forgotten handles intentionally leak metadata, so it is not leak-clean. Uses `d8dbc580` Release frontend/backend with repaired library/fresh runtime; `3ccd407` cache-only compiler changes independently checked with Debug. |
| Owner-authorized formatting | Whitespace-only analysis/origins.cpp, lowering/opaque.cpp, syntax/parser/expressions.cpp; all C++ pinned clang-format 22.1.3, incremental Debug and three compiler CTests above pass. Not repository-wide tidy/reproducibility. |

Logs/markers/hashes: untracked `build/review-verification/`; execution artifacts:
`/home/nites/lanes/review-repairs-3ccd407/build/`. Complete compiler sanitizers,
clean reproducibility, LNX matrix and retained-memory bounds remain unqualified.

Main qualification request (2026-11-09; executable-source baseline `458096e`):
the owner requested the remaining full CTest, repository static-analysis,
clean-build reproducibility, complete compiler ASan/UBSan and Linux-host
checks. The repair implementation and acceptance fixtures above are complete;
the three subsequent source edits are verified whitespace-only. This is the
source-freeze gate for this verification batch, not I13 or LNX milestone closure.

| Task | State before consolidated qualification | Acceptance / owning inputs |
| --- | --- | --- |
| Repair source, fixtures and owning documentation | Implemented; focused scope verified as above | `compiler`, `runtime`, `library`, `tests`, this ledger; no known repair implementation gap |
| Linux host environment and input identity | Installed Ubuntu 26.04 WSL selected by owner; full qualification pending | Pinned `tools/toolchain-artifacts.json`; record actual OS/libc/source/tool/sysroot hashes |
| Debug quality and full CTest | Pending frozen-input run | `tools/build.py --configuration Debug --quality`; no weakened assertions or timeouts |
| Release full CTest and clean rebuild | Pending Debug gate | `tools/build.py --configuration Release`; compare artifact bytes |
| Complete compiler/runtime ASan/UBSan | Pending ordinary qualification | `tools/build.py --configuration Debug --sanitizers`; startup/detector probes and full CTest |
| Failure recovery and final record | Pending results | Reopen affected source/freeze tasks for any repair; preserve failed receipts; rerun only invalidated checks and commit fixes |

Historical preflight failures (2026-11-09): Ubuntu 24.04 stopped before compile
on unavailable `/sys/class/dmi/id/sys_vendor`; tools/build.py now records the
optional probe/error and withholds hardware/performance qualification. Preserve
console/foundation failures; no compile/test result was invalidated. Its later
completed build/partial tidy was interrupted by the owner, not a full pass.
Refreeze tool/ledger and continue on installed Ubuntu 26.04 WSL with actual
identities (no distro/libc mandate). Repair qualification does not close the
larger language inventory.

**L054 status (const evaluation): implemented and verified on macOS ARM64.** The `bootstrap/consteval` evaluator and `const fn` are wired into constants, array lengths, constant generic arguments and statics. Evidence: `tests/source/{run,fail}/const-eval-*.mt` (Debug and Release, including the recursion-depth limit, which evaluates on a dedicated large stack) and `compiler.consteval-target` (`tests/consteval/target_width.cpp`); the driver admits no 32-bit target, so target-width evidence is that checker-level unit test. Gap addressed, verified on macOS arm64: a mutable unsuffixed integer local in a `const fn` (`var i = 0`) stays open instead of being fixed to `i32`; assignment of a typed value or a use against a scalar expectation fixes its type (`tests/source/run/const-eval-open-integer-local.mt`). An immutable `let` or a copy into another binding still defaults to `i32`.

I13 L005 extends const evaluation through an LLVM-free driver/LSP callback with
exact target-software IEEE bits, byte arrays, enums and source const receivers.
All 28 values, 92 stable const records (80 forms) and the 79-record supporting-
trait batch have focused receipts in i13-library.md#current-integration-state,
including typed/precondition negatives. This is not complete 301-record runtime/
profile closure; unsized/Static Any and default comparison RHS-Self remain open.

I09 completes required constant evaluation, hygienic declarative macros, host
procedural extensions, attribute/derive/cfg phases and versioned token APIs.
Implement manifest resolution, exact locks, feature/host/target separation,
build scripts and dependency-keyed incremental reuse. Demonstrate a native
multi-package project with a generated input and extension. Corrupted artifacts
must fail verification; untracked host inputs must trigger conservative reruns;
incremental and clean builds must agree. Host Mettle extensions can use the
services delivered in I08, avoiding an undeclared compiler-bootstrap dependency.

I09 T001 additions (package-instance identities, coexisting incompatible
versions, Git commit sources, host/target feature contexts and
`[build-dependencies]`) are implemented and verified on macOS arm64 Release
by `tests/packages.py`; SemVer-compatible registry versions unify (with
backtracking) and only incompatible ones coexist. Every resolved package is
mounted as a root module unless a root module of that name exists. Package
instances receive unique internal module roots and symbol identities; Git
sources use the system `git` CLI and are locked by commit and source checksum.
The host graph is separate from target dependencies and features. Remote HTTP
registries remain open: the package specification does not define a registry
protocol. Existing manifest parsing, SemVer solving over path and local
registry sources, checksums, feature selection, `--locked/--offline/--frozen`
and `mettle check|build` on package directories remain covered by
`tests/packages.py`.

Package configuration migration (2026-11-09): implemented `.mettle` manifests
and locks, explicit library/executable entries, native static/shared and multiple
outputs, minimum `mettle-version`, supporting-module imports and root
development dependencies. Library fixtures and compiler package manifests use
explicit library kinds; the self-hosted implementation is unchanged. Focused
Linux checks pass for entries, native debug/release C++ callers, freestanding
archives, output preservation, version diagnostics, development-context
selection, data/lock parsing, nested imports and resolver features/backtracking/
conflicts. The current package/runtime components and changed driver/backend
objects build with pinned tools. Execution uses changed bootstrap objects with
existing unaffected compiler libraries; this is scoped config/ABI evidence,
not full-current-source qualification. Compiled package interfaces remain I15
work, excluded from this migration.

I09 T002/T003 baseline: implemented and verified on macOS arm64 (Release and Debug).
`[build] script` programs run on the host with declared `mettle:` outputs
(generated modules, features, link libraries) and a `reproducible` input
contract, otherwise rerun conservatively (`bootstrap/driver/build_script.cpp`);
`mettle build` reuses executables/objects through a content-addressed,
deduplicated, byte/age-bounded store keyed by token-level source inputs and
build options (`bootstrap/packages/store.cpp`, `bootstrap/driver/cache.cpp`),
with `mettle clean`. `[build-dependencies]` and host dependency compilation
are verified by the same suite.

I09 cache lease work and the multi-package extension demonstration are
implemented and verified on macOS arm64 Release (`multi_package_extension`). A build holds an RAII lease on its
whole-program key through materialization, publication and pruning;
`bootstrap/packages/store.cpp` excludes leased entries from age/byte eviction
and refuses `clean` while a lease is live. The
`tests/packages/multi-package-extension` fixture combines a generated module,
a procedural extension dependency and a regular dependency. Existing
whole-build cache behavior remains covered by `incremental_reuse`,
`edit_invalidation`, `cache_dedup_and_bound`, `cache_corruption_and_clean`,
`build_script` and `build_script_untracked_inputs` in `tests/packages.py`.
Parsed-AST/name/type/ownership/instantiation dependency separation and
retained-byte/compile-time measurement (performance.md 5.1.1) move to I14 by
owner decision (2026-10-31); Linux evidence is owner-run.

The owner subsequently authorized a bootstrap exception for proper compiled
library reuse: complete `core` first, then `alloc`/`std` through the same
portable interface/import path. Architecture section 1.2 owns the scope and
acceptance contract. Interface encoding/remapping, imported declarations and
constant bodies, symbolic IR linking, invalidation and native-object reuse
are separate obligations, not verified by the existing object cache.
Only focused cold/warm, semantic and corruption/invalidation checks are
authorized for this work; no broad suite restart is implied.
The first implemented prerequisite is `evaluation::CheckedFunction`
(`bootstrap/consteval/evaluate.h`): resolved callable contracts no longer need
a syntax function declaration. Source and imported-call descriptors share the
interpreter's cast, default, unsafe, overflow and recursion-budget behavior;
focused Release `compiler.consteval-target` passes for 32/64-bit target facts.
Persistent checked expressions, declaration/type/region remapping and the
complete import pipeline remain missing. The two-consumer
`checked_core_reuse` acceptance case is currently red at interface publication;
ordinary native execution succeeds, but no checked-core reuse is delivered.
Verified symbolic preparation is now a separate in-memory pipeline boundary
(`PreparedProgram`); ordinary source compilation uses it before specialization
and concrete admission. Its focused phase-ownership regression has passed
translation-unit checks and Release `compiler.boundaries` plus
`compiler.consteval-target` (2/2, 0.02 seconds). Portable type/region and macro records, imported declarations and
checked expressions, symbolic IR linking and store/native integration are not
qualified by this preparation API.
The expansion-owned macro prerequisite is implemented in
`bootstrap/expansion/macro_library.{h,cpp}` and `macros.{h,cpp}`. Portable rule
records preserve private supports, imports/reexports, hygiene and provenance;
complete overlapping module inventories deduplicate only when logically
equal. Focused Release `compiler.macro-library` passes (1/1, 0.05 seconds);
changed decoder/mount/test code also passes targeted pinned ASan/UBSan.
Compiler/configuration/dependency compatibility, revision validation and
registered source/generation provenance remain host obligations. This does
not provide checked declarations, persistent constant bodies or core reuse.
The type/region graph prerequisite is implemented in
`bootstrap/metadata/type_graph.{h,cpp}`, with semantic reconstruction support
in `types`. It uses logical definition/symbol mapping, preserves canonical
structural identities and region ancestry/binders, and commits imports
transactionally. Focused Release `compiler.type-graph` passes (1/1,
0.04 seconds), including pre-existing/future factory equality, substitution,
drop, recursive/regional types, closures/opaque storage and malformed-input
rollback; focused pinned ASan/UBSan also passes. Full declaration/expression/
IR encoding and consumer/store/native integration remain missing.
The subsequent type-graph v2 correction separates closure ordinals from
source-function identities; a polluted consumer mapping regression and focused
ASan/UBSan pass. Driver archive/store primitives are implemented but not wired
into compilation: revision-qualified source/generation/module catalogs,
checksummed section envelopes, bounded verified blob reads and content-based
source/configuration/dependency keys. Focused `compiler.library-archive` and
pinned ASan/UBSan cover remapping, malformed input, corruption recovery,
deduplication, leased eviction and concurrent publication. Source-module catalog
extension currently has incremental sanitizer evidence; its Release rebuild is
pending the shared build slot. Neither these primitives nor the codec
prerequisites demonstrate end-to-end reuse or a speedup.
Portable frontend declarations/checked expressions and symbolic IR now have
focused source-free roundtrip coverage. The integrated compiler builds, and
`compiler.boundaries`, `compiler.library-declarations`,
`compiler.library-archive` and `ir.codec` passed together (4/4, 0.10 seconds)
before the subsequent imported-const eligibility correction reopened the
frontend inputs. The driver now wires lazy checked-core production/import and
native object partitioning, including interface identity in the whole-build
key. This supersedes the earlier missing-integration status: actual full-core
publication and warm source-free interface import now execute two distinct
consumers successfully. Integration fixes preserve Unit literal source identity
and avoid rechecking producer-checked implementation contracts.
Post-correction Release `compiler.library-declarations`,
`compiler.modules-memory` and `compiler.macro-library` pass (3/3, 0.03 seconds);
`compiler.boundaries` and `ir.codec` also have focused passing receipts.
The native-object acceptance exposed whole-build fingerprint bookkeeping that
disabled package-object eligibility; the interface fingerprint now enters the
whole-build key without declaring generated source inputs. Targeted
`checked_core_reuse` and `native_core_object_reuse` now pass: different consumers
reuse both checked interfaces and native objects, with debug/Release ABI and
source-content invalidation coverage. Driver-level interface corruption recovery
and no-cache execution parity also pass. Ineligible source layouts now select
ordinary compilation before registering compiled providers, and native partition
verification errors fail compilation explicitly. The final incremental compiler
build and both targeted reuse cases pass, including executing an externally
linked source module through the ordinary compilation fallback.
A single isolated Linux x86_64 debug sample before these last fallback/error-path
adjustments measured 19.57 seconds cold, 9.69 seconds for a different warm
consumer and 11.80 seconds without caching. Peak compiler RSS was respectively
985128, 595536 and 924812 KiB; the shared cache retained 100989968 bytes for
four entries/blobs and was then cleaned. This is not a repeated benchmark,
release measurement or general speedup claim. Subsequent `alloc`/`std`
integration and focused sanitizer receipts are recorded below.

The subsequent `alloc`/`std` implementation uses the same portable format for
dependency-closed native units, with deterministic replacement of smaller
compiled headers before resolution and separate native-root object ownership.
Actual full hosted-library source checking passes before caching changes.
The integrated incremental build and focused real-library cross-consumer
`alloc`/`std` execution/reuse pass in debug, including different generic arguments,
different consumer function counts and execution of an imported async function.
Coroutine partition support required logical callback names and hidden external
declarations in non-owning partitions, rather than invalid internal declarations.
The new header-replacement/dependency-shadow regression passes in
`compiler.modules-memory`.
2026-11-11 execution/reuse follow-up (working tree based on `75bcceb`;
opportunities, not speedup promises):

| Obligation | Implementation and focused evidence |
| --- | --- |
| Independent machine/ABI cases and profiles | Isolated work directories and bounded parallel units in `tests/backend/machine.py`; focused runner/native evidence, not full ABI qualification. |
| Independent package cases | Process-isolated fixture/cache/work directories in `tests/packages.py`; deliberate cold-cache, corruption and eviction semantics are retained. |
| Smaller scheduling units and early long work | CTest shards and recorded-duration ordering in the existing runners/CMake; coverage is unchanged. |
| Checked preparation reuse | Unchanged imported bodies retain normalization; sealed preparation retains successful loan effects. Exact function equality and transitive callee invalidation guard reuse after specialization; static-storage loan users, changed bodies and new specializations are reanalyzed. Full structural/type verification and cleanup admission remain. |
| Test cache working set | Six real `core`/`alloc`/`std` debug/release interfaces retain 794,493,268 logical bytes, already above 512 MiB without objects. Shared tests use a configurable 2 GiB budget; package cache tests and the normal 512 MiB default are unchanged. This is a lower-bound sample, not the complete suite working set. |
| Library input/archive work | Each native root is snapshotted once per coordinator, reusing captured dependency bytes/keys. Archive payload decoding, hashing and provenance mounting avoid redundant payload copies; content, inventory, checksum and corruption validation remain. |

Baseline compiler SHA-256
`ae455cd2fc11f8aa6e3cff0d87aa22b19e5261c2f498b90c828abbfb931daf9e`
was measured on Linux x86-64/WSL with pinned Clang 22.1.3. Two concurrent
std-profile checks took about 32 seconds cold and 11 seconds warm; these are
single engineering samples, not controlled comparisons. The baseline and
final updated Release boundary/declaration/archive CTests pass (3/3,
0.02 seconds); six changed compiler translation units pass pinned static
analysis. Changed archive/snapshot and preparation/dataflow code also pass
targeted ASan/UBSan instrumentation, linked with uninstrumented supporting
libraries; this is not a full compiler sanitizer qualification.
Final executable inputs are frozen in `optimization-inputs.json` in the
private validation build. Compiler SHA-256:
`4a7a9753c56f5b4970b79cac995a586bcf90b778376aca68d18f8ca358ec3f9e`.
That binary passes four machine/ABI profile units, three source/profile units,
the four-invocation cache-environment regression, `checked_core_reuse`,
`checked_alloc_std_release_reuse` and `checked_library_diagnostics`.
The runner's nine focused scheduling/isolation regressions also pass.
These final package cases cover cross-consumer reuse, uncached execution parity,
dependency-content invalidation, corruption recovery and diagnostic parity.
No broad qualification matrix, I14 performance gate or milestone closure is
claimed by this batch.

The 2026-11-11 focused delivery supersedes the earlier missing-integration status:
`checked_core_reuse`, `native_core_object_reuse`, `checked_alloc_std_reuse` and
`checked_alloc_std_release_reuse` all pass. They check hits for every included
native root, dependency-content invalidation, corruption recovery, uncached
execution parity and imported async execution. `checked_native_macro_reuse`
also passes with a consumer macro shadowing the library's private helper.
An emitted ASan/leak-enabled build importing the real hosted async closure
executes cleanly; its isolated cache and executable were cleaned. This does not
instrument the C++ compiler or qualify every cleanup path.
Cold source failures now forward original phases, spans, related messages and
generated provenance rather than wrapping source errors as metadata errors.
The final incremental build, `compiler.modules-memory`,
`checked_native_macro_reuse` and `checked_library_diagnostics` pass after that
error-path correction; the last test compares exact ordinary and macro-generated
source diagnostic lines against uncached compilation and rejects publication.
The heavy passing execution groups were not repeated after the error-only change.
This error-path receipt covers the focused cases above; cross-target,
reproducibility and full compiler-sanitizer qualification are separate scopes.
No new general speedup claim is made.

The subsequent Linux host qualification exposed a checked-interface phase
mismatch: text iterator calls failed with caching but passed from source.
Imported implementation targets had already been region-decorated while
consumer receiver selection still used nominal types. Contracts now retain
separate checking and finalized region databases; import selects each at its
owning phase without erasing constraints or rechecking dependency bodies.
A minimal regional associated-interface roundtrip reproduces the failure and
passes under the compiler's ASan/UBSan build after the fix. Final affected
integration reruns also exposed implementation-owned callable bounds missing
from consumer region context. Restoring those bounds before the imported-rule
early return fixes the minimal mapper regression and the real alloc iterator
adapter in both source profiles; the adapter also builds and executes with the
ASan/UBSan compiler. Five affected instrumented compiler groups pass.

The same qualification found macro exports being overwritten for every loaded
source, so checked libraries retained only the last module's macro inventory.
Per-source exports now accumulate through expansion's existing validated
import/export machinery, preserving overlap checks and source-qualified hygiene.
The extended multi-file native macro reuse and exact diagnostic cases pass,
as do the original global-assembly generic-symbol case and macro/module units.
Ten affected ASan/UBSan compiler groups and both macro/diagnostic driver cases
also pass after that fix. The final host batch's owner-accepted disposition is
recorded at the start of this section.

Controlled profiling found loan-origin initialization traversing large static
tables without view-bearing values. It now uses the existing conservative
`containsViews(type, true)` check to skip those initializer subtrees; only view
addresses can seed static loans, and erased payloads remain included.
Three static-address/initializer execution cases pass in both
profiles and three static-borrow rejection cases pass. The same focused source
cases pass under ASan/UBSan, along with four affected
compiler/cleanup groups. The superseded old-compiler batch was stopped and its
receipts preserved.
The arbitrary 20-second CPU gate and its timing-only fixture were removed;
behavioral cases remain unchanged. No general speedup claim is made.

Dependency-object reuse passes macOS ARM64 Release `object_cache_integrity`
(root-only reuse, clean/incremental equivalence, corruption recovery). Package
ownership survives loader/IR specialization; only non-generic unambiguous
functions/statics enter dependency objects, with stable external package
symbols. Helpers/generics/entry remain root-owned. Uncertain/generated inputs,
global asm, debug info, sanitizers, harness, freestanding/package-context,
Release and non-executable builds retain one object. Exact source/dependency/
compiler/target/profile/feature/codegen identities key reuse; batch publication
hashes outside the store lock. No package leases: eviction causes a safe miss.
Front-end/specialization still reruns whole-program. Storage design and unmeasured
D17 gate: performance.md section 5.1.1.

I10 can progress alongside I08/I09 after I07. The initial I10 surface is
implemented (see S018-S023) with `library.std`, `runtime.thread` and scalar
compiler cases; Linux-target qualification remains open. Emitted-program
`--sanitize address` and `--sanitize thread` support, including runtime variants
and cache separation, is implemented and verified on macOS arm64 by
`probe.sanitizers`, which requires an ASan heap-buffer-overflow report, a
clean ASan run of a program holding a zero-sized allocator (zero-sized loads
and stores are removed before instrumentation), and a TSan data-race report
from emitted programs.
`--sanitize address,thread` is rejected. UBSan for emitted Mettle IR is not
implemented; `--sanitize undefined` produces an explicit unsupported diagnostic
because Mettle already checks integer overflow and this backend emits no other
UBSan checks. The prior manual out-of-tree TSan run is not qualification. The
S022/S023 additions are implemented and verified on macOS arm64 (std programs).
Channels provide an unbounded `channel`, bounded
`sync_channel` including zero-capacity rendezvous, timeout/try operations,
receiver iteration and `Select`. TLS supports static lazy-initialized keys and
documented thread/main-exit destruction ordering. Static keys use aggregate
initializers rather than `LocalKey.new`, because generic const functions are
not evaluated in static initializers.
Implement owned/scoped threads,
Transferable/Shareable, Arc/weak races, mutex/RwLock guards, condition variables,
barriers, once, channels and TLS. Test scope exit during panic, last-owner
destruction, guard affinity, channel shutdown and atomic publication under
contention. Race freedom is not a claim of fairness or deadlock freedom.
Add P09 and complete concurrent P08 coverage. (P08/P09 move to I14 by owner
decision, 2026-10-31.) The thread, sync and async std programs ran clean under
emitted TSan on macOS arm64 at the I07-I12 closure revision.

I11 implements pinned future state machines, async callable/interface contracts,
poll/wake integration and a separately selectable executor. Establish direct
borrowed await and owned tasks before borrowed-task execution epochs. The scope
must retain soundness for forgotten handles/parents, repeated wakes, worker panic,
parent destruction and an uncooperative child poll. Check actual cleanup versus
cancellation requests; no hidden mandatory boxing or default executor in core.
Exercise an async network service and P10 without weaker lifetime guarantees.

I11 implementation contracts: compiler-architecture.md's I11 interface plan;
the complete requirement/file/fixture inventory below remains authoritative.
`core.future` is allocation/executor-free; `std.task` is optional.

- Static `alloc.future.Erased<T>` owns a fixed-address payload with typed
  poll/release callbacks. Executor registrations outlive handles/wakes; spawn
  requires Transferable + Static. Drop/abort cancels and handles report poll/drop
  panic. Close/completion serialize queue insertion; foreign wakers own metadata
  only; reentrant cancellation defers until poll returns and same-executor join/
  run/run_until_stalled rejects. Finished-registration reclamation has the
  **2026-11-09 focused** ASan/leak/TSan receipts above, not full qualification.
- Synchronous task.scope drives ready children and drains suspended children on
  exit/unwind, including forgotten handles; it does not suspend across parent
  polls. Async task.async_scope owns pinned children, polls only in parent
  epochs, closes wake metadata/drains synchronously on parent drop, and drains
  before propagating child panic. Wakers own readiness/parent-waker metadata,
  never parent/child storage. Within bounds bind the nominal scope region before
  receiver shortening. Earlier unsound receiver attempt was withdrawn; accepted
  and rejected cases accompany the repair.
- Async I/O uses optional reactor/timer futures and nonblocking TCP; kqueue on
  macOS, poll fallback elsewhere. Retry classifies raw EAGAIN independently of
  blocking timeout mapping; unsized async slice parameters capture views.
- Parser desugars async free/method/block/closure bodies into an ordinary checked
  take coroutine behind opaque Future, await into poll/suspend. Exit::Suspend
  carries resume edges through ownership analyses. Backend persistent frame
  retains SSA/locals/drop flags, stable child storage, cancellation and safe
  post-completion/panic poll behavior. State is !Unpin; concurrency includes
  output/captures/scope-based interior, which can conservatively reject dead
  values whose scopes cross await. Static requires output/captures.
- Async interface methods expose output/region-bound future families; defaults
  infer their own result, inherited Self-substitution and overrides retain
  correct families (`ir::Function::interfaceResult`). Captured read/mut parameters
  remain views; invariant nominal region inference uses same-origin fields.
  Pinned erased Future.poll dispatch requires fixed Output; witness adapters
  reconstruct Pin<mut Concrete> from erased data. Box<any Future> uses ordinary
  unsizing/drop with unsafe payload pin; safe pinned owners remain S003.
  **Erased async-interface dispatch** still requires an explicit future-storage
  contract; borrowed heap-erased futures require region-carrying erasure.

Historical macOS ARM64 evidence:

| Receipt | Scope and remaining limitation |
| --- | --- |
| Core coroutine/executor | Release 23/23 CTest; Debug 23/23 at `c81bc6d`. `async-await-anywhere` and async run cases cover control flow, self-borrows, typed failure, exactly-once drops; std async_executor/async_spawn and Rc-across-await/borrowed-spawn negatives. CPS combinators and their unsupported fixtures removed. |
| Compiler sanitizers | Debug-sanitized 22/24; packages.resolution/probe.broken-pipe time out (43 s std compile versus 30 s bound), then pass unmodified without that bound. Not a passing bounded run. Historical throwaway emitted ASan/UBSan async Debug/Release runs are not a repository gate. |
| Async I/O | async_net_echo passes Release library.std and emitted ASan/TSan: concurrent clients, timer, suspended-accept drop. Linux poll fallback remains unqualified. |
| Async families/defaults | Release 24/24 with arrow closure, try-await, interface/default/erasure-diagnostic/debug-info changes. Five positive default paths now consolidated in `async-interface-default-explicit-output.mt`; separate `fail/async-interface-default-future-outlives-receiver.mt`. Mapping does not requalify changed fixtures. |
| Borrowed scopes | library.std, emitted ASan/TSan and independent review without blocking findings: completion, parent cancellation, panic/sibling drain, stale wakes and short-capture rejection; exact cases in inventory. |
| Erased polling/owners | `tests/std/erased_future_dispatch.mt`, `owned_erased_future.mt`: typed witness polling, polled/unpolled exactly-once owner drops. Not erased async-interface dispatch. |
| Region/debug follow-ups | `constructor-infers-region-across-invariant-fields.mt` plus invariant negatives; direct/mutual recursive async call type diagnostics at call spans; debug_info state variants/discriminator. LLDB summary not interactively rerun. |

Linux/Windows coroutine-path qualification and executor TSan beyond these scoped
receipts remain open. P10's equivalent async-service source/comparator/protocol
moves to I14 (owner decision 2026-10-31), not a specified benchmark pass.

#### I11 coroutine replacement inventory

Revision: uncommitted lane changes on `9d865a1`; scope as stated per row.

| Requirement | State and owning files | Remaining work and required fixtures |
| --- | --- | --- |
| Preserve async source; type future and await | Implemented and verified on macOS arm64, including arrow async closures and `try await`: `syntax/parser/closures.cpp`, `syntax/parser/async.cpp`, `semantics/sums.cpp`, `semantics/regions.cpp`, `lowering/sums.cpp`. | `async-arrow-closure.mt`, `async-try-await.mt`. |
| Async interface futures and dispatch | Output/region-bound families, concrete/generic calls, inferred defaults, inherited Self-substitution and override families verified on macOS arm64. | `async-interface-method.mt`, `async-interface-erased-dispatch.mt`, `async-interface-default-explicit-output.mt` (all five default paths), `fail/async-interface-default-future-outlives-receiver.mt`. Erased async-interface dispatch remains unsupported; borrowed heap-erased futures require region-carrying storage. |
| Erased Future polling and storage | Pinned poll dispatch through `any Future<Output = T>` and the `alloc.future.Erased<T>` static heap wrapper are implemented. The verifier accepts the Pin-wrapped erased receiver, and LLVM emits a witness adapter that repackages the data pointer as `Pin<mut Concrete>`; the adapter and verifier changes are verified on macOS arm64. The wrapper owns a stable concrete payload and uses typed poll/release callbacks. The general `Box<any Future<Output = T>>` path is verified. | `tests/std/erased_future_dispatch.mt`, `tests/std/owned_erased_future.mt`; erased async-interface returns remain unsupported. |
| Recursive async future cycles | Implemented and verified on macOS arm64: `semantics/check.cpp` diagnoses direct and mutual recursive async call cycles in the type phase at the recursive call span and names the cycle. | `async-recursive-future-direct.mt`, `async-recursive-future-mutual.mt`. |
| Ownership-checked suspension CFG | Implemented: `ir/ir.h` `Exit::Suspend`, `ir/verify.cpp`, successor updates in `analysis/*`, `ir/dominance.cpp`, `instances/arrays.cpp`, `lowering/scalar.cpp`. | None known; borrow-across-await is covered by `async-await-anywhere.mt`. |
| Inline pinned state and poll | Implemented: `types` coroutine aggregate and layout resolver, `instances/specialize.cpp`, backend frame/dispatch. Transferable/Shareable/Static in `semantics/interface_solver.cpp` with the interior from `semantics/captures.cpp`. | Liveness-precise interior (optional precision gain). |
| Control flow | Implemented: ordinary CFG of the closure body. | None known. |
| Cleanup and cancellation | Implemented: persistent frame flags and `unwind` in `backend/llvm/cleanup.cpp`; exactly-once drops verified. | None known; lexical drop order across suspension and cancellation is verified on macOS arm64 by `async-drop-order-across-await.mt`. |
| Optional executor drives async I/O (S030) | Implemented and verified on macOS arm64: `library/std/task.mt`, `library/std/net.mt`, `library/std/sys.mt`, `library/core/future.mt`, `runtime/sys.{h,cpp}`; `tests/std/async_net_echo.mt` passes in Release CTest and under emitted ASan/TSan. | Kqueue wake-race stress; Linux poll-fallback qualification (owner-run). |
| Asynchronous borrowed task scopes | Implemented and verified on macOS arm64 (Release `library.std`, emitted ASan/TSan, independent review without blocking findings): `library/std/task.mt` provides `task.async_scope(anchor)`, whose future owns registered borrowed children and polls them only inside parent epochs; handles do not own registrations, wake metadata cannot access parent storage, parent destruction synchronously drains children, and child panic drains before propagation. `Executor.run` and `run_until_stalled` now reject same-executor reentrancy with a panic. | `tests/std/async_scope_borrowed.mt`, `async_scope_panic.mt`, `neg_async_scope_borrow_escape.mt`, `neg_async_scope_mut_receiver_short_borrow.mt` and `async-scope-{abandon,drop-panic,wake-close-race,pinned-children,completion,reentrant-executor}.mt`; the retired `async_scope_cancel.mt` repeated stale-wake check is retained in `async-scope-abandon.mt`, without extending historical qualification. |
| Integration and qualification | Release CTest, sanitized compiler CTest and ASan/UBSan emitted async programs passed on macOS arm64 before this change; the Debug-profile CTest passed 23/23 at `c81bc6d`. The full Release CTest passed 24/24 with the async closure, `try await`, interface dispatch, erasure-diagnostic and debug-info state-discriminator changes. | Linux/Windows (owner-run). |

The source-freeze gate depends on all rows, fixtures and documentation; a
design or a partially implemented row is not a verified milestone.

### 8.5. Workflow, profiles and V1: I12-I14

I12 closes the complete native developer workflow: command selection, diagnostic
categories, test/benchmark results, doctest checking phases, formatting, linting,
LSP and source-level debug information, including owners/erasure/async states.
Build minimal formatting/editor/debug support as the relevant syntax and IR land;
do not wait until I12 to preserve spans or discover uninspectable values.
I12 is the completion gate, not the first tooling work.

I12 macOS ARM64 implementation/evidence (owning contracts:
tooling-and-packages.md sections 3-5):

| Surface | Verified behavior / exact package or source cases |
| --- | --- |
| fmt | Token/fingerprint/idempotence-checked whitespace formatting; list-comma/operator line breaks; chained calls not broken. |
| run/test/bench/doc | Package-wide qualified test/bench collection, JSON lines, per-test timeout, isolated module doctests and deterministic HTML; `test_json_timeout_and_modules`, `doc_writes_deterministic_html`, `doctests_run_isolated_examples`. Fences: no_run/ignore/should_panic/compile_fail(PHASE). black_box, deliberately no invented handle API. |
| docs/lint | Resolved dependency links/pages, unresolved warnings and static search index; `doc_resolves_dependency_links_and_warns`. Five checked-fact lints, flags/attributes/JSON: `lint_reports_semantic_findings` and lint_/doc cases. No unspecified extra lint rules. |
| LSP | `language_server`: checked hover, completion/signature/references, pattern navigation, provider indexing and readable notes/help; `diagnostic-help-*`. Documented precision limits are not omitted I12 acceptance cases. |
| Debug | `debug_info`: layout-based sums, slice lengths, generic/products/closures/macro locations, coroutine variants/state/live locals/captures/output, lexical/move locations, erased witness types and release inlining. `debugger_workflow`: LLDB breakpoints/locals/parameters/List/slice/sum/erased/suspended-coroutine summaries. Earlier updated summaries were not interactively rerun. Windows CodeView/PDB excluded from historical macOS gate. |

Driver/component ownership is in compiler-architecture.md, not duplicated here.

Moved into I13 (owner decision 2026-10-31): S003 safe pinned heap/shared owners.
Current library implementation, blockers and exact focused receipts are owned by
[i13-library.md](i13-library.md#handoff-start-here-in-a-new-session); the
[capability inventory](capability-coverage.md#i13-macos-arm64-acceptance-inventory)
retains row/fixture ownership. All eighteen library areas remain partial.
Latest 2026-11-12 operation ledger: **11,345 evidenced, 74 declared,
1,871 missing, 5 not applicable** (13,295 total, grouped into 2,442 operation
and 2,309 implementation families; subset/source-cfg reconciliation pending).
Unzip has focused Linux native/emitted-ASan debug/release evidence; 20
conversion blanket exposures remain declared. Fifteen callable-adapter
Clone/ToOwned rows now have debug/release execution evidence. Peekable
cached-absence cloning passes; complete cache-cloning qualification remains open.
The first collection/vector group's 403 records now have scoped evidence,
including its 35 stable-const obligations and six exclusive-split exposures.
Shared read-view endpoints additionally close four core-slice exposures;
exclusive splits close six more. Current normal/negative, compiler-ASan/UBSan
and emitted-ASan receipts are recorded in i13-library.md; this is not complete
library-area, Linux-host or I13 qualification.
Minimal NonNull, borrowed chaining, bounds/exact/fused protocols
and collision-safe Any identity have scoped evidence, not full-area closure;
Static/unsized Any, synchronization and complete operation coverage remain open.
The [2026-11-11 reconciliation](i13-library.md#parallel-reconciliation-2026-11-11)
adds generic synchronous socket inputs, UDP peek_from and focused NonNull
signature/alignment repairs. Eleven network and ten non-stable-const pointer
records gain scoped evidence. Another 54 pointer records retain runtime
acceptance but lack required stable-const support. Canonical-ID-deduplicated
review corrected 2,197 further integer records to declared, beyond the earlier
312 power/division records: their runtime passes did not establish the required
constant-callability. All 2,509 stable-const integer method records now have
exact required-constant mappings and sixteen passing normal/compiler-ASan/UBSan
debug/release units on frozen Linux x86-64 inputs (twelve executions and four
intended invalid-radix rejections). The
[integer acceptance](i13-library.md#current-constcompiler-integration-2026-11-12)
records identities and scope; it is not later-compiler or whole-area closure.
D31's ownership-type separation has focused
ordinary and emitted-ASan cleanup acceptance; exact operation mapping remains
open. Five IO records and one owning-array implementation gain scoped evidence.
Fifteen further buffered-reader/BufRead records have focused both-profile
state/error/recovery evidence. Minimal borrowed-iterator retirement is repaired
with branch-origin refinement; borrowed-inner Flatten's loop-carried result
and callable Clone remain compiler blockers.
No whole library area is closed.
Ten File/UDP operations have focused Linux debug/release evidence from the
[hosted reconciliation](i13-library.md#focused-hosted-reconciliation-2026-11-09).
Its generic UDP address, empty-datagram
and nonblocking gaps are superseded by the focused 2026-11-11 batch, not by the
earlier blocking loopback tests. Neither batch qualifies a compiler revision.

I13 closes the V1 operation subset defined in `docs/library-surface.md`
section 6.1 with compiled native declarations and per-operation semantic
evidence, including its supporting protocols, reexports and target cfg branches
missing from rendered docs. Other applicable non-deprecated stable inventory
obligations move to I17 and are not a V1 gate. The 2026-11-09 owner amendment
excludes deprecated APIs from required scope while preserving reference records.
Gate only the `linux-x64` profile (Linux x86-64 compiler host and
x86_64-unknown-linux-gnu target; owner decision 2026-11-08, section 8.0). The
earlier macOS ARM64/Darwin lane gate is superseded; Windows remains excluded
from gates and not qualified. Other target references (Android, WASI, non-hosted Wasm and
freestanding) are likewise not qualified by this lane. Verify applicable native
C ABI and debug/unwind/TLS/atomic behavior on the selected profile; the optional
Rust bridge (A009) belongs to I17. Cross-compiling is not a substitute for
execution/probes; an inapplicable service is not a pass. Evidence must retain
exact target applicability.

Historical macOS ARM64 capability inventory: source/fixture audit at `0eea2fa`,
no new build/run. After recorded updates it has **88 evidenced, 18 partial,
1 missing** (A009, owner-deferred to I17), not the earlier 67/39 snapshot.
Capability evidence is not per-operation qualification: the baseline has
106,125 canonical contracts; V1 selects about 2,900 folded operation families
and 1,760 trait/type pairs. No receipt closes that subset. Linux qualification of pinned owners,
erased async-interface dispatch, per-item target/cfg applicability (S031),
supporting protocols/reexports and selected ABI/debug/unwind/TLS/atomic probes
remain governed by the capability inventory/work package. Other applicable
non-deprecated stable operations belong to I17, not a silently expanded I13 gate.

Moved into I14 by owner decision (2026-10-31): I09 compile-time and
retained-byte measurement with front-end dependency separation (performance.md
5.1.1), I10 benchmarks P08 and P09, and I11 benchmark P10 with its async
network service, measurement protocol and comparator.

I14 freezes a release candidate and checks the whole accepted scope, rather than
removing difficult capabilities to produce a smaller V1. The owner-selected V1
operation subset (`docs/library-surface.md` section 6.1) is the only accepted
operation-scope reduction; it does not drop any capability row. Run the predeclared
pilot/fixed-sample runtime protocol, the compile-time and build-storage gates
(performance.md section 5.1) and all supported-profile acceptance suites;
preserve raw failures/inconclusive results. A faster workload cannot offset a
credible regression elsewhere. Verify clean installation and native compilation
without Rust. Resolve the owner's license/distribution decisions before public
publication; internal implementation does not require inventing those decisions.

### 8.6. Architectural evolution and operation completion: I15-I17

I15 ports substantive compiler functionality to Mettle, not a thin launcher
around the C++ implementation. Port incrementally, starting with self-contained
front-end components (lexer, parser) checked for identical output against the
C++ reference. Retain the C++ bootstrap/compiler reference,
record staged builds and exercise the resulting compiler on itself and the
full capability/target corpus. Add the applicable P12 compiler workload.
Self-hosting alone proves neither correctness nor improved runtime.

I15 preparation started 2026-11-09. The
[self-hosted architecture](compiler-architecture.md#11-self-hosted-compiler-package-and-incremental-compilation-contract)
owns package boundaries, compiled interfaces, query invalidation and storage.
Preparatory work does not close I13/I14 or qualify I15.

| Obligation | Current state and evidence | Owning implementation / remaining acceptance |
| --- | --- | --- |
| Package/API and rebuild contracts | Source-package edges exercised by the lexer seed; independent compilation remains specified only | Architecture section 1.1; implement compiled interfaces and query reuse |
| Foundation, syntax and driver seed | Builds and runs on Linux x86-64 in debug/release; 114 token/diagnostic parity cases pass per profile | `compiler/{foundation,syntax,driver}`; `tests/probes.py selfhost-lexer BOOTSTRAP EVIDENCE --seed DRIVER`; complete syntax coverage remains open |
| Parser core | Partial grammar implemented; initial 60-case debug/release receipt, expanded receipts below | `syntax/{tree,parser}` owns unchanged tokens, compact node/child arenas, spans and syntax-only IDs. Functions, types, generic applications, imports/modules, core expressions/statements, precedence, newline/semicolon tails, nested blocks, recovery and depth limits are exercised. This is historical subset evidence; the remaining forms are covered by the parser-closure row. No semantic type/IR/ownership interface changes are required. |
| Structural type parser | Implemented; expanded 105-case parser probe passes in debug/release and the address-sanitized native driver on Linux x86-64, based on `20e7bba` | `syntax/{parser,tree}` now represents slices/arrays, tuples/groups, borrows, owners/pinning, pointers, optionals and source annotations from language-grammar section 3. `selfhost-parser` adds accepted structure, immutable token spans, malformed/recovery and depth cases. Generic, callable, bounded and projection types remain outside this batch. No semantic/IR/backend changes. |
| Parser lookahead hardening | Implemented; 108 focused cases pass in debug/release and the address-sanitized native driver | `syntax/parser` named-generic lookahead previously rescanned comma-separated comparisons. A lazy per-opening rejection bitset and reusable unmatched-opening stack preserve viable inner applications. Existing 105-case receipts precede this change; the expanded probe retains 108 cases and 223 commands per configuration. No C++/library changes or release speed claim. |
| Extended type parser | Implemented; final 150-case probe passes in debug/release and the address-sanitized native driver | `syntax/{parser,tree}` now represents named/region/constant/associated arguments, higher-ranked region binders, callable signatures/effects, erased/opaque bounds and associated projections from language-grammar sections 2-3. `selfhost-parser` covers type structure, angle-token boundaries, effect attachment, rejection/recovery and depth, including quoted `Outcome` identity. Async callable types retained the bootstrap's explicit feature diagnostic in that batch; parser closure adds their syntax. Declaration generics and generic calls are implemented in the following batch; no semantic/IR/backend changes. |
| Generic function declarations and applications | Implemented; 183 cases verified in debug incrementally and in complete release/address-sanitized runs | `syntax/{parser,tree}` now represents generic parameters/defaults, bounds/where clauses, parameter defaults, effects, visibility/unsafe/const modifiers and expression bodies. Applications use the shared type-argument parser with rollback and context-aware rejection caching. Focused probes cover declaration structure, generic followers, mixed constant/type arguments, diagnostics/recovery and comparison scaling. Contextual `.drop` names now parse. Other item declarations, parameter patterns/receivers, foreign/variadic function declarations and async bodies remain separate work. Prior 150-case receipts precede this batch. |
| Import/module declarations | Implemented; 203 cases verified in debug incrementally and in complete release/address-sanitized runs | `syntax/{parser,tree}` now represents import paths/aliases/groups/globs, shared visibility, external/inline modules, item separators, scoped recovery and nesting limits. The existing parser probe checks hierarchy/spans, lexical token parity and bootstrap syntax acceptance/rejection. Source loading, canonical module identities and name resolution stay outside parsing. Prior 183-case receipts precede this batch; no I15 closure claim. |
| Remaining native parser closure | Implemented; frozen debug/release/emitted-ASan runs pass 260 focused cases and 997 corpus expectations per profile | `syntax/{parser,tree,characters}` represents products/unions/enums, interfaces/extensions/associated items, aliases/constants/statics/foreign items, attributes/balanced token trees, full patterns/matching, closures/async bodies, conditional bindings, iteration/labels, interpolation, named/optional/projection postfixes and nested items. Focused cases cover tree ownership/spans, malformed forms and recovery. Each profile passes 260 focused probes and 997 corpus expectations (990 accepted; seven malformed fixtures rejected); all four native parser package tests also pass in debug. Contextual `extend` probes restore failed declaration attempts before expression parsing; recovery skips callable `fn` tokens inside malformed parameter/type delimiters. Compiler/seed-library/probe identities and receipts are retained under `/home/nites/lanes/selfhost-86da951/parser-closure/` (`frozen-inputs.json`, `final-{debug,release,asan}`, corpus receipts and `unit-tests-debug.json`). No sanitizer reports occurred; source inputs stayed unchanged through qualification. No semantic desugaring, macro expansion/schema checking, module loading or code generation is included. The separate Unicode-XID/NFC qualification is recorded in the following row. |
| Parser/driver correctness review | Implemented; 14 focused probes and two bounded-reader tests pass in debug/release/emitted-ASan | `syntax/parser` isolates/restores block generic boundaries and retains contextual `format` parameter modifiers. `driver/main` checks opened regular-file size before allocation and bounds reads before appending. Probes cover nested generic shifts/closers, modifier structure/contextual names and oversized sparse-file rejection in both CLI modes (96 MiB process cap in debug/release; uncapped under ASan); reader tests cover zero/exact/over-limit and multi-chunk input. Preserved `seed-final/mettle` and `/home/nites/mettle-d/library` were used; receipts are under the existing selfhost evidence directory in `repairs-focus-{debug,release,asan}` plus `repairs-restore-debug`. Current concurrent bootstrap/library work and milestone closure remain unqualified. |
| Source-size policy alignment | Implemented; bootstrap syntax/packages build and pinned formatting pass; debug/release/emitted-ASan sparse-file probes pass | Source/data byte ceilings are 2^32 - 1, the self-hosted per-file `u32` span range, rather than an arbitrary 1 GiB cap. `foundation.SOURCE_BYTES` is shared by the driver/lexer; `bootstrap/support/limits.h` matches it. The existing probe rejects a sparse 4 GiB source in both CLI modes before allocation (96 MiB cap in debug/release, uncapped under ASan); receipts are in `source-cap-{debug,release,asan}` under the existing selfhost evidence directory, using the preserved bootstrap/library. Prior review receipts exercised the old 1 GiB boundary; no multi-GiB successful compilation, full bootstrap requalification or milestone closure is claimed. |
| Native Unicode identifiers | Implemented and verified on frozen inputs in debug/release/emitted-ASan | `syntax/{lexer,token,identifiers,unicode_data}` uses pinned Unicode 16.0.0 XID/normalization data, retains original token/source spans and exposes NFC names on demand through `Token.identifier`. `tools/identifier_tables.py` validates official UCD hashes before generating 66,892 bytes of table entries. The existing probe runner and `tests/selfhost/unicode` cover ordinary/backtick names, invalid starts, byte spans, canonical identity, blocked composition/Hangul/long combining runs, all 19,965 normalization rows, the unlisted-singleton rule across all 1,112,064 scalars and XID membership across 1,114,112 code points. All three profiles pass 123 lexer cases, 57 parser grammar compatibility cases and complete NFC/XID conformance without sanitizer reports. Pinned formatting and exact table regeneration pass. Receipts and unchanged source/seed-library/UCD identities are under `/home/nites/lanes/selfhost-86da951/unicode/`: `final-{debug,release,asan}`, `frozen-inputs.json` and the reused, identical-input debug conformance receipt `development-full-debug`. No expansion/semantics work. |
| Compiled dependency interfaces and query engine | Missing | Future `pipeline`, `ir`, `packages`; consumers must skip unchanged dependency parsing/checking; validate metadata and invalidation edges |
| Checked frontend and verified middle end | Missing | Future `frontend`, `types`, `ir`, `middle`; preserve full language/ownership contracts and existing corpus |
| Backend, build and editor integration | Missing | Future backend/pipeline/packages/editor/driver implementations; replace C++ responsibilities through defined interfaces |
| Bounded storage and compiler/runtime performance | Unverified for self-hosting | Existing store is bootstrap code; qualify self-hosted eviction/corruption/concurrency and clean/edited workloads under performance.md, including P12 |
| Source freeze and staged bootstrap | Not ready; depends on all implementation, fixtures and owning documentation | Stage 1/2/3 identities, repeatability and complete capability/target gates; retain C++ reference |

The 2026-11-09 lexer batch covers token kinds/byte spans, diagnostic phases,
messages/start locations, complete character-literal diagnostic ranges and the
diagnostic budget. Its 112 cases include malformed UTF-8/literals, nested
comments/interpolation, 64 deterministic mixed inputs and all eight compiler
source files. Build `compiler/driver` with the C++ bootstrap and run the produced
lexer with a source-file argument. That batch does not qualify parsed syntax,
decoded text payloads, independent compilation or performance.

The following parser-core batch adds `DRIVER syntax SOURCE` and
`tests/probes.py selfhost-parser BOOTSTRAP EVIDENCE --seed DRIVER`. Its 60 cases
compare supported function-body structure, token spans and rejection diagnostics
with the C++ reference, and check arena reachability, recovery, literal escapes,
explicit feature diagnostics and resource limits. Debug/release and the
address-sanitized native driver pass all 60; both ordinary profiles also pass
the expanded 114-case lexer corpus, including all ten compiler source files.
Evidence is retained under `/home/nites/lanes/selfhost-86da951/parser-final-{debug,release,asan}`.
This qualifies the exercised parser subset, not the entire bootstrap compiler
under sanitizers. Full grammar, semantic checking and self-compilation remain open.

The 2026-11-10 structural-type batch expands that probe to 105 cases (219
commands) per debug/release/address-sanitized native driver. Type acceptance and
rejection locations are compared with the preserved C++ seed; type-node shapes
are checked against explicit grammar expectations because the C++ inspector
does not expose type trees. The batch covers partial-token `>>=` pointer closers,
individual `??` suffix spans, parenthesized borrow/optional nesting, source
annotations, malformed-type recovery and type-depth limits. Evidence is retained
under `/home/nites/lanes/selfhost-86da951/types-final-{debug,release,asan}`.
It does not qualify concurrent C++/library changes, semantic typing or I15 closure.

The subsequent parser review reproduced repeated named-application lookahead on
flat comparison arguments. At 512/2,048/8,192 arguments, the native release
`syntax` command took 0.045/0.447/7.115 seconds before rejection caching and
0.008/0.028/0.129 seconds afterward. These single-run, shared-host measurements
include inspection output and are engineering evidence, not P12 or a release
comparison. Inputs and binary identities are retained under the existing
selfhost evidence directory in `parser-scaling/{before,after}.json`; focused
debug/release/address-sanitized receipts are in `lookahead-final-{debug,release,asan}`.
The three added cases cover repeated comparisons and viable flat/nested generic
calls inside rejected outer lookahead. Generic syntax was unimplemented at that
batch's source revision; the following batch adds generic types.

The extended-type batch passes 150 cases (339 commands) per native debug,
release and address-sanitized driver, with receipts under the existing selfhost
evidence directory in `extended-final-{debug,release,asan}`. Generic constants
preserve closing-angle boundaries while parentheses/braces permit shift
expressions; named-to-constant fallback leaves no orphan nodes. Callable cases
cover access, ABI/variadic syntax, region binders and nested/grouped effect
attachment. Outcome arity/positional requirements also apply to quoted names.
The selected grammar's `Buffer<const {N + 1}>` is accepted and checked against
explicit native structure and bootstrap lexer tokens; the preserved C++ seed
rejects this form at `{`, so its parser is not used as the acceptance oracle
for that case. This records a reference discrepancy, not a new language form.
Concurrent C++/library changes, semantic typing and I15 closure are unqualified.

The generic-function batch verifies 183 parser cases. Debug evidence combines
178 passing cases in `functions-final-debug` with five signature/application
cases in `functions-final-debug-tail`, using the same native binary identity;
the first run stopped on a test-display expectation corrected without native
source changes. Release and address-sanitized runs pass all 183 cases (459
commands each) under `functions-final-{release,asan}` in the existing selfhost
evidence directory. The existing probe's `--filter` selects focused parser cases.
Coverage includes syntax-only generic followers, qualified specialized members,
contextual `.drop`, full signature structure, failed-lookahead rollback and the
100-diagnostic cap. The 512/2,048/8,192 comparison-argument inspection took
0.019/0.065/0.225 seconds on the shared host, retained in
`parser-scaling/generic-functions.json`; this is engineering scaling evidence,
not a release or best-in-class performance result.

The import/module batch verifies 203 cases. Debug combines 26 focused cases
under `modules-focus-debug` and 177 remaining cases under
`modules-regressions-debug`, using the same native binary identity. Release and
address-sanitized runs pass all 203 cases (496 commands each) under
`modules-final-{release,asan}` in the existing selfhost evidence directory.
New cases cover nested hierarchy, visibility/aliases/groups/globs, item
terminators, external-module comment lookahead, malformed-item recovery and
module-depth limits. Nine literal diagnostic messages were matched against the
preserved bootstrap in the debug run, then retained as explicit expectations;
`modules-literal-expectations-debug` rechecks those nine cases without redundant
bootstrap library checks. Native phase/message/full-literal-span assertions
remain enforced. Concurrent C++/library work, module loading, name resolution
and full self-hosting remain unqualified.

Seed compilation exposed a bootstrap ownership-analysis crash: generic payload
traversal discarded enclosing field paths and used payload indices against
wrapper fields. `analysis/origins.cpp` now preserves prefixes and typed field
metadata. The current analysis component builds; two run cases pass both source
profiles and three ownership rejection cases pass. Focused ASan/UBSan checks
instrument that changed translation unit with existing unaffected Release
objects, not the whole compiler or emitted lexer. Startup and intentional
detectors pass. The new boxed-view rejection exceeded the ordinary 60-second
instrumented compile limit, then passed unchanged in 164 seconds with the
runner's `--timeout-scale 3`; the other focused cases pass at their normal limits.

I16 replaces LLVM's production backend responsibilities behind the compiler IR
boundary: instruction selection/legalization, registers, machine optimization,
object/debug/unwind emission and each accepted target's ABI integration.
System linkers/SDKs remain explicit profile dependencies; LLVM code generation
cannot remain a hidden fallback. Compare both backend paths and Rust under
equivalent semantics and requalify every accepted profile. The independent
backend must provide address/undefined-behavior and thread checking equivalent
to the current ASan/UBSan/TSan qualification, or run the full unsafe/runtime
corpus under it; losing sanitizer coverage blocks I16.

I17 closes the applicable non-deprecated pinned stable obligations outside the V1 subset:
remaining inherent operations and trait
implementations, architecture intrinsics and OS extension modules, each with
the same declaration, applicability and per-operation evidence rules as I13.
It may proceed alongside I15-I16.

Owner worklist amendment (2026-11-09): deprecated APIs are no longer required,
and all eight [reference profiles](reference-profiles.md) remain in post-V1
scope. The [reconciled worklist](post-v1-worklist.md) accounts for all 106,125
stable canonical records: 629 excluded deprecated records, 13,295 V1
obligations, 41,151 post-V1 contextual obligations, 50,190 attached
implementation members, 684 attached inherent blocks and 176 namespaces.
The post-V1 obligations group into 32,355 source-declaration work units;
4,864 also occur in V1, leaving 27,491 units not represented there.
Shared code does not discharge type/profile evidence. These are inventory
counts before source-cfg and implementation-state review, not missing-code
counts or I17 qualification. A009 and profile/toolchain work remain separate.

### 8.7. Experience track: readability, compile cost and storage

Decisions D16-D29 (decisions.md) fix Mettle's identity: it must not read like a
Rust copy, with better source readability, Rust-level or better runtime, faster
compilation and smaller build-cache storage than Rust/Cargo. This track delivers
the source/API half of that identity and its evidence. It retains the V1
capability, ownership, failure and runtime contracts, and it does not mark any
I06-I08 repair or milestone complete. It is judged on the two exhibit programs
below and on measured gates, not on punctuation counts or resemblance to any
other language. A shorter listing is an exhibit, not a productivity or runtime
claim.

**Existing facilities (not missing work).** The track builds on landed code:
iterator interfaces, adapters and `collect` in `library/core/iter.mt`; the
lowest-priority library prelude in `bootstrap/resolution/load.cpp`
(`preludeNames()`); panic/assert and the runtime hook in `library/core/panic.mt`;
text splitting, lines and byte/scalar iteration in `library/core/text.mt`; sink
formatting in `library/core/fmt.mt`; allocator-aware collections and owned text
in `library/alloc/{vec,hash_map,string}.mt`; hosted I/O and threads in
`library/std/{io,module,thread}.mt` with synchronization in `library/std/sync/`;
named call arguments in `bootstrap/syntax/parser/expressions.cpp` and
`bootstrap/semantics/calls.cpp`, with their rejection fixtures (`duplicate-label`,
`unknown-label`, `positional-after-label`); and the workloads
`tests/std/cli_wordcount.mt` and `tests/alloc/ini_parser.mt`. The gaps are source
ergonomics, API composition, precise new contracts and their verification.

| Order | Deliverable and gate | Status |
| --- | --- | --- |
| Cutover | Dotted paths, `extend` implementation blocks, D21 vocabulary, and optional item-level semicolons | Implemented and verified |
| R1 | Bounded lookup, associated namespace, constructor selection, inference, vocabulary and the `experience-1` prelude | Verified: namespace/dotted syntax; constructors/applicability/overlap (`custom-init-shapes`, `collection-inits`, constructor negatives); slice-interface lookup/projection (`slice-interface-implementations`, `slice_iterable`). Implemented, unverified: slice/fixed-array argument inference, String/Set private storage factories. Slice/array/tuple/parenthesized-view projection subjects need verification despite parser support. Focused R1 closure remains open. |
| F1 | Fixed borrowed `Message`, `format` parameters, two-level forwarding and the std Writer adapter (library-surface section 10); lifetime, error and code-size tests; measure indirect-call cost, renderer/code size and check cost | In progress |
| R2 | Lending lines, Copy-valued `[u8].bytes()`, KeyView, PathInput/`write_path` and equivalent workloads within qualified profiles; reconcile `library-and-abi.md` POSIX path statements with the native Windows path contract before delivering that profile | Implemented for POSIX in current spelling, focused fixtures pass; Windows paths and collision stress pending |
| R3 | Expression-bodied `fn`, diagnostics, formatter/editor completion | Named/method/default `=>` bodies pass source/formatter regressions. `match-move-*-without-take` negatives cover actionable ownership diagnostics, including region-generic callees. LSP completion/signature/references/hover/pattern navigation and readable notes/help have the macOS evidence in I12 above; remaining editor precision gaps are in tooling-and-packages section 5. |
| Qualification | Frozen-input quality, target, safety and performance checks, including performance.md sections 5.1-5.2. D17 comparison harness (`tools/bench_compare.py`, `benchmarks/`, performance.md section 5.3): implemented; its `.mt` workloads type-check, but the harness has not been run and no result is claimed | After R1-R3 |
| WP-S | Storage audit work package of tooling-and-packages.md section 7.1; operational, no dependency on an artifact store | Open |
| D32-D34 syntax composition | Prefix named-parameter access, native `Outcome<T, E>` values and comma-separated if/while conditions; preserve I04/I05 ownership/effect contracts and I06 L004 short-circuit behavior | Implemented, qualification pending. Linux x86-64 pinned Debug build and focused debug/release execution cover access modes, stored outcomes, short-circuiting, cleanup and generic branch inference; scope/escaping-view/feature negatives and formatter/LSP probes pass. Parser migration receipts preserve 601 originally valid fragment trees; macro templates and region-explicit Rc/Arc view conversions are separately migrated. This is not milestone or full-library qualification. |

**R1 follow-up.** Constructor selection/overlap/applicability and fixtures have
the verification recorded in the table; the earlier source-only constructor
inventory is superseded. Same-shape candidates with unresolved applicability
still need argument-contextualization review: a trial may check an argument
before selection. String/Set private storage factories and the table's other
unverified changes still require applicable source/library/ownership/target/
quality checks. Reconcile with I06-I08 obligations; design alone closes none.

**Acceptance.** Use the existing source, module and library runners; no new
framework. Compare exact successful outputs and exit codes, error identity,
ownership/cleanup, allocation and peak memory, with blank/unterminated lines,
invalid UTF-8 bytes, CRLF, non-Unicode paths, overflow profiles, partial output,
and conflicts between a live line view and a refill. Compile-time and
build-storage evidence follows performance.md section 5. Reader exercises ask
unfamiliar developers to explain, modify and debug the exhibits, including the
four Text/String ownership cases of library-surface section 9. Test fixtures:

- *Named arguments with a default.* `scaled(value: 3) == 6` and
  `scaled(factor: 4, value: 3) == 12` for `fn scaled(value: i32, factor: i32 = 2): i32`,
  retaining the existing default-evaluation-order regressions (named expressions
  in written order, omitted defaults in declaration order).
- *Allocator construction.* With an instrumented `Arena: Allocator`, accept
  `List<i32, Arena>(allocator: take arena)` with exactly one allocator transfer
  and matching deallocation, and accept `List<i32>()`. Reject
  `List<i32, Arena>()` for the applicability reason, a double consumption of
  `arena`, a generic zero-argument call without an `A = Global` proof (even if
  later instantiated with Global), and overlapping constructor conditions;
  check defaults applied after argument constraints and no fallback to Global.
  Diagnostics must be the intended applicability/ownership ones, not an unknown
  Arena or unsupported-parser error.
- *Message forwarding.* Three `format` functions `emit` (writes to stdout with
  `write_line`), `log` and `relay`, each forwarding its parameter, are called
  with `f"{a < b}"` (also by name `message:`), `f"value={42}"` and `"plain"`;
  expected stdout `true\nvalue=42\nplain\n`. Checked instantiation records show no
  message-shape specialization of the three functions (renderer thunks may differ
  and normal inlining is separate). A destructible hole temporary with a sink
  failure survives both forwarding levels, drops exactly once on success and on
  failure, and no Message escapes.
- *Format-hole boundaries.* The table in language-grammar section 13.5, with valid
  declarations for the called functions, hole spans, escape rejection and single
  evaluation; plus nested const braces, calls, comparisons and forwarded Messages.
  An unknown callee or an unrelated syntax error does not exercise the contract.
- *Broken pipe.* Subprocess tests for closed stdout (child SIGPIPE disposition set
  explicitly to default and to ignore, so both the signal and the EPIPE-to-141
  paths run), stderr failure, other errors, status/no-diagnostic behavior and
  unchanged low-level error identity.
- *Borrowed keys, lending lines, paths.* KeyView hash/equality coherence,
  collisions, query-temporary expiry and map invalidation; line-view/refill
  conflicts; non-Unicode POSIX names and Windows console/redirected output
  including unpaired code units before claiming portable execution.
- *Contextual `extend`.* Declaration, member declaration, member call and
  local-name positions.
- *Closures.* `p => fn(x) => x + 1, q => ...`, `apply(fn(x) => x + 1, other)`,
  `apply(fn(x) => pair(x, 1), other)` and tuple-valued bodies.
- *Generic application.* Calls, function values, projections, const arguments,
  nested closers, malformed arguments and newline cases, including the
  diagnosed `assert(a < b, c > (d))` parse.

Compile/execute both exhibits with the matched edge/error/ownership cases;
a documentation check alone is not equivalence evidence.
The readable fixture revisions below still need current-library type checking
and runtime comparison; their source updates do not close this acceptance gate.

**Exhibit 1: byte-streaming word count.** The before program is the fixture
[cli_wordcount.mt](../tests/std/cli_wordcount.mt). The after program is
[cli_wordcount_lines.mt](../tests/std/cli_wordcount_lines.mt), using the current syntax and
keeps the input/report arguments,
raw path support, byte count, space/LF/tab separators, final unterminated line,
report/stdout bytes and exit codes; error-message output retains `eprint`'s
panic-on-write-failure policy. Streaming formatting changes write
granularity, not an atomic-write contract, so injected-failure tests check error
identity and allowed partial output. Memory stays proportional to the longest line.

```text
import std.env
import std.fs
import std.io
import std.path.PathInput
import alloc.vec.List

fn words_in(read line: [u8]): usize {
    var words: usize = 0
    var inside = false
    for byte in line.bytes() {
        let space = byte == b' ' || byte == b'\n' || byte == b'\t'
        if !space && !inside { words += 1 }
        inside = !space
    }
    words
}

fn count(read input: PathInput, read report: PathInput): Unit throws io.Error {
    var reader = io.buf_reader(try fs.open(input))
    var buffer = List<u8>()
    var lines: usize = 0
    var words: usize = 0
    var bytes: usize = 0
    while let present(line) = try reader.read_bytes_line_into(buffer) {
        lines += 1
        bytes += line.len()
        words += words_in(line)
    }
    {
        var out = io.buf_writer(try fs.create(report))
        try out.write_line(f"lines={lines}")
        try out.write_line(f"words={words}")
        try out.write_line(f"bytes={bytes}")
        try out.flush()
    }
    var out = io.stdout()
    try out.write_path(input)
    try out.write_line(f": {lines} lines, {words} words, {bytes} bytes")
}

fn main(): i32 {
    let args = env.args()
    if args.len() != 3 {
        io.eprint("usage: wordcount INPUT REPORT\n")
        return 2
    }
    let result = capture count(args[1], args[2])
    match take result {
        success(_) => 0,
        failure(error) => {
            let message = error.message()
            io.eprint(f"wordcount: {message}\n")
            1
        }
    }
}
```

The `PathInput` parameters are independently generic and borrowed, not erased
interface objects. The std-owned writer types find std's Writer methods under
the owning-package rule (semantic-rules section 13.2), with no Writer import.
The byte-oriented input is intentional: a UTF-8 reader would reject previously
valid inputs, and keeping line terminators leaves the byte count unchanged. The
required byte-for-byte comparison must be rerun for the updated fixture;
POSIX evidence does not cover Windows output, which needs its own PathInput tests.

**Exhibit 2: digit-list configuration parser.** The before program is the
fixture [ini_parser.mt](../tests/alloc/ini_parser.mt). The after program is
[ini_parser_readable.mt](../tests/alloc/ini_parser_readable.mt), still without std, and keeps
empty-line and empty-comma-field skipping, first-`=` splitting, digit-only
nonnegative input, repeated-key accumulation, empty lists, partial updates before
failure and all return codes. CR is not trimmed (use `split("\n")`, not a line
helper that strips CRLF), and the original debug-overflow/release-wrapping
arithmetic is retained rather than substituting the existing signed, checked
numeric parser, which would change accepted inputs.

```text
fn parse_number(read text: Text): i64? {
    if text.is_empty() { return none }
    var value = 0i64
    for byte in text.bytes() {
        if byte < b'0' || byte > b'9' { return none }
        value = value * 10 + ((byte - b'0') as i64)
    }
    present(value)
}

fn parse_list(read text: Text, mut out: List<i64>): bool {
    for part in text.split(",") {
        if part.is_empty() { continue }
        let present(value) = parse_number(part) else { return false }
        out.push(value)
    }
    true
}

fn parse(read input: Text, mut map: Map<String, List<i64>>): bool {
    for line in input.split("\n") {
        if line.is_empty() { continue }
        let present((key, rest)) = line.split_once("=") else { return false }
        let values = map.or_insert(String(key), List<i64>())
        if !parse_list(rest, values) { return false }
    }
    true
}

fn sum(read values: List<i64>): i64 {
    var total = 0i64
    for value in values { total += *value }
    total
}

fn main(): i32 {
    var map = Map<String, List<i64>>()
    if !parse("a=1,2,3\nb=40,50\na=4\nc=\n", map) { return 1 }
    if map.len() != 3 { return 2 }
    match map.get("a") {
        present(values) => { if values.len() != 4 || sum(values) != 10 { return 3 } },
        none => { return 4 }
    }
    match map.get("b") {
        present(values) => { if sum(values) != 90 { return 5 } },
        none => { return 6 }
    }
    match map.get("c") {
        present(values) => { if !values.is_empty() { return 7 } },
        none => { return 8 }
    }
    var bad = Map<String, List<i64>>()
    if parse("x=1,zz\n", bad) { return 9 }
    0
}
```

Insertion constructs owned String keys; KeyView Text lookups allocate no key.

## 9. Capability ownership and completion evidence

The primary implementation owner for each of the 107 capability rows is below.
This is not a claim that a row is fully complete at its first local demonstration:
I13 checks every owner's complete applicable operation/profile obligations, and
I14 applies the release gates. I01/I02 establish foundations/vertical slices;
I14-I16 own qualification/evolution rather than additional baseline capability IDs.

| Milestone | Primary capability IDs |
| --- | --- |
| I03 | L019-L024, L028-L030 |
| I04 | L006-L008, L010-L011, L013, L017, L034-L039, L059 |
| I05 | L025-L027, L040-L051 |
| I06 | L001-L005, L012, L014-L016, L018, L031-L033, S015-S017, A001-A008 |
| I07 | L009, S001-S004, S006-S014, S029 |
| I08 | S024-S028 |
| I09 | L054-L058, T001-T003 |
| I10 | S005, S018-S023 |
| I11 | L052-L053, S030 |
| I12 | L060, T004-T007 |
| I13 | S031 |
| I17 | A009 |

I09 macOS ARM64 implementation/evidence:

- **L057:** located attributes/unknown-attribute errors, generated provenance
  and derives Clone/Copy/Debug/PartialEq/Eq/PartialOrd/Ord/Hash on generic
  products/enums. Default (`static fn default(): Self`) covers primitives,
  Unit, absent optional, pairs/triples, Global/List/String; product derive
  supplies field defaults and bounds only used parameters. Default on enums
  (no default-variant syntax), unions/arrays remains unsupported; no derives for
  unions, empty enums or custom-init types. Debug/Release fixtures:
  `derive-default-and-manual-default.mt`,
  `fail/derive-default-field-without-default.mt`,
  `fail/derive-default-on-enum-is-unsupported.mt`.
- **L058:** all/any/not cfg over target OS/arch/family/endian/pointer-width/
  features and package features. Single-file `--features a,b`; package roots/
  dependencies see their own resolved features, standard libraries none
  (`tests/packages.py::features`).
  Post-cfg inactive dependency filtering is integrated; the disabled external
  module Debug/Release and modules-memory receipts do not verify pre-execution
  staging. Owner-approved parser suspension/resumption remains unimplemented;
  partial-token expansion and output-independent inactive-syntax validation
  remain selected obligations.
- **L055:** token matching/repetition/follow sets, provenance, binder hygiene,
  grouped expressions and explicit `$capture(name)`; eager argument expansion.
  Inline lexical namespaces and qualified public file/package invocations
  retain definition-module hygiene; private cross-module access rejects in name
  phase. Restricted visibility, explicit/grouped imports, reexports and
  namespace ambiguity pass `macro-*`, `macro-explicit-imports`,
  `macro-import-reexport`, `macro-import-ambiguous`, `restricted-macro-*` and
  package cases. Only pub import reexports; syntax stays unresolved in AST,
  bindings/visibility in side tables.
  Review hygiene producer/consumer and demanded-definition-namespace patches
  are prepared, not integrated or native-verified. The occurrence-level
  region/borrow-source producer, identity-aware consumers, nested result-source
  matching/deduplication, clones and fingerprints are also prepared. The native
  checker fixture asserts distinct outer/authored `RegionId`s and nested
  sources; its execution remains pending. L055 therefore remains partial.
- **L056:** `tests/packages.py::{procedural_macro,procedural_macro_failure}`.
  `[macros.NAME] source/api` invokes host programs via driver/procedural.cpp;
  versioned line-token protocol in expansion/procedural and std.macros,
  invocation-attributed re-lexed output, macro-phase errors. Reuse requires
  reproducible declared files/environment; otherwise rerun. Response text keys
  consumers. Gaps: graph-global namespaces, text-only tokens, no attribute/
  derive procedural macros, fresh/definition-site constructors or per-token
  error spans (tooling-and-packages.md).

Each milestone's evidence bundle records source/toolchain revisions, target/
profile, exact commands, fixture and operation IDs, expected versus actual
results, diagnostics/exit statuses and raw measurements where applicable.
Capability status changes require that evidence, not this schedule.
Keep specification, implemented, tested and release-qualified states distinct.
New tests should exercise the behavior landing in that milestone and protect
it in later milestones; do not defer all correctness or performance work to I14.

F1 (f-strings and `format` parameters): partial, verified on macOS arm64; status and gaps in library-surface section 10.3.
