# Compiler implementation plan

Status: I01 foundation is complete for the native macOS ARM64 compiler host and
Linux x86-64 target execution. I02 scalar source compilation is qualified within
that host/target scope. I03 concrete ownership and resource cleanup is qualified
within the same scope; I04-I16 remain planned.
The selected design is in the linked specifications. Scalar execution does not
establish full language, library or release correctness.

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
Avoid claiming the complete Rust arithmetic matrix until every operation is
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

The normative [compiler architecture](compiler-architecture.md) defines component
ownership, phase representations, future feature placement and dependency
enforcement. The tree below is a repository overview, not a sufficient module
design. The architecture correction and its passing gates precede I03.

Create these only when implementing the owning milestone:

```text
compiler/
  source/       source buffers, spans, expansion identities
  syntax/       lexer, lossless syntax, parser and recovery
  semantics/    names, types, constraints and access-mode checking
  ir/           typed control flow, places, loans and cleanup operations
  lowering/     runtime, ABI, async and erasure lowering
  backend/llvm/ LLVM adapter and object generation
  driver/       commands and orchestration
runtime/        minimal support; no executor in core by default
library/        core, allocation and hosted layers
tests/          semantic fixtures, runtime cases and ABI probes
benchmarks/     matched Rust/Mettle workloads
```

Avoid separate service/process boundaries for compiler components initially.
Use typed internal APIs. An internal validator failure is a compiler defect, not
a user error. Keep public extension APIs separate from unstable internal classes.

## 4. IR contracts

| Boundary | Required information | Forbidden shortcut |
| --- | --- | --- |
| Source -> syntax | Exact spans, trivia, malformed nodes | Discarding provenance needed for editor errors |
| Syntax -> typed representation | Resolved symbols, types, modes, effects | Whole-program guessing of public ownership |
| Typed -> ownership CFG | Places, projections, moves/copies, loans, initialization, explicit exits | Erasing ownership before checking it |
| Checked CFG -> cleanup CFG | Per-edge destruction and state, panic/error successors | Cleanup based only on lexical variable names |
| Runtime lowering | Concrete calling/storage policy, closures, erased values, async state | Silent boxing, retain, or executor dependency |
| Backend adapter | Layout, calls, memory operations and justified assumptions | Inferring noalias from informal borrow descriptions |

Initial operations: constants, projection, load/copy, move, borrow, initialize,
replace, call, branch, return, and explicit cleanup. Add exceptional successors
before functions can panic/unwind through resource-owning code.

Represent type/source identities with stable handles within a compilation.
Do not make LLVM types the language type system. The LLVM adapter maps checked
operations to target IR; it cannot decide missing language semantics.

An SSA representation for scalar optimization is useful, but keep addressable
places and cleanup semantics until lowering has preserved them. Do not implement
an elaborate optimizer before correctness and end-to-end execution.

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

Planning found no CMake/Ninja on PATH and no selected Clang installation.
Implementation now uses checksum-pinned project-local artifacts; the bootstrap
does not substitute the host's Apple Clang. A local Lima/QEMU runner supplies the
Linux x86-64 execution environment. Its cross-architecture guest agents are host
runner dependencies, not compiler dependencies.

Use a Linux x86-64 runner/VM for authoritative target execution. A macOS build or
cross-produced ELF file alone is not evidence that the Linux executable works.
The compiler host and executable target are separate identities: native macOS
Debug/Release builds may cross-emit objects that are linked and executed under
the Linux x86-64 kernel. This does not qualify a Linux-hosted compiler build.
Do not require local Rust for ordinary Mettle users; Rust is a comparison tool
and optional interop build dependency.

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
but the user has explicitly selected a stronger project gate: finish documentation
first. Do not start implementation on the strength of the subset alone.
`specification-status.md` defines the documentation completion evidence and its
limits. The documentation gate closed before the user authorized I01
implementation; source/build files are now permitted. Documentation validation
excludes tool caches and build output without relaxing the frozen API audit.

