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


I15 obligations: compiled dependency interfaces and a query engine; a checked frontend
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

I17 closes the applicable non-deprecated pinned stable obligations outside the V1 subset:
remaining inherent operations and trait
implementations, architecture intrinsics and OS extension modules, each with
the same declaration, applicability and per-operation evidence rules as I13.
It may proceed alongside I15-I16.

Owner worklist amendment (2026-11-09): deprecated APIs are no longer required,
and all eight [reference profiles](../spec/platform-contracts.md#8-reference-profiles) remain in post-V1
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
