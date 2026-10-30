# Compiler implementation plan

Status: the `c485aa1` correctness re-review has reopened I06 and its prerequisites'
affected correctness claims. Historical green receipts are retained, not current
approval; reported crashes, soundness/ABI defects and validation gaps must close
before a new freeze and completion verdict.
I01 foundation is recorded for the native macOS ARM64 compiler host and
Linux x86-64 target execution. I02 scalar source compilation is qualified within
that host/target scope. I03 concrete ownership and resource cleanup is qualified
within the same scope. I04 composition and I05 generic typing/dispatch are
covered by historical native, sanitizer, quality, reproducibility and target
receipts. Those receipts do not close the newly confirmed correctness findings.
I06 is reopened; I07-I16 remain planned.
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
but the `c485aa1` re-review exposed missed correctness obligations. I06 is reopened
for those repairs; I07-I16 are not started.

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

The first I04 dependency implements non-generic transparent aliases and concrete
static associated functions. Product identities are collected before forward
alias expansion, and aliases preserve nominal/Copy/access/destruction behavior
rather than defining wrapper types. Cycles, unknown targets and unbound
region-specific aliases diagnose. `Type::function`, alias-qualified calls and
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
I06's historical qualified snapshot and its limits are recorded below; the
`c485aa1` re-review reopened I06, so that snapshot is not current approval. The
older focused batches remain integration history, not substitutes for a new gate.

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
| S018 | Transferable/Shareable/Static: implemented initial contracts | Structural derivation in `interface_solver.cpp` (raw pointers, cells and `Ref`/`RefMut` opt out; atomics and plain data opt in), `unsafe impl`/`impl X not P` declarations, bounds enforced at call sites; Static additionally requires `static` regions | Frozen-input generic/region/projection qualification. Immutable statics must be Shareable (raw pointers and a bare `UnsafeCell` are exempt; `static mut` needs unsafe). Scoped spawns require `F: Within<region s>`, checked in `regions.cpp` (`withinBounds`), so closures cannot capture locals declared inside the scope body. `fs::ReadDir` is an `Iterator`; `mpsc::sync_channel(n)` gives a blocking bounded channel (bound 0 is treated as 1). A panic in a spawned thread is caught per thread and `join()` returns `Err(Panicked{code: 101})`. Known bug: inside a function bounded by `Within<region s>` (impl-level region), method calls on other types report `unknown region argument`; `Scope::spawn` works around it with a private `register` helper. |
| S019 | Thread spawn and scope: implemented initial library | `std::thread` (`spawn`, `JoinHandle::join` reporting `Panicked`, `scope` joining on panic) over `runtime/thread.cpp`; owned threads require Transferable + Static, scoped ones Transferable | Linux target execution of `library.std`, sanitizer/TSan evidence of the shim, stress on the target. Race freedom is not a fairness or deadlock-freedom claim. |
| S020 | Mutex and RwLock: implemented initial library | `std::sync::{mutex,rwlock}` with poisoning, thread-affine guards (`not Transferable`) and an error-checking mutex that reports relock | Target stress and applicable poison/failure-policy cases. |
| S021 | Condition variables, barriers, once: implemented initial library | `std::sync::{condvar,barrier,once}`; a panicking initialiser re-arms `Once` | Target stress. |
| S022 | Channels: implemented initial library | `std::sync::mpsc` unbounded channel with sender/receiver shutdown; `Arc`/`Weak` in `alloc::arc` | Bounded/backpressure channels and `select` remain future work. |
| S023 | Thread-local storage: implemented initial library | `std::sync::tls::LocalKey` over pthread keys with per-thread destructors | Static-initialised keys and destruction-order guarantees across `main` exit. |
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