Borrow checking and resource lowering must wait for precise CFG/loan/drop
contracts. Unwind recovery, borrowed spawned tasks, and strong backend aliasing
metadata must wait for their soundness-critical rules.

Before external source publication/distribution, resolve the project license.
No release date, staffing commitment, package installation, repository publishing,
or CI infrastructure purchase is implied by this plan.

## 8. Delivery milestones

Each milestone ends in an executable or independently inspectable artifact,
with positive/negative checks and retained evidence. Creating directories,
emitting unchecked LLVM IR, assigning API mappings or counting source lines is
not completion. I01-I03 are complete within their recorded host/target scope;
I04-I16 are not started.

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
| I13 | Platform and capability closure | All 107 capability requirements and applicable stable operation contracts have checked declarations and evidence across selected profiles | I12 |
| I14 | V1 release qualification | Reproducible installable C++/LLVM toolchain passes safety, capability, target and Rust-runtime gates | I13 |
| I15 | V1.1 substantive self-hosting | Mettle compiler builds itself through repeatable bootstrap stages and preserves V1 capability/performance gates | I14 |
| I16 | V1.2 independent production backend | LLVM-free code generation covers every accepted profile/capability and passes Rust/LLVM-path comparisons | I15 |

This is fourteen delivery milestones to V1, followed by two architectural
evolution milestones. I02 is the first useful native compiler, not a reduced V1.
Dependencies are completion gates; a component's preparatory work may start once
its own contracts/inputs exist, without marking the enclosing milestone complete.

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

I01 evidence (2026-10-28): macOS ARM64 Debug and Release each pass all three
CTest fixtures and a byte-identical clean rebuild of the CLI, backend archive
and smoke emitter. Debug object DWARF verification passes. Both emitters produce
x86-64 ELF objects that Clang/LLD 21.1.8 link and the Ubuntu 24.04/glibc 2.39
Linux x86-64 kernel executes with status 37. Source/tool/sysroot identities,
commands, logs and retained artifacts are under `build/macos-arm64/` and
`build/linux-target/`. An attempted full Linux-hosted compiler link was
interrupted when its emulated VM was killed; that host configuration is not
qualified by this gate.

I02 implements the vertical slice in section 2: source buffers/spans, tokens,
lossless parsing, resolution, scalar types, compiler-owned IR, LLVM lowering,
linking and native exit status. Include the separator/precedence recovery corpus
and arithmetic failure paths. Reject unsupported features explicitly.
Begin P01 runtime comparisons and retain compiler time/memory measurements;
these early measurements are engineering signals, not the V1 verdict.

I02 evidence (2026-10-28): the scalar frontend retains source/trivia tokens and
grouping/spans, resolves functions and lexical scopes, solves result inference
components, and builds compiler-owned CFG. CFG checking validates initialization
and immutable writes across branches/back edges before LLVM lowering.
The CLI checks/builds i32/bool/Unit programs with Never results, optional colon
results, named calls, block tails/discards, if/while/loop and return/break/continue.
Debug overflow checks and release wrapping preserve the specified i32 rules;
division/remainder failures always trap, and shifts are checked or masked.

Both macOS compiler configurations pass seven CTest suites and byte-identical
clean rebuilds; compiler Debug DWARF verification passes. Each configuration
retains 34 positive executions, 44 invalid/unsupported rejection cases,
24 arithmetic/profile executions and 11 syntax/inspection commands under
`build/macos-arm64/<configuration>/scalar-evidence/`. JSON token reconstruction,
UTF-8/CRLF/nested comments, parser recovery/limits, span/phase diagnostics and
output preservation are included. `build/linux-target/foundation-evidence.json`
records 28 source cases linked/executed under the actual Linux x86-64 kernel,
covering both compiler builds and source profiles, plus both foundation smokes.
The dedicated VM was stopped after validation.

