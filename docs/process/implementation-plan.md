# Compiler implementation plan

Gated profile: `linux-x64` (owner decision). Evidence from other hosts or
profiles does not transfer; see section 8.0. Milestone status, receipts and
operation counts are not kept here: the ledger tooling generates operation
status (`tools/v1_operations.py`), and each milestone's evidence bundle is bound
to a source revision (section 9). A completed sub-batch is not a completed
milestone.

Owner scope moves: safe pinned owners (S003) are I13; front-end dependency
separation, compile/storage measurement and P08-P10 are I14; the optional Rust
bridge (A009) is I17. Standalone operation-contract migration is tracked in the
[native authority register](baseline-mapping.md#7-native-operation-authority),
the post-V1 inventory in [post-v1-worklist.md](post-v1-worklist.md).


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
upstream source identities and platform-contracts.md selects target environments.
Before the first backend build, capture installed artifact hashes and perform
object/link/debug probes. Source selection is fixed; joint build compatibility
and platform execution are not claimed before those probes.

Use checksum-pinned project-local tools, not host substitutes. A Linux kernel
runner must link/execute cross-emitted ELF; emission on another host does not
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
`status.md` defines the documentation completion evidence and its
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
| I13B | Library and trait-implementation closure | The 27,217 reconciled library and trait-implementation obligations (post-V1 worklist groups D-J) have checked declarations and evidence on Linux, in addition to I13's V1 subset | I13 |
| I14 | V1 release qualification | Reproducible installable C++/LLVM toolchain passes safety, capability, target and Rust runtime, compile-time and build-storage gates | I13B |
| I15 | V1.1 substantive self-hosting | Mettle compiler builds itself through repeatable bootstrap stages and preserves V1 capability/performance gates | I14 |
| I16 | V1.2 independent production backend | LLVM-free code generation covers every accepted profile/capability and passes Rust/LLVM-path comparisons | I15 |
| I17 | Complete stable-operation closure | Every applicable non-deprecated stable architecture-intrinsic and OS-extension obligation outside I13/I13B, has checked declarations and evidence across all reference profiles | I14 |

This is fifteen delivery milestones to V1, followed by two architectural
evolution milestones and I17's post-V1 completion of the operation inventory. I02 is the first useful native compiler, not a reduced V1.
Dependencies are completion gates; a component's preparatory work may start once
its own contracts/inputs exist, without marking the enclosing milestone complete.
The experience track of section 8.7 runs alongside these milestones and is
delivered by its own gates.

### 8.0. Gated profile: `linux-x64`

The remaining V1 milestones gate on `linux-x64` from
[platform-contracts.md](../spec/platform-contracts.md#8-reference-profiles): a Linux x86-64 compiler host
producing x86_64-unknown-linux-gnu executables on the installed maintained Linux
userland (WSL2 is acceptable). No distribution or glibc version is mandated;
each qualification run records the actual OS, libc, kernel and sysroot.
Windows x64 stays outside the V1 gate. All reference profiles remain post-V1
obligations ([post-v1-worklist.md](post-v1-worklist.md)).

- Evidence from another host or profile does not transfer. A milestone closed
  on a different profile is requalified on `linux-x64` before further I13 area
  closure (LNX): pinned bootstrap, Debug and Release builds, CTest, source/std/
  package suites, the I07-I12 decisive checks including emitted ASan/TSan and
  the LLDB workflow.
- Classify each failure as a non-Linux assumption in tests or tools, a genuine
  Linux runtime/ABI defect, or an inapplicable record. Fix the first two; never
  relabel a failure as inapplicable.
- I13 re-evaluates every target-conditional and `not applicable` record for
  Linux. Linux-only services (for example epoll and `/proc`) become applicable
  where selected.
- I14 qualifies `linux-x64`. Correctness, sanitizer and reproducibility checks
  may run under WSL2 or a container; runtime, compile-time and storage gates
  need a qualified runner, and virtualized timings are pilot evidence only.

### 8.1. Foundation and first executable: I01-I02

I01 establishes source/build identities and installed artifact hashes for the
selected compiler, LLVM, linker and sysroot, plus host/target configuration.
Build Debug and optimized configurations and prove object emission, linking and
execution on Linux x86-64. Keep the fixture harness small and CTest-driven.

I02 implements the vertical slice of section 2: source buffers/spans, tokens,
lossless parsing, resolution, scalar types, compiler-owned IR, LLVM lowering,
linking and native exit status, with the separator/precedence recovery corpus
and arithmetic failure paths. Unsupported features are rejected explicitly.
Early P01 measurements are engineering signals, not the V1 verdict.

### 8.2. Ownership and type-system foundation: I03-I05

I03: nominal/Copy products and finite layouts; canonical places and sparse
field-sensitive initialization/moves; value/read/mut/take, stored and returned
views, region-only sources, methods, reborrows and two-phase receivers;
scope/temporary/drop plans with partial cleanup and pending arguments/results.
Exceptional cleanup precedes unwinding through resources: an outer catch sees a
valid replacement after the old destructor panics, and a second panic aborts
before installation. `examples/core/values.mt` and `ownership.mt` execute
unchanged and the original move/take negatives reject for ownership reasons.

I04: products, enums and patterns; nested presence and outcomes; typed
propagation/capture; modules/reexports/aliases; methods and default arguments;
labels, ranges, arrays and exhaustive control flow. Required array lengths use
checked arithmetic in every profile. Compact non-droppable arrays use one place
and memory lowering; droppable arrays stay expanded (implementation cap 2^16
elements).

I05: declaration-based generic bodies and specialization; named and
higher-ranked regions; variance; const parameters; associated types, constants
and GATs; coherence and lookup; operators; closures and callable modes;
unsized constraints; explicit erased dispatch; opaque return identities.
Negative cases check that a Copy instantiation grants no undeclared ownership
rights, overlap is never selected by order, and a region cannot escape its
binder. Erasing a witness-metadata implementor requires the explicit sized
adapter of [compiler-architecture.md](compiler-architecture.md); never add
silent allocation.

### 8.3. Native libraries and machine boundary: I06-I08

I06: integer, float and conversion behavior; raw-pointer provenance;
initialization and manual destruction; interior mutability; atomics; pinned
storage; layout, symbols and linkage; C callbacks, varargs and compatible
unwind; volatile, assembly/intrinsics and freestanding mechanisms. Use C round
trips, layout/calling probes and independent memory-model cases; sanitizer
success is not a safety proof. Never substitute an unsafe caller workaround for
an unimplemented safe operation. Contracts and shared interfaces:
[compiler-architecture.md](compiler-architecture.md) section 4.

I07: core and alloc operation families: unique, local-shared and weak owners;
allocator identity and failure; optional/outcome operations; UTF-8;
slices/collections; iteration; hashing; formatting/parsing; type identity and
downcast. Atomic-shared ownership lands here, its concurrent safety closes in
I10. Test allocation failure, partial initialization, invalidation and panic,
not only happy paths. Loading, prelude and layering rules:
[compiler-architecture.md](compiler-architecture.md) section 6.

I08: files, paths and OS strings; synchronous networking; processes and
environment; time; hosted panic handling. Demonstrate partial I/O, non-Unicode
names, timeouts, child failure and raw OS-error round trips. Core and alloc must
still build without these services. POSIX calls live in `std.sys` over
`runtime/sys.cpp`.

Seam obligations for the library/compiler boundary:

- Borrowed slices use element-count metadata; text literals are validated static
  storage. Symbolic bodies are always checked, even when unused.
- Interface equality can determine generic parameters (`I: Iterator<Item = T>`);
  callable bounds and region-bearing bounds preserve declared argument/result
  sources.
- Blanket coherence rules out only impossible requirements, not potentially
  downstream implementations.
- Region-family iteration carries Item regions; live loops and items block
  mutation and escape. `match` through `mut` needs explicit `match mut`.
- `take` consumes Copy values too; use a fresh binding for independent use.

### 8.4. Builds, concurrency and async: I09-I11

I09 completes required constant evaluation, hygienic declarative macros, host
procedural extensions, attribute/derive/cfg phases and versioned token APIs,
with manifest resolution, exact locks, feature and host/target separation,
build scripts and dependency-keyed incremental reuse. Demonstrate a native
multi-package project with a generated input and an extension. Corrupted
artifacts must fail verification, untracked host inputs must trigger
conservative reruns, and incremental and clean builds must agree. Remote
registries stay open until a registry protocol is specified.

Compiled-interface reuse for `core`, `alloc` and `std` follows
[compiler-architecture.md](compiler-architecture.md) section 1.2: two different
consumers must reuse one checked interface and its native objects, with
clean/warm equivalence, invalidation, corruption and eviction cases. Front-end
dependency separation and the retained-byte and compile-time measurements
(performance.md section 5.1.1) are I14 work.

I10: owned and scoped threads, Transferable/Shareable, Shared/weak races,
mutex/RwLock guards, condition variables, barriers, once, channels and TLS.
Test scope exit during panic, last-owner destruction, guard affinity, channel
shutdown and atomic publication under contention. Race freedom is not a claim
of fairness or deadlock freedom. P08/P09 belong to I14. Emitted-program
`--sanitize address|thread` is supported; UBSan for emitted IR is not.

I11: pinned future state machines, async callable/interface contracts,
poll/wake integration and a separately selectable executor. Establish direct
borrowed await and owned tasks before borrowed-task execution epochs. The scope
must stay sound for forgotten handles/parents, repeated wakes, worker panic,
parent destruction and an uncooperative child poll. Check actual cleanup versus
cancellation requests; no hidden mandatory boxing and no default executor in
core. P10 belongs to I14. Interface plan:
[compiler-architecture.md](compiler-architecture.md) (I11 async state-machine
interface plan). `core.future` is allocation/executor-free; `std.task` is
optional.
I11 implementation contracts:

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
- Async I/O uses optional reactor/timer futures and nonblocking TCP with a
  platform reactor. Retry classifies raw EAGAIN independently of
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
  reconstruct Pin<mut Concrete> from erased data. Heap<any Future> uses ordinary
  unsizing/drop with unsafe payload pin; safe pinned owners remain S003.
  **Erased async-interface dispatch** still requires an explicit future-storage
  contract; borrowed heap-erased futures require region-carrying erasure.

### 8.5. Workflow, profiles and V1: I12-I14

I12 closes the complete native developer workflow: command selection, diagnostic
categories, test/benchmark results, doctest checking phases, formatting, linting,
LSP and source-level debug information, including owners/erasure/async states.
Build minimal formatting/editor/debug support as the relevant syntax and IR land;
do not wait until I12 to preserve spans or discover uninspectable values.
I12 is the completion gate, not the first tooling work.

I12 contracts are owned by tooling-and-packages.md sections 3-5.

I13 closes the V1 operation subset defined in `docs/library-surface.md`
section 6.1 with compiled native declarations and per-operation semantic
evidence, including its supporting protocols, reexports and target cfg branches
missing from rendered docs. Other applicable non-deprecated stable inventory
obligations move to I17 and are not a V1 gate. The 2026-11-09 owner amendment
excludes deprecated APIs from required scope while preserving reference records.
Gate only the `linux-x64` profile (Linux x86-64 compiler host and
x86_64-unknown-linux-gnu target; section 8.0). Windows remains excluded
from gates and not qualified. Other target references (Android, WASI, non-hosted Wasm and
freestanding) are likewise not qualified by this lane. Verify applicable native
C ABI and debug/unwind/TLS/atomic behavior on the selected profile; the optional
Rust bridge (A009) belongs to I17. Cross-compiling is not a substitute for
execution/probes; an inapplicable service is not a pass. Evidence must retain
exact target applicability.

I13 and I13B implementation is complete (2026-11-15). Their remaining test
evidence comes from I14's single consolidated qualification run, built to share
one primed library cache and use every core, not from per-milestone matrices.

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

I14 continuation (2026-11-16): source freeze remains open. `9363a26f` has
2013/2015 source run cases plus both OOM-killed iterator profiles passing on a
single-worker rerun, and 857/857 fail cases. `4ef6d4c9` fixes zero-size allocator
alignment; six allocator source/profile cases pass with the ASan/UBSan compiler,
and the allocator fixture passes emitted AddressSanitizer. Follow-up repairs
cover scoped callback regions/invocation modes, dereferenced slice operations
and leaking/stale fixtures. Focused normal and ASan/UBSan compiler regressions,
seven emitted AddressSanitizer cases and the emitted ThreadSanitizer wake/close
race pass; raw evidence is under WSL `~/w/`. These are focused results, not the
remaining CTest qualification. The interrupted CTest run predates these fixes.
`1f53e9aa` contains those follow-up repairs. The hash-verified Rust/Cargo 1.99.1
comparison completed all six workloads with matching original and edited outputs
(two pairs, three runtime runs, one warmup, no scaling families). Results and raw
inputs remain in WSL `~/w/bench-current/`. Allocating workloads measured median
cold builds of 66–68 s versus Rust's 0.26–0.31 s, with substantial runtime and
retained-storage gaps too. These are WSL engineering measurements, not release
qualification; performance repair and the registered gates remain open.
Owner requested wrap-up before another sanitizer batch. The old CTest log has
134/258 completed tests: 110 passed and 24 failed/timed out; the other 124 are
unrun. Its failures need current-tree CTest confirmation despite the focused
repairs passing. Next resume affected/unfinished sanitizer CTest from
`~/mettle-i-asan/build`, preserving `~/w/asan/ctest.log`; apply the requested
10800-second timeout only to `library.std.0`. Run the memory-heavy
`source.run.15` and `.16` shards separately at one worker. No background test or
benchmark remains running at this handoff.
Root cause of the allocating-workload gaps (runtime 33–48x, 66 s cold builds, 8 MB
binaries): every function is emitted as an outlined `<name>.body` plus `.unwind`
pair run by the C++ trampoline `mettle_rt_run`, with all locals in a memory frame
the optimizer cannot see through, so library `len`/`index`/`push` calls are never
inlined or promoted to registers and every function prologue materializes the
static addresses. The repair is to emit ordinary LLVM functions with
`invoke`/landing-pad cleanup (personality in the runtime) so inlining, mem2reg
and dead-function removal work; this is a backend redesign, not a library or
analysis tweak, and gates the I14 performance milestone.
Status after `ee2323ca`/`1f160cce` (WSL, release compiler): the backend now emits
`invoke`/landing-pad code (p04_struct_vec runtime 8.8 s to 0.34 s; Rust about
0.2 s); executables instantiate only reachable library bodies and trust bodies
verified at library build (small std-collections program, semantic edit, warm
library: 8.4 s to 2.9 s; Rust about 0.5 s); a shipped library store
(`mettle-shipped-store`, keyed to the installed compiler) cuts a fresh-cache
p04 build from 66 s to about 10 s (Rust about 0.3 s). Profile of the 2.9 s
rebuild: library archive import 26% (type-graph import, IR decode, store read),
checker pass over imports 15%, loan analysis about 10%, specialization and
LLVM codegen the rest. Remaining structural work, none of which may drop a
check: decode only the archive sections a program touches (lazy function
bodies); cache instantiations of library generics across programs; run
per-function analyses and LLVM codegen on several cores; then rerun the full
run suite and the ASan/UBSan CTest (library.std.0/.2/.3 open) on the final
binary and record the Rust-parity gates.
The latest import patch maps the cache blob instead of copying it, seals the
archive with a parallel block digest and decodes length-prefixed IR records on
several threads (small rebuild 2.9 s to 2.7 s). Type-graph import (about 350 ms)
and declaration import (about 140 ms) are now the largest serial pieces; lazy
function-body decode needs stubs in `lower`, `prepare` and `specialize`.
Import batch following `63f099aa`: replaced three archive-local type-ID tree
maps with bounded indexing of the consecutively allocated decoded IDs, retaining
graph validation, canonical identities and transactional publication.
`compiler.type-graph` passes in Release and ASan/UBSan builds. Four alternating
warm semantic-edit pairs (after separate cache primes) reduced median type-graph
import from 362 ms to 257 ms; whole-build medians were 2.94 s and 2.89 s, too
noisy to establish an overall speedup. All eight measured executables passed.
Transient instrumentation was removed; evidence is in `~/w/import-dense/`.
IR format v10 batch: per-record string tables decoded as borrowed views, IR
decode overlapped with declaration import, and LEB128 overflow rejected in both
IR and declaration readers (declaration map bounds now match variable-length
encoding). Largest library blob 249.3 MB to 206.4 MB; four alternating warm
semantic-edit pairs: median 2.72 s to 2.42 s; alternating cold primes 33.8 s
before and 33.4-34.3 s after (no cold regression). All measured executables
passed; `ir.codec` and `compiler.library-declarations` pass. ASan/UBSan and
broad suites not rerun for this batch. Evidence: `~/w/perf-import/`.
Imported bodies are now moved into the lowered program and marked
`libraryBodies`; the passes that rewrite existing calls (`opaqueAdapters`,
`callableContracts`) clear the mark, replacing the pristine copy and deep
equality comparison (about 10% of the warm profile in copies and destructors).
Eight alternating warm pairs: median 2.55-2.80 s to 2.35-2.65 s; executables
passed; `mettle-ir-tests` and `mettle-library-declaration-tests` pass.
Follow-up import change decodes the type-graph header, tables, definitions and
roots once into the transactional staging store, and moves that store instead
of copying it. `compiler.type-graph`, `compiler.library-declarations` and the
checked-library identity case pass. Eight alternating warm semantic-edit pairs
were 2.50 s before and 2.505 s after; no whole-build improvement is established.
The single-pass decoder's structural preflight has since been restored: without
it, malformed sequences could allocate from unvalidated counts and trigger
symbol resolution before structural rejection. A focused regression confirms
the preflight; the staging-store move remains.
Profiles still place `importTypeGraph` at 12-14% inclusive; evidence is in
`~/w/perf-import/`. A size-only skip for repeated `reserveCompiledSources`
scans was discarded after eight pairs (2.41 s before, 2.395 s after; no
measurable gain).
Current local continuation: imported functions now create inference variables
only for parameters, while retaining all checked local facts. Six alternating
warm semantic-edit pairs measured 2.656 s before and 2.524 s after; median peak
RSS fell from 1205 to 1196 MiB. Canonical type import avoids comparing a newly
installed definition against itself, while still comparing existing or
colliding definitions. A second six-pair experiment measured 2.458 s before
and 2.365 s after, with essentially unchanged peak RSS. All measured programs
ran successfully. A separate six-pair comparison of both changes together
measured 2.389 s before and 2.295 s after; median peak RSS was 1201 and
1192 MiB. IR record merging now caches recently validated symbol bindings
without weakening cross-record alias checks. Six alternating warm pairs measured
2.362 s before and 2.272 s after, with median peak RSS 1192 and 1196 MiB.
All three changes together measured 2.302 s before and 2.179 s after in six
more alternating pairs; median peak RSS was 1201 and 1192 MiB.
These are noisy WSL engineering measurements, not release qualification.
`compiler.library-declarations`, `compiler.type-graph` and `ir.codec` pass in
Release; the latter two also pass under ASan/UBSan. Focused fixtures cover
imported constant body locals, conflicting canonical definitions and
cross-record symbol aliases. Two experiments (hashed IR symbol maps and moving
canonical definitions) were discarded: neither established a sufficiently
reliable gain to justify their trade-offs. IR profiling showed 95-119 ms in
parallel record decode and 59-89 ms merging symbol bindings before the cache.
Evidence is under `~/w/perf-import/`; temporary WSL source instrumentation was
removed.
The store no longer trusts blob size and modification time as proof of
integrity: mapped reads hash the blob, and materialization hashes the copied
bytes before replacing the output. Existing timestamped entries remain
readable. Same-size corruption with a restored timestamp is rejected in both
paths. Single and batch publication hash staged copies and atomically replace
any existing blob, including a corrupt one. Two alternating cold pairs measured
35.63 s before and 37.00 s after staging; this small, noisy sample leaves a
possible cold regression to investigate. A direct `putData` staging experiment
was discarded: two cold pairs measured 34.05 s before and 34.56 s after, with
no established benefit. One instrumented cold build spent 118 ms copying and
142 ms hashing its 206 MB archive; the previous missing-blob path also copied
and hashed it. This does not explain the earlier 1.37 s median difference.
Instrumentation was removed. Four alternating warm pairs measured
2.209 s before and 2.304 s after restoring verification; this comparison changes
the safety contract and is not a speedup claim. Unrolling the x86 hardware
SHA-256 rounds recovered part of that cost: six alternating pairs measured
2.325 s before and 2.206 s after, with median peak RSS 1192 and 1196 MiB.
The hardware path also checks SSSE3 before using its instructions. After that
guard, four further pairs measured 2.526 s before and 2.479 s after, with
median peak RSS 1192 and 1196 MiB; these warm measurements precede the
publication change. Four warm pairs comparing guarded SHA with and without
staged publication were 2.480 s and 2.476 s, respectively, with median peak
RSS about 1192 MiB for both. All outputs ran successfully. The focused
`compiler.library-archive` test
passes in Release and ASan/UBSan, including SHA-256 boundary and
incremental-input checks; the executable and object cache integration cases
also pass. A warm profile found none of 8428 imported bodies rewritten by the
adapter passes, so separating rewritten-body trust from reachability is not a
demonstrated gain on this workload. Instrumentation was removed. These results
remain noisy WSL engineering evidence.
Imported function contracts remain in the checked module's existing immutable
import owner rather than being copied into a second declaration snapshot.
Inventories and exports include both imported and local contracts. Six
alternating warm semantic-edit pairs measured 2.224 s before and 2.080 s after,
with median peak RSS 1192 and 1114 MiB; all outputs ran successfully. The
focused declaration test passes in Release and ASan/UBSan, including a
transitive export/import of imported generics, constant bodies and defaults.
Two cold primes were 32.87 s and 32.76 s, respectively, and do not establish a
cold-build result. Evidence: `~/w/perf-import/overlay-timings.json`. These are
noisy WSL engineering measurements, not release qualification.
Cached archives are now verified once, by their sealing digest inside the
store lookup, instead of by a serial blob hash followed by the seal; a
rejected archive is evicted and rebuilt. Mounting registers library sources
in place with rollback instead of copying `Diagnostics`, and moves generation
tables instead of copying them twice. Six alternating warm pairs each:
2.227 s to 2.124 s for the seal change, then 2.002 s to 1.961 s and 1110 to
1083 MiB for the mount change; all outputs ran successfully.
Library objects are program-independent, as in Rust: each checked native
package (core/alloc/std) compiles once per checked archive and profile into an
object holding every non-generic body it owns, keyed by the checked-library
key, its source paths and the compiler identity. A library-scope
specialization supplies the bodies only on a store miss; generic instances
and other unowned helpers stay private copies, so objects never collide with
the program's own instances. Objects are emitted with function/data sections
and executables link with `--gc-sections`/`-dead_strip`. This fixes
`checked_alloc_std_reuse`: a second program reusing more library code (async)
hits all three objects. The consumer now represents those bodies as ordinary
external IR declarations using the same stable symbols as the package objects;
implementation-only locals are not exposed. Hidden-variadic signatures and ABI
functions without an external symbol fall back to the existing path.

Release validation passes all eight focused package/cache cases:
`checked_core_reuse`, `checked_alloc_std_reuse`,
`checked_alloc_std_release_reuse`, `checked_native_macro_reuse`,
`checked_library_diagnostics`, `cache_corruption_and_clean`,
`object_cache_integrity` and `incremental_reuse`. The debug `async_spawn` and
`async_executor` programs also pass. Broad suites and ASan/UBSan were not rerun.

The latest WSL `sm.mt` experiment does not establish a performance win. Four
alternating warm semantic-edit pairs measured 2.425 s before and 2.465 s after,
with median peak RSS 1,110,464 and 1,114,662 KiB. Both builds hit their objects
4/4 times for this unchanged reachable set. The executable grows from 454,504
to 879,576 bytes; cold primes measured 37.14 s before and 47.24 s after.
A separate one-pair, different-reachability probe missed the old core object
and hit the new one (1.49 s vs 1.47 s), too little evidence for a speed claim;
a core-only cold prime also regressed (18.48 s to 25.83 s). These are WSL
engineering measurements, not release qualification.

A 550-sample warm candidate profile attributed overlapping inclusive samples
to `Compiler::prepare` (45.5%), `Checker::run` (16.9%),
`CheckedLibrary::import` (13.5%), `resolution::load` (11.5%),
`metadata::importTypeGraph` (10.0%), `ir::decodeProgram` (8.9%) and
`backend::emitObject` (5.8%). This led to IR v11 lazy body loading: import
preflights record extents, identities, headers, statics and trailing data;
specialization decodes and validates a complete body before use, merging its
symbol bindings against the archive and previously loaded bodies. Eager
`decodeProgram` remains fully validating. The checked archive stays alive
through compilation; library-object misses load every body they emit.

Focused Release validation passes `mettle-ir-codec-tests`,
`mettle-library-declaration-tests` and package case
`checked_alloc_std_reuse`, including cross-consumer core/alloc/std object
reuse, generic instances, constants and an async std body. Eight alternating
warm semantic-edit pairs against the pre-lazy `mettle-pkgkey` binary measured
2.665 s baseline versus 2.535 s candidate median, and 1,114,842 versus
958,578 KiB median peak RSS. All eight outputs ran successfully. One cold
prime per binary measured 55.73 s baseline versus 57.34 s candidate and
2,805,304 versus 2,807,816 KiB peak RSS; this does not establish a cold-build
improvement. The encoder writes function records directly to the archive
buffer to avoid a full-record intermediate copy. These are WSL engineering
measurements, not release qualification. Broad suites and ASan/UBSan were not
rerun.

Package emission remains serial on one LLVM context. Cross-program instance
caching, parallel analyses/codegen, source freeze and final qualification
remain open; I14 is not complete. Handoff: this work extends
`b67251e1` on `main`; reusable evidence is in `~/w/perf-import/lazy-ir-pairs.txt`,
`~/w/perf-import/lazy-ir-final-pairs.txt`, `~/w/perf-import/lazy-ir-cold-base2.txt`
and `~/w/perf-import/lazy-ir-cold-final.txt`. The type-graph follow-up is
recorded below.
The full run suite and ASan/UBSan qualification remain outstanding; the prior
sanitizer tree `~/mettle-i-asan` is stale.

A follow-up profile identified repeated vector growth in
`metadata::importTypeGraph`; it now reserves from validated type, root and
local-type counts without changing graph decoding or validation. Eight
alternating WSL ext4 warm semantic-edit pairs against `b67251e1` measured a
2.2115 s baseline median and a 2.0800 s candidate median (5.95% lower); all
outputs ran successfully. The focused Release type-graph test and formatting
check pass. This is engineering evidence for one warm workload, not a cold-build
or Rust-parity result. Raw timings: `~/w/perf-import/reserve-pairs.txt`.

Receiver lookup now lazily indexes inherent and interface implementation
candidates by method name, preserving the existing applicability, visibility
and ambiguity checks while avoiding repeated full scans. Three fresh-cache p04
`check` runs measured 35.02 s baseline versus 32.37 s candidate median (7.6%
lower), with unchanged peak RSS at about 2.72 GiB. Four warm pairs measured
1.505 s versus 1.515 s median, so no warm-check improvement is established.
The cold-check profile's `receiverCandidate` self share fell from 5.9% to 1.4%;
solver applicability remains dominant. The two interface-ambiguity fixtures
and argument-selected interface-method program pass. Evidence: `~/w/anal/check.raw`,
`~/w/anal/check-receiver.raw`, and the three fresh-cache runs under
`~/w/anal/check-{base,receiver}-{2,3}`.

A shared cache now reuses settled pure interface-selection and normalization
results across solver instances. Five fresh-cache p04 checks measured a 30.51 s
median and 2,572,800 KiB peak RSS, versus the receiver-index baseline's three
checks at 32.66 s and 2,722,352 KiB. A follow-up removed redundant interface
visibility work: `visible(definition)` had been evaluated eagerly for each
implementation even when that interface declaration was already in the local
visibility map. Two alternating pairs measured 30.28 s before and 26.91 s
after (11.1% lower); peak RSS was unchanged. Combined with the cache, the
candidate median is 17.6% below the receiver-index baseline. Focused visible
and hidden blanket-method fixtures pass. The post-change profile's inclusive
`receiverCandidate` share fell from 23.1% to 10.9%; remaining hotspots include
`Solver::implementation` (27.9%), `normalizeUncached` (23.3%) and
`Checker::checkRegions` (18.5%). A region-substitution cache-key factoring
trial showed no median improvement in two pairs and was discarded. These are
small-sample WSL engineering signals, not Rust-parity or release-gate results;
continue from the installed-store measurements below, without broad test runs.

To match Rust's prebuilt standard-library model, the current compiler's
`mettle-shipped-store` target populated the installed core/alloc/std store
(1.1 GiB). With separate fresh project caches, two p04 checks took 1.88 s and
1.61 s with the shipped store, versus 26.53 s and 26.84 s without it; median
time fell 15.3x and peak RSS fell from 2,573,070 KiB to 748,904 KiB. Compared
with the frozen Rust check result (0.058 s), installed Mettle remains about
30x slower; this is engineering evidence, not a gate result. Two fresh release
builds with the store took 2.35 s and 1.81 s. The local p04 source is the
harness semantic-edit variant (`seed` 12346 plus a comment), so its executable
exits 83; the frozen result's checksum 64 is from the unedited source. The
installed-store profile now concentrates on `importTypeGraph` (18.0%),
`resolution::load` (16.5%) and `decodeProgramLazy` (11.9%). Evidence:
`~/w/anal/check-{shipped,noship}-{1,2}.time`,
`~/w/anal/p04-shipped-build-{1,2}.time` and
`~/w/anal/check-shipped-profile.txt`. A candidate replacing one `TypeStore`
copy in `importTypeGraph` passed the type-graph test, but two matched
alternating no-cache p04 checks measured 30.38 s baseline versus 30.44 s
candidate; it was reverted because it showed no gain. Timings:
`~/w/anal/typegraph-import-matched-20261117/`.

A profiling-only Release build with line tables sampled a no-cache p04 check
(5,428 samples). The largest inclusive semantic costs were
`Solver::implementation` (32.2%), `normalizeUncached` (22.2%) and
`Checker::checkRegions` (17.6%); `TypeStore::instantiateProduct` accounted for
6.8% self time and `ProductType` copying 5.8%. A candidate reducing copies in
generic product instantiation passed `mettle-ir-tests`, but two alternating
no-cache p04 pairs measured 26.20 s baseline versus 27.73 s candidate, so it
was reverted. Evidence: `~/w/anal/typegraph-line-profile.raw` and
`~/w/anal/instantiate-product-matched-20261117/`.

Performance-only continuation on `b212a55c` plus the uncommitted working tree:
empty type substitutions now return immediately, failed asymmetric matches no
longer enumerate the actual type's parameters, and incompatible nominal
implementations are rejected before region instantiation. Four randomized WSL
p04 pairs reduced median full `check --no-cache` time from 22.176 s to 16.031 s
(27.7%). Eight installed-library check pairs (0.903 s versus 0.910 s) and six
semantic-edit build pairs (1.169 s versus 1.160 s) establish no everyday-build
gain; all six paired executable outputs match. The final compiler SHA-256 is
`ba06898e728188daeb1c720284df567d1f8a4ee33ebdedfa12d2aa4c43d7f890`;
raw samples and commands are in `~/w/anal/perf-solver-20261117/`.
Identity-substitution, builtin-leaf, ordered-interning and canonical-import
experiments were removed because they established no elapsed-time gain.
Only the Release compiler was rebuilt; test suites and qualification were not
run, as requested. Source freeze and Rust parity remain open.

The next performance-only batch targets installed-library import: canonical
identity lookup now uses a reserved hash table, identity generation reuses its
graph state, reference collection omits discarded key bytes, product descriptor
export avoids a second copy, and imported implementation remapping indexes
source spans instead of repeatedly scanning all implementations. Structural
preflight and archive formats are unchanged. Against the preceding retained
compiler, eight randomized installed-check pairs per workload measured p03
0.8894 s -> 0.8455 s (4.9%), p04 0.8901 s -> 0.8495 s (4.6%), and p05
0.9171 s -> 0.8601 s (6.2%). Six semantic-edit build pairs per workload measured
1.1498 s -> 1.1174 s (2.8%), 1.1664 s -> 1.1022 s (5.5%), and
1.3025 s -> 1.2378 s (5.0%), respectively; all 18 paired generated executables
are byte-identical. These are WSL engineering measurements, not Rust parity or
release qualification. Compiler SHA-256:
`fd52f2a203f6cd2a31f5673ecf4dc480b54518a6c15b9bfd4ed43dfaf3e2eb5b`.
Commands, raw samples and stage profiles:
`~/w/anal/perf-import-20261117/`. A const-key copy experiment regressed installed
checks and was removed; temporary timing instrumentation was also removed.
Only the Release compiler and performance workloads were built; no test suites,
sanitizers or qualification were run, as requested.

I14 structural performance continuation (2026-11-17): the owner explicitly moved
validation/materialization separation, indexed demand-loaded metadata, immutable
dependency contracts and resident compiler/query work into I14, regardless of
their earlier milestone placement. The first native-library query batch is
implemented, not complete fine-grained query architecture or I14 acceptance:

- `mettle serve` processes serial JSON-line check/build requests using the
  ordinary driver. Successful imports retain owned archive/remap storage and
  are reused only for matching content, configuration and complete consumer
  remaps. A changed generation replaces the previous entry for that native root.
  Runtime identities refresh between requests; compiler-image identity remains
  fixed to the running image.
- Imported type stores are const snapshots with consumer-owned paged copy-on-write
  records. Function facts are borrowed through indexed slots and copied on
  mutable access. Generic environments materialize on first use; imported type
  declarations have reusable span indices.
- Complete IR headers are validated before admission. Retained call headers omit
  body-local metadata; indexed CFG loading restores it before verification.
  Deferred decoders own their source/remap/archive lifetimes across requests.

Final WSL Release compiler SHA-256:
`53ee90d688159c2574f6530bbf14ec4215272fb20f0412ce24941d3cf7dd6c01`.
The final const-snapshot rebuild is byte-identical to the measured executable.
Against the preceding `fd52f2a2...` compiler, randomized semantic-edit measurements
with independently primed, isolated whole-output caches produced these medians:

| Workload | Check: prior / fresh / resident | Build: prior / fresh / resident |
| --- | --- | --- |
| P03 | 0.855 / 0.802 / 0.434 s | 1.088 / 1.092 / 0.691 s |
| P04 | 0.875 / 0.858 / 0.473 s | 1.101 / 1.090 / 0.703 s |
| P05 | 0.851 / 0.855 / 0.474 s | 1.243 / 1.246 / 0.854 s |

P04 uses six check and four build triples; P03/P05 use four check and three
build triples each. All ten build triples are byte-identical. Resident checks
are 44-49% lower and builds 31-36% lower; fresh-process gains are not established
across the workloads. Cache priming is excluded, and these are neither Rust
parity nor release qualification. Results, hashes and raw samples:
`~/w/anal/perf-query-20261117/{results,additional-results}.json`.
An early build comparison shared output caches between fresh and resident
requests; its build timings were rejected and rerun with isolated caches.

Focused request probes cover malformed-input recovery, source failure/fix,
semantic edits, added/removed function remaps, profile switches, newly created
and deleted imports, native-tool stdout/stderr framing, failed-output
preservation and emitted-program results. The negative-lookup probe exposed an
implicit-module/import binding collision, also present in the frozen baseline.
The resolver now merges a discovered namespace with its originating import,
preserving duplicate-import errors and public reexports. Both new multi-file
regressions passed without running the module suite.

First-load metadata continuation (2026-11-17): type records are semantically
validated before descriptor materialization. Empty stores directly adopt
structurally unique graphs; canonical merging remains for aliases, existing
consumer types and logical lookups. Compact IR admission streams locals/scopes,
retains parameter/special slots, and borrows nested string tables. Full body
loading restores omitted metadata. No archive-format or language change.
Compiler SHA-256:
`ec95b339f3bd12767d2aa77facdf8982ded3f64a756f1711d9e54b85666ff4cf`.
Against `53ee90d6...`, six randomized fresh-check and four edited-build pairs
per workload produced:

| Workload | Fresh check: prior / current | Build: prior / current |
| --- | --- | --- |
| P03 | 0.839625 / 0.776091 s | 1.093852 / 1.047875 s |
| P04 | 0.850123 / 0.784849 s | 1.091462 / 1.030716 s |
| P05 | 0.855613 / 0.792220 s | 1.243837 / 1.178149 s |

Checks are 7.4-7.7% lower; builds 4.2-5.6% lower. All twelve build pairs are
byte-identical. The streaming-header addition has no independently established
latency gain beyond the graph work. No memory improvement is established;
build peak RSS increased approximately 2-4 MiB. Evidence:
`~/w/anal/perf-metadata-20261117/{results,graph-results}.json`.

Resident archive continuation retains one verified, owned immutable archive
snapshot per root, shares section storage, and copies source state before
mounting. Source-provenance validation is reused only while its inputs are
unchanged. Complete source/configuration hashing remains per request. Compiler:
`7ee55d6309ff6659538535d0d132793a0ef00202c0185da0215f6434e07d2c9c`.
Against `ec95b339...`, six randomized resident-check and four edited-build pairs
per workload, with independently primed caches and fresh semantic edits:

| Workload | Resident check: prior / current | Resident build: prior / current |
| --- | --- | --- |
| P03 | 0.450148 / 0.403646 s | 0.697382 / 0.654893 s |
| P04 | 0.437370 / 0.400409 s | 0.701217 / 0.649151 s |
| P05 | 0.458010 / 0.423971 s | 0.860623 / 0.804645 s |

Checks are another 7.4-10.3% lower; builds 6.1-7.4% lower, with twelve
byte-identical build pairs. The six-pair fresh P04 sample was
0.758533 / 0.777026 s: no fresh-process benefit is established for archive reuse.
One-session resident peak RSS was 674572 / 649692 KiB, not memory qualification.
An initial comparison was rejected because only the candidate resident had
performed cold library compilation, retaining different allocator state.
The final run primes native compilation in separate processes and excludes
whole-output hits. Evidence: `~/w/anal/perf-mount-20261117/results.json`.

Focused graph, IR codec and archive probes passed, including canonical fallback,
special-slot restoration and invalidated provenance validation. Resident probes
preserved build/runtime results after in-place replacement of all backing
archive bytes, and rejected same-size native source edits with restored mtimes.
The pinned Rust 1.99.1 compiler was found outside PATH; direct P04 engineering
medians were 0.021221 s for metadata and 0.252018 s for linking, using the
workload manifest's edition/release codegen/panic settings. This is not a
consolidated parity comparison; the gap remains substantial. Raw Rust samples:
`~/w/anal/perf-metadata-20261117/rust-results.json`.

Resident source-query continuation now shares immutable function/type contracts,
demand-creates imported type environments and borrows native bodies without
copying their inventory. Decoded headers are retained by archive content and
exact mounted source IDs; consumer header fields are copied without reparsing.
Eligible user functions retain successful declaration/type contracts and raw
symbolic IR. Body edits invalidate transitive semantic/IR callers, including
unreachable checked references. Replayed indirect calls rebind request-local
contracts. Unchanged functions reuse successful body-analysis proofs but retain
normalization, structural verification and concrete executable admission.
Only successful preparation replaces the source snapshot.

Compiler `1530ee9619b2a9bf40628e7ee229c7bcfebaea3e9556c74123c762881397fa59`,
against frozen `7ee55d63...`: five randomized edited-check and three edited-build
pairs per workload, independently primed native caches, no whole-output hits:

| Workload | Resident check: prior / current | Resident build: prior / current |
| --- | --- | --- |
| P03 | 0.396767 / 0.359910 s | 0.644859 / 0.628497 s |
| P04 | 0.400631 / 0.351106 s | 0.662231 / 0.608800 s |
| P05 | 0.419835 / 0.388270 s | 0.820149 / 0.773907 s |
| 80 independent functions | 0.098507 / 0.063393 s | 0.237276 / 0.186813 s |

Native-workload checks are 7.5-12.4% lower and builds 2.5-8.1% lower. Independent
function checks are 35.7% lower and builds 21.3% lower. P04 reuses one source
function; P03/P05 reuse none, isolating their gains to native/header work.
All twelve paired builds are byte-identical. Four fresh P04 pairs give
0.794826 / 0.739584 s, engineering evidence only. Combined resident peak RSS
increased 636536 / 807716 KiB; no memory improvement or qualification is claimed.
Evidence: `~/w/anal/perf-demand-20261117/results.json`.

Native type-interning indices now share an immutable prefix with consumer-local
additions, preserving full identity predicates and canonical ordering. Imported
key changes invalidate only the consumer index. Compiler
`154606276e5ec3c53246eedd5a810294da02c3926a53931a5739bd946b2451b9`,
against frozen `1530ee96...`, with the same paired measurement shape:
P03/P04/P05 checks are another 3.4-10.7% lower, builds 4.1-6.8% lower, with twelve
byte-identical paired builds. Independent-function checks were 9.1% higher and
builds essentially unchanged; no additional benefit is established there.
Fresh P04 checks were 0.793532 / 0.757142 s. Peak RSS was 784560 / 803172 KiB;
sharing indices has not established a memory reduction.
Evidence: `~/w/anal/perf-interning-20261117/results.json`.

Focused source-query, library-declaration and type-graph regressions pass:
cached/fresh IR equivalence, transitive invalidation, inferred results, failed
request recovery, generics, indirect calls, header ownership and interning
isolation. No broad suites, sanitizers or qualification ran.

Further frozen engineering batches, with the same paired measurement shape:

| Candidate / prior | Native edited checks | Native edited builds | Fresh P04 prior / current | Peak RSS prior / current |
| --- | --- | --- | --- | --- |
| `a18f6d72...` / `15460627...` | 12.4-17.4% lower | 6.0-10.1% lower | 0.763366 / 0.666299 s | 798920 / 782560 KiB |
| `899349dc...` / `a18f6d72...` | broadly similar | broadly similar | 0.713882 / 0.691987 s | 768136 / 778620 KiB |
| `64eaa188...` / `899349dc...` | 6.6-16.3% lower | 4.2-9.5% lower | 0.693824 / 0.633265 s | 775540 / 738232 KiB |
| `944b589f...` / `64eaa188...` | no consistent gain | mixed, within 3.3% | 0.652512 / 0.646468 s | 735972 / 706504 KiB |
| `83ecad04...` / `944b589f...` | mixed, -4.4% to +4.5% | broadly similar | 0.640648 / 0.621488 s | 705528 / 708028 KiB |
| `0a323ae2...` / `83ecad04...` | mixed | P05 6.5% lower; others mixed | not isolated | 698268 / 715204 KiB |
| `93a01506...` / `0a323ae2...` | mixed | P04 7.5% lower; others mixed | not isolated | 704300 / 708328 KiB |
| `bd90c503...` / `93a01506...` | 16.3-22.8% lower | 10.7-14.5% lower | 0.639486 / 0.616166 s | 697896 / 633220 KiB |

Each batch has twelve byte-identical paired builds. Evidence:
`~/w/anal/perf-{refresh,projection,semantic-prefix,typed-admission,borrowed-admission}-20261117/results.json`.
The refresh batch avoids detaching native records on reads and refreshes source
generic origins explicitly, including late destructor finalization. Projection
retains only live source type/region closures over the native prefix; focused
same-length array edits discard obsolete body types, and region projection
preserves reachable binder/universe relationships. This is not a general RSS
bound. The semantic-prefix batch shares implementation records through paged
COW storage, persists finalized callable-bound contracts and checks coherence
only for pairs containing a source rule. Fresh graph admission uses streamed
fingerprint buckets with exact collision comparison and a DAG fast path before
SCC fallback; complete graph validation/canonical merging remain mandatory.
Typed admission replaces the largest-variant staging arena with typed pages and
a compact ordinal index; validation borrows descriptors and only canonical
fallback constructs the heavyweight variant arena. The latest pair establishes
a lower observed resident peak, not a consistent latency improvement.
Borrowed admission then removes the separate staging pools entirely: decoding
fills the transactional typed store, validation borrows descriptors, and unique
identities publish it directly. Canonical fallback alone copies owned variants.
Its paired results do not establish another resident latency or memory win.

The semantic-prefix compiler is
`64eaa188b4254f764fdb0bc85072dd212a1dc3d35db0363f9d4c45e0fcdb7609`.
The measured borrowed-admission compiler is
`83ecad04a94cb0674672f2114ac2b419de9c0d1152a4df08079b0fd93c7d85f0`.
Focused type-graph, declaration and module-memory checks pass. Specialization
queries now retain eligible instantiated IR before callee binding, with the
source-query context and dependency invalidation. Calls and destructor demand
rebind to current result IDs; region signatures recompute, successful executable
admission governs publication, and only reached entries survive each compile.
Portable recipes now cover eligible consumer structural types, scalar constants
and native generic instances across type-ID renumbering. Source nominal and
normalized/regional shapes, generated helpers and assembly still fall back.
Fixed builtin call contracts stop unnecessary caller invalidation while edited
functions remain invalidated. Differential concrete-IR cases cover
generic reuse, caller edits and changed demand order. The resident protocol now
reports `instanceQueryHits` separately from semantic/raw-IR function reuse.

The shared-declaration batch also makes imported region signatures demand-created.
Checked headers share stable read-only records; source syntax remains owned,
consumer mutations detach explicitly, and function identity no longer assumes
contiguous objects. That batch's measured compiler is
`bd90c50360a8e7d1c4c1572d26689c967c79939be623217c686ac6a4334932f9`.
The comparison includes lazy regions and shared headers together, not an
isolated attribution. Native edited-check medians are 0.220-0.238 s versus
0.263-0.289 s; edited builds 0.464-0.601 s versus 0.531-0.672 s.
Independent-function checks were 2.4% higher and builds 3.4% lower.
Each new batch has twelve byte-identical paired builds. Evidence:
`~/w/anal/perf-{structural-queries,fixed-contracts,shared-declarations}-20261117/results.json`.
Integrated module-memory and declaration checks pass, including repeated
consumers of one retained header.

Subsequent batches share native annotation/expression indexes, construct constant
evaluator shapes on demand, and consult admitted function contracts without
reconstructing per-consumer membership sets. Against `bd90c503...`, the immutable
index batch (`2a444f96...`) lowered native edited checks 4.1-12.5% and builds
1.6-6.9%, with peak RSS 632280 / 643296 KiB. Direct contract views
(`ba35c043...`) had mixed edited checks and 2.6-5.0% lower native builds;
fresh P04 was 0.620040 / 0.618612 s, peak RSS 640116 / 640288 KiB.

Checked-expression wire validation is now separate from AST/fact-map
materialization. Admission retains owned byte slices and frozen remaps;
constant calls, defaults and associated initializers materialize only on demand.
The finalized measured candidate is
`33844d2c2042848f135b61b40739a506b14276814f7661d4c14189cfd740ac1f`,
against `ba35c043...`: fresh P04 checks 0.619470 / 0.571414 s (7.8% lower),
resident peak RSS 636540 / 599948 KiB. Edited checks/builds are mixed, not a
general latency win. An apparent text-build regression in the three-pair run
did not reproduce in eight focused pairs (0.440521 / 0.438693 s).
All twelve main paired builds were byte-identical.
Evidence:
`~/w/anal/perf-{immutable-index,native-contract-views,deferred-admission}-20261117/`.
The earlier `perf-deferred-expressions-20261117` experiment recorded a fresh-check
regression before remap recording was confined to deferred expressions.

The integrated associated-constant index additionally retains exact immutable
implementation/declaration matches, avoiding the repeated cross-inventory
consumer scan. Ambiguous source spans and detached headers keep the fallback.
Compiler `eb65a184be48beb8acf6e55d8bede28799ce295f8cf64216d54ac46e80eeb5ef`
includes this follow-on, which has not been separately latency-measured.
Integrated module-memory/declaration checks pass, including temporary byte and
callback lifetimes and rejection of a mismatched associated-constant header.

Hardware-counter profiling subsequently identified repeated native provenance
copies/remapping and global IR type verification as material resident costs.
Native source/provenance inventories now share immutable ownership through
archive copies and diagnostics; resident mounts reuse only matching source-ID
and hygiene allocations. Compiler
`7c8b2277387e964178d55857c9482a4198410d96bdbadae158aaf317430db5f7`,
against frozen `eb65a184...`, lowered native edited-check medians:
P04 0.203448 / 0.168505 s, P03 0.213342 / 0.158922 s,
P05 0.228192 / 0.181524 s (17.2-25.5% lower).
Edited builds were 2.7-6.4% lower; independent-function checks/builds were
0.067401 / 0.064919 s and 0.184384 / 0.184796 s.
Fresh P04 checks did not improve (0.599474 / 0.609468 s).
All twelve paired builds were byte-identical.
Evidence: `~/w/anal/perf-native-snapshots-20261117/results.json`.
Integrated archive/module-memory/declaration checks pass; the affected archive
ownership, replay, remapping and lifetime cases also pass under ASan/UBSan.
This is not whole-compiler sanitizer or I14 qualification.

The subsequent source-only batch removes the preliminary type-graph decoding
pass and duplicate root reads, with schema-derived allocation bounds. Resident
IR verification now shares type proofs with transitive dependency invalidation,
including destructor signatures, and retains product records instead of copying
them during traversal. Read-only imported function-symbol lookup no longer
detaches imported facts. Hash-map insertion
and set replacement reuse vacant probe positions unless reservation rebuilds
the index. Deferred symbol resolution preserves rejection of malformed wire
input before resolver callbacks. Type proofs retain record-only snapshots,
not copied interning indexes or normalization caches.

The subsequent five-triple, six-workload comparison used compiler
`e511e5de049ec40b964cb310ba42f503513029eaa6b8b5384909b2c68dd1eecd`
against frozen `7c8b2277...` and direct Rust 1.99.1:
native edited checks P03/P04/P05 were 0.166219 / 0.155713 s,
0.173431 / 0.164872 s and 0.183482 / 0.166466 s (4.9-9.3% lower).
Fresh P04 checks fell 9.0%; fresh P03 checks rose 2.7%.
Native fresh builds were 0.837909 / 0.830019 s,
0.870394 / 0.839450 s and 0.996514 / 0.958752 s.
Runtime changes were small and mixed, not a material win; all six outputs
matched Rust. Resident peak memory rose approximately 574 to 588 MiB.
The experimental LLVM O3 policy regressed hash-map runtime in crossed
compiler/library comparisons and was reverted to O2.
Evidence: `~/w/anal/perf-three-final-20261117-1701/results.json`;
the rejected experiment and isolation are in `perf-three-20261117-1701`.
Focused type-graph and IR-boundary checks pass. These are engineering timings,
not qualification; the new type-proof ownership work has no fresh sanitizer
qualification. Full lazy type/signature loading and I14 remain open.

An experimental decoded native-body cache added about 39 MiB of resident peak
without a clear edited-build win and was removed. Its measurements in
`~/w/anal/perf-specialization-bodies-20261117/results.json` are not an accepted
optimization. Temporary instrumentation was removed.
No broad suites or milestone qualification ran. HEAD remains `b212a55c`,
with task and unrelated dirty changes preserved.

The uncommitted borrowed-admission follow-up retains validated compact type
descriptors for classification, region decoding and variadic escape checks;
adapter discovery reuses native metadata instead of rescanning native roots.
The focused type-graph executable passes, including input-buffer lifetime and
consumer mutation. A three-triple P04 comparison against the preceding
revision-index candidate measured fresh checks 658.134 / 632.312 ms, resident
checks 138.985 / 132.773 ms and resident builds 410.018 / 393.677 ms.
Peak resident memory increased 490084 / 506804 KiB. This is a small partial
result, not removal of the dominant import cost or qualification.
Evidence: `~/w/anal/perf-borrowed-admission-20261117-204951`.
The hash SIMD-controls experiment regressed P05 44.589 / 49.669 ms and was
reverted. The owner subsequently approved removing the public contiguous bucket
slices and `Bucket.hash` contract for direct key/value buckets; that redesign is
in progress. Evidence: `~/w/anal/perf-simd-hash-p05-20261117-2037`.

The owner also approved linker build IDs for compiler-cache identity, with
SHA-256 fallback when unavailable. Runtime archive digests remain unchanged.
The focused cache-identity regression passes, including ID invalidation and
content-hash fallback. Three-triple P01 fresh checks measured 65.060 / 11.299 ms
(Rust 16.623 ms), and fresh builds 184.116 / 131.909 ms (Rust 231.511 ms).
With the latest borrowed consumers, P04 fresh checks measured
601.317 / 548.362 ms (Rust 19.974 ms); resident checks 140.703 / 135.134 ms.
This removes the startup hashing floor, not the dominant native-import gap.
Evidence: `~/w/anal/perf-native-build-id-20261117-r1/results.json`.
The approved direct-bucket implementation measured P05 44.514 / 32.959 ms
(Rust 37.077 ms) with matching outputs, one frozen compiler and three randomized
pairs. Eighteen focused ASan runs passed, including portable probing, allocation
failure, hash-panic rehash rollback and unwind cleanup. The validated library
also builds and runs P05 with the latest borrowed-view/build-ID compiler.
Evidence: `~/w/anal/perf-three-final-20261117-1701/runtime-root/direct-buckets/`;
integration: `perf-native-build-id-20261117-r1/hash-integration.json`.

The indexed-admission follow-up uses persisted compact declaration queries,
archive-backed type/signature records, demand-loaded generic environments,
shared checking/finalized interface records and consumer-local overlays.
IR admission extracts compact headers directly. Independently authenticated
checked-function and IR payloads load on demand; source slices retain their
backing and eager identity/provenance validation. Driver linkage discovery uses
query headers rather than reconstructing imported syntax. Actual P04 demand
fell from 8,205 function/56 static trees to 26 function/no static trees.
Compiler `2ddb0217b2350bc40809df0e66e5201bced2247a0709e1021403ce38254ec5a9`,
against frozen `dd956087...`, measured fresh P03/P04/P05 checks at
454.806 / 385.805, 451.060 / 396.445 and 493.541 / 446.736 ms
(9.5-15.2% lower). Their fresh builds were 733.216 / 709.378,
757.474 / 689.661 and 904.460 / 901.810 ms. All six outputs matched Rust.
These are three-triple engineering timings, not I14 qualification; native fresh
checks remain 21-27 times Rust. Reverse re-export chains at 2,048 imports fell
from 6,929.121 to 45.190 ms (Rust 152.955 ms). Affected archive, declaration,
module, codec and cleanup cases pass optimized and ASan/UBSan builds; focused
type, wildcard and package/cache/output cases also pass.
Evidence: `~/w/anal/perf-compact-query-six-20261117-234049/results.json`
and `~/w/anal/perf-indexed-import-scaling/results.json`.

A further type-index change eliminates a second identity-projection decode for
60,727 of P04's 67,449 imported types; 6,722 symbol-dependent records retain
the remapping pass. Compiler `a402c438...` against `2ddb0217...` measured
P03/P04/P05 fresh checks at 397.474 / 383.394, 445.432 / 405.464 and
451.834 / 441.647 ms in three matched triples. Builds were mixed
(-4.4% to +0.5%), and all outputs matched Rust. Focused graph/import checks
pass optimized and ASan/UBSan builds. These are engineering measurements:
`~/w/anal/perf-type-query-pass-20261117-235802/results.json`.

Generated provenance now retains validated archive frames and rebases only
demanded records. The native inventory contained 161,771 mappings and 160,494
context occurrences but only 988 distinct bound marks. Span validation no longer
allocates revision strings; provenance edges and exact contexts are deduplicated.
Compiler `2b8b702b...` against `a402c438...` measured P03/P04/P05 fresh checks at
423.156 / 342.658, 397.627 / 338.577 and 453.294 / 383.645 ms (14.9-19.0%
lower), and builds at 707.859 / 623.246, 702.446 / 632.109 and
852.980 / 786.365 ms. All three outputs matched Rust. Archive, module, macro and
boundary cases pass optimized and ASan/UBSan builds, including deferred lifetime,
binder variants and rejection of unused cyclic/out-of-bounds provenance.
These remain three-triple engineering timings, not qualification:
`~/w/anal/perf-provenance-final-20261118-074314/results.json`.

Imported candidate groups now share contiguous ordinal storage; canonical
encoding reuses its buffer, logical-identity uniqueness uses retained wire
slices, and demanded validation reuses completed drop/array-expansion proofs.
The validation context retains regions and ABI rather than another TypeStore.
Compiler `40b98922...` against `2b8b702b...` measured P03/P04/P05 fresh checks
at 330.647 / 324.253, 344.547 / 315.023 and 385.052 / 367.168 ms
(1.9-8.6% lower), and builds at 649.103 / 607.953, 643.216 / 618.438 and
814.252 / 779.595 ms. Outputs matched Rust; affected graph/import cases pass
optimized and ASan/UBSan builds. These are three-triple engineering timings,
not qualification; fresh checks remain 17-23 times Rust:
`~/w/anal/perf-proof-type-admission-20261118-025003/results.json`.

Header admission now borrows its section instead of copying 8,135,248 bytes,
binds source revisions once and skips the redundant span-consistency sort.
Structural-key uniqueness uses a flat ordinal table with exact collision checks.
Compiler `74d0a1eb...` against `40b98922...` measured P03/P04/P05 fresh checks
at 309.254 / 292.979, 341.052 / 303.769 and 352.782 / 352.911 ms, and builds
at 617.920 / 603.498, 627.409 / 616.133 and 791.281 / 779.166 ms.
Outputs matched Rust; affected imports pass optimized and ASan/UBSan cases,
including backing lifetime, relocated ranges and invalid source bounds.
P04 median peak RSS fell from 296,550,400 to 288,432,128 bytes in three pairs.
P05 checks did not improve; these remain engineering measurements, not I14
qualification: `~/w/anal/perf-source-range-admission-20261118-034212/`.

Demand validation no longer allocates/clears an inventory-sized reachability
bitmap per new root. One retained bitmap clears only queued nodes, including
failed demands. For 32,768 independent demands, median time fell from 40.571
to 34.535-35.131 ms with 32,768 types, and from 44.941 to 31.438-31.825 ms
with 262,144 types. Affected imports pass optimized and ASan/UBSan cases;
repeated invalid demands still reject. This is an isolated algorithm measurement,
not an end-to-end/Rust parity result:
`~/w/anal/perf-demand-reachability-20261118/comparison.json`.

Still missing: specialization recipes do not cover every consumer-local type.
Source queries conservatively fall back for unsupported cache shapes and shifted
spans. Consolidated memory/storage/performance gates and whole-milestone
lifetime/sanitizer qualification remain open, as do source freeze and I14.
Initial canonical type/index validation and checking-database admission remain
eager; the dominant fresh-import gap is reduced, not eliminated.
Next action: reduce those remaining admission costs without dropping graph
validation or implementation-selection closure. Broader specialization reuse
needs explicit canonical type remapping,
not reused numeric consumer TypeIds.
Preserve frozen candidates and reuse unchanged-input evidence rather than
rerunning broad passing groups.

### 8.6. Architectural evolution and operation completion: I15-I17

I15 ports substantive compiler functionality to Mettle, not a thin launcher
around the C++ implementation. Port incrementally, starting with self-contained
front-end components (lexer, parser) checked for identical output against the
C++ reference. Retain the C++ bootstrap/compiler reference,
record staged builds and exercise the resulting compiler on itself and the
full capability/target corpus. Add the applicable P12 compiler workload.
Self-hosting alone proves neither correctness nor improved runtime.


I15 obligations: port the compiled dependency interfaces and query engine to Mettle
(the performance-enabling bootstrap work above belongs to I14); a checked frontend
and verified middle end; backend, build and editor integration; bounded storage and
compiler/runtime performance including P12; then source freeze and staged
bootstrap (stage 1/2/3 identities, repeatability, complete capability and target
gates, C++ reference retained). Package boundaries and compiled-interface
contracts are in [compiler-architecture.md](compiler-architecture.md) section 1.1.

I16 replaces LLVM's production backend responsibilities behind the compiler IR
boundary: instruction selection/legalization, registers, machine optimization,
object/debug/unwind emission and each accepted target's ABI integration.
System linkers/SDKs remain explicit profile dependencies; LLVM code generation
cannot remain a hidden fallback. Compare both backend paths and Rust under
equivalent semantics and requalify every accepted profile. The independent
backend must provide address/undefined-behavior and thread checking equivalent
to the current ASan/UBSan/TSan qualification, or run the full unsafe/runtime
corpus under it; losing sanitizer coverage blocks I16.

I13B closes the library and trait-implementation obligations of worklist groups D-J
before V1 qualification. I17 closes the applicable non-deprecated pinned stable
obligations outside I13/I13B: architecture intrinsics and OS extension modules, each with
the same declaration, applicability and per-operation evidence rules as I13.
It may proceed alongside I15-I16.

Owner worklist amendment (2026-11-09): deprecated APIs are no longer required,
and all eight [reference profiles](../spec/platform-contracts.md#8-reference-profiles) remain in post-V1
scope. The [reconciled worklist](post-v1-worklist.md) accounts for all 106,120
stable canonical records: 629 excluded deprecated records, 13,291 V1
obligations, 41,150 post-V1 contextual obligations, 50,190 attached
implementation members, 684 attached inherent blocks and 176 namespaces.
The post-V1 obligations group into 32,354 source-declaration work units;
4,864 also occur in V1, leaving 27,490 units not represented there.
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
| Cutover | Dotted paths, `extend` implementation blocks, D21 vocabulary, and optional item-level semicolons | Landed |
| R1 | Bounded lookup, associated namespace, constructor selection, inference, vocabulary and the `experience-1` prelude | Open: slice/fixed-array argument inference, String/Set private storage factories, slice/array/tuple/parenthesized-view projection subjects |
| F1 | Fixed borrowed `Message`, `format` parameters, two-level forwarding and the std Writer adapter (library-surface section 10); lifetime, error and code-size tests; measure indirect-call cost, renderer/code size and check cost | In progress |
| R2 | Lending lines, Copy-valued `[u8].bytes()`, KeyView, PathInput/`write_path` and equivalent workloads within qualified profiles; reconcile `library-and-abi.md` POSIX path statements with the native Windows path contract before delivering that profile | POSIX landed; Windows paths and collision stress open |
| R3 | Expression-bodied `fn`, diagnostics, formatter/editor completion | Remaining editor precision gaps: tooling-and-packages.md section 5. |
| Qualification | Frozen-input quality, target, safety and performance checks, including performance.md sections 5.1-5.2 and the D17 comparison harness (`tools/bench_compare.py`, `benchmarks/`, performance.md section 5.3) | After R1-R3; no result claimed |
| WP-S | Storage audit work package of tooling-and-packages.md section 7.1; operational, no dependency on an artifact store | Open |
| D32-D34 syntax composition | Prefix named-parameter access, native `Outcome<T, E>` values and comma-separated if/while conditions; preserve I04/I05 ownership/effect contracts and I06 L004 short-circuit behavior | Landed; qualification pending |

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

Exhibit programs: [cli_wordcount_lines.mt](../../tests/std/cli_wordcount_lines.mt)
(byte-streaming word count; before: [cli_wordcount.mt](../../tests/std/cli_wordcount.mt)) and
[ini_parser_readable.mt](../../tests/alloc/ini_parser_readable.mt) (digit-list parser; before:
[ini_parser.mt](../../tests/alloc/ini_parser.mt)). They keep arguments, raw path support, byte
counts, separators, final unterminated line, exit codes, first-`=` splitting,
CR retention and the original overflow-profile arithmetic. Compare outputs
byte for byte against the originals.

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

Each milestone's evidence bundle records source/toolchain revisions, target/
profile, exact commands, fixture and operation IDs, expected versus actual
results, diagnostics/exit statuses and raw measurements where applicable.
Capability status changes require that evidence, not this schedule.
Keep specification, implemented, tested and release-qualified states distinct.
New tests should exercise the behavior landing in that milestone and protect
it in later milestones; do not defer all correctness or performance work to I14.
