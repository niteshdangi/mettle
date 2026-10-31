# Compiler implementation plan

Status: I06 is closed for the native macOS ARM64 compiler host and Darwin
target after the `c485aa1` re-review findings were repaired and requalified on
frozen commit `ff1daa3`. By owner decision (2026-10-31), Linux and Windows
execution is excluded from gates on this machine and runs separately.
I01 foundation is recorded for the native macOS ARM64 compiler host and
Linux x86-64 target execution. I02 scalar source compilation is qualified within
that host/target scope. I03 concrete ownership and resource cleanup is qualified
within the same scope. I04 composition and I05 generic typing/dispatch are
covered by historical native, sanitizer, quality, reproducibility and target
receipts; their re-review findings are covered by the I06 requalification.
I06 is complete within the scope above. I07-I11 are partially implemented on macOS arm64 (per-item
status in sections 8.3-8.4); none is qualified. I12 workflow commands are in
progress; I13-I16 are not started.
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

Each milestone ends in an executable or independently inspectable artifact,
with positive/negative checks and retained evidence. Creating directories,
emitting unchecked LLVM IR, assigning API mappings or counting source lines is
not completion. Historical I01-I06 receipts record their tested host/target scope,
and the `c485aa1` re-review's missed obligations were repaired before I06's
requalification. I07-I11 items carry per-item implementation/verification
status below; no milestone after I06 is complete.

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
| I14 | V1 release qualification | Reproducible installable C++/LLVM toolchain passes safety, capability, target and Rust runtime, compile-time and build-storage gates | I13 |
| I15 | V1.1 substantive self-hosting | Mettle compiler builds itself through repeatable bootstrap stages and preserves V1 capability/performance gates | I14 |
| I16 | V1.2 independent production backend | LLVM-free code generation covers every accepted profile/capability and passes Rust/LLVM-path comparisons | I15 |

This is fourteen delivery milestones to V1, followed by two architectural
evolution milestones. I02 is the first useful native compiler, not a reduced V1.
Dependencies are completion gates; a component's preparatory work may start once
its own contracts/inputs exist, without marking the enclosing milestone complete.
The experience track of section 8.7 runs alongside these milestones and is
delivered by its own gates.

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

The first I04 dependency implements non-generic transparent aliases and concrete
static associated functions. Product identities are collected before forward
alias expansion, and aliases preserve nominal/Copy/access/destruction behavior
rather than defining wrapper types. Cycles, unknown targets and unbound
region-specific aliases diagnose. `Type.function`, alias-qualified calls and
`Self` construction/lookup resolve without changing source spelling; static
functions have no implicit receiver. Explicit qualified read/mut/take method
calls retain their access contracts and are not implicitly two-phase.
Existing source/IR runners cover execution, intended rejection phases, inferred
associated results, view origins, resource cleanup and checked-data lifetime.
The next dependency adds lexical labeled break/continue targets and value-producing
`loop` expressions. Target-aware flow summaries distinguish outer exits from inner
ones; joined break values preserve declaration-based result inference and while
loops remain unit-valued. Lowering cleans all exited scopes and protects owned
break results during cleanup/unwind before transferring into the loop result.
The existing native trace fixture now checks fifty ordered destructions across
normal source scopes, including labeled jumps, and a pending break result destroyed
when scope cleanup panics during later-argument evaluation.
The remaining I04 work is integrated in one batch rather than separately
requalifying each small syntax addition: source-preserving external/inline module
assembly, imports/reexports/visibility, concrete enums and active-alternative
cleanup, guarded read/mut/take patterns, nested coverage and scalar/range/or-patterns,
conditional/destructuring/parameter patterns, nested optionals/outcomes and typed
failure continuations, defaults/custom constructors, tuples/fixed arrays/rest
borrows, bounded indexing, ranges/iteration, and Unicode scalar/byte literals.
Required array lengths evaluate checked integer expressions independently of
source arithmetic profile; the general const-function/package evaluator remains I09.
Large arrays are compact (one place, element type and length) and lowered
memory-based: `[u8; 1_000_000]` repeat, copy, by-value, return, `for` and
dynamic indexing build in about a second (previously 13 s and 2.4 GB for index
alone, and copy/by-value/`for` did not finish). Honest limits: arrays of
droppable elements stay expanded per element and are capped at 2^16 elements;
array patterns, constant-index projection of large static arrays, by-value
`for` over large droppable arrays and large aggregates across `extern "C"`
are not implemented (`error[feature]`/unsupported); each large local lives in
the frame, so total locals are bounded by the 8 MB thread stack.

The existing extended examples for nested optionals, typed outcomes and
defaults/methods execute unchanged. Interface/generic/callable fixtures remain
their I05 owners rather than being weakened to fit I04. Current behavioral,
native-cleanup and multi-file module runners provide the implementation evidence;
final native, sanitizer, reproducibility and Linux receipts remain the qualification
authority. This does not claim generic typing, a stable foreign ABI, complete
numeric/library behavior, release-platform coverage or Rust-runtime parity.

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

The I05 source corpus covers generic declaration rights, type/const defaults and
specialization, associated families/constants, coherence and explicit lookup,
receiver priority and once-only dereference projections, operators, callable
modes, higher-ranked region obligations, slice/tail metadata, borrowed erased
mutation/upcasts and opaque Self/associated results. Ownership regressions retain
loans through generic erased results and unknown mutable writebacks. The compiler
architecture records the private slice/witness representations and the explicit
sized-adapter requirement for erasing a witness-metadata implementor itself.
That conversion is not silently implemented with allocation.

I05 closure requires current Debug/Release and ASan/UBSan CTest, byte-identical
clean rebuilds, the fast and build-directory quality gates, and Linux x86-64
source/module/cleanup execution. Revision-bound receipts under
`build/macos-arm64/`, `build/quality/` and `build/linux-target/` are the authority;
historical I04 counts or focused scratch runs do not establish I05 completion.
This scope does not claim complete libraries, the I06 machine boundary, stable
foreign ABI, Linux compiler-host qualification or Rust-runtime parity.

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

Current I06 integration includes primitive widths, IEEE floats/conversions,
raw pointers, volatile and memory-copy/swap/replacement operations,
transmutation/zeroing with unsafe validity obligations, explicit uninitialized
and manual-drop storage, interior mutation, inline pinning and scalar atomics.
Native C scalar/aggregate/callback/varargs and compatible-unwind probes execute,
as does a no-entry freestanding object with no undefined runtime symbols.
Packed-field destruction now uses aligned storage that survives a destructor
panic; remaining fields finish once on re-entry. Structural pin projections,
pinned destructors, explicit pin receivers, Unpin properties, integer/C enum
representations and overlapping unions have native and target evidence.
I06's requalification after the `c485aa1` re-review and its limits are
recorded below; the older snapshot and focused batches remain history.

#### I06 acceptance inventory

Reconciled on 2026-10-29 against section 8.3, the 24 I06-owned rows in
`docs/capabilities.csv`, their linked specifications, current implementation
paths and retained receipts. This inventories existing obligations; it does not
add a new milestone or amend a language contract. Section 9's distinction
between initial milestone delivery and I13's complete operation/profile closure
still applies. Resolve an ambiguous boundary explicitly rather than silently
expanding or deferring it.