`build/p01/evidence.json` records three integer-reduction sizes, six randomized
pairs per size, independently checked exit checksums and compiler time/peak RSS.
Its installed Rust comparator is 1.94.1, not the frozen 1.99.1 baseline.
Process startup/shared-host noise and the single session make these engineering
measurements, not a pilot/release result or a runtime parity claim.

This gate does not implement ownership/products/generics, libraries, other
numeric widths, uninhabited parameters, a stable inspection API or source-level
program DWARF. Unsupported language features are explicit diagnostics, not
reclassified as invalid V1 contracts. Full Linux compiler-host qualification and
release/platform/performance gates remain separate.

Toolchain compatibility requalification (2026-10-28): LLVM/Clang/LLD/compiler-rt
22.1.3 replaces 21.1.8 to resolve Darwin sanitizer startup. Immutable source and
host/target archive identities are updated together; CMake/Ninja are unchanged.
The backend uses LLVM's Triple-taking target lookup instead of its deprecated
string overload. No language rule or arithmetic check was weakened.
Debug and Release again pass all seven suites, and Debug ASan/UBSan passes
eight, including actual detector/error-exit probes. All three builds pass
byte-identical clean rebuilds, and the instrumented build passes the complete
quality/static-analysis gate. Both ordinary builds again link/execute all
28 scalar target cases and both foundation smokes on Linux x86-64.
Earlier tools/build evidence is preserved with `llvm-21.1.8`/`-llvm21` names;
the original P01 measurements remain historical engineering evidence, not a
performance comparison qualified for the new toolchain.

Architecture correction (2026-10-28): the
[production compiler architecture](compiler-architecture.md) supersedes a
directory-only interpretation of section 3. Twelve actual components have
manifest-driven CMake targets, owned source/public headers and checked
dependencies. Parsed syntax, semantic facts and the admitted CFG have distinct
owners; lexing/parsing, inference, flow, dataflow, lowering, verification and
driver side effects no longer share combined implementation files.
The boundary suite is independent of LLVM and covers verification failures,
SSA/phi/initialization and in-memory/checked-data ownership.
Debug/Release pass eight suites, ASan/UBSan nine, all three clean rebuilds are
byte-identical, and both ordinary builds repeat the 28 Linux source cases.
I03 starts only after this structural gate, not by accepting future design
responsibilities as implemented features.

### 8.2. Ownership and type-system foundation: I03-I05

I03's first dependency implements compilation-owned nominal type identities and
concrete Copy products: checked declarations, finite by-value layouts, generated
construction, named argument order, whole-value copies/results and field reads.
`examples/core/values.mt` is executed without modification through the existing
source runner. Its additional product regressions check native behavior and
specific declaration/type failures, not repository layout.
The next dependency adds canonical projected places, sparse field-sensitive
initialization/move state and value/read/mut/take parameter contracts. Source
cases now execute `ownership.mt` and reject the original move/take failures for
ownership reasons. CFG borrow-value liveness permits disjoint field borrows,
restores reborrow authority after calls and rejects argument-evaluation conflicts.
The integrated implementation adds first-class stored/returned views, copied read
views, non-Copy exclusive views, basic region-only source contracts, concrete
methods and receiver reservation/activation. Scope/temporary metadata and static
cleanup plans drive native per-frame flags, user destructors, partial cleanup,
pending arguments/returns and replacement restoration during unwind. Origin/effect
analysis preserves declared lifetime dependencies through wrappers and view writes,
including implicit destructors.

I03 qualification (2026-10-29): Debug/Release pass twelve CTest suites each and
ASan/UBSan thirteen. All three builds reproduce their compiler/runtime/test
artifacts byte-for-byte; ordinary and instrumented quality gates pass.
Per compiler build, the existing source runner executes 112 run-pass profile cases,
104 compile-fail cases with intended diagnostics, and 24 arithmetic/profile cases.
The IR suite rejects duplicated non-Copy SSA consumption, lost cleanup and live
resource redeclaration, while accepting mutually exclusive phi transfers.
Method lowering preserves the checked receiver dereference path and distinguishes
borrowing a view handle from borrowing its referent.

