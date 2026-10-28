# Compiler, runtime and library architecture

Status: selected production architecture, with enforced component boundaries
and a qualified concrete I03 pipeline. The contracts below govern the full
language, not a disposable scalar compiler. Components marked future are
specified responsibilities, not implemented features.

## 1. Repository and component boundaries

Keep one repository for the compiler, first-party runtime/libraries, tools and
tests. These share language contracts and must evolve atomically. Packages
compiled by Mettle are not C++ compiler components. A separate repository is
justified by an independently owned/released product, not by folder size.

The current compiler graph lives in `compiler/modules.json`. It owns source
membership and direct dependencies and drives CMake targets. The quality gate
rejects cycles, unowned compiler files, undeclared component includes and LLVM
leaks. Direct includes are checked; this is not a C++ semantic dependency proof.
The design below also identifies later components; do not create empty targets
for them.

| Component | Owns | Must not own |
| --- | --- | --- |
| `support` | Named compiler resource limits and small domain-independent facilities | Language types, compilation state, a miscellaneous service locator |
| `source` | Original source bytes, spans and encoding validation | Diagnostics policy, AST or filesystem command orchestration |
| `diagnostics` | Structured failures and source rendering | Parsing/recovery decisions or process exit |
| `syntax` | Tokens, keyword/operator metadata, lexer, parsed AST and parser/recovery | Resolved bindings, inferred types, CFG slots, LLVM |
| `types` | Compiler-owned language type identities and operations | Parsed AST, LLVM types, target layouts |
| `places` | Function-local storage roots, typed field paths and structural overlap | AST traversal, CFG control flow, mutability/loan policy |
| `semantics` | Declaration/lexical resolution, inference, flow facts and checked syntax | LLVM, code emission, filesystem/linker side effects |
| `ir` | Typed CFG model, structural/type/SSA verification and inspection | AST traversal, ownership policy implemented in a printer, LLVM |
| `lowering` | Checked syntax to typed CFG with explicit evaluation order | Accepting unchecked AST or invoking the linker |
| `analysis` | CFG initialization/moves, view origins, call/destructor effects and loan liveness | Mutating the parsed tree or inferring semantics from LLVM |
| `cleanup` | Static owned-place flag hierarchy, lexical/unwind cleanup plans and ordering | LLVM types, per-object runtime registration, region inference |
| `pipeline` | Backend-independent compilation entry points and stage ordering | CLI parsing, output publication, package downloads |
| `backend` | LLVM adapter, target-machine setup, optimization and object emission | Discovering unresolved names/types or deciding ownership |
| `driver` | CLI, inspection serialization, source loading, artifact publication and native link invocation | Typing, inference, borrow rules or dataflow algorithms |

Components are build/link units, not processes or public plugin APIs. Public
headers expose the minimum boundary; algorithm context and mutable working state
remain private. Splitting one algorithm across many trivial files is not a goal.
Neither arbitrary line limits nor the number of directories establish quality.

## 2. Syntax and checked representations

Source is immutable for a compilation. Tokens retain exact original text and
byte spans, including trivia. A parsed node owns only syntactic information:
kind, children, spelling, annotations, separators and provenance. Type variables,
resolved locals/callees, normalized values and flow facts do not belong in AST
nodes.

Semantic checking produces a move-only checked module that owns the parsed
module plus resolved facts. Facts are indexed by stable node addresses within
that owned tree and exposed read-only after checking. Inference variables remain
private to the checker and do not cross the checked boundary.
Syntax ownership propagates const access through child/body owners; a const
checked module must not expose mutable children through `unique_ptr` accessors.
Moving the owner preserves heap-owned node addresses; deleting/replacing nodes
would invalidate the facts and requires a new checked result.

This is a deliberate current representation, not a persistent identity scheme.
When macros/modules/incremental work arrive, introduce source/expansion,
definition and query identities at their owning boundaries. Never serialize
node addresses, use offsets as globally stable declaration identities, or carry
semantic side tables across source revisions.