Implementation state is separate from evidence. **Partial** means a known
implementation gap remains; **implemented** does not mean fully verified.
The historical snapshot passed its recorded gate commands, but the re-review
showed that those commands missed applicable correctness obligations. Affected
rows must be revalidated against their regressions before another completion
verdict. The last column names acceptance checks and explicit later limits.

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
| S018 | Transferable/Shareable/Static: implemented initial contracts | Structural derivation in `interface_solver.cpp` (raw pointers, cells and `Ref`/`RefMut` opt out; atomics and plain data opt in), `unsafe extend`/negative `extend X not P` declarations, bounds enforced at call sites; Static additionally requires `static` regions | Frozen-input generic/region/projection qualification. Immutable statics must be Shareable (raw pointers and a bare `UnsafeCell` are exempt; `static mut` needs unsafe). Scoped spawns require `F: Within<region s>`, checked in `regions.cpp` (`withinBounds`), so closures cannot capture locals declared inside the scope body. `fs.ReadDir` is an `Iterator`; `mpsc.sync_channel(n)` has capacity `n`, including rendezvous at zero. A panic in a spawned thread is caught per thread and `join()` reports a Panicked result with code 101. Extension-level region names are now resolved from the current function's region scope when a callee's annotation scope is active (`regionReference`); verified on macOS arm64 (`impl-region-method-call-on-other-type.mt`), and `Scope.spawn` no longer needs its private `register` workaround. |
| S019 | Thread spawn and scope: implemented initial library | `std.thread` (`spawn`, `JoinHandle.join` reporting `Panicked`, `scope` joining on panic) over `runtime/thread.cpp`; owned threads require Transferable + Static, scoped ones Transferable | Linux target execution of `library.std`, sanitizer/TSan evidence of the shim, stress on the target. Race freedom is not a fairness or deadlock-freedom claim. |
| S020 | Mutex and RwLock: implemented initial library | `std.sync.{mutex,rwlock}` with poisoning, thread-affine guards (`not Transferable`) and an error-checking mutex that reports relock | Target stress and applicable poison/failure-policy cases. |
| S021 | Condition variables, barriers, once: implemented initial library | `std.sync.{condvar,barrier,once}`; a panicking initialiser re-arms `Once` | Target stress. |
| S022 | Channels: implemented, verified on macOS arm64 (`tests/std/channel_rendezvous_select_timeouts_iterator.mt`) | `std.sync.mpsc` unbounded FIFO, bounded channels including zero-capacity rendezvous, nonblocking and timed operations, blocking receiver iteration, and a condvar-backed multi-receiver `Select` | Run focused hosted channel cases, then Linux-target and TSan qualification; no build or runtime evidence is claimed for this change. |
| S023 | Thread-local storage: implemented, verified on macOS arm64 (`tests/std/tls_static_init_and_exit_order.mt`) | Static `std.sync.tls.LocalKey<T>` aggregate declarations with lazy native-key creation, plus owned dynamic keys, per-thread initialization and reverse first-installation destruction at thread exit and hosted main exit | Run static initializer and thread/main exit destructor cases, then qualify destructor iteration/order and target profiles; no build or runtime evidence is claimed for this change. |
| A001 | Initial C ABIs/callbacks/varargs: implemented mechanisms | Darwin ARM64/Linux x86-64 adapters, physical-entry cursor capture, independent copies, promoted/aggregate reads and cleanup | Frozen-input C round trips/cursor/cleanup qualification on Linux. Cursor transfers outside the represented initial contract are explicitly diagnosed; no new target ABI is implied. |
| A002 | Layout/alignment: implemented initial combinations | Combined C/integer tags, transparent single-variant enums/products, unions and packed/aligned storage; exact transparent scalar ABI/callback/vararg forwarding has focused C evidence | Frozen-input sanitizer and Linux calling/layout/validity qualification; additional profile/operation closure remains I13. |
| A003 | Symbols/linkage: implemented mechanisms | Function/static imports/exports/library selection, stable storage identities, full-width required initializers and relocations | Frozen-input symbol/link/lifetime/initialization and freestanding qualification. |
| A004 | Compatible unwind: implemented initial boundary | Ordinary-C abort and compatible C-unwind cleanup probes | Current direct/indirect ABI rejection and cross-language cleanup/escape cases on the target. |
| A005 | Assembly: implemented initial mechanisms | Inline/global/naked variants, typed full-width/generic constants, function/static symbols, operands/registers/clobbers/options and compiler-owned verification | Frozen-input execution, unwind/evaluation and rejection qualification; naked entries must remain physical non-inlined ABI entries. |
| A006 | SIMD/target operations: implemented initial mechanisms | Native vector identity/layout/ABI, initial operation tables, explicit target facts, recognized feature contracts and guarded dispatch | Frozen-input sanitizer and Linux execution; distinguish unavailable optional instructions from baseline execution. Complete per-operation/profile closure remains I13. |
| A007 | Volatile access: implemented | Explicit volatile loads/stores and raw-pointer cases | Preserve accesses under optimization without treating volatile as synchronization. |
| A008 | Freestanding core: implemented mechanisms and fixture selection | No-entry abort, assembly/SIMD objects and undefined-symbol checks; Linux selection omits the hosted runtime | Frozen-input Linux execution and no accidental hosted dependencies for the delivered core boundary. |

#### Focused integration history before qualification

Evidence locations are `build/i06-focused/memory-layout/evidence.json` for the
earlier native/sanitized batch and `build/i06-focused/pin-layout/` for the newer
native layout/pin/union cases and localized follow-ups. The latter's selected
35-translation-unit static analysis passed, but the newer batch has no completed
I06 sanitizer, reproducibility or Linux qualification. Receipts retain their
actual compiler hashes; no aggregate current-I06 approval is asserted.

The shared-interface plan is recorded in `docs/compiler-architecture.md`.
The subsequent representation-completion batch adds the combined/transparent
cases above, raw slice metadata preservation and zero-size owned iteration.
`build/i06-focused/representation-closure/` retains six source/profile positives,
three source rejections, 22 C-interoperability/profile round trips and three
foreign-ABI rejections on its Debug compiler snapshot. This is focused native
evidence, not a new whole-milestone or sanitizer/target qualification.
The 35-unit static-analysis result predates this representation change; the
fresh final static, sanitizer, reproducibility and target gates were still required.

The existing ledger groups the known source gaps into numeric composition and
policy, cell/borrow guards, remaining pin conditions, representation combinations,
static/linkage storage, variadic definitions, assembly, and SIMD/target features.
The representation and numeric implementation workstreams now have focused
completion evidence. Numeric integration retained 74 positive profiles, 39
rejections and 16 arithmetic/override cases. Parent review corrected additional
wide-count, usize-index and zero-array-alignment gaps directly; the original
agent delta, parent fixes and evidence are retained under the session's
`files/i06-parallel/results/numeric/`. Its temporary worktree was removed only
after integration and checks. The ownership and FFI lanes have also been merged
and checked, including their cross-lane native-cleanup, proof-context and static
initialization seams. Their raw receipts retain 94 passing positive profiles and
51 rejections; two corrected source fixtures and one owning diagnostic are covered
by explicit passing follow-ups, without relabeling the raw failed batch. Eight
arithmetic/trap cases, IR boundaries and 44 native C/profile round trips plus three
ABI rejections passed. Source changes and exact scopes are retained in the
session's `files/i06-parallel/results/ffi-ownership-integrated-evidence.json`.
The cancelled assembly/SIMD worker's complete source was recovered and integrated
by the parent without restarting it. Parent fixes connected static symbols and
full-width/generic required constants, kept naked entries separate from static
frames and variadic cursors, and corrected wide-vector variadic overflow reads.
A release-only regression exposed LLVM inlining a naked physical entry; those
entries now carry an explicit no-inline contract. Scoped native positives,
32 rejections, IR boundaries and 20 C/profile round trips plus an assembler
rejection passed, with exact follow-ups retained for the original failed receipt.
The integrated Linux x86-64 cross-emission batch passed 91 cases; this is not
Linux execution. Evidence is under `build/i06-focused/target-integration/`.
Final parent review also found mismatched register ABIs across guarded vector
calls. Storage-only bridges now cover direct/indirect calls, C calls and reverse
transitions into baseline generic code. Linux AVX2 availability was confirmed;
four affected source/profile cases and two independent C/profile follow-ups
passed. The retained pre-fix compiler fails the independent C case. Its C
translation unit uses an explicit AVX ABI profile; a per-function codegen
attribute alone did not establish that ABI in the original fixture. Raw failed
diagnostic receipts remain unchanged. The final affected native batch passed
38 positive profiles, 20 C/profile round trips, one assembler rejection and IR
boundaries. These are scoped integration checks, not whole-I06 qualification.
The first frozen Debug gate completed static analysis and passed 14 of 16 CTest
suites, but exposed a unit-result materialization crash in the new call bridge.
The freeze was reopened: native Unit/Never calls must retain a real unit value,
not a null LLVM value, for subsequent storage/cleanup lowering. The original
failed receipts remain retained; only the affected cases and translation unit
need repeating before qualification resumes.
The independent constructed cleanup-frame fixture separately lacked the typed
destructor descriptors now required to distinguish pinned receivers. Its
ordinary runtime callbacks now have matching compiler-owned descriptors rather
than weakening the backend's validated-program contract.
The six affected source profiles, constructed cleanup-frame test and both
changed translation units' static analysis now pass. Unchanged passing groups
are retained with the conditional-unit-result dependency rationale; the failed
original gate is not relabeled as passing.
All four worker deltas and parent fixes are retained under the session's
`files/i06-parallel/results/`; worktree cleanup is recorded separately.
Linux fixture selection now explicitly uses x86-64 source templates rather than
the compiler host's architecture and includes both standalone freestanding cases.
Acceptance-fixture integration and documentation synchronization preceded freezing;
these focused batches alone did not establish whole-I06 qualification.
The source-freeze gate depends on these tasks; qualification depends on that gate,
and milestone completion depends on qualification. Reopen affected gates and
invalidate dependent evidence when a later source change is necessary.

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