Native cleanup evidence checks exact local/field/temporary order, partial
initialization/moves, early exits, pending arguments/returns, first-panic replacement
restoration visible at catch, and second-panic abort before installation.
Each ordinary compiler build additionally passes 134 Linux source/profile cases,
six native cleanup/recovery probes and its foundation smoke. Source/compiler/
runtime/generator identities match the retained receipts, and the dedicated VM is
verified stopped. Evidence remains under `build/macos-arm64/`, `build/quality/`
and `build/linux-target/`.

This closes I03 for the concrete single-file subset. Region-only source contracts
do not establish I05 generic/variance/higher-ranked checking; checked-IR catch
integration does not introduce source panic APIs. Linux target execution remains
distinct from Linux compiler-host and release-platform qualification.

I03 implements field-sensitive initialization, explicit access modes, Copy/take,
reborrows, two-phase receivers, temporary scopes and drop elaboration.
Implement exceptional cleanup before permitting unwind through resources;
test an outer catch observing a valid replacement after an old destructor panics.
Use ordered trace fixtures and negative ownership cases, not just successful
compilation. Generic ownership rules are exercised fully in I05.

I04 adds complete product/enum/pattern composition, nested presence and outcomes,
typed propagation/capture, modules/reexports/aliases, methods/default arguments,
labels/ranges/arrays and exhaustive control flow. Consume all applicable existing
example fixtures without weakening their expectations. A malformed program
must not satisfy a fixture intended to reject ownership or generic-body use.

I05 implements declaration-based generic bodies and specialization, named and
higher-ranked regions, variance, const parameters, associated types/constants
and GATs, coherence, lookup, operators, closures and callable modes. Add unsized
constraints, explicit erased dispatch and opaque return identities. Prove with
negative cases that a Copy instantiation grants no undeclared ownership rights,
overlap cannot be selected by order and a region cannot escape its binder.
The core constant expressions needed by const parameters precede the expanded
const-function evaluator in I09.

### 8.3. Native libraries and machine boundary: I06-I08

I06 completes integer/float/conversion behavior, raw-pointer provenance,
initialization/manual destruction, interior mutability, atomics, pinned storage,
layout, symbol/linkage, C callbacks/varargs and compatible unwind. Provide
volatile, assembly/intrinsic and freestanding mechanisms, initially demonstrated
on their applicable first execution/reference environments. Never substitute
an unsafe caller workaround for an unimplemented safe operation.
Use C round trips, layout/calling probes and independent memory-model cases;
sanitizer success alone is not a safety proof.

I07 implements core/alloc operation families against the pinned inventory:
unique/local-shared/weak owners, allocator identity/failure, optional/outcome
operations, UTF-8, slices/collections, iteration, hashing, formatting/parsing and
type identity/downcast. Native atomic-shared ownership lands here as needed,
but its concurrent safety closes in I10. Test allocation failure, partial
initialization, invalidation and panic, not only happy-path values.
Run a structured parser and collection workload without mandatory Rust, OS or
executor dependencies in core/alloc. Start applicable P02-P06/P08/P11 comparisons.

I08 adds files/paths/OS strings, synchronous networking, processes/environment,
time and hosted panic handling. Demonstrate partial I/O, non-Unicode names,
timeouts, child failure and raw OS-error round trips. Core/alloc must still
build without these hosted services. Record the initial profile's actual
behavior; other profile implementations close in I13.

### 8.4. Builds, concurrency and async: I09-I11

I09 completes required constant evaluation, hygienic declarative macros, host
procedural extensions, attribute/derive/cfg phases and versioned token APIs.
Implement manifest resolution, exact locks, feature/host/target separation,
build scripts and dependency-keyed incremental reuse. Demonstrate a native
multi-package project with a generated input and extension. Corrupted artifacts
must fail verification; untracked host inputs must trigger conservative reruns;
incremental and clean builds must agree. Host Mettle extensions can use the
services delivered in I08, avoiding an undeclared compiler-bootstrap dependency.