Builtin, view and nominal product types use opaque `TypeId` handles interpreted in
their compilation's `TypeStore`. Checking owns the mutable declaration-building
phase; published checked syntax and CFG retain a shared const store owner.
No AST pointer or LLVM type represents a language type. Releasing checked syntax
cannot invalidate the CFG's types. Handles are meaningful only with their store,
not across independent compilations. Name binding and constructor lookup stay
in semantics; the type store holds identities, descriptors and display names,
not the source namespace resolver. Generic/region identities must extend that
ownership model; serialization/query identities are separate from in-memory IDs.

Typing may consult syntax and definitions. Syntax cannot consult typing.
Name resolution, type constraint solving and control-flow classification have
separate implementation ownership even where one checking traversal uses them
together. Introducing modules or generics must extend those owners, not add
unrelated logic to a single `check()` body.

## 3. Typed CFG and verification

The CFG owns values, local storage, instructions, blocks and explicit exits.
It contains no AST pointers or LLVM types. Lowering copies the information
needed for executable semantics and diagnostics. Releasing checked syntax must
not invalidate a CFG.

Before any dataflow or backend traversal, verify indices, operand/result types,
function/call signatures, terminators, predecessor/phi consistency and SSA
availability. Treat a malformed compiler-owned IR as an internal defect, not
an invalid source program.

Initialization analysis is a separate CFG client. It must not be hidden inside
AST lowering. After structural validation and required semantic analyses, a
move-only verified program is the backend's input. Construction is restricted
to the checking boundary; consumers receive a const view. Transformations must
produce a new validated result, not mutate a verified program behind consumers.
Owned SSA consumption is checked separately from place initialization: non-Copy
values transfer at most once on each path, phi transfers occur on incoming edges,
and live destructible values/storage cannot disappear at a normal return or
redeclaration. Aggregate SSA projection only reads Copy fields; moving a non-Copy
field uses an explicit projected place.

Checked syntax and IR share canonical `Place` roots/projections without
depending on one another's representation. A field load/store addresses that
field, not a loaded copy of its parent. Initialization/move analysis tracks
definite/current-possible initialization, historical initialization and moved
paths. It uses sparse accessed prefixes and uniform state for unaccessed fields,
not the Cartesian expansion of all locals and all type fields.

Function parameters retain value/read/mut/take contracts. Transient IR borrow
values distinguish call access from owned first-class view handles. The former
cannot be stored or returned as owned values; the latter can, with origins tracked
through memory, aggregates, copies, calls and returns. Read views are Copy;
exclusive views are not. Backend signatures lower borrowed parameters and view
payloads to addresses, without inventing `noalias`.
Loan analysis solves backward liveness across CFG branches/back edges, retaining
declared result-source dependencies separately from precise referent projections.
Interprocedural effects include view-storage writes by implicit destructors.
Possible writes and every-normal-return overwrites are distinct. Only definite,
uniquely resolved ordinary-call overwrites release an old stored loan; conditional
writes and caught calls retain it. Effect inputs are captured before updating
destinations so self-writeback preserves its original referent.
Overlapping reads coexist, exclusive access conflicts, and parent authority resumes
after a child loan's last use. Receiver reservations permit intervening reads but
require conflict-free activation on every incoming path. Borrow operations are
semantic effects, not pre-check CSE candidates.

Unreachable syntax still receives the language's required checks. Reachability
of executable CFG blocks is distinct from whether a definition is checked.
Never-returning paths, short circuit and named argument evaluation order remain
explicit across boundaries.

## 4. Evolution of representations

| Boundary | Required invariant | Owner of future expansion |
| --- | --- | --- |
| Source to syntax | Lossless tokens, spans, malformed/recovered input never executable | `source`, `syntax`, future macro expansion |
| Syntax to checked representation | Symbols/types/results resolved; no private inference handles escape | `semantics`, `types`, future resolver/trait solver |
| Checked representation to typed CFG | Evaluation order and effects explicit; no syntax dependency in CFG | `lowering`, `ir` |
| Typed CFG to ownership-checked CFG | Places/projections, moves/loans and initialization agree at joins | `analysis`, future ownership component |
| Ownership-checked CFG to cleanup plan | Scope/order metadata and initialized-only destruction on normal and exceptional paths | `lowering`, `analysis`, `cleanup` |
| Cleanup CFG to instantiated/runtime form | Concrete generic instances, closure/task storage, panic policy and ABI calls justified | Future instance/runtime/ABI lowering |
| Runtime form to backend | Layout and target features explicit; language safety decisions already made | Future target/layout layer and backend adapter |