Before the `c485aa1` re-review reopened I06, it was recorded complete on 2026-10-29
for the native macOS ARM64 compiler host and Linux x86-64 target execution. These
receipts are retained history, not current approval.
`build/i06-qualification.json` binds the qualified source,
tools, sysroots, artifacts, raw receipts and final documentation-only status delta.
The historical `build/i05-qualification.json` remains unchanged.

- Debug: all 247 source cases/494 profiles covered through the explicit continuation
  of the original gate; fourteen originally passing suites were retained, three
  repaired cases passed both profiles and the constructed cleanup fixture passed.
  The original failed receipts remain unchanged.
- Static analysis: 127 selected translation units, with both changed units refreshed.
  Release passed 16/16 CTest suites; ASan/UBSan passed 17/17, including startup and
  intentional detector probes. All three configurations rebuilt byte-identically.
- Linux: Debug and Release each passed 620 source/profile cases and six cleanup
  cases, plus object smoke execution. Both storage and assembly/SIMD freestanding
  probes had no undefined symbols and linked without the Mettle runtime.
- Selected emitted-code TSan/race/model checks passed; this is not a complete
  memory-model proof. No Linux compiler-host, release-platform, runtime-parity or
  I13 complete stable-operation/profile qualification is claimed.

All four owned implementation worktrees were removed after retention and checked
integration. The dedicated Linux VM was stopped and its stopped state verified.