I10 can progress alongside I08/I09 after I07. Implement owned/scoped threads,
Transferable/Shareable, Arc/weak races, mutex/RwLock guards, condition variables,
barriers, once, channels and TLS. Test scope exit during panic, last-owner
destruction, guard affinity, channel shutdown and atomic publication under
contention. Race freedom is not a claim of fairness or deadlock freedom.
Add P09 and complete concurrent P08 coverage.

I11 implements pinned future state machines, async callable/interface contracts,
poll/wake integration and a separately selectable executor. Establish direct
borrowed await and owned tasks before borrowed-task execution epochs. The scope
must retain soundness for forgotten handles/parents, repeated wakes, worker panic,
parent destruction and an uncooperative child poll. Check actual cleanup versus
cancellation requests; no hidden mandatory boxing or default executor in core.
Exercise an async network service and P10 without weaker lifetime guarantees.

### 8.5. Workflow, profiles and V1: I12-I14

I12 closes the complete native developer workflow: command selection, diagnostic
categories, test/benchmark results, doctest checking phases, formatting, linting,
LSP and source-level debug information, including owners/erasure/async states.
Build minimal formatting/editor/debug support as the relevant syntax and IR land;
do not wait until I12 to preserve spans or discover uninspectable values.
I12 is the completion gate, not the first tooling work.

I13 closes remaining operation mappings with compiled native declarations and
per-operation semantic evidence, including supporting protocols, reexports,
deprecated stable APIs and target cfg branches missing from rendered docs.
Exercise the selected Linux x86-64/ARM64, Windows, macOS, Android, WASI,
non-hosted Wasm and freestanding references with their appropriate layers.
Verify native C ABI, debug/unwind/TLS/atomic behavior and optional Rust adapters.
Cross-compiling an artifact is not a substitute for execution/probes; an
inapplicable service is not a pass. Evidence must retain exact target applicability.

I14 freezes a release candidate and checks the whole accepted scope, rather than
removing difficult capabilities to produce a smaller V1. Run the predeclared
pilot/fixed-sample runtime protocol and all supported-profile acceptance suites;
preserve raw failures/inconclusive results. A faster workload cannot offset a
credible regression elsewhere. Verify clean installation and native compilation
without Rust. Resolve the owner's license/distribution decisions before public
publication; internal implementation does not require inventing those decisions.

### 8.6. Architectural evolution: I15-I16

I15 ports substantive compiler functionality to Mettle, not a thin launcher
around the C++ implementation. Retain the C++ bootstrap/compiler reference,
record staged builds and exercise the resulting compiler on itself and the
full capability/target corpus. Add the applicable P12 compiler workload.
Self-hosting alone proves neither correctness nor improved runtime.

I16 replaces LLVM's production backend responsibilities behind the compiler IR
boundary: instruction selection/legalization, registers, machine optimization,
object/debug/unwind emission and each accepted target's ABI integration.
System linkers/SDKs remain explicit profile dependencies; LLVM code generation
cannot remain a hidden fallback. Compare both backend paths and Rust under
equivalent semantics and requalify every accepted profile.

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
| I13 | S031, A009 |

Each milestone's evidence bundle records source/toolchain revisions, target/
profile, exact commands, fixture and operation IDs, expected versus actual
results, diagnostics/exit statuses and raw measurements where applicable.
Capability status changes require that evidence, not this schedule.
Keep specification, implemented, tested and release-qualified states distinct.
New tests should exercise the behavior landing in that milestone and protect
it in later milestones; do not defer all correctness or performance work to I14.

No calendar duration is asserted before measured prototype throughput exists.
No implementation, package installation or target infrastructure was started
by dividing this plan.