Do not introduce a new full IR for every row merely to match another compiler.
Use distinct operations, analysis products and verified wrapper types until
a representation actually needs different structure. Do not retain one
ever-growing AST with flags standing in for all these stages.

Lowering records lexical/temporary scopes, declaration order, pending arguments,
protected return storage and explicit scope exits. The backend-independent
`cleanup` component expands owned drop places and orders reverse locals and
declaration-order fields. Native flags distinguish initialized paths and established
whole values; moving a value transfers its obligations. User destructors precede
their fields, and partially initialized products drop only initialized fields.

Generated wrapper frames keep owned storage alive while body callbacks unwind;
cleanup never follows addresses into an already-unwound callback frame. The native
runtime re-enters flag-clearing glue after the first destructor panic, restores a
pending replacement, and aborts on a second panic before installation. Borrowed
referents are not scope-owned cleanup roots. Physical entry-block storage does not
extend a source lifetime: only eligible direct borrowed initializers extend their
temporary to the binding block. Generic ownership, owning library handles and
source-level panic APIs remain subsequent milestones.

## 5. Full-language growth map

These are component responsibilities to instantiate when the relevant milestone
is implemented. Each addition requires dependencies, interfaces, invariants and
tests in the same change.

| Work | Owning components and boundary |
| --- | --- |
| Products, ownership and destruction (I03) | Products/views in `types`; access/source contracts in `semantics`; canonical `places`; loan/move/init/effects in `analysis`; scope elaboration in `lowering`; static plans in `cleanup` |
| Modules, enums, patterns, errors and methods (I04) | Module/definition resolver under semantics; syntax families under parser; exhaustiveness/type rules under semantics; explicit effects/exceptional CFG edges |
| Generics, interfaces, regions and dispatch (I05) | Declaration-checked bodies, canonical type/region identities, constraint/coherence solver and instance planning; backend consumes instances rather than solving bounds |
| Layout, unsafe operations and C ABI (I06) | Target description/layout/ABI lowering separate from language types; unsafe validity checks and explicit intrinsics; target-specific probes |
| Core/alloc/hosted libraries (I07-I08) | Native Mettle modules and minimal runtime contracts, not hardcoded collections or OS calls inside the parser/checker |
| Constants, macros and packages (I09) | Const evaluator over defined IR; hygienic expansion with source ancestry; package graph/build planner outside compiler semantics |
| Threads and async (I10-I11) | Concurrency contracts in types/semantics; task state-machine and cancellation/cleanup lowering; separately selected executor/runtime |
| IDE/tooling/incremental (I12) | Reusable in-memory pipeline, immutable inputs/results and revision-bound diagnostics; module/item query boundaries and dependency tracking |
| Additional backends/self-hosting (I15-I16) | Preserve checked/runtime/ABI boundaries; replace compiler implementation/backend without importing LLVM into language representations |

Modules are not packages, compiler components are not Mettle modules, and
syntax extensions are not a public plugin system. Keep these identities distinct.
The language remains the complete agreed V1 scope; future placement is not
permission to remove capabilities.

## 6. Compilation state, errors and side effects

One compilation owns its source, parsed/checked data, type/definition identities,
diagnostics and analysis state. No mutable global current module, implicit
allocator/runtime selection or shared singleton type universe is introduced.
Process-wide immutable backend initialization may use a synchronized one-time
mechanism.

The pipeline is callable with in-memory source and diagnostics and returns only
a checked executable representation on success. Its component entry points
remain usable separately by syntax inspection and later editor tools.
No component terminates the process for an ordinary source failure.

Recovery is a parser concern; error formatting is a diagnostic concern; final
exit status is a driver concern. Unsupported features stay distinct from
invalid source. Internal failures stop emission rather than becoming successful
compilation after catch-and-continue.

Only the driver/build tooling performs source-file loading, native linker
invocation and atomic output publication. Backends may write requested object
streams/files but do not invoke package/network operations or publish partially
checked output. Keep linker arguments as argv, not shell interpolation.