#### Historical I06 qualification result (superseded by reopening)

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
`read core::text::Text from static` (static private constant plus length
metadata); and a first `library/core` (`text`: UTF-8 validation, checked
slicing, chars/bytes iteration, equality, ordering, find/trim/split/lines/
char_indices; `option`/`outcome` operations as inherent impls on `T?` and
`(T throws E)`; `cmp` (Ordering, PartialEq/Eq/PartialOrd/Ord, min/max/clamp,
Reverse; ints, bool, char, Text, tuples, slices, options); `iter` (Iterator with
lazy adapters, DoubleEndedIterator, IntoIterator, library ranges, sources, sum/
product/min/max); `hash` (Hash/Hasher, FNV-1a, SipHash-1-3/2-4 verified against
reference vectors); `fmt` (Write sink, Formatter with fill/align/width/precision/
sign/alternate/zero, Display/Debug/radix traits for scalars and Text, fixed-buffer
and counting sinks, writer-failure propagation); `num` (integer parsing with radix
and distinct error kinds); `slice` (get/first/last/contains/swap/reverse/fill/
copy_from_slice/split_at(_mut)/binary_search/heapsort/window/chunk/iter/iter_mut);
`any` (TypeId from the `core::intrinsics::type_id` compiler intrinsic, is,
downcast_ref/mut); `ops` operator interfaces. Tests: `tests/library/*.mt` through
`library.core` (`tests/modules.py ... library`).
Prelude: when core is mounted and not shadowed by a user `module core`, the
loader binds `Text`, the iterator interfaces, `PartialEq/Eq/PartialOrd/Ord/Ordering`,
`panic`, `assert` and (when alloc is available) `String` at lowest priority, so
declarations, explicit imports and globs shadow them; libraries are mounted
lazily when a prelude name or a core inherent method name appears. There is no
opt-out attribute (unspecified). `const` items reuse the static evaluator
(immutable statics; usable in expressions, array lengths, integer/bool
patterns and associated `T::NAME` forms; inherent `impl S { const }` is not
supported). Panic: `core::panic::{panic, assert, unreachable}` lower through
`core::intrinsics::panic_message`, which is `llvm.trap` freestanding and the
runtime hook `mettle_rt_panic_message` when hosted (stderr `panicked: msg`,
exit status 101); core `unwrap`/`expect`/slice-split failures use it. Builtin
arithmetic/index traps still abort; there is no `core::process::exit` (core has
no OS; std is a stub).
Known core gaps: the built-in `a..b` range is not an `Iterator` (library
`iter::range` is used instead); heapsort is not stable and there
is no allocation-backed stable sort; slice `Iterable`/`IterableMut` cannot be
implemented because associated types cannot name the `self` region, so `iter()`
is inherent; Debug for composites and generic nested `fmt` calls are blocked by
exclusive-loan retention after a generic `mut Formatter` call (`fmt::write_i64`
helpers are provided); sort stability and Unicode
whitespace/case are not implemented; mounting compiles the whole of `core`, which
costs seconds in Debug builds.
Also: text literals are usable as `static` initializers and
byte/raw literals (`b"..."` is `read [u8; N] from static`; `r"..."`, `r#"..."#`,
`br"..."`); range slicing `read a[i..j]`, `a[i..]`, `a[..j]`, `a[..]`, `a[i..=j]`
on arrays and slices (bounds-checked, `mut` for mutable subslices) and, through
the `core::ops::IndexRange`/`IndexRangeMut` protocol, on Text (panics on
out-of-range or non-char-boundary) and user types; `core::slice::from_raw_parts`
and `from_raw_parts_mut`, `core::text::from_utf8_unchecked[_mut]` (unsafe; the
result region is the caller's choice); generic parameters determined by an
`I: Iterator<Item = T>` bound; closures passed to generic callable parameters and
explicit generic constructors. Open-ended
range values (as opposed to range indexing), `f"..."` interpolation, `const`
items, `u32 as char` (only `u8 as char` is defined), `core::process::exit`,
remain open; this is not I07 completion or qualification.
The first native `library/alloc` now provides `alloc::alloc` (checked
`Layout`, `Allocator` contract with `allocate/deallocate/grow/shrink` returning
`AllocError`, stateless `Global`, `handle_alloc_error` = abort policy), `Box`,
`Rc`/`Weak`, `Vec`, `String`, `HashMap`/`HashSet`, `BTreeMap`/`BTreeSet`,
`VecDeque`, `BinaryHeap` and `LinkedList`, each generic over an allocator
(`A: Allocator = Global`) that is stored in the collection and used for every
block it owns. Hosted builds link the `mettle_rt_alloc/dealloc/realloc` hooks in
`runtime/alloc.cpp`; freestanding builds supply those symbols. Tests live in
`tests/alloc/` (`library.alloc`): happy paths, large growth, hash collisions,
a failing allocator, counted drops, a trap on a non-boundary `String::truncate`,
a borrow-invalidation rejection and a structured parser + `HashMap<String,
Vec<i64>>` workload built without std. Known gaps: `BTreeMap` is a sorted array
(O(n) updates), not a node B-tree; no entry API beyond `or_insert`; borrowed
iteration is implemented through the core interfaces: see the integration
note below; `Box<[T]>`/unsized owners, `Arc`, `Pin` and
the native `heap T`/`local shared T`/`weak` syntax (still a feature error) are
not mapped; a `take` argument always
moves even a `Copy` binding, so generic calls pass `i + 0` or a fresh `let`.
Panics are runtime traps (no unwinding catch), so panic-safety is tested for
drop order only. Alloc/core integration (lane allocint): `library/alloc/support.mt` is gone and
`library/alloc` depends only on `core`. New `core::clone::Clone` (integers,
`bool`, `char`, `Unit`, `Ordering`, pairs, `T?`); `core::iter::Iterable`/
`IterableMut` are region-family interfaces (`type Iter<region r>`,
`fn iter<region r>(receiver self: read Self from r)`). `Vec` implements
`IntoIterator` (`IntoIter` is double-ended), `Iterable`/`IterableMut`
(`for x in read v`, `for x in mut v`, `for x in take v`), `Deref`/`DerefMut` to
`[T]`, `IndexRange`/`IndexRangeMut`, `Clone`, `PartialEq/Eq/PartialOrd/Ord` and
`Hash`. `String` implements `fmt::Write` (`fmt::Error`), `Deref` to `Text`,
`IndexRange` (-> `Text`), `Display`, `Debug`, `Hash` (equal to `Text`'s hash),
`Ord`. `Box` and `Rc` are transparent over `Deref`, comparison, `Hash`,
`Display`/`Debug` (`Box` also `DerefMut`, `Clone`). `HashMap`/`HashSet`,
`BTreeMap`/`BTreeSet`, `BinaryHeap`, `VecDeque` and `LinkedList` implement
`Iterable` (maps yield stored buckets/entries; map `IterableMut` is withheld
because it would expose keys). `HashMap` hashes with `core::hash` (SipHash-1-3).
Compiler changes: blanket-impl coherence now rules out a concrete subject when
no implementation of the required interface could apply (so
`impl<I: Iterator> I implements IntoIterator` coexists with concrete
impls); calling a body-less interface method through the interface name is a
structured type error (use method syntax or `<T implements I>::m`); the region
solver compares raw pointers structurally and treats cycles through recursive
nominal types/pointers coinductively. Standard-interface surface (lane allocfmt): `Vec`, `VecDeque`, `LinkedList`,
`BinaryHeap`, `HashMap`/`HashSet` and `BTreeMap`/`BTreeSet` implement `Debug`
with Rust-style output (`[1, 2]`, `{k: v}`, `{a, b}`) and the pretty
`alternate` form (`Formatter` carries an indent level and indents lazily at line
starts; helpers `debug_open/debug_item_start/debug_item_end/debug_close`; `[T]`
has `Debug`). All but `BinaryHeap` implement `Clone` (needing `Clone` elements
and allocator) and `PartialEq/Eq`; maps/sets compare order-independently,
ordered ones (`VecDeque`, `LinkedList`, `BTreeMap`, `BTreeSet`) add
`PartialOrd/Ord` (lexicographic) and `Hash` (length-prefixed); `HashMap`/
`HashSet` deliberately have no `Hash`. `IterableMut` covers `VecDeque`,
`LinkedList` and, over values only, `HashMap`/`BTreeMap` (`for v in mut m`,
`values_mut()`); keys are never mutable. `core::iter` gains `FromIterator`,
`Extend` and a free `collect` (`let v: Vec<i32> = collect(it)`), implemented for
every collection (maps take `(K, V)` items); they take any `IntoIterator` (its
`IntoIter` is declared `Iterator<Item = Self::Item>`), and `Iterator::collect` is a
provided method (bound elaboration is coinductive over bounds already in progress). `Unit` gained comparison
impls. `Debug` now also covers `T?`, outcomes, tuples (arity 1-12) and `[T; N]`;
maps expose borrowed `keys()`/`values()`. Deliberate omissions: `Display` for
collections and `BinaryHeap` `PartialEq`/`IterableMut` (Rust has none).
Region-lane I07 work: a user collection (`ptr`/`len`/`cap`) can implement
`Iterable`/`IterableMut` with a region-family associated iterator
(`type Iter<region r> = VecIter<T, region r>`), so `for x in v` and
`for x in mut v` yield `read T from v`/`mut T from v` and reject mutation or
escape while the loop or an item is live. Optional/mutable view results
(`(read V from self)?`) re-borrow matched views, closures may be passed to generic
function-pointer parameters, and raw-pointer dereference views are treated as
`static`-backed. Family bounds may mention the family region
(`type Iter<region r>: Iterator<Item = read Self::Item from r>`), so generic
`for x in c` over `C: Iterable<Item = i32>` and `for x in mut c` over
`IterableMut` type-check and region-check; mutation during iteration and item
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
struct (`Cursor<region r>{ v: mut Vec<T> from r }`) now keeps a loan on the
view's referent even when the callee derives it through a raw-pointer deref
(summary places are truncated at the last view deref, and result paths with no
tracked targets are backed by their `from` parameters). A borrow of a place
that holds a stored `mut` view also freezes that view's referent (`Loan::frozen`),
so reborrows such as `let b = mut a.v` block later use of `a.v`. The library
`Iterable`/`IterableMut` interfaces declare bounded `Iter<region r>` families,
so generic code can call `.iter().next()`.
A result path that mixes safe and raw-pointer-derived views keeps the safe
targets and adds the `from`-parameter backing. Adversarial closure-capture probes
(stored, nested, view-returning and escaping closures over `mut` views) found no
hole; generic `F: mut fn(): mut T` bounds still require an unambiguous `from`
contract.

I08 status (initial macOS ARM64 hosted profile): `library/std` provides `io`
(Read/Write with visible partial transfers, `write_all`/`read_exact`/
`read_to_end`, buffered reader/writer, an `io::Error` that round-trips the raw
errno), `ffi` (`OsStr`/`OsString`), `path`, `fs`, `process`, `env`, `time`,
`net` (synchronous IPv4 TCP and UDP with timeouts) and `panic` (hook around the
runtime's exit-101 path). The POSIX layer is the libc calls declared in
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
`tools/build.py` receipt, which the runner requires. Gaps: IPv6, connect timeouts and DNS are absent; a panic in a spawned thread is caught and reported by
`join()`, but there is no general panic recovery (S028), so a main-thread panic
still ends the process; macOS file systems
may reject non-UTF-8 names (EILSEQ), which the tests check but cannot exercise
on-disk there; hosted names avoid reserved words (`read_some`, `write_some`,
`read_bytes`, `var_os`, `set_*` open options). `ReadDir` implements `Iterator`
(`next_entry` remains).

### 8.4. Builds, concurrency and async: I09-I11

I09 completes required constant evaluation, hygienic declarative macros, host
procedural extensions, attribute/derive/cfg phases and versioned token APIs.
Implement manifest resolution, exact locks, feature/host/target separation,
build scripts and dependency-keyed incremental reuse. Demonstrate a native
multi-package project with a generated input and extension. Corrupted artifacts
must fail verification; untracked host inputs must trigger conservative reruns;
incremental and clean builds must agree. Host Mettle extensions can use the
services delivered in I08, avoiding an undeclared compiler-bootstrap dependency.

I10 can progress alongside I08/I09 after I07. The initial I10 surface is
implemented (see S018-S023) with `library.std`, `runtime.thread` and scalar
compiler cases; Linux-target and TSan qualification of the library remain open
(a manual out-of-tree TSan run of five threaded programs reported nothing; the
driver has no TSan link mode). Channels: unbounded `channel` and bounded
`sync_channel`; there is no `select`.
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

F1 (f-strings and `format` parameters): implemented, not yet verified (no build/test run); see library-surface F1 notes for gaps.
