# Compiler, runtime and library architecture

Status: selected production architecture, with enforced component boundaries
and concrete I03-I05 phase representations. The contracts below govern the full
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
| `expansion` | Attribute validation, `@cfg` target/feature predicate evaluation (inactive items are parsed but dropped before resolution), `@derive` generation of ordinary `extend` declarations as separately registered generated sources with span provenance back to the attribute and offending field/variant; test/benchmark collection and harness synthesis (`harness.cpp`: in a test build, the selected package's `@test`/`@bench` functions are recorded with qualified module paths, the root `main` is dropped and Mettle source for a selector-dispatching `main` is generated and loaded beside the root; each test then runs in its own process); declarative macro expansion (`macros.cpp`, token-level, before parsing; the generated source maps every token to its template/argument origin and the invocation) and the procedural-macro protocol (`procedural.{h,cpp}`: versioned request/response encoding and parsing; `macros.cpp` calls an injected host callback, re-lexes its text output and attributes the tokens to the invocation, and never starts a process itself) | Name resolution, type checking, LLVM |
| `documentation` | `mettle doc` and doctests, verified on macOS arm64: documentation extraction from the lexer's comment tokens (`///` item docs, `//!` module docs, declaration headers as written, visibility filtering, `document.cpp`), reduced markdown blocks (`markdown.cpp`), fenced-example classification and generated `@test` functions (`doctest.cpp`) and deterministic dependency-free HTML (`html.cpp`) | Name resolution, type checking, filesystem I/O, process execution, LLVM |
| `resolution` | Compilation-local module identities, item/import scopes, visibility and canonical declaration names; source-provider-driven module assembly | Inference, backend types or filesystem I/O |
| `packages` | Manifest/lock TOML, SemVer requirements, dependency solving with features, checksums, the package build plan (mounts, build scripts and `[macros]` programs handed to the driver) and the content-addressed build store (`store`) | Source parsing, semantics, network access or artifact publication |
| `types` | Compiler-owned language type identities/operations, target facts and target-layout results | Parsed AST, LLVM types/target machines, toolchain state |
| `consteval` | Pure target-aware compile-time interpreter over syntax: scalar/aggregate values at the selected target's integer widths, `const fn` calls, control flow, step/depth budgets (`error[limit]`); names and diagnostics come from a host interface | Name resolution, checker state, LLVM, host-width arithmetic |
| `places` | Function-local storage roots, typed field paths and structural overlap | AST traversal, CFG control flow, mutability/loan policy |
| `semantics` | Lexical resolution, module-resolution consumption, inference, flow facts and checked syntax | LLVM, code emission, filesystem/linker side effects |
| `ir` | Typed CFG model, structural/type/SSA verification and inspection | AST traversal, ownership policy implemented in a printer, LLVM |
| `lowering` | Checked syntax to typed CFG with explicit evaluation order | Accepting unchecked AST or invoking the linker |
| `analysis` | CFG initialization/moves, view origins, call/destructor effects and loan liveness | Mutating the parsed tree or inferring semantics from LLVM |
| `instances` | Canonical concrete function planning, type/const substitution, callable ABI adapters and const-array repeat/iteration expansion | Rechecking source under stronger instantiated ownership rights or selecting LLVM representations |
| `cleanup` | Static owned-place flag hierarchy, lexical/unwind cleanup plans and ordering | LLVM types, per-object runtime registration, region inference |
| `lint` | Semantic lints (`mettle lint`) over a checked module's side tables: unused bindings and `var`s, unused imports (recorded by `resolution` lookups), unreachable statements (checker flow summaries) and ignored Outcomes; level selection (flags, function attributes) | Mutating syntax, re-resolving names, LLVM, printing or exit policy |
| `pipeline` | Backend-independent compilation entry points and stage ordering, including a read-only observer of the checked module before lowering | CLI parsing, output publication, package downloads |
| `lsp` | `mettle lsp` language server: JSON-RPC/LSP framing over streams (`server.cpp`), a self-contained JSON reader/writer, UTF-16 position mapping, a token-based declaration/occurrence index that works on incomplete source (`symbols.cpp`) and definition, hover and rename planning over it (`navigation.cpp`); diagnostics come from the real front end (`resolution::load` + `pipeline::compile`) run on in-memory documents | LLVM, file I/O (the host supplies a source provider), process lifetime, checked-IR publication |
| `backend` | LLVM adapter, target-machine setup, optimization and object emission | Discovering unresolved names/types or deciding ownership |
| `driver` | CLI, inspection serialization, source loading, build-script and procedural-macro execution (`procedural.cpp`: host build, process run, reproducible-result reuse; `observe.cpp`: declared-input state shared with build scripts), cache-key assembly and lookup, artifact publication and native link invocation, `mettle run`/`test`/`bench` execution (`execute.cpp`: temporary builds, per-test process spawning and optional timeout, human/JSON result reporting, and doctest builds that overlay generated tests on package module sources and judge `compile_fail` examples from captured diagnostics) and `mettle doc` (`document.cpp`: path discovery, parse validation, output files) | Typing, inference, borrow rules or dataflow algorithms |

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
Module/source identities now have explicit owners; macros/incremental work must
extend these with expansion/definition/query identities at their owning boundaries.
Never serialize
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

`types/regions` owns compilation-local region identities, declaration binders,
universe ancestry and intersection regions. Names resolve to identities within
each declaration; equal source spellings do not equate independent binders.
`semantics/region_solver` proves outlives and structural type-variance obligations
under an explicit environment. Its cache includes assumptions, substitutions and
the binder universe. Higher-ranked callable comparison uses fresh rigid target
regions and checked source instantiations; younger regions cannot solve outer
variables. Cyclic or exhausted proof searches report inconclusive results.
`semantics/regions` invokes these checks on source declarations, expressions,
calls and returns, retaining semantic signatures separately from region-erased
runtime types. Concrete CFG origin/loan checks remain mandatory: an abstract
outlives proof does not authorize returning or storing a local owner's address.
Interface bound descriptors retain region arguments and quantified identities;
selection instantiates implementation regions in the query universe, rather
than treating a `static` implementation as a universal one. Associated families
retain their own region parameters separately from type/const parameters.
Each projection substitutes those identities and checks its outlives obligations.
Normalized semantic annotation facts are retained before runtime region erasure.
Explicit borrowed erasure preserves the source view's access and region, while
opaque values retain region-bearing hidden fields.
Generic associated-region calls substitute declaration-owned family binders.
`Within<region s>` bounds (used by scoped spawn) are enforced by the region
pass (`withinBounds`): every region captured by the argument must outlive `s`,
and closures checked against a callable bound receive a higher-ranked binder.
Concurrency properties (Transferable/Shareable/Static) are structural proofs in
`semantics/interface_solver`; immutable statics must be Shareable. Interface
implementation candidates are indexed by interface declaration.
Runtime normalization erases regions only after the semantic region checks;
it never substitutes for those checks. Slice identities describe element-count
metadata and lower through explicit unsizing, length and checked-index operations.
Recursive region well-formedness that cannot yet be established reports an
inconclusive limit diagnostic, not an accepted recursive proof.

Typing may consult syntax and definitions. Syntax cannot consult typing.
Name resolution, type constraint solving and control-flow classification have
separate implementation ownership even where one checking traversal uses them
together. Introducing modules or generics must extend those owners, not add
unrelated logic to a single `check()` body.

Declaration collection and alias expansion live in `semantics/declarations.cpp`.
Products receive nominal identities before alias targets and field annotations
resolve. Aliases introduce no `TypeStore` entry: their names resolve to an existing
identity, with cycle/depth diagnostics. Qualified associated lookup canonicalizes
only semantic names, preserving parsed source spelling. Static functions have no
receiver parameter; explicit qualified method calls retain declared parameter
access without acquiring an implicit two-phase receiver. Module/import identities live in the backend-independent `resolution` component.
Bare interface parameters desugar to implicit generic parameters; one accessed through `read`/`mut` omits the default Sized bound so unsized implementors are accepted.
Parsed declarations retain source spelling, lexical module paths and visibility
syntax; immutable resolution side tables own canonical names and compilation-local
module identities. Generic aliases expand under their declaration environment and preserve their
source/module identities; evaluated const arguments participate in identity.

Concrete enum, optional and outcome descriptors own their alternatives and active
payload field maps. Tuples, fixed arrays and ranges are structural identities (a range outside a `for` source is checked as a call of `core.iter.range`/`range_inclusive` when `core` is mounted);
named products/enums remain nominal. Recursive structural constraints are solved
inside inference, not by inserting unresolved types into published CFGs. Optional
injections are checked expected-type adaptations, never flattening of nested
presence. Character/byte decoding rejects invalid scalars/escapes before checking.

Pattern checking, coverage specialization and aggregate/effect rules have separate
semantic owners. Coverage includes nested constructors, integer/scalar intervals,
alternative binding compatibility and guards that cannot establish coverage.
Borrowed pattern bindings lower to views; consuming guards borrow until acceptance.
The source spelling of patterns and qualified paths remains unchanged.

Parameter defaults have declaration-checked bodies and checked caller plans.
Private default thunks reborrow already-evaluated arguments; omitted arguments run
in declaration order after explicit source-order evaluation. Constructor metadata
identifies unestablished `self` storage: normal success moves it into a result,
while failure cleanup runs initialized field destructors, not its user destructor.
Constructor candidates are registered by nominal origin in semantics, with
distinct internal function identities and target applicability constraints.
Shape intersection is checked at declaration time, and calls select a checked
candidate before ordinary call and generic substitution planning. Generated
field construction is unavailable whenever a nominal type has custom inits.
Inherent-extension inits use the same hidden-self lowering and cleanup as
type-body inits; their target and bounds remain declaration-owned conditions.
Expansion retains derive request names and spans so semantics can reject an
unsupported derive after constructors from other extensions have been collected.
This constructor-selection change is implemented but has not yet been built
or verified.

Callable descriptors retain parameter access, success/error types, result-source
indices and read/mut/take capability independently of native function pointers.
Closure syntax keeps its original body and names. Checked closure records own
inferred signatures and minimal capture-place maps; lowering maps those places
into compiler-owned nominal environment products rather than rewriting syntax.
Owned environments use ordinary lexical storage and field cleanup, including
closures that are never invoked. Borrowed capture fields use the same origin and
loan analysis as other stored views.

Function addresses and indirect calls are explicit CFG operations. An indirect
call references a signature-only contract function for verification and
conservative view effects, with its code-pointer SSA target kept separately.
That contract is not an executable shim, environment registry or public ABI.
Concrete closure calls instead invoke generated bodies with an explicit
environment parameter when captures exist; noncapturing bodies have thin
signatures. Neither representation requires heap allocation.

Callable generic bounds attach a checked signature/capability to a rigid type
parameter without granting Copy or converting it to a thin pointer. Concrete
instance lowering selects the function-pointer call or closure body and emits
an ABI adapter when the receiver passing mode differs. Such adapters preserve
the bound's parameter access and typed result, and consuming adapters clean any
remaining owned captures after invocation. The CFG's closure-body index map is
compilation-local metadata, never a runtime capture registry.

Receiver selection retains each candidate type before considering its consuming,
read and exclusive receiver forms. Inherent methods precede applicable visible
interface methods at each form; a selected move or exclusivity failure does not
restart lookup at a weaker candidate. Checked receiver/conversion plans record
native dereferences, declared `Deref`/`DerefMut` projection calls and final view
adaptations without changing parsed names or inserting syntax nodes.
Projection steps retain generic/interface dispatch facts and declared returned
view types. Lowering evaluates the receiver and each projection once, emits
ordinary typed calls/borrows, and delegates slice/erased metadata formation to
their existing ABI helpers. Region and loan checking therefore see the actual
projection calls and their result-source contracts rather than an unchecked
pointer reinterpretation.

Generic declarations use rigid, compilation-owned parameter identities. A
parameter exposes only its declared Copy/Sized, interface and callable rights;
nominal aggregate queries never treat an abstract parameter as a product.
Checking publishes separate call substitutions without rewriting parsed names,
spans or generic argument spellings. Bounds resolve in the callee declaration's
namespace but are proved only from the caller's assumptions and coherent
implementation evidence.

Implementation applicability combines target/interface identity matching with
declared type/const equalities before proving its requirements from caller
evidence. The same constraint helper tests coherence intersections; missing
current implementations do not prove disjointness when downstream
implementations remain possible. Implementation parameters must be determined
by their target, interface inputs or equalities, rather than surviving unresolved
until specialization.

The pipeline verifies and analyzes every symbolic body, including unused
declarations, before requesting concrete instances. The `instances` component
then substitutes already-checked CFGs and preserves declared parameter modes.
Its normalization/selection hooks receive compiler-owned types and dispatch
metadata, not syntax. The resulting concrete CFG is verified and analyzed again;
unresolved parameters or dispatch are never handed to LLVM.
Symbolic CFG functions retain their declaration interface bounds and equalities
as proof-only metadata. Private representation normalization can reveal an opaque
hidden representation after source checking, including associated result types;
source lookup still exposes only the opaque declaration's public bounds.
Concrete instances discard declaration-only proof metadata.

Compact arrays: a concrete array of non-droppable elements with more than 64
elements (1024 expanded when nested; `TypeStore::compactArrayShape`) is a
single leaf place carrying an element type and a constant length instead of one
field per element. It keeps `ArrayRepeat`, `ArrayBorrow*` and `ArrayTake`
loops unexpanded, so initialization, loan and cleanup dataflow is O(1) per
statement; constant-index projection, array patterns and by-value loops over
droppable elements are rejected with `error[feature]`. Arrays of droppable
elements stay expanded (capped at `droppableArrayElements`). The LLVM adapter
treats aggregates over `LoweringContext::indirectThreshold` bytes as memory:
the SSA value is a pointer to a snapshot temporary, copies are memcpy/memmove,
repeat is memset or a store loop, large results use a trailing `sret`
parameter, and static repeats emit `zeroinitializer`/constant arrays.
Const-array repeats have an explicit symbolic operation that concrete expansion
replaces with a construction when the array is not compact. A dynamically indexed array element is one
`ArrayBorrowRead/Mut` operation for every array, concrete or generic; it never
expands into a per-element CFG, and analyses treat it as a conservative access
to the whole array unless the index is an in-range literal. The LLVM adapter
lowers it to one unsigned bounds comparison (a negative signed index is
sign-extended so it fails the comparison) with the out-of-bounds panic, followed
by a single element GEP. Generic array iteration checks one bounded-cursor loop body with ordinary
back-edge ownership/loan analysis. A consuming element transfer is valid only
inside its verified iteration cursor. Concrete expansion clones each iteration's
SSA and locals, retaining break/continue destinations, remaining-element cleanup
and evaluation order. Resource bounds diagnose excessive instance/CFG growth.

`for` over a user iterator is not rewritten in the AST. The checker stores an
iteration plan in `CheckedModule::iterations` (mode, protocol, selected method
and a synthetic elaboration block that borrows the original body through
`NodeOwner::borrow`); ownership, region, capture and lowering passes walk the
elaboration, and lowering emits the loop, `next` call, match and cleanup from it.

Borrowed slices use a private `{data, count}` representation. Borrowed erased
interfaces use `{data, count, witness}`; the count is zero for sized implementors.
The slice `len()` primitive reads element-count metadata through the existing
verified `SliceLength` operation; it evaluates its receiver once and returns
`usize`. This does not yet provide the remaining I07 slice or text surface.
Immutable witness tables record the receiver metadata kind and concrete alignment,
then method entries and verified parent-interface links. Calls reconstruct a
slice handle when needed, rather than retaining an address into a temporary
handle. Structural unsized tails use their concrete alignment, including through
erased upcasts. Metadata temporaries are allocated at function entry, not once per
loop iteration. These are compiler-private representations, not stable foreign ABIs.
Erasing a witness-metadata implementor itself, rather than upcasting its existing
interface or structurally unsizing its tail, still requires a sized adapter.
The compiler diagnoses that unsupported conversion; it never silently allocates
an adapter or retains dangling metadata.
This is not a restriction on ordinary concrete-to-interface erasure or
child-to-superinterface upcasts. It concerns a new erasure whose implementor
already needs witness metadata, which the new view must not discard. A sized
adapter retains the original handle under ordinary borrow/lifetime rules and
implements the target interface; the adapter need not allocate on the heap.

Opaque return declarations retain one hidden type identity across all return
paths. Generated adapters preserve declared receiver modes, Self arguments and
Self results; the logical opaque wrapper has no physical field offset or extra
allocation. Associated-result lookup uses declared projection bounds, not
properties accidentally available on the hidden concrete type.

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
Fixed-array rest views use validated bounded subarray projections. Canonical
projection composition preserves the original element offsets in loans, returned
origins and call effects; overlap checks distinguish disjoint element intervals.

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
Indirect or erased mutable calls conservatively union possible view-storage
writes. Analysis-only opaque/typed element paths preserve compatible origins
through unknown aggregate shapes; they are forbidden in executable CFG places.
An imprecise write cannot kill an old origin or establish a definite overwrite.
Returned generic view values retain the borrowed sources captured by their
interface arguments, even when the dispatch signature hides their concrete shape.
Overlapping reads coexist, exclusive access conflicts, and parent authority resumes
after a child loan's last use. Receiver reservations permit intervening reads but
require conflict-free activation on every incoming path. Borrow operations are
semantic effects, not pre-check CSE candidates.

Variant construction and tag tests are explicit IR operations. Initialization
dataflow refines possible variants on branch edges and invalidates refinements on
replacement or mutable calls. A payload cannot be admitted without a compatible
active tag. SSA projection cannot bypass these place checks. Cleanup flags are set
only for the active alternative; inactive representation bytes establish no owned
value or destructor obligation. Default/native enum storage remains private.
Explicit C, integer and transparent representations instead use their checked
layout and physical C ABI; logical alternatives do not become stored tags in a
transparent single-variant enum.

Typed failures use ordinary discriminated outcomes at the internal call boundary,
not the panic runtime. Source success types remain distinct from that physical
result. Capture/propagation continuations clean their exited scopes and protect
owned pending values/errors before joining or returning; panic continues to unwind
through native cleanup independently.

Lexical break/continue targets are resolved in `semantics/control_flow.cpp` to
function-local checked identities. Flow summaries carry target sets, so an inner
loop cannot accidentally consume an outer loop's exit or hide a path from
initialization/result inference. `lowering/control_flow.cpp` maps those checked
targets to CFG successors and cleanup depths. Break values are evaluated before
cleanup; owned pending values use protected storage until the exited scopes
finish, then incoming-edge ownership transfers feed the result phi. Neither
source labels nor AST pointers escape into the CFG.

Unreachable syntax still receives the language's required checks. Reachability
of executable CFG blocks is distinct from whether a definition is checked.
Never-returning paths, short circuit and named argument evaluation order remain
explicit across boundaries.

## 4. Evolution of representations

| Boundary | Required invariant | Owner of future expansion |
| --- | --- | --- |
| Source to syntax | Lossless tokens, spans, malformed/recovered input never executable | `source`, `syntax`, future macro expansion |
| Syntax to checked representation | Symbols/types/results resolved; no private inference handles escape | `resolution`, `semantics`, `types` |
| Checked representation to typed CFG | Evaluation order and effects explicit; no syntax dependency in CFG | `lowering`, `ir` |
| Typed CFG to ownership-checked CFG | Places/projections, moves/loans and initialization agree at joins | `analysis` |
| Ownership-checked CFG to cleanup plan | Scope/order metadata and initialized-only destruction on normal and exceptional paths | `lowering`, `analysis`, `cleanup` |
| Cleanup CFG to instantiated/runtime form | Concrete generic instances, closure/task storage, panic policy and ABI calls justified | `instances`, `pipeline`, future task/runtime/ABI expansion |
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
temporary to the binding block. Generic instances preserve these declared
ownership rules. Owning library handles and source-level panic APIs remain
subsequent milestones.

The I06 machine boundary shares operation signatures between checking and IR
verification in `types/machine`. Raw memory operations retain explicit unsafe
requirements: callers establish provenance, extent, alignment, initialized
validity, exclusive access and non-overlap where required. Bytewise copies and
swaps do not manufacture typed reads of uninitialized payloads. Transmutation
checks equal object sizes; target validity and retained provenance remain unsafe
obligations. No runtime provenance registry or informal `noalias` assumption
substitutes for those obligations. Copy operands remain usable unless the source
explicitly transfers them.

Packed storage never grants an unaligned safe view. Before invoking an unaligned
field's destructor, cleanup moves its bytes to aligned wrapper-frame storage and
records that location. Re-entry after panic follows the same location and
remaining field flags rather than dropping the original bytes again. Structurally
pinned unaligned fields are rejected, not silently relocated.

`--freestanding` skips the implicit hosted entry and uses aborting traps rather
than an unwind runtime. Normal destruction/replacement calls its generated glue
directly; foreign unwind requirements are rejected at emission. This initial
object-emission path does not qualify additional target ABIs or establish a
complete standalone target runtime.

Parameter default expressions retain their declaration-owned syntax and checked
facts. Lowering emits checked default thunks with earlier parameters borrowed,
then evaluates supplied arguments in written order before invoking omitted
defaults in declaration order. Pending owned arguments remain in cleanup-aware
storage until the final call; an unused default still receives declaration and
ownership checking. Custom constructors use ordinary function calls and a
hidden uninitialized product place. Successful returns move the established
whole product; partial failure uses the existing initialized-field cleanup,
without running a whole-value destructor on an incomplete product.
Irrefutable parameter patterns retain contiguous formal parameter slots and
bind their projected locals in the function prologue. Checked binding-to-formal
relationships preserve returned-view sources and expose only earlier bindings
to defaults. Default thunks reborrow those projections rather than consuming
the destructured input.

### I06 completion interface plan

Status: shared interface plan implemented for the initial section 8.3 machine
boundary; frozen-input qualification remains separate. It covers the eight source
workstreams together so their representations are not rediscovered one feature
at a time. It does not add targets, portable SIMD, thread libraries,
allocator-backed pin owners or general I09 compile-time programming.

| Workstream | Producer and shared representation | Validators and consumers |
| --- | --- | --- |
| Numeric composition/policy | `types` owns typed, canonical 128-bit integer values and checked required-constant operations. Keep projection ordinals separate from constant payloads in `TypeParameter`. Pattern/range facts carry typed numeric values, not truncated i32s. Existing IR numeric payloads remain the runtime-literal boundary. Function/module arithmetic metadata records explicit floating relaxations. | Checking validates contextual types, ranges and const failures; aggregate lengths use checked narrowing to compiler limits. Lowering preserves operand types and runtime profiles. LLVM rounds floating representations directly and applies only declared relaxations; release mode never implies fast-math. |
| Cells and borrow guards | Extend compiler-owned storage kinds with `Cell`, `RefCell`, read/exclusive guards and their checked operation signatures. Guards hold lifetime authority for their backing cell separately from a payload-access capability. Add a native cleanup action alongside user-destructor function identity; do not manufacture a user destructor index. | Checking/IR verification distinguish authorized interior exchange from ordinary writes through read views. Origin analysis captures the old value before exchange and records writeback of the new one. Runtime counters justify dynamic exclusivity; cleanup releases a guard once, without allocation or OS services. |
| Remaining Unpin conditions | Interface implementations own conditional property requirements and coherence. `types` retains structural/native properties and validated property facts, not a callback into the semantic solver. Assumed generic properties remain distinct from proven concrete facts. | The interface solver proves arbitrary permitted interface conditions before native pin signatures are admitted. Substitution, region erasure and instance planning preserve only valid facts. Unknown conditions cannot become unconditional Unpin; generated projections and pinned cleanup retain the existing view/writeback contracts. |
| Representation combinations | The existing attribute token tree expresses combined representations; `ProductLayout` records C arrangement independently of the integer tag and records a transparent enum's single logical alternative. Logical variant ordinals remain distinct from physical discriminants. ABI descriptors distinguish logical values from forwarded physical scalar/aggregate types. | Semantics rejects conflicting schemes and validates transparent payload rules. Layout, tag tests, active-field cleanup and C encode/decode share the representation. Transparent forwarding must preserve the payload's actual C ABI, not merely its byte size. Metadata and zero-size cases use the same path. |
| Statics and linkage | Add module static declarations with type, initializer, mutability, visibility, import/export/library metadata and stable resolved identity. Checked facts and typed IR retain that identity. Static storage has an explicit analysis root/lifetime category, never an overloaded caller-parameter index. Initializers use typed, validated constant representations. | Resolution handles imports/shadowing/duplicates; checking enforces required constants, unsafe mutable-static access and no move from static storage. Ownership/region analysis admits static-lifetime references without treating them as caller-owned or scope-owned locals. LLVM emits storage, relocations and linkage with no dynamic hosted startup dependency. |
| Variadic definitions | A checked cursor capability is tied to a variadic invocation. Source signatures and IR distinguish its hidden context from named parameters. Native start/argument/copy/end operations carry requested promoted types and ABI identity. Cursor cleanup uses the same native-action mechanism as guards. | The physical variadic C entry creates the ABI cursor before any logical-body/cleanup callback; an ordinary Mettle wrapper must not try to recover discarded register/stack arguments. Target ABI lowering decodes register/overflow areas and reuses C value classification. Analysis rejects cursor escape/use after end; copying a cursor copies state rather than aliases its advancement. |
| Assembly | Syntax records templates, operand modes/names, register classes or explicit registers, expression/destination identities, symbols, constants, clobber ABIs and options. Checked facts resolve them. Compiler-owned IR keeps resolved constraints/effects and ordered inputs/outputs without syntax pointers. Function/module metadata distinguishes inline, global and naked assembly. | Target-aware checking validates types, features, conflicts and option combinations. Lowering evaluates operands/destination places once in source order, obtains inputs before execution and publishes outputs only on normal completion. LLVM receives validated constraints. Naked physical ABI entries bypass ordinary frame/cleanup/prologue generation; no implicit unwind permission is granted. |
| SIMD and target features | A compiler-owned target-facts record carries the selected architecture/data model, baseline and recognized features. The driver derives it from the explicit target; front-end types/IR do not include LLVM. Stable target-vector descriptors and operation signatures record element/lane shape, alignment and required features. Function features and checked feature predicates are explicit metadata. | Semantics and IR verification check availability under the function/profile or a dominating supported dispatch guard. The LLVM adapter lowers vector/target operations and validates agreement with its target machine. Detection must respect OS register-state requirements and the core/hosted boundary. Scalar intrinsics alone do not satisfy SIMD delivery. |

Shared invariants for the implementation pass:

- Keep current call sites source-compatible where practical by using explicit
  optional metadata/defaults, but never default an unknown target or capability
  to permission. Retain the current qualified host/initial target scope.
- Thread target facts through driver, checking, pipeline and the verified
  program once. Assembly, feature contracts, vector layout and varargs must use
  the same facts rather than independent host guesses.
- Required integer evaluation is checked in every profile and remains
  LLVM-independent. A bounded array/index/count conversion is not a lossy
  integer cast. Preserve selected index contracts; wider scalar support does
  not authorize an implicit numeric conversion.
- A typed constant initializer is validated before emission. Target floating
  representation uses the existing direct-rounding rule, not host `double`;
  global address constants retain symbol/relocation provenance. Full user
  const-function/macro execution remains I09.
- Immutable static bindings containing interior-mutable storage must not become
  LLVM read-only memory. Statics are not automatic scope-destruction roots.
  Linkage and assembly symbol references share resolved identities and target
  name mangling. Do not invent unrelated TLS or process-startup services.
- `Cell` exchange installs the new value before an owned old value is dropped.
  RefCell guards keep the cell alive; payload exclusivity comes from the checked
  runtime guard, not an unsound ordinary mutable loan derived from a read view.
  Forgetting a guard may retain the borrow state but must not enable an alias,
  owner move, invalid reference or dangling guard-counter access.
- The native cleanup-action path must coexist with suppressed MaybeUninit/
  ManuallyDrop payload cleanup, packed relocation, pinned destructors and
  repeated-unwind flags. Guard/cursor release cannot repeat or introduce a
  second, hidden user destructor.
- Assembly outputs and varargs arguments are typed Copy/register or C-ABI
  values as appropriate, not arbitrary managed owners. Register/ABI/effect
  validation is a compiler-owned decision, not a repair left to the assembler.
  Unspecified memory and flag effects remain conservative.
- Required assembly constants retain their typed identity through specialization,
  including full-width arithmetic and named immutable statics. Function/static
  symbol identities use the same physical resolver. Naked physical entries
  cannot be inlined into ordinary framed code or acquire hidden cursor storage.
- Guarded vector calls use storage-only bridges when caller and callee feature
  profiles select different native vector register ABIs, including reverse
  transitions into generic baseline code. A dispatch guard does not change the
  containing function's physical ABI or permit instruction leakage before it.
- Stable architecture-specific SIMD/register interfaces follow the frozen
  target inventory. Do not invent a portable SIMD API or silently promise every
  target/profile operation before I13. A known but unavailable facility gets an
  explicit unsupported diagnostic, not unchecked instructions.

Acceptance fixtures are planned with these interfaces: typed numeric boundaries
and const failures; Cell replacement and RefCell conflict/forget/unwind cases;
conditional/generic Unpin and projected view effects; representation/metadata/
zero-size C probes; static symbols, initialization, visibility and freestanding
objects; C-to-Mettle variadic definitions with cursor copies and aggregates;
assembly operand order, early/late clobbers, options, symbols and naked entries;
and SIMD/feature acceptance, guarded execution and rejection. Reuse
`tests/source`, `tests/backend/machine.py` and its C/C++ callbacks, plus
`tools/test_linux_target.py`. Prepare the Linux freestanding and independent
atomic memory-model/race cases before the source-freeze gate.

Implement shared metadata and its dependent producers/validators/consumers
coherently, with one writer and no builds racing source edits. A shared
representation change invalidates dependent compiler objects and relevant
receipts; it does not justify rerunning unrelated passing test groups per edit.
New files enter `compiler/modules.json` only with their implementation and
component-owned dependencies. No full qualification matrix starts until the
inventory, fixtures and documentation satisfy the source-freeze gate.

### I11 async state-machine interface plan

Status: partial; the awaiting-loop change is verified on macOS arm64
(`async-await-loop-retains-local`, `await-borrow-in-loop`); the parser-combinator
implementation remains in use. `analysis/liveness` computes SSA block-boundary
liveness with phi uses on incoming edges, but does not yet analyze suspended
places, loans or cleanup and is not connected to a coroutine transform.
The current parser path also moves live immutable locals through an awaiting
loop's carried state rather than recapturing them in each step; this does not
enable borrowed locals across suspension.
No coroutine IR, generated poll function or new cancellation path described
below has been implemented or verified. The I11 inventory and the existing
feature diagnostics remain in `implementation-plan.md` section 8.4.

The shared interfaces must be implemented together, not enabled one at a time
for source programs:

- **Syntax and checking.** Preserve async function, closure and block bodies
  and their `await` expressions as syntax, with their original spans. Checking
  records the body result and error, captured input regions, resolved
  `Future.Output` and poll dispatch in side tables. It must create a
  compiler-owned future identity and a usable `Future` implementation before
  checking callers, while keeping the hidden representation behind the
  existing opaque return contract. An async call captures its arguments but
  does not execute its body. The implementation must resolve how generic
  future identities and interface witnesses are declared before CFG analysis
  supplies their fields; the current parser lowering avoids that cycle.
- **CFG and analyses.** Lower the checked body into a typed CFG retaining
  explicit suspension and its resume edge, evaluation order, source scopes and
  source spans. Extend structural verification, initialization, SSA ownership,
  origin and loan analyses to understand that edge before they inspect it.
  Their checked suspension facts must include live loans and their referents,
  partially initialized owned places and cleanup obligations, not just locals
  read after suspension. Values live across the edge, including SSA operands
  and phi-edge transfers, need persistent storage. Symbolic bodies must still
  be checked before specialization; generated concrete CFGs must be verified
  and analyzed again before backend admission.
- **State and pinning.** Form one inline state with captured parameters,
  retained places and temporaries, an active suspension identity and persistent
  initialization/drop flags. A started child future remains in a stable,
  structurally pinned field until its in-place completion or destruction.
  Loans into state storage are created only after the parent has pinned access;
  they cannot escape the parent or authorize moving, replacing or destroying a
  borrowed referent. The generated type must not acquire `Unpin` when its
  state can contain an address-sensitive loan or child. Moving an unpinned
  future before first poll remains subject to its ordinary type rules.
  Transferability must account for captures, retained fields, loans and child
  futures rather than treating the opaque result or executor as a proof.
- **Poll and cleanup.** Generate a constructor, a pinned poll body and
  destructor/cleanup integration using ordinary compiler-owned types and CFG
  operations wherever possible. Poll dispatch resumes the recorded edge;
  pending preserves initialized state and its loans, while ready transfers the
  output and marks completion. Poll after completion must remain memory-safe.
  Preserve the checked loop back-edges, branch joins, typed failure and lexical
  exits rather than encoding them as separate continuation closures.
  Suspension is not scope exit: normal exit and cancellation use the original
  lexical cleanup order, and cancellation destroys only initialized state,
  exactly once. Per-place flags must survive polls, partial moves and unwind;
  an instruction-level liveness set or a suspension tag alone is insufficient.
  The design must account for destructor panics, re-entry and the lifetimes of
  references and referents during cleanup.
- **Pipeline and backend.** Add a backend-independent transform after checking
  the symbolic suspension CFG and before concrete executable admission.
  Transformation must not mutate a published `VerifiedProgram`; revalidate
  its generated constructor, poll and cleanup paths. The LLVM adapter only
  consumes the verified resulting representation and must not infer pinning or
  repair missing cleanup semantics. Introduce module dependencies only with
  their actual implementation. `core.future` remains executor-free and the
  existing optional executor consumes the same `Future` protocol.

Required fixtures cover read and mutable self-borrows, non-Copy locals,
borrowed iteration, nested exits and typed failures, lexical drop order,
cancellation at each initialization state, partial moves and panic cleanup.
Negative cases must reject moves while loans remain live and invalid
cross-thread state at the intended ownership/type phase. Existing unsupported
fixtures must be updated when their cases are implemented, not merely removed.
Until these interfaces, fixtures and documentation are complete, no source-freeze
or I11 qualification gate is satisfied.

## 5. Full-language growth map

These are component responsibilities to instantiate when the relevant milestone
is implemented. Each addition requires dependencies, interfaces, invariants and
tests in the same change.

| Work | Owning components and boundary |
| --- | --- |
| Products, ownership and destruction (I03) | Products/views in `types`; access/source contracts in `semantics`; canonical `places`; loan/move/init/effects in `analysis`; scope elaboration in `lowering`; static plans in `cleanup` |
| Modules, enums, patterns, errors and methods (I04) | `resolution` owns modules/imports; parser families own syntax; semantics owns coverage/effects/default plans; lowering owns guarded binding and typed-failure continuations |
| Generics, interfaces, regions and dispatch (I05) | Declaration-checked bodies, canonical type/region identities, constraint/coherence solver and instance planning; backend consumes instances rather than solving bounds |
| Layout, unsafe operations and C ABI (I06) | Target facts and object layout in `types`, distinct from language type identity; physical ABI lowering in `backend`; unsafe validity checks and explicit intrinsics; target-specific probes |
| Core/alloc/hosted libraries (I07-I08) | Native Mettle modules and minimal runtime contracts, not hardcoded collections or OS calls inside the parser/checker. `alloc` reaches memory only through the `mettle_rt_alloc/dealloc/realloc` hooks (`runtime/alloc.cpp`). `std` reaches the OS through declared libc externs and the shims in `runtime/sys.cpp` (errno, flags, `stat`, `readdir`, `spawn`, sockets, clocks); the panic hook lives in `runtime/panic.cpp` |
| Constants, macros and packages (I09) | Const evaluator over defined IR; hygienic expansion with source ancestry; package graph/build planner outside compiler semantics |
| Threads and async (I10-I11) | Transferable/Shareable/Static are intrinsic properties proved structurally by `semantics/interface_solver.cpp` (`proveConcurrency`), with manual `unsafe extend`/negative `extend X not P` recorded in `interfaces::Database::concurrencyDeclarations`; thread/lock/TLS operations reach pthreads only through the `mettle_rt_thread_*`/`mettle_rt_mutex_*`/`mettle_rt_cond_*`/`mettle_rt_rwlock_*`/`mettle_rt_tls_*` hooks (`runtime/thread.cpp`), while channel selection uses its process-wide generation condition there to sleep without polling. Static TLS descriptors are keyed by their static addresses; TLS values share a per-thread active-key list so thread exit and the hosted main exit destroy them in reverse first-installation order. `std.thread`/`std.sync` and `alloc.arc` are native Mettle modules. `async fn` is lowered in the parser (`syntax/parser/async.cpp`) to `core.future` `defer`/`then`/`lazy`/`Either` state types behind an opaque `some Future` result (also async blocks/closures, hoisted subexpression awaits, tail-branch awaits and early returns); awaits in loops (`core.future.Repeat` over the carried `var` state with a `LoopKind<R>` result witness, `for` via `into_iterator` or a counted built-in range), nested blocks and non-tail branches are lowered the same way (verified); `return`/`?` inside them, `while let` with an await, borrowed `for` sources and a CFG-level coroutine transform remain; `std.task` is the separately selected executor |
| IDE/tooling/incremental (I12) | Reusable in-memory pipeline, immutable inputs/results and revision-bound diagnostics; module/item query boundaries and dependency tracking |
| Additional backends/self-hosting (I15-I16) | Preserve checked/runtime/ABI boundaries; replace compiler implementation/backend without importing LLVM into language representations |

Modules are not packages, compiler components are not Mettle modules, and
syntax extensions are not a public plugin system. Keep these identities distinct.
The language remains the complete agreed V1 scope; future placement is not
permission to remove capabilities.

## Source spans and debug information

Every IR instruction, terminator and function (`ir::Function::span`, set by
lowering from the declaration, closure or default body) carries one source
`Span`; IR transforms and generic instantiation copy it. Spans are LLVM-free.
Only the LLVM adapter (`backend/llvm/debug.*`, active under the driver's `-g`)
turns spans into `DILocation`s with line tables built from the loaded sources,
and builds `DISubprogram`, `DILocalVariable` and type metadata (layout offsets
come from `types/layout.h`). The driver supplies the diagnostics provenance
mapping: copied text retains its source offset and macro-produced tokens use
the invocation span. Closure environment fields use captured place names.
Type names use dotted display paths and instantiated TypeStore names.
Length-bearing views expose `data_ptr` and `length`; erased views expose their
data pointer, alignment and witness fields. Sums use a discriminator and
per-variant payload structures in a DWARF variant part; offsets come from the
compiler layout, including overlapping payloads. A final pass drops locations
that would not verify. Without `-g` the adapter emits no metadata. These
changes are implemented but not yet built or verified.

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

Module assembly takes an explicit source provider. The driver supplies canonical
file identities and filesystem reads; the in-memory pipeline supplies a source
catalog and never consults the filesystem. Each original source keeps its own
source identity and byte spans through diagnostics and lowering. External module
discovery requires exactly one candidate, and rejects repeated canonical file
identities rather than synthesizing duplicate module instances.

The loader also mounts the native libraries `core`, `alloc` and `std` from a
library directory (`<dir>/<name>/module.mt`). The driver defaults it to the
source-tree `library/` (a CMake definition) and `--library-dir` overrides it;
the in-memory pipeline passes a directory prefix and supplies the files in its
catalog, so no filesystem access is added. A root is mounted on demand, only
when the loaded program (or an already mounted library) names it by a
`core.`, `alloc.` or `std.` path: `core.x` mounts core only if `x` is declared or
re-exported by `library/core/module.mt`, so compiler built-ins such as
`core.ptr`, `core.mem` and the by-path interfaces needed by tests never pay
for library loading. Text literals reference `core.text`. Detection is lexical
and may over-load but never under-loads. Mounted roots are ordinary modules with
their own source identities, so diagnostics point into library files and bodies
are fully checked. A user root module with the same name shadows the library
(freestanding and test setups define their own `core`); library and built-in
`core` submodule names must not collide. Layering is enforced structurally:
`core` may not name `alloc` or `std`, `alloc` may not name `std`. `std` is
rejected in `--freestanding` builds; `core` and `alloc` are accepted.

## 7. Target and backend independence

Language type identity is distinct from physical layout. The `types` component
owns explicit target descriptions for widths/endianness/features and separate
`ObjectLayout` results; the LLVM adapter owns physical ABI classification and
maps checked operations to LLVM. It cannot
invent lifetime, aliasing or overflow assumptions. The module data layout is
taken from the LLVM target machine, and the driver verifies that the
compiler-owned scalar and pointer sizes/alignments agree with it before
lowering; the two must not silently diverge. Executable output validates
runtime/link availability for the target before code generation.

Normalization interns derived product records instead of rewriting shared
nominal definitions under a caller's substitutions or interface assumptions.
Erasing regions preserves those normalized field identities. Pipeline admission
also preflights the compiler-owned cleanup plan, so its resource limits are
source diagnostics during both checking and building, not backend failures.

Keep LLVM headers/libraries in the LLVM backend and its driver integration.
The current adapter implements the specified scalar arithmetic profiles;
resource panic/unwind lowering consumes explicit scopes and static cleanup plans,
then emits native runtime callbacks and per-frame flags.

Backend-neutral semantic/ABI operations are the replacement point for V1.2,
not an LLVM wrapper interface claimed to be a universal backend API.
Do not implement speculative plugin loading or a second backend now.

## 8. Runtime, libraries and tools

`library/core` requires no allocator, OS or executor (`library/alloc` and
`library/std` are currently root stubs without implementations). `library/alloc` depends
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

Package resolution/build planning (`packages`, planned before compilation and
handed to the loader as `Library::packages` mounts; failures carry the
`manifest`, `package`, `lock` or `feature` phase), documentation, formatting and editor protocol
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

Current realization (2026-10-29): sixteen components have actual source owners
and distinct CMake targets. The former combined syntax/IR files and frontend
archive are replaced by the components above. The boundary suite checks actual
IR rejection, dominance/phi handling, independent initialization analysis,
checked-tree move/lifetime behavior, immutable source spelling, in-memory UTF-8
validation and rejection before a verified program can be published.
Dependency regressions reject cycles, unknown edges, unowned files, private
header access and LLVM leaks.

Historical I03 qualification passed twelve CTest suites in each ordinary configuration and
thirteen under ASan/UBSan, with byte-identical clean rebuilds and ordinary/instrumented
quality receipts. The instrumented quality gate analyzes all owned C++ translation units.
Frontend/IR/analysis compilation
does not receive LLVM include paths, and the standalone boundary-test executable
has no LLVM symbol dependency. Both ordinary builds cross-emit objects for
the scalar/product/ownership source executions, two foundation smokes and native
cleanup/recovery probes on Linux. Per ordinary compiler build, the Linux runner
executed 134 source/profile cases, six cleanup probes and the foundation smoke;
identity guards bound those results to that milestone's source, compiler, runtime and generators.
Evidence remains under `build/macos-arm64/`, `build/quality/` and
`build/linux-target/`; none of this claims the future components implemented.

Current I05 qualification (2026-10-29) passes fourteen ordinary CTest suites and
fifteen under ASan/UBSan, including the independent detector probes. Ordinary and
instrumented static analysis and fast quality pass. All three native clean
rebuilds are byte-identical. Each ordinary compiler passes 316 Linux
source/profile cases, six cleanup cases and the foundation smoke; source,
compiler, runtime, tool and artifact identities are checked.
`build/i05-qualification.json` records the evidence and any separately checked
documentation-only completion update. This qualifies the macOS ARM64 compiler
host and Linux x86-64 target, not a Linux compiler host, public ABI or runtime parity.

## F-string lowering

The lexer emits `FormatOpen/Piece/HoleOpen/HoleClose/Close` tokens; the parser desugars an f-string into a labelled call chain `core.fmt.message(read [field(hole, piece)...], tail)` (labels `f-string`, `f-string-internal`). The checker (`calls.cpp`, `expressions.cpp`) confines these nodes to `format` argument positions; no new AST kind, IR or backend work.

Cross-branch inference: a generic call at the tail of an `if`/`else` or `match` arm without an expected type (or an argument of such a call) may leave generic arguments open (`if c { left(a) } else { right(b) }`). `Checker::genericCall` then defers its errors and obligations (`deferredCalls`); `joinDeferred` merges the arm types structurally (`mergePartial`) and `finishDeferred` completes the bindings from the merged type, recomputes the call facts and refines its arguments top-down before the ordinary join. Arguments still open are reported as before.

A hole's type is checked through the `core.fmt.Hole` bound of `core.fmt.field`: one blanket library implementation covers every sized `Display` type and `Text` has its own; when the bound fails, `Checker::interfaceObligation` reports a dedicated "cannot fill an f-string hole" error instead of the generic obligation message.

Dotted-path resolution and generic application (grammar section 13; parser and checker behavior verified): the parser applies the syntax-only generic-follower rule, including for `a<b>(c)`. A dotted expression chain stays a syntax-only `Field` chain; `dottedPath` (`syntax/ast.h`) flattens such a chain. The checker decides field versus qualified path in `Checker::qualifyDottedPath` (`semantics/names.cpp`), called by the `controlFlow` pre-check walk (which tracks lexical bindings) and over static initializers, before flow analysis and the call graph so both see the qualified call target: a lexically bound root is a value and keeps its field/method meaning (a local named like a type or module shadows it); otherwise the longest prefix whose leading segments are modules, types, interfaces, `Self` or generic parameters is resolved as a path (per-segment generic arguments map to `ownerGenericArguments`/`genericArguments`), and remaining links stay `Field` accesses. This is the one deliberate in-place syntax rewrite, done before any checked fact exists. The library loader also mounts a library root named by `core.x`/`alloc.x`/`std.x`.

`lint/lint.{h,cpp}` implements `mettle lint` (implemented and verified on macOS arm64; test `lint_reports_semantic_findings`): the driver compiles through `pipeline::compile` with a checked-module observer, so a lint run reports every front-end and ownership error first; findings are produced only when compilation succeeds. Rules (`unused-binding`, `unused-mutability`, `unused-import`, `unreachable-code`, `unused-outcome`) read `CheckedModule` facts (`find` accessors, `exclusivePlace`, `flow`, closure captures) and `Resolution::importUsed`; `Diagnostic` carries a severity so findings print as `warning[rule]` or, when denied, `error[rule]`. The driver filters out library, dependency and generated-source spans.

`syntax/fingerprint.{h,cpp}` provides the syntax-tree fingerprint used by formatting checks. `syntax/format.{h,cpp}` is the token-based formatter behind `mettle fmt` (verified): it lays out lines from the lexer's tokens (indentation from bracket nesting, normalized horizontal gaps, collapsed blank lines, no line break added or removed) and returns text only after re-lexing it and proving the same token sequence, the same fingerprint and idempotence; it has no LLVM or semantic dependency and the driver owns file I/O (atomic replace, `--check`) and passes declarative-macro expansion as the parse hook.