## 7. Target and backend independence

Language types are not target layouts. Introduce explicit target descriptions
for widths/endianness/features and an owned layout/ABI result before expanding
FFI/platform support. The LLVM adapter maps checked operations to LLVM; it cannot
invent lifetime, aliasing or overflow assumptions.

Keep LLVM headers/libraries in the LLVM backend and its driver integration.
The current adapter implements the specified scalar arithmetic profiles;
resource panic/unwind lowering consumes explicit scopes and static cleanup plans,
then emits native runtime callbacks and per-frame flags.

Backend-neutral semantic/ABI operations are the replacement point for V1.2,
not an LLVM wrapper interface claimed to be a universal backend API.
Do not implement speculative plugin loading or a second backend now.

## 8. Runtime, libraries and tools

`library/core` will require no allocator, OS or executor. `library/alloc` depends
on core and an explicit allocator. `library/std` adds hosted services. Create
these source trees with their implementations, not empty architecture markers.
Library contracts include access/regions, allocation, failure, invalidation and
complexity; they do not depend on compiler C++ AST/type structures.

`runtime` contains the minimal defined low-level support for language operations,
with versioned compiler/runtime ABI contracts and target-specific implementations.
It does not become a hidden universal dependency of core/no-OS output.
The async executor remains a separate opt-in facility.
The current hosted runtime's panic ABI is private compiler support, not a stable
public C ABI. It uses C++ exceptions, a thread-local unwind-depth indicator and
integer panic codes. Internal checked-IR catch integration proves cleanup/recovery;
it does not implement generic hosted panic APIs or C-unwind interoperability.

Package resolution/build planning, documentation, formatting and editor protocol
handling are clients of the compiler, not branches in semantic analysis.
Expose internal library interfaces first; stabilize external APIs only with an
explicit compatibility decision. The native compiler remains independent of
an installed Rust toolchain.

## 9. Incrementality, determinism and testing

This refactor does not implement a query engine. Preserve its future boundary:
explicit inputs/options/target, compilation-scoped IDs, immutable published
results and no undeclared environment reads in semantic components.
Future cache keys must include source/dependency identities, features, target,
compiler/runtime revisions and relevant configuration. A cache miss is not
permission to guess a type or skip checking an unused generic body.

Tests attach to component contracts as well as end-to-end behavior. In
particular, syntax is usable without semantics, IR/analysis without parser or
LLVM, and the backend without the syntax/checker libraries. Malformed-IR and
dependency-violation regressions exercise the boundaries rather than checking
only directory names.

The acceptance gate is current-source Debug/Release and sanitizer builds,
static analysis, complete behavioral suites, byte-identical clean rebuilds and
Linux target execution. Documentation must distinguish existing implementation,
future boundaries and unqualified claims. Architecture changes update this
contract, the module graph and affected tests together.

Current realization (2026-10-28): fourteen components have actual source owners
and distinct CMake targets. The former combined syntax/IR files and frontend
archive are replaced by the components above. The boundary suite checks actual
IR rejection, dominance/phi handling, independent initialization analysis,
checked-tree move/lifetime behavior, immutable source spelling, in-memory UTF-8
validation and rejection before a verified program can be published.
Dependency regressions reject cycles, unknown edges, unowned files, private
header access and LLVM leaks.

I03 qualification passes twelve CTest suites in each ordinary configuration and
thirteen under ASan/UBSan, with byte-identical clean rebuilds and ordinary/instrumented
quality receipts. The instrumented quality gate analyzes all owned C++ translation units.
Frontend/IR/analysis compilation
does not receive LLVM include paths, and the standalone boundary-test executable
has no LLVM symbol dependency. Both ordinary builds cross-emit objects for
the scalar/product/ownership source executions, two foundation smokes and native
cleanup/recovery probes on Linux. Per ordinary compiler build, the Linux runner
executes 134 source/profile cases, six cleanup probes and the foundation smoke;
identity guards bind these to the current source, compiler, runtime and generators.
Evidence remains under `build/macos-arm64/`, `build/quality/` and
`build/linux-target/`; none of this claims the future components implemented.