I07 implements core/alloc operation families against the pinned inventory:
unique/local-shared/weak owners, allocator identity/failure, optional/outcome
operations, UTF-8, slices/collections, iteration, hashing, formatting/parsing and
type identity/downcast. Native atomic-shared ownership lands here as needed,
but its concurrent safety closes in I10. Test allocation failure, partial
initialization, invalidation and panic, not only happy-path values.
Partial I07 work adds `len()` on borrowed slices using existing element-count
metadata; on-demand mounting of native `library/{core,alloc,std}` sources
(`--library-dir`, catalog-supplied for in-memory builds, layering and
freestanding rules, user-root shadowing); text literals typed
`read core.text.Text from static` (static private constant plus length
metadata); and a first `library/core` (`text`: UTF-8 validation, checked
slicing, chars/bytes iteration, equality, ordering, find/trim/split/lines/
char_indices; `option`/`outcome` operations as inherent extensions on `T?` and
`(T throws E)`; `cmp` (Ordering, PartialEq/Eq/PartialOrd/Ord, min/max/clamp,
Reverse; ints, bool, char, Text, tuples, slices, options); `iter` (Iterator with
lazy adapters, BidirectionalIterator, OwnedIterable, library ranges, sources, sum/
product/min/max); `hash` (Hash/Hasher, FNV-1a, SipHash-1-3/2-4 verified against
reference vectors); `fmt` (Write sink, Formatter with fill/align/width/precision/
sign/alternate/zero, Display/Debug/radix traits for scalars and Text, fixed-buffer
and counting sinks, writer-failure propagation); `num` (integer parsing with radix
and distinct error kinds); `slice` (get/first/last/contains/swap/reverse/fill/
copy_from_slice/split_at(_mut)/binary_search/heapsort/window/chunk/iter/iter_mut);
`any` (TypeId from the `core.intrinsics.type_id` compiler intrinsic, is,
downcast_ref/mut); `ops` operator interfaces. Tests: `tests/library/*.mt` through
`library.core` (`tests/modules.py ... library`).
Prelude: when core is mounted and not shadowed by a user `module core`, the
loader binds `Text`, the iterator interfaces, `PartialEq/Eq/PartialOrd/Ord/Ordering`,
`panic`, `assert` and (when alloc is available) `String` at lowest priority, so
declarations, explicit imports and globs shadow them; libraries are mounted
lazily when a prelude name or a core inherent method name appears. There is no
opt-out attribute (unspecified). `const` items reuse the static evaluator
(immutable statics; usable in expressions, array lengths, integer/bool
patterns and associated `T.NAME` forms; inherent `extend S { const }` is
implemented and verified on macOS arm64 by the inherent-associated-constant
run and fail cases). Panic:
`core.panic.{panic, assert, unreachable}` lower through
`core.intrinsics.panic_message`, which is `llvm.trap` freestanding and the
runtime hook `mettle_rt_panic_message` when hosted (stderr `panicked: msg`,
exit status 101); core `unwrap`/`expect`/slice-split failures use it. Builtin
arithmetic/index traps still abort. Core has no process-exit API; hosted
`std.process.exit` is implemented in `library/std/process.mt` and delegates to
the hosted system boundary; exit status and prior output are verified on macOS
arm64 by `tests/std/process_exit.mt`.
`core.hint.black_box(value)` is a compiler intrinsic identity: the value
round-trips through memory an empty `asm sideeffect` with a memory clobber may
touch, so optimization cannot fold or delete it.
Built-in ranges: `a..b`/`a..=b` map to the library `core.iter.range` /
`range_inclusive` values (`Range<T>`/`RangeInclusive<T>`, Iterators and
bidirectional) wherever the range is not the direct source of a `for`, when
`core` is mounted; the checker rewrites the node to that call (calls chained on
`)` with an Iterator method name mount `core`). A range that is the source of a
`for` keeps the structural counted-loop form, and without `core` a range stays
structural. An iterator held in a local is consumed by `for x in it`. The
bounded-range behavior was previously verified by `tests/library/range_value.mt`.
Open-ended range values (`RangeFrom<T>`, `RangeTo<T>`,
`RangeToInclusive<T>`, and `RangeFull`) and `RangeFrom` iteration are
implemented and verified on macOS arm64 (Release) by
`tests/library/range_value.mt`, `open-ended-range-values` and
`end-bounded-range-is-not-an-iterator`. In a `for` head, `{` at the head's
parenthesis depth ends an open range, so `for v in 2.. { ... }` iterates. `RangeFrom` stops after yielding the integer type's
maximum or Unicode scalar maximum by using checked stepping. The `Step`
implementations cover primitive integers and Unicode scalar `char`, including
skipping the surrogate interval.
Core slice `sort_unstable`, `sort_unstable_by` and `sort_unstable_by_key` are an
allocation-free introsort (median-of-three quicksort, insertion sort for short
ranges, heapsort fallback; fixed pending-range stack). Allocation-backed
slice and `List` `sort`/`sort_by`/`sort_by_key` use a stable index merge sort,
two index buffers from the global allocator and only swap initialized elements after all
comparisons; verified by `tests/alloc/stable_sort.mt` and
`tests/library/range_value.mt`. Slice stable methods are provided by
`alloc.vec`, which must be mounted. Slice `Iterable`/`MutableIterable`
implementations are implemented and verified on macOS arm64
(`slice_iterable`); the inherent slice `iter()`/`iter_mut()` methods remain for
resolution precedence. Composite Debug implementations and the
generic mutable-formatter loan correction are already present, with nested
collection coverage described below; they have not been reverified by this
lane. Unicode `char.is_whitespace` and Unicode-aware `Text.trim*` are
implemented with compact scalar ranges and verified on macOS arm64 by
`tests/library/unicode_whitespace.mt`. Unicode
alphabetic/numeric properties and full character/text case mapping remain
unimplemented: the frozen operation inventory supplies signatures, but
Unicode-16 generated property/case tables and multi-scalar mapping machinery
are not present in core. No per-codepoint fallback tables or alternate Unicode
version were introduced. Mounting compiles the whole of `core`, which costs
seconds in Debug builds.
Also: text literals are usable as `static` initializers and
byte/raw literals (`b"..."` is `read [u8; N] from static`; `r"..."`, `r#"..."#`,
`br"..."`); range slicing `read a[i..j]`, `a[i..]`, `a[..j]`, `a[..]`, `a[i..=j]`
on arrays and slices (bounds-checked, `mut` for mutable subslices) and, through
the `core.ops.IndexRange`/`IndexRangeMut` protocol, on Text (panics on
out-of-range or non-char-boundary) and user types; `core.slice.from_raw_parts`
and `from_raw_parts_mut`, `core.text.from_utf8_unchecked[_mut]` (unsafe; the
result region is the caller's choice); generic parameters determined by an
`I: Iterator<Item = T>` bound; closures passed to generic callable parameters and
explicit generic constructors. `core.char.from_u32` returns an optional scalar
and is verified on macOS arm64 (`char_from_u32`, `char-from-u32-is-checked`); direct `u32 as char` remains
invalid. `f"..."` interpolation and `const` items are implemented (see `fstring-*` and `const-*` source cases). There is no
`core.process.exit`; hosted `std.process.exit` is verified as above. These changes do not constitute I07 completion or
qualification.
The first native `library/alloc` now provides `alloc.alloc` (checked
`Layout`, `Allocator` contract with `allocate/deallocate/grow/shrink` returning
`AllocError`, stateless `Global`, `handle_alloc_error` = abort policy), `Box`,
`Rc`/`Weak`, `List`, `String`, `Map`/`Set`, `SortedMap`/`SortedSet`,
`VecDeque`, `BinaryHeap` and `LinkedList`, each generic over an allocator
(`A: Allocator = Global`) that is stored in the collection and used for every
block it owns. Hosted builds link the `mettle_rt_alloc/dealloc/realloc` hooks in
`runtime/alloc.cpp`; freestanding builds supply those symbols. Tests live in
`tests/alloc/` (`library.alloc`): happy paths, large growth, hash collisions,
a failing allocator, counted drops, a trap on a non-boundary `String.truncate`,
a borrow-invalidation rejection and a structured parser + `Map<String,
List<i64>>` workload built without std. Map `entry` operations are verified
by `tests/alloc/map_entry.mt` on macOS; `Entry.and_modify` passes
`get_mut()` to its callback. Access parameters of a callable bound without a
declared source region are call-local in the indirect-call summary, so they
cannot be reported as retained
(`tests/source/run/generic-callable-bound-mut-view-is-call-local.mt`).
Region-declared callable bounds now instantiate their region contracts for
indirect calls, so argument regions and result sources remain tied to the
declared callable contract. Implemented, unverified (not yet built).
`tests/alloc/map_entry_blocks_map_use.mt` rejects map use while an entry holds
its loan.
`SortedMap`/`SortedSet` are a node B-tree (minimum degree 6, nodes from the
map's allocator, parent links, split on the way down and borrow/merge on
removal), verified on macOS by `tests/alloc/btree_stress.mt` and
`btree_heap.mt`. Generic specialization no longer treats a `read K`/`mut K`
parameter's own borrow as a result source when `K` merely appears in the
result; only views carried by the instantiated argument flow
(`generic-read-argument-*` source fixtures). Iteration is in key order (borrowing, values-only
mutable, consuming and half-open `range`); the old contiguous `as_entries()`
and the position-based `range` result are replaced by ordered iterators.
Known gaps: the `SortedMap` entry API and BTree-specific `try_` allocation
tests are implemented and verified on macOS arm64 (`sorted_entry`,
`btree_alloc_failure`). Panics are runtime traps
without unwinding or catch, so cleanup cannot continue after a key/value
destructor traps; recoverable post-trap cleanup is not a supported contract.
Borrowed iteration is implemented through the core interfaces: see the integration
note below; `Box<[T]>`/unsized owners, `Arc`, `Pin` and
the native `heap T`/`local shared T`/`weak` syntax (still a feature error) are
not mapped; a `take` argument always
moves even a `Copy` binding, so generic calls pass `i + 0` or a fresh `let`.
Panics are runtime traps (no unwinding catch), so panic-safety is tested for
drop order only. Alloc/core integration (lane allocint): `library/alloc/support.mt` is gone and
`library/alloc` depends only on `core`. New `core.clone.Clone` (integers,
`bool`, `char`, `Unit`, `Ordering`, pairs, `T?`); `core.iter.Iterable`/
`MutableIterable` are region-family interfaces (`type Iter<region r>`,
`fn iter<region r>(receiver self: read Self from r)`). `List` implements
`OwnedIterable` (`IntoIter` is double-ended), `Iterable`/`MutableIterable`
(`for x in read v`, `for x in mut v`, `for x in take v`), `Deref`/`DerefMut` to
`[T]`, `IndexRange`/`IndexRangeMut`, `Clone`, `PartialEq/Eq/PartialOrd/Ord` and
`Hash`. Scalar `Index<usize>` on a `List` of region-bounded views preserves the
element view's region separately from the temporary list borrow; focused
acceptance and escaping-region regressions are added, but this fix is
implemented and unverified pending lane integration. `String` implements
`fmt.Write` (`fmt.Error`), `Deref` to `Text`,
`IndexRange` (-> `Text`), `Display`, `Debug`, `Hash` (equal to `Text`'s hash),
`Ord`. `Box` and `Rc` are transparent over `Deref`, comparison, `Hash`,
`Display`/`Debug` (`Box` also `DerefMut`, `Clone`). `Map`/`Set`,
`SortedMap`/`SortedSet`, `BinaryHeap`, `VecDeque` and `LinkedList` implement
`Iterable` (maps yield stored buckets/entries; map `MutableIterable` is withheld
because it would expose keys). `Map` hashes with `core.hash` (SipHash-1-3).
Compiler changes: blanket-extension coherence now rules out a concrete subject
when no implementation of the required interface could apply (so
`extend<I: Iterator> I implements OwnedIterable` coexists with concrete
implementation declarations); calling a body-less interface method through the interface name is a
structured type error (use method syntax or `T.(I).m`); the region
solver compares raw pointers structurally and treats cycles through recursive
nominal types/pointers coinductively. Standard-interface surface (lane allocfmt): `List`, `VecDeque`, `LinkedList`,
`BinaryHeap`, `Map`/`Set` and `SortedMap`/`SortedSet` implement `Debug`
with Rust-style output (`[1, 2]`, `{k: v}`, `{a, b}`) and the pretty
`alternate` form (`Formatter` carries an indent level and indents lazily at line
starts; helpers `debug_open/debug_item_start/debug_item_end/debug_close`; `[T]`
has `Debug`). All but `BinaryHeap` implement `Clone` (needing `Clone` elements
and allocator) and `PartialEq/Eq`; maps/sets compare order-independently,
ordered ones (`VecDeque`, `LinkedList`, `SortedMap`, `SortedSet`) add
`PartialOrd/Ord` (lexicographic) and `Hash` (length-prefixed); `Map`/`Set`
deliberately have no `Hash`. `MutableIterable` covers `VecDeque`,
`LinkedList` and, over values only, `Map`/`SortedMap` (`for v in mut m`,
`values_mut()`); keys are never mutable. `core.iter` gains `FromItems`,
`ExtendItems` and a free `collect` (`let v: List<i32> = collect(it)`), implemented for
every collection (maps take `(K, V)` items); they take any `OwnedIterable` (its
`IntoIter` is declared `Iterator<Item = Self.Item>`), and `Iterator.collect` is a
provided method (bound elaboration is coinductive over bounds already in progress). `Unit` gained comparison
implementations. `Debug` now also covers `T?`, outcomes, tuples (arity 1-12) and `[T; N]`;
maps expose borrowed `keys()`/`values()`. Deliberate omissions: `Display` for
collections and `BinaryHeap` `PartialEq`/`MutableIterable` (Rust has none).
Region-lane I07 work: a user collection (`ptr`/`len`/`cap`) can implement
`Iterable`/`MutableIterable` with a region-family associated iterator
(`type Iter<region r> = ListIter<T, region r>`), so `for x in v` and
`for x in mut v` yield `read T from v`/`mut T from v` and reject mutation or
escape while the loop or an item is live. Optional/mutable view results
(`(read V from self)?`) re-borrow matched views, closures may be passed to generic
function-pointer parameters, and raw-pointer dereference views are treated as
`static`-backed. Family bounds may mention the family region
(`type Iter<region r>: Iterator<Item = read Self.Item from r>`), so generic
`for x in c` over `C: Iterable<Item = i32>` and `for x in mut c` over
`MutableIterable` type-check and region-check; mutation during iteration and item
escape are rejected when the generic function is instantiated, like other
ownership diagnostics. A result whose `from` region is carried inside a borrowed
parameter (not the parameter's own borrow) depends only on the shared loans stored
there, so `var it = c.iter(); it.next()` returns `(read T from c)?`. For exclusive
contents (`var it = c.iter_mut(); it.next()` returning `(mut T from c)?`) the item
stays tied to the iterator borrow while the iterator is live, so a second `next`
or a write to `c` conflicts, but ending the local iterator's storage does not
(`Loan::borrowed`: parents that only keep referents unavailable). A call that writes through an erased
contract no longer retains the caller's own borrow of the written argument, so
generic `self.x.fmt(mut f)` can be followed by `f.write_str`. Gaps: `match`
through a `mut` view still needs `match mut` (the grammar defines no default
binding modes).
Run a structured parser and collection workload without mandatory Rust, OS or
executor dependencies in core/alloc. Start applicable P02-P06/P08/P11 comparisons.

I08 adds files/paths/OS strings, synchronous networking, processes/environment,
time and hosted panic handling. Demonstrate partial I/O, non-Unicode names,
timeouts, child failure and raw OS-error round trips. Core/alloc must still
build without these hosted services. Record the initial profile's actual
behavior; other profile implementations close in I13.

Stored exclusive views. A result borrowed through a `mut` view stored in a
struct (`Cursor<region r>{ v: mut List<T> from r }`) now keeps a loan on the
view's referent even when the callee derives it through a raw-pointer deref
(summary places are truncated at the last view deref, and result paths with no
tracked targets are backed by their `from` parameters). A borrow of a place
that holds a stored `mut` view also freezes that view's referent (`Loan::frozen`),
so reborrows such as `let b = mut a.v` block later use of `a.v`. The library
`Iterable`/`MutableIterable` interfaces declare bounded `Iter<region r>` families,
so generic code can call `.iter().next()`.
A result path that mixes safe and raw-pointer-derived views keeps the safe
targets and adds the `from`-parameter backing. Adversarial closure-capture probes
(stored, nested, view-returning and escaping closures over `mut` views) found no
hole; generic `F: mut fn(): mut T` bounds still require an unambiguous `from`
contract.

I08 status (initial macOS ARM64 hosted profile): `library/std` provides `io`
(Reader/Writer with visible partial transfers, `write_all`/`read_exact`/
`read_to_end`, buffered reader/writer, an `io.Error` that round-trips the raw
errno), `ffi` (`OsStr`/`OsString`), `path`, `fs`, `process`, `env`, `time`,
`net` (synchronous IPv4/IPv6 TCP and UDP, socket timeouts, timed TCP connects
and DNS; the IPv6/connect-timeout/DNS additions are implemented and verified on macOS
arm64) and `panic` (hook around the runtime's exit-101 path). The
POSIX layer is the libc calls declared in
`library/std/sys.mt` plus the thin shims in `runtime/sys.cpp`. `tests/std` is
run as `library.std` and holds the file-processing CLI (`cli_wordcount`), the
loopback socket programs (`net_loopback`, `net_process`) and the child-process
round trip (`process_roundtrip`), with partial I/O, non-UTF-8 names, timeouts,
child failure/signals and raw OS-error cases. Linux x86-64 status: with
`python3 tools/test_linux_target.py --libraries`, the 12 core, 19 alloc and 14
std programs (stdin/args/exit-code/stderr/file expectations as in `tests/std.py`)
were cross-emitted, linked with the cross-built `runtime/{panic,alloc,sys}.cpp`
and executed under the Linux kernel (Debug compiler, emulated); all passed with
no portability defect in `runtime/sys.cpp`. `fs_nonunicode` now prints a marker
when the non-UTF-8 name really lives on disk (asserted on Linux) and accepts
EILSEQ 84 as well as 92. The same Debug-compiler run passed 740 source/profile
cases and the six cleanup cases. Official evidence (`build/linux-target/
foundation-evidence.json`) for both configurations is pending a fresh
`tools/build.py` receipt, which the runner requires.
S028 status: implemented and verified on macOS arm64 (Release `library.std`):
`std.panic.catch_panic` recovers source-level panics on the current thread with
an owned code/message payload after cleanup, including nested catches and
replacement cleanup (`tests/std/panic_catch.mt`); hook take/reset and
abort-on-hook-panic are covered by `panic_catch.mt` and `panic_hook_abort.mt`.
Other profiles and targets remain unqualified. Freestanding/abort execution does not provide recovery.
Spawned-thread panics continue to be caught and reported by `join()`.
Remaining I08 gaps: macOS file systems may reject non-UTF-8 names (EILSEQ),
which the tests check but cannot exercise on-disk there; hosted names avoid
reserved words
(`read_some`, `write_some`, `read_bytes`, `var_os`, `set_*` open options).
`ReadDir` implements `Iterator` (`next_entry` remains).

### 8.4. Builds, concurrency and async: I09-I11

**L054 status (const evaluation): implemented and verified on macOS ARM64.** The `compiler/consteval` evaluator and `const fn` are wired into constants, array lengths, constant generic arguments and statics. Evidence: `tests/source/{run,fail}/const-eval-*.mt` (Debug and Release, including the recursion-depth limit, which evaluates on a dedicated large stack) and `compiler.consteval-target` (`tests/consteval/target_width.cpp`); the driver admits no 32-bit target, so target-width evidence is that checker-level unit test. Gap addressed, verified on macOS arm64: a mutable unsuffixed integer local in a `const fn` (`var i = 0`) stays open instead of being fixed to `i32`; assignment of a typed value or a use against a scalar expectation fixes its type (`tests/source/run/const-eval-open-integer-local.mt`). An immutable `let` or a copy into another binding still defaults to `i32`.

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

I09 T002/T003 baseline: implemented and verified on macOS arm64 (Release and Debug).
`[build] script` programs run on the host with declared `mettle:` outputs
(generated modules, features, link libraries) and a `reproducible` input
contract, otherwise rerun conservatively (`compiler/driver/build_script.cpp`);
`mettle build` reuses executables/objects through a content-addressed,
deduplicated, byte/age-bounded store keyed by token-level source inputs and
build options (`compiler/packages/store.cpp`, `compiler/driver/cache.cpp`),
with `mettle clean`. `[build-dependencies]` and host dependency compilation
are verified by the same suite.

I09 cache lease work, the per-module lexed-token cache and the multi-package
extension demonstration are implemented, unverified (not yet built). A build
holds an RAII lease on its whole-program key through materialization,
publication and pruning; `compiler/packages/store.cpp` excludes leased entries
from age/byte eviction and refuses `clean` while a lease is live. The driver
stores validated token records keyed by compiler identity, token content and
exact source bytes; unchanged dependency modules can reuse lexing after a root
edit, while parsing and all later compiler phases still rerun. The new
`tests/packages/multi-package-extension` fixture combines a generated module,
a procedural extension dependency and a regular dependency. The cache remains
whole-program for compiled artifacts: per-dependency-package
analysis/object reuse and reuse of parsed ASTs are not implemented, so editing
the root still recompiles the combined program. Tests: `incremental_reuse`,
`edit_invalidation`,
`module_token_cache_reuse`, `cache_dedup_and_bound`,
`cache_corruption_and_clean`, `build_script` and
`build_script_untracked_inputs` cases of `tests/packages.py` remain prior
verified evidence for the original cache; the new token-cache case and
multi-package demonstration are registered but not run. The lease changes
remain unbuilt. Open: parsed-AST/name/type/ownership/instantiation dependency
separation,
retained-byte/compile-time measurement (performance.md 5.1.1) and Linux
evidence.

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
Add P09 and complete concurrent P08 coverage.

I11 implements pinned future state machines, async callable/interface contracts,
poll/wake integration and a separately selectable executor. Establish direct
borrowed await and owned tasks before borrowed-task execution epochs. The scope
must retain soundness for forgotten handles/parents, repeated wakes, worker panic,
parent destruction and an uncooperative child poll. Check actual cleanup versus
cancellation requests; no hidden mandatory boxing or default executor in core.
Exercise an async network service and P10 without weaker lifetime guarantees.

I11 library sub-batch, implemented and verified on macOS arm64 by the std
programs (Release ctest 23/23): `alloc.future`
adds explicitly heap-erased `Static` futures with a fixed-address payload and
typed poll/drop dispatch. The local `std.task.Executor` retains task
registrations independently of handles and wakes; owned `spawn` requires
`Transferable + Static`, returns a result-bearing `JoinHandle`, and drop/abort
cancels. Poll and destruction panic codes are reported through the handle.
Close and completion serialize with queue insertion; foreign wakers own only
task metadata. Reentrant cancellation defers destruction until poll returns;
reentrant joins on an active executor are rejected. The synchronous local
`task.scope` drives ready children and cancels suspended children before exit,
including on parent unwind; its private executor retains children even when
their handles are forgotten. It does not provide an asynchronous scope whose
children remain suspended across parent polls. Completed task metadata stays
registered until executor destruction. Tests added or updated:
`tests/std/{erased_future,direct_borrowed_future,neg_erased_future_borrow,
neg_spawn_borrowed_future,neg_task_scope_body_local,task_owned,
task_panic_isolation,task_scope,task_scope_async,async_executor}.mt`. Raw-waker
construction now requires thread-safe callbacks and `Waker` is Transferable
and Shareable. None has been built or run at this revision; this is not I11
completion or sanitizer evidence.

The async-I/O sub-batch: `std.task` parks the optional executor in a hosted
reactor, provides readiness and timer futures, and `std.net` exposes
nonblocking async TCP wrappers. `runtime/sys.cpp` uses kqueue on macOS and a
POSIX poll fallback elsewhere. `tests/std/async_net_echo.mt` covers concurrent
echo clients, timer sleep, and dropping a suspended accept. It passes in the
Release `library.std` CTest and as an emitted program under ASan and TSan on
macOS arm64. Async retry loops classify `EAGAIN` from the raw OS error (the
blocking-socket timeout mapping does not apply), and unsized slice-view
parameters are captured as views by async bodies.

The async arrow-closure, `try await`, and async-interface changes below are
implemented and verified by the Release CTest on macOS arm64. Async interface declarations now preserve their
async modifier and publish a per-method associated future family constrained by
its output (including typed error outcomes) and declared method regions.
Implementations bind the family to their concrete opaque coroutine future,
allowing concrete and generic-bound calls to await it. Erased dispatch reports a
feature diagnostic until an explicit future-storage erasure contract exists.
Remaining I11 work includes a full asynchronous borrowed-scope
interface using the poll epochs in memory-and-concurrency section 6, including
its independent soundness/race review and sanitizer qualification. A library
`AsyncScope` attempt was withdrawn: it accepted a child future borrowing a
local shorter than the scope (the `Within<region s>` bound on a method of a
region-parameterized type was not enforced). Borrowed
heap-erased futures require region-carrying erasure.
Compiler erasure admits the pinned `Future.poll` receiver when `Output` is
fixed in `any Future<Output = T>`; the witness dispatches polling to the concrete
implementation; type checking accepts it, but IR verification/lowering of the
pinned erased call is incomplete, so `tests/std/erased_future_dispatch.mt`
currently fails (open). Owned heap storage
remains the explicit `alloc.future.Erased<T>` wrapper. `Box<any Future<Output =
T>>` is still unsupported: the general unsized-owner mapping is an I07 gap.
Erased async-interface dispatch remains unsupported until an explicit
future-storage contract exists (`async-interface-erased-dispatch.mt`).
P10 has only a backlog entry, not a specified benchmark source; an async
network service, measurement protocol and equivalent comparator remain open.

I11 status (partial; the prior core coroutine/executor paths were built and run
on macOS arm64 Release; the async-I/O addition above is verified there):
`core.future` has
`Future`/`Poll`/`Context`/`Waker` (vtable protocol, no allocation) and the
inline coroutine future `Coroutine<T, C>`; `std.task` is the optional executor
(`block_on`, `Executor` with spawn/run, `yield_now`). Async bodies are
coroutines: the parser (`compiler/syntax/parser/async.cpp`) turns an
`async fn` (free function or method), `async { .. }` block or
`async fn(..) { .. }` closure into `core.future.coroutine(take fn(): T { body })`
(`throwing_coroutine` when the body throws) behind an opaque
`some Future<Output = T>` result, and `await e` into a poll loop over a
temporary that suspends through `core.intrinsics.coroutine_suspend` while
`core.future.poll_await` returns `none`. The body is checked, lowered and
ownership-analyzed as an ordinary take closure, so `await` composes with every
statement and expression form. Suspension is the IR terminator
`Exit::Suspend` with a resume edge that the initialization, liveness, origin
and loan analyses treat as an ordinary edge. `core.future.CoroutineState<T, C>`
is a compiler aggregate whose layout is the body's persistent backend frame
(`TypeStore::coroutineLayout`); `Coroutine` is `!Unpin` (`PhantomPinned`), so
loans of state across a suspension are self-borrows of pinned storage. The
LLVM backend (`backend/llvm/lower.cpp`, `cleanup.cpp`) keeps a resume state,
spills values live across suspension into the frame, keeps drop flags across
polls, destroys only initialized places on cancellation and panics on a poll
after completion or panic. A coroutine state is Transferable/Shareable when
its output, captures and interior are; the interior is scope-based like the
original Rust generators (bindings in scope at a suspension and operands
evaluated before it), so it may reject a value whose scope, but not its
liveness, spans an await. Static requires the output and captures.

Verified on macOS arm64 Release (all 23 CTest suites): `await` in loops,
nested blocks, any branch, lazy operands, loop values and early
`return`/`throw`, borrows of locals across an await, typed failure fed by
await and exactly-once drops of unfinished futures
(`tests/source/run/async-await-anywhere.mt` with the existing `async-*` run
cases); executor and spawn use (`tests/std/async_executor.mt`,
`async_spawn.mt`); and rejection of an `Rc` held across an await and of a
borrowed capture by spawn (`neg_async_rc_across_await.mt`,
`neg_async_borrow_static.mt`). In the `build/macos-arm64/Debug-sanitized`
CTest 22 of 24 tests passed; `packages.resolution` and `probe.broken-pipe`
exceeded their timeouts because the sanitized compiler is slow (43 s for the
probe's std program against a 30 s bound, as at I06) and passed when rerun
unmodified without the timeout. Every async run fixture and the
std async programs above also ran clean as ASan/UBSan-instrumented emitted
programs, Debug and Release profiles (a throwaway harness, not a repository
gate). The CPS combinators (`Lazy`, `Then`, `Defer`, `Either`, `Repeat`)
and their feature-fail fixtures are removed.

The recursive async future-cycle diagnostic is implemented and verified on
macOS arm64: direct and mutual recursive async call cycles are diagnosed in the
type phase at the call span (`async-recursive-future-{direct,mutual}.mt`).
Async interface default bodies still require an explicit result type; an
inferred-output attempt was withdrawn (its default future failed the Sized
obligation). Explicit erased-future storage and erased async-interface dispatch
remain unsupported.
Coroutine-state DWARF metadata (a `state` discriminator with per-state
variants) and its LLDB summary are implemented and verified by `debug_info`
on macOS arm64; the LLDB summary has not been re-run interactively.
An async future borrows from every borrowed parameter, and an owning closure
or async body captures a borrowed non-Copy parameter as a view
(`borrowed-parameter-captures-keep-views`,
`async-future-outlives-borrowed-argument`).
Region-carrying erased futures, asynchronous borrowed-task scopes and P10
remain open; Linux poll-fallback qualification of async I/O is open. Erased async dispatch is explicitly rejected pending a
future-storage erasure contract. Linux and Windows targets and TSan of executor
code are not run for the coroutine path.

#### I11 coroutine replacement inventory

Revision: uncommitted lane changes on `c81bc6d`; scope as stated per row.

| Requirement | State and owning files | Remaining work and required fixtures |
| --- | --- | --- |
| Preserve async source; type future and await | Implemented and verified on macOS arm64, including arrow async closures and `try await`: `syntax/parser/closures.cpp`, `syntax/parser/async.cpp`, `semantics/sums.cpp`, `semantics/regions.cpp`, `lowering/sums.cpp`. | `async-arrow-closure.mt`, `async-try-await.mt`. |
| Async interface futures and dispatch | Bodyless async methods publish region- and output-constrained associated future families; implementations bind concrete opaque coroutine futures; concrete and generic-bound calls use the family. Verified on macOS arm64. Async default bodies require an explicit result type. | `async-interface-method.mt`, `async-interface-erased-dispatch.mt`; inferred async default outputs remain open. Explicit erased-future storage and erased async-interface dispatch remain unsupported. |
| Erased Future polling and storage | Pinned poll dispatch through `any Future<Output = T>` and the `alloc.future.Erased<T>` static heap wrapper are implemented; compiler dispatch change is unverified (not yet built). The wrapper owns a stable concrete payload and uses typed poll/release callbacks. | Build/run `tests/std/erased_future_dispatch.mt`; general `Box<any Future<Output = T>>` remains blocked on I07 unsized-owner support and a compiler-owned dynamic drop contract. |
| Recursive async future cycles | Implemented and verified on macOS arm64: `semantics/check.cpp` diagnoses direct and mutual recursive async call cycles in the type phase at the recursive call span and names the cycle. | `async-recursive-future-direct.mt`, `async-recursive-future-mutual.mt`. |
| Ownership-checked suspension CFG | Implemented: `ir/ir.h` `Exit::Suspend`, `ir/verify.cpp`, successor updates in `analysis/*`, `ir/dominance.cpp`, `instances/arrays.cpp`, `lowering/scalar.cpp`. | None known; borrow-across-await is covered by `async-await-anywhere.mt`. |
| Inline pinned state and poll | Implemented: `types` coroutine aggregate and layout resolver, `instances/specialize.cpp`, backend frame/dispatch. Transferable/Shareable/Static in `semantics/interface_solver.cpp` with the interior from `semantics/captures.cpp`. | Liveness-precise interior (optional precision gain). |
| Control flow | Implemented: ordinary CFG of the closure body. | None known. |
| Cleanup and cancellation | Implemented: persistent frame flags and `unwind` in `backend/llvm/cleanup.cpp`; exactly-once drops verified. | Dedicated lexical drop-order-across-suspension fixture. |
| Optional executor drives async I/O (S030) | Implemented and verified on macOS arm64: `library/std/task.mt`, `library/std/net.mt`, `library/std/sys.mt`, `library/core/future.mt`, `runtime/sys.{h,cpp}`; `tests/std/async_net_echo.mt` passes in Release CTest and under emitted ASan/TSan. | Kqueue wake-race stress; Linux poll-fallback qualification (owner-run). |
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

I12 status: `mettle fmt FILE... [--check]` was previously implemented and
verified (see `docs/tooling-and-packages.md` section 3): whitespace-only,
token-based layout checked by token sequence, syntax-tree fingerprint and
idempotence. Line breaking after list commas and binary operators
(call/parameter/generic lists, constructors, match arms) is implemented and
verified on macOS arm64; chained calls are not broken (core-grammar section 3). `mettle run`,
`mettle test` and `mettle bench` are implemented and verified (driver
`execute.cpp`, expansion `harness.cpp`; contract in tooling-and-packages sections
3 and 4). T007's package-wide test/benchmark collection, qualified names,
newline-delimited JSON results, optional per-test timeout and doctests from
every package module file are implemented and verified on macOS arm64 (regression
`test_json_timeout_and_modules`). `mettle doc` (static HTML from `///`/`//!`)
and doctests (`mettle test [--doc]`, fence annotations `no_run`/`ignore`/
`should_panic`/`compile_fail(PHASE)`) are implemented and verified on macOS
arm64 (driver `document.cpp`/`execute.cpp`, component `compiler/documentation`;
tooling-and-packages section 4.1; tests `doc_writes_deterministic_html` and
`doctests_run_isolated_examples` in `tests/packages.py`). `mettle lint` is
implemented and verified on macOS arm64 (test `lint_reports_semantic_findings`):
five semantic rules over checked facts, `--allow/--warn/--deny` and
function-level `@allow/@warn/@deny` (tooling-and-packages section 3). Resolved
documentation references, dependency-package pages and unresolved-link warnings
are implemented, unverified (not yet built). JSON lint findings and the static
search index remain implemented and previously verified on macOS arm64
(`lint_` and prior `doc` cases of `tests/packages.py`); this lane's full
wrapping and resolved-link regressions have no current build/test evidence.
Section 3 currently selects the five existing lint rules; it names no additional
rules. The benchmark contract explicitly provides `black_box` and excludes
handles, so no handle API was invented. Debugger metadata/workflows remain
open. The language
server (`mettle lsp`, T005) is implemented
and verified on macOS arm64 (test `language_server`); see
`docs/tooling-and-packages.md` section 5. The milestone is not complete.

I12/T006 status, source-level debug info: the earlier basic `-g` DWARF
implementation was verified. This lane's layout-based sum variants,
length-bearing pointer fields and corresponding LLDB summary updates are
implemented; the `debug_info` package test, which asserts variant and slice
metadata, passes on the I06 freeze. Product/generic/closure capture and macro
invocation locations have prior macOS arm64 verification. The updated LLDB
summaries have not been re-run interactively. Coroutine resume-state variants,
the discriminator, scope-initialized saved-local fields, captured environment
and output fields, and the LLDB `state = await #N (line L)` summary are
implemented; the focused `debug_info` assertions pass on macOS arm64. This
lane adds DWARF lexical scopes, moved-value location ranges, erased witness
table types, and release inlining metadata; these changes and assertions are
implemented, unverified (not yet built). Windows CodeView/PDB remains open and
is out of scope for this lane.
T006 and I12 are not complete.

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
pilot/fixed-sample runtime protocol, the compile-time and build-storage gates
(performance.md section 5.1) and all supported-profile acceptance suites;
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
equivalent semantics and requalify every accepted profile. The independent
backend must provide address/undefined-behavior and thread checking equivalent
to the current ASan/UBSan/TSan qualification, or run the full unsafe/runtime
corpus under it; losing sanitizer coverage blocks I16.

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
lowest-priority library prelude in `compiler/resolution/load.cpp`
(`preludeNames()`); panic/assert and the runtime hook in `library/core/panic.mt`;
text splitting, lines and byte/scalar iteration in `library/core/text.mt`; sink
formatting in `library/core/fmt.mt`; allocator-aware collections and owned text
in `library/alloc/{vec,hash_map,string}.mt`; hosted I/O and threads in
`library/std/{io,module,thread}.mt` with synchronization in `library/std/sync/`;
named call arguments in `compiler/syntax/parser/expressions.cpp` and
`compiler/semantics/calls.cpp`, with their rejection fixtures (`duplicate-label`,
`unknown-label`, `positional-after-label`); and the workloads
`tests/std/cli_wordcount.mt` and `tests/alloc/ini_parser.mt`. The gaps are source
ergonomics, API composition, precise new contracts and their verification.

| Order | Deliverable and gate | Status |
| --- | --- | --- |
| Cutover | Dotted paths, `extend` implementation blocks, D21 vocabulary, and optional item-level semicolons | Implemented and verified |
| R1 | Bounded lookup, associated namespace, constructor selection, inference, vocabulary and the `experience-1` prelude | Associated-namespace resolution, dotted-path resolution, and the syntax/vocabulary cutover are implemented and verified. Generic inference from slice elements and fixed-array arguments to slice parameters is implemented, unverified here. Constructor shape selection, extension applicability, overlap checks and the collection and String inits in semantic-rules section 13.4 are implemented and verified by `custom-init-shapes`, `collection-inits` and the constructor fail fixtures; private adopting inits currently need marker parameters because shape overlap is arity-only. The existing parser and annotation paths appear to support slice, array, tuple and parenthesized-view projection subjects; the grammar records fixed-array subjects, but behavior remains unverified. Slice-interface bounded lookup, projection and `[T].(I).member` expressions are implemented and verified by `slice-interface-implementations` and `slice_iterable`. Focused R1 verification remains open. |
| F1 | Fixed borrowed `Message`, `format` parameters, two-level forwarding and the std Writer adapter (library-surface section 10); lifetime, error and code-size tests; measure indirect-call cost, renderer/code size and check cost | In progress |
| R2 | Lending lines, Copy-valued `[u8].bytes()`, KeyView, PathInput/`write_path` and equivalent workloads within qualified profiles; reconcile `library-and-abi.md` POSIX path statements with the native Windows path contract before delivering that profile | Implemented for POSIX in current spelling, focused fixtures pass; Windows paths and collision stress pending |
| R3 | Expression-bodied `fn`, diagnostics, formatter/editor completion | Expression-bodied named functions (`=> expression`, the closure body form) are implemented, including methods and interface default methods; verified by source and formatter regressions. The actionable ownership diagnostic for moving a non-Copy payload from a read match without `take` is implemented and verified by the `match-move-*-without-take` fail fixtures, including region-generic `take` callees. Readable type display/notes/help and LSP completion remain gaps pending a more specific selection. |
| Qualification | Frozen-input quality, target, safety and performance checks, including performance.md sections 5.1-5.2. D17 comparison harness (`tools/bench_compare.py`, `benchmarks/`, performance.md section 5.3): implemented; its `.mt` workloads type-check, but the harness has not been run and no result is claimed | After R1-R3 |
| WP-S | Storage audit work package of tooling-and-packages.md section 7.1; operational, no dependency on an artifact store | Open |

**R1 constructor inventory (unverified working-tree changes).** Type-body and
inherent-extension inits, argument-shape selection and overlap rejection,
target/bound applicability and default-after-argument inference are
implemented in syntax, resolution and semantics. Distinct checked function
identities feed the existing constructor call, hidden-self and cleanup paths.
The `List`, `Map`, `Set` and `String` constructors and their existing factories
are updated. Source fixtures cover ordinary and conditional overloads,
allocator transfer, defaults, mismatch and overlap; none has been built or
executed. The allocator and symbolic-applicability acceptance below still
requires the applicable source, library, ownership, target and quality gates.
Argument contextualization while resolving multiple same-shape candidates
with unresolved applicability also needs review: a trial may check an argument
before its candidate is selected. No qualification evidence is claimed.

Reconcile this work with the I06 repair and I07-I08 obligations; a design
document cannot mark them complete.

**Implemented syntax cutover.** Dotted paths, `extend` implementation blocks,
D21 collection/iterator/I/O names, and newline-terminated item declarations
have been implemented and verified. The associated-namespace and dotted-path
regressions are covered by the focused source cases and the source suite.

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

Passing the listings' documentation check does not establish semantic
equivalence; the after programs must compile and execute once their features
land, with the matched edge, error and ownership cases above.

**Exhibit 1: byte-streaming word count.** The before program is the fixture
`tests/std/cli_wordcount.mt`. The after program uses the current syntax and
keeps the input/report arguments,
raw path support, byte count, space/LF/tab separators, final unterminated line,
report/stdout bytes and exit codes; error-message output still deliberately
ignores its own failure, now visibly. Streaming formatting changes write
granularity, not an atomic-write contract, so injected-failure tests check error
identity and allowed partial output. Memory stays proportional to the longest line.

```text
import std.env
import std.fs
import std.io
import std.path

fn words_in(line: read [u8]): usize {
    var words: usize = 0
    var inside = false
    for byte in line.bytes() {
        let space = byte == b' ' || byte == b'\n' || byte == b'\t'
        if !space && !inside { words += 1 }
        inside = !space
    }
    words
}

fn count(input: read path.PathInput, report: read path.PathInput): Unit throws io.Error {
    var reader = io.BufferedReader(try fs.open(input))
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
        var out = io.BufferedWriter(try fs.create(report))
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
        var err = io.stderr()
        let _ = capture err.write_line(f"usage: wordcount INPUT REPORT")
        return 2
    }
    let result = capture count(args[1], args[2])
    match take result {
        success(_) => 0,
        failure(error) => {
            var err = io.stderr()
            let message = error.message()
            let _ = capture err.write_line(f"wordcount: {message}")
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
before fixture and byte-for-byte output comparison are POSIX-profile evidence;
Windows output needs its own PathInput tests.

**Exhibit 2: digit-list configuration parser.** The before program is the
fixture `tests/alloc/ini_parser.mt`. The after program, still without std, keeps
empty-line and empty-comma-field skipping, first-`=` splitting, digit-only
nonnegative input, repeated-key accumulation, empty lists, partial updates before
failure and all return codes. CR is not trimmed (use `split("\n")`, not a line
helper that strips CRLF), and the original debug-overflow/release-wrapping
arithmetic is retained rather than substituting the existing signed, checked
numeric parser, which would change accepted inputs.

```text
fn parse_number(text: read Text): i64? {
    if text.is_empty() { return none }
    var value = 0i64
    for byte in text.bytes() {
        if byte < b'0' || byte > b'9' { return none }
        value = value * 10 + ((byte - b'0') as i64)
    }
    present(value)
}

fn parse_list(text: read Text, out: mut List<i64>): bool {
    for part in text.split(",") {
        if part.is_empty() { continue }
        let present(value) = parse_number(part) else { return false }
        out.push(value)
    }
    true
}

fn parse(input: read Text, map: mut Map<String, List<i64>>): bool {
    for line in input.split("\n") {
        if line.is_empty() { continue }
        let present((key, rest)) = line.split_once("=") else { return false }
        let values = map.or_insert(String(key), List<i64>())
        if !parse_list(rest, values) { return false }
    }
    true
}

fn sum(values: read List<i64>): i64 {
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

Existing splitting, iteration and conditional bindings, not the new spellings,
remove the scanning loops; the digit parser is kept because a different numeric
grammar would be a behavior change. Insertion still builds owned String keys
explicitly, while lookups borrow Text through KeyView and allocate no key.

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

I09 status: L057 implemented and verified by focused source cases (attribute parsing with spans, unknown-attribute diagnostics, `@derive` of Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash on products and enums including generic types, generated-code provenance diagnostics). `Default`: implemented and verified on macOS arm64 (Release and Debug) - `core.default.Default` (`static fn default(): Self`) with implementations for integers, floats, `bool`, `char`, `Unit`, `T?` (none), 2- and 3-tuples, `Global`, `List` and `String`, and `@derive(Default)` for products including generic types (field defaults, `Default` bound on used type parameters); enums (no default-variant syntax), unions and arrays are not covered, so `derive(Default)` on an enum is a `feature` diagnostic. Fixtures: `tests/source/run/derive-default-and-manual-default.mt`, `tests/source/fail/derive-default-field-without-default.mt`, `tests/source/fail/derive-default-on-enum-is-unsupported.mt`. L058 implemented and verified (`@cfg` with `all`/`any`/`not`, `target_os/arch/family/endian/pointer_width/feature`, `feature`). Single-file builds take `--features a,b`; in a package build the root source tests its resolved features and each dependency its own (tests/packages.py `features`), while the standard libraries see none. Unions, empty enums and types with `init` constructors cannot derive; L056 procedural macros are implemented, unverified (see below).
L055 (declarative macros): existing token-level matching, repetitions,
follow-set checks, generated-source provenance, binder hygiene, expression
grouping and `$capture(name)` remain implemented. This lane adds lexical
inline-module-scoped definitions within each source file (so sibling inline
modules can define the same name independently) and accepts the item visibility
form syntactically on macro definitions. The focused inline-module namespace
fixture is implemented, unverified (not yet built). Public visibility is
currently syntactic only:
macro imports/reexports and macro-namespace resolution across files, modules
and packages remain unimplemented, as does definition-site identity/visibility
context for private names across module boundaries. This lane does not close
L055. Arguments are expanded eagerly; the macro specifications do not require
lazy argument expansion. Do not treat this work as verified until the fixture
and applicable compiler checks pass.
L056 (procedural macros): implemented and verified on macOS arm64 (tests `procedural_macro`, `procedural_macro_failure`). `[macros.NAME] source/api` in `Mettle.toml`, host-program build and run per invocation (`driver/procedural.cpp`), a versioned line-based token request/response (`expansion/procedural.{h,cpp}`, library side `std.macros`), output re-lexed and attributed to the invocation, failures as `macro` diagnostics, reuse only under a `reproducible` contract with declared files/environment (undeclared inputs rerun) and the response text part of the consumer's build key. Evidence to produce: `tests/packages.py` `procedural_macro` and `procedural_macro_failure`. Known gaps: macros are graph-global (no per-package namespace), no attribute/derive procedural macros, no definition-site/fresh identity constructors or per-token error spans, tokens are exposed as text (see tooling-and-packages, Procedural macros).
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

F1 (f-strings and `format` parameters): partial, verified on macOS arm64; status and gaps in library-surface section 10.3.
