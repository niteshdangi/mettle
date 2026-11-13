# Compiler, runtime and library architecture

Normative component and phase contracts for the full language. Future components
are responsibilities, not delivered features. Implementation/qualification scope
is tracked in [implementation-plan.md](implementation-plan.md).

## 1. Repository and component boundaries

Keep one repository for the compiler, first-party runtime/libraries, tools and
tests. These share language contracts and must evolve atomically. Packages
compiled by Mettle are not C++ compiler components. A separate repository is
justified by an independently owned/released product, not by folder size.

`bootstrap/` contains the C++ seed/reference compiler. `compiler/` contains the
Mettle implementation. Compiler packages use `src/main.mt` as their default
entry, with imports loading supporting modules; no separate library aggregator
is required. `kind: "library"` marks source packages that provide dependency APIs;
entry maps can pair that library with named executables. The package planner
owns manifest/version/entry validation; the driver selects requested artifacts
and publishes outputs; the LLVM adapter suppresses hosted entry wrappers for
libraries. Runtime archives are position independent for native shared output.
The component table below describes the C++ bootstrap.

The current compiler targets and direct link dependencies live in `CMakeLists.txt`.
CMake discovers sources within each component directory. Include isolation,
public-header use and the LLVM boundary are reviewed at source level; target
dependencies alone do not prove them.
The design below also identifies later components; do not create empty targets
for them.

| Component | Owns | Must not own |
| --- | --- | --- |
| `support` | Named compiler resource limits and small domain-independent facilities | Language types, compilation state, a miscellaneous service locator |
| `source` | Original source bytes, spans and encoding validation | Diagnostics policy, AST or filesystem command orchestration |
| `diagnostics` | Structured failures and source rendering | Parsing/recovery decisions or process exit |
| `syntax` | Tokens, keyword/operator metadata, lexer, parsed AST and parser/recovery | Resolved bindings, inferred types, CFG slots, LLVM |
| `expansion` | Attribute validation, `@cfg` target/feature predicate evaluation (inactive items are parsed but dropped before resolution), `@derive` generation of ordinary `extend` declarations as separately registered generated sources with span provenance back to the attribute and offending field/variant; test/benchmark collection and harness synthesis (`harness.cpp`: in a test build, the selected package's `@test`/`@bench` functions are recorded with qualified module paths, the root `main` is dropped and a synthesized harness entry is loaded beside it; each test then runs in its own process); declarative macro expansion (`macros.cpp`, token-level, before parsing; qualified lookup and explicit/grouped macro imports resolve through an injected loader callback, public imports become macro reexports, and macro declaration syntax facts are retained for resolution; the loader owns source discovery; generated tokens retain definition-site hygiene, template/argument provenance and invocation spans) and the procedural-macro protocol (`procedural.{h,cpp}`: versioned request/response encoding and parsing; `macros.cpp` calls an injected host callback, re-lexes its text output and attributes the tokens to the invocation, and never starts a process itself) | Name resolution, type checking, LLVM |
| `documentation` | `mettle doc` and doctests: documentation extraction from the lexer's comment tokens (`///` item docs, `//!` module docs, declaration headers as written, visibility filtering, `document.cpp`), reduced markdown blocks (`markdown.cpp`), fenced-example classification and generated `@test` functions (`doctest.cpp`) and deterministic dependency-free HTML (`html.cpp`). Resolved-reference rendering accepts canonical identities from the driver; the static search index remains deterministic. | Performing name resolution, type checking, filesystem I/O, process execution, LLVM |
| `resolution` | Compilation-local module identities, distinct type/value/module/macro namespaces, item/import scopes, package alias mounting, `pub(path)` visibility boundaries and canonical declaration names; source-provider-driven module assembly | Inference, backend types or filesystem I/O |
| `packages` | `.mettle` data parsing, `package.mettle`/`lock.mettle` validation, SemVer requirements, dependency solving with features over path, local-registry and Git sources, checksums, the package build plan (mounts, build scripts and macro programs handed to the driver) and the content-addressed build store (`store`) | Source parsing, semantics, network access or artifact publication |
| `types` | Compiler-owned language type identities/operations, source-oriented diagnostic type display, target facts and target-layout results | Parsed AST, LLVM types/target machines, toolchain state |
| `metadata` | Versioned logical type/region graph encoding, bounded validation and transactional remapping into consumer stores | Source checking, cache/filesystem policy, executable admission, LLVM |
| `consteval` | Pure target-aware compile-time interpreter over syntax: scalar/aggregate values at the selected target's integer widths, `const fn` calls, control flow, step/depth budgets (`error[limit]`); names and diagnostics come from a host interface | Name resolution, checker state, LLVM, host-width arithmetic |
| `places` | Function-local storage roots, typed field paths and structural overlap | AST traversal, CFG control flow, mutability/loan policy |
| `semantics` | Lexical resolution, module-resolution consumption, inference, flow facts and checked syntax | LLVM, code emission, filesystem/linker side effects |
| `ir` | Typed CFG model, structural/type/SSA verification and inspection | AST traversal, ownership policy implemented in a printer, LLVM |
| `lowering` | Checked syntax to typed CFG with explicit evaluation order | Accepting unchecked AST or invoking the linker |
| `analysis` | CFG initialization/moves, view origins, call/destructor effects and loan liveness | Mutating the parsed tree or inferring semantics from LLVM |
| `instances` | Canonical concrete function planning, type/const substitution, callable ABI adapters and const-array repeat/iteration expansion | Rechecking source under stronger instantiated ownership rights or selecting LLVM representations |
| `cleanup` | Static owned-place flag hierarchy, lexical/unwind cleanup plans and ordering | LLVM types, per-object runtime registration, region inference |
| `lint` | Semantic lints (`mettle lint`) over a checked module's side tables: unused bindings and `var`s, unused imports (recorded by `resolution` lookups), unreachable statements (checker flow summaries) and ignored Outcomes; level selection (flags, function attributes) | Mutating syntax, re-resolving names, LLVM, printing or exit policy |
| `pipeline` | Backend-independent compilation entry points and stage ordering; verified symbolic declaration preparation, specialization and concrete admission; a read-only observer of the checked module before lowering | CLI parsing, output publication, package downloads |
| `lsp` | `mettle lsp` language server: JSON-RPC/LSP framing over streams (`server.cpp`), a self-contained JSON reader/writer, UTF-16 position mapping, a token-based declaration/occurrence index that works on incomplete source (`symbols.cpp`), completion/signature help (`server.cpp`/`symbols.cpp`) and definition/reference/hover/rename planning (`navigation.cpp`); diagnostics and read-only checked facts come from the real front end (`resolution::load` + `pipeline::compile`) run on in-memory documents | LLVM, file I/O (the host supplies a source provider), process lifetime, checked-IR publication |
| `backend` | LLVM adapter, target-machine setup, optimization and object emission | Discovering unresolved names/types or deciding ownership |
| `driver` | CLI, inspection serialization, Git source fetching (system `git`), source loading, build-script and procedural-macro execution (`procedural.cpp`: host build, process run, reproducible-result reuse; `observe.cpp`: declared-input state shared with build scripts), cache-key assembly and lookup, artifact publication and native link invocation, `mettle run`/`test`/`bench` execution (`execute.cpp`: temporary builds, per-test process spawning and optional timeout, human/JSON result reporting, and doctest builds that overlay generated tests on package module sources and judge `compile_fail` examples from captured diagnostics) and `mettle doc` (`document.cpp`: package graph/name-resolution orchestration, path discovery, parse validation, warnings and output files) | Typing, inference, borrow rules or dataflow algorithms |

Components are build/link units, not processes or public plugin APIs. Public
headers expose the minimum boundary; algorithm context and mutable state stay
private. Trivial file splits, line limits and directory counts are not quality
criteria.

The package planner retains authoritative instance and checkout provenance.
The driver alone materializes and locks writable host/target package views for
host-tool execution, preserving relative paths while leaving verified Git
sources immutable. Physical remapping does not change graph, lock, cache-routing
or semantic package identities; generated sources inherit the declaring
instance. No component dependency or public ABI changes are required.

Conditional lists are source-owned `ConditionChain` nodes containing `Condition`
clauses. Checking owns sequential binding scope, bool/pattern requirements and
region facts; lowering emits existing branches, pattern operations and scope
exits. It must not duplicate an else body or let failed-chain bindings escape.
Each header scope owns its temporaries through later clauses and the body;
failure and loop exits clean up initialized values exactly once. Const evaluation
uses the same short-circuit and scope rules. `Outcome<T, E>` maps to the existing
native Outcome type and IR; parameter access remains declaration metadata,
separate from its payload type. No component target, dependency or runtime ABI
changes are required.

Floating constant evaluation uses a per-compilation numeric callback, injected
by the driver through the backend-independent pipeline and checker (including
LSP compilations). `types` owns its scalar interface and exact binary32/binary64
IEEE-bit carrier; the carrier is mutually exclusive with decimal text and is
invalid for integer values. `backend/llvm/numeric` owns target software
APFloat/APInt folding, without host floating arithmetic or libm. `consteval`
owns contextual types, stable-const admission, source function frames, byte
arrays and target endianness; semantics owns method/type/variant resolution and
typed static materialization. IR verification validates the carrier before LLVM
lowering.

Integer constant methods reuse `types`' 128-bit magnitude arithmetic and native
machine signatures; `consteval` owns aggregate results, target byte order and
provenance-checked mutable writeback. Typed throws propagate as interpreter
control flow through calls and loops. Capture handles only typed errors, never
evaluation faults; checked semantic facts distinguish Outcome propagation.
Nominal error construction and patterns select the active variant's fields,
including named payloads and empty variants in payload-bearing enums.

Constant pointer operations use target layouts and allocation-relative offsets,
not host addresses. Raw byte transfers retain initialization and pointer
provenance; typed reads validate the reconstructed value. Unaligned operations
relax only alignment, overlapping copies snapshot their input, and writes require
exclusive writable provenance. Empty accesses still enforce alignment; a
zero-sized operation does not manufacture allocation authority.

The evaluator's host supplies checked expression shapes and inferred function
results; evaluation does not independently re-infer integer locals.
Function and static identities are registered before header elaboration.
An early constant requesting an inferred result checks the declaration and its
dependencies through ordinary inference, preserving the caller's checking
context. Referenced static headers resolve lazily with cycle detection;
prechecked bodies and resolved signatures are reused by the ordinary pass.
Static initializers containing lazy control flow are checked through temporary
function contexts borrowing their existing syntax. These contexts are removed
before publishing the checked module; the parsed static owns the syntax
throughout. Type checking visits dead branches, while evaluation remains lazy.
No component target or dependency changes are required.

Constant aggregate views retain evaluator storage provenance, byte offsets and
slice extents, never host addresses. `semantics` supplies concrete target shapes,
generic bindings and selected interface implementations, including implicit
receiver projections; the interpreter preserves parameter access, const/unsafe
admission and storage lifetime. Views of expired locals cannot become statics.
Raw-pointer casts use the existing machine cast contract and retain backing
storage, offsets, extents and writable provenance independently of pointer
mutability. Cell/UnsafeCell constants use their single offset-zero payload;
Cell projection retypes the live address without creating replacement storage.
Static constant-call owner probes retain explicit owner arguments.
`types::StaticConstant` carries static-symbol interior relocations and
address-only empty/zero-sized pointers. `ir` validates their target alignment,
extent, metadata and mutability before `backend` lowers them. Library checked
expression descriptors preserve symbolic shapes for concrete call preparation.

Literal byte roots are owned by the evaluation host; interpreter references stay
non-owning and retain immutable provenance even through mutable pointer casts.
Literal-backed static views preserve the complete backing bytes, interior offset
and explicit extent rather than copying a substring. `types::textConstantCount`
shares their shape/extent validation between checked archives and IR admission;
LLVM materializes interior addresses into the complete interned literal.
This representation uses IR format 3 and checked-library contracts 6; older
archives must be rebuilt.
Checked expressions retain interface dispatch identities and Outcome propagation
so imported const bodies select concrete implementations and typed effects.

Concrete nominal associated constants retain typed `StaticConstant` payloads
through checked library contracts. Each expression constructs a fresh value
with its own cleanup ownership, rather than moving from shared static storage.
Required projections preserve field visibility and evaluator storage lifetime.
Region normalization decorates nominal arguments and associated bindings in
source interface bounds before expanding their inherited obligations.
Associated implementation bounds are proved after nominal region decoration,
inside the implementation/family region environment; method contracts are
prepared earlier so the region pass can validate them.

### 1.1. Self-hosted compiler: package and incremental compilation contract

The self-hosted compiler uses independently compiled Mettle packages in
`compiler/`. Modules control source organization and visibility; packages control
dependency/API boundaries; declaration queries and code-generation batches
control rebuild work. A package is not an indivisible recompilation unit.
The C++ component table above describes the bootstrap implementation; it does
not prescribe one Mettle package per C++ component.

| Package (`mettle-` prefix) | Owns | Direct compiler-package dependencies |
| --- | --- | --- |
| `foundation` | Source snapshots, spans, diagnostics, identifier/storage primitives | None |
| `syntax` | Tokens, lossless parsed syntax and recovery | foundation |
| `types` | Language types, region identities, target facts and layout contracts | foundation |
| `ir` | Typed CFG, places, structural verification and serialization model | foundation, types |
| `frontend` | Expansion, resolution, constants, typing, interface/region solving and checked facts | foundation, syntax, types |
| `middle` | Lowering, ownership/dataflow, cleanup, instantiation and language optimizations | foundation, syntax, types, ir, frontend |
| `pipeline` | Revision/query ownership, dependency tracking and verified compilation entry points | foundation, syntax, types, ir, frontend, middle |
| `packages` | Manifest/lock resolution, build graph and bounded artifact store | foundation |
| `backend-llvm` | LLVM lowering, optimization, object/debug/unwind emission and physical ABI | foundation, types, ir |
| `editor` | LSP, documentation and lint presentation through shared compiler results | foundation, syntax, types, frontend, pipeline |
| `driver` | CLI, source providers, execution, build scheduling, linking and publication | foundation, syntax, types, ir, pipeline, packages, backend-llvm, editor |

These dependencies are acyclic and explicit in package manifests. Library and
runtime dependencies retain their existing layer rules. Add packages when their
implementation starts; do not create empty packages. `frontend` retains separate
resolution/checking/solver modules; `middle` retains separate lowering/analysis/
cleanup/instance modules. Their APIs use typed IDs and compilation-owned stores,
not mutable cross-package pointer graphs. CLI/editor share an in-memory pipeline;
the driver injects filesystem, process, macro-host and numerical services.
LLVM handles and foreign calls remain inside the backend adapter.

**Independent compilation.** Each package publishes an indexed, versioned binary
interface and native object batches. Interfaces contain resolved exports, access/
region/effect contracts, required layout/drop facts, implementation-selection
metadata, and verified symbolic IR for generics, constants and cross-package
inlining, including referenced private support definitions. Consumers do not
reparse or recheck unchanged dependency source. Persist logical definition/type
identities and remap them into local stores; never serialize pointers or local
indices as cross-build identities. Validate imported lengths, references, types,
format/compiler compatibility and content hashes before admitting cached IR.
No stable public metadata ABI is promised.

**Invalidation.** Separate syntax, declaration/signature, body checking,
ownership, specialization, optimization, object and link results. Queries record
the facts actually read, including name-lookup failures, visible implementation
candidate sets, cfg/features, macro inputs and relevant target facts. Changed
inputs re-evaluate their dependents; unchanged result fingerprints stop further
invalidation. A private body edit does not recheck consumers unless they depend
on that body or its derived facts. Layout, constants, generics and inlining are
dependencies even when an exported function's spelling/signature is unchanged.
Content hashes establish equality; timestamps may only accelerate discovery.
Diagnostic/source-map identities include source revisions even when executable
code is reusable after a comment edit. Unknown dependencies invalidate
conservatively; failed or incomplete analyses never become successful artifacts.

**Compilation and optimization.** Check generic bodies once under declared
contracts, retain symbolic verified IR, then instantiate and reverify concrete
forms. Contextual `Sized` bounds travel with checked declarations and symbolic
IR; verification must not turn them into global type capabilities. Concrete
instances discard these assumptions and reverify their substituted storage.
Canonical instance ownership includes definition, substitutions, target
and codegen policy; consumers share identical instances. Check mutually dependent
declarations as strongly connected groups. Schedule independent queries with
bounded workers and memory, using compact stores and releasing temporary phase
data. Batch code generation by package with deterministic bounded partitions;
do not create a file/cache entry per function. Normal builds support independent
objects in both profiles. Cross-package optimization is explicit and optional;
its additional dependency edges participate in invalidation. The future native
backend consumes the same verified concrete IR through the pipeline boundary.

**Storage.** Use one content-addressed, deduplicated store with the existing
512 MiB default cache budget and configurable limit. Interface/query/object data
share that budget; do not retain complete compiler heaps, duplicate syntax trees
or full historical generations. Evict recomputable unused entries and reclaim
unreferenced blobs; a missing/evicted entry changes work, never behavior. Active
builds protect their inputs; temporary/live excess is reported and pruned after
release, rather than claiming an absolute bound on live working storage. Account
for package sources, outputs, debug data, linker scratch and temporary/cache
bytes in build-storage measurements even where they are outside the cache cap.
Clean builds must remain usable without a warm store.

**Bootstrap and acceptance.** The current C++ compiler reuses eligible debug
dependency objects after whole-program checking and the checked native-library
units described in section 1.2. It may build the seed compiler from package sources.
Independent interface loading/query reuse must be implemented in the Mettle
compiler before its build architecture is declared complete. First validate
cross-package calls/generics/cleanup and clean-versus-incremental behavior,
including private/API/implementation-set edits, eviction and corruption; then
build stage 1 with C++, stage 2 with stage 1 and stage 3 with stage 2, recording
input identities and comparing behavior and reproducible artifacts. Measure
clean and edited build time, peak memory, total retained bytes and generated
program runtime separately under the existing performance protocol. Package
boundaries or self-compilation alone establish no performance or safety claim.

### 1.2. Approved bootstrap compiled-interface work

The owner permits the C++ bootstrap work needed for this reusable boundary;
this is not permission for unrelated bootstrap tuning or a test-only cache.
The first delivery must reuse checked `core` across different consumers.
`alloc` and `std` follow through the same format and import path. The format
must remain implementable by the self-hosted compiler; no public metadata ABI
stability is promised.

Native interfaces are dependency-closed units: `core`, `core` plus `alloc`,
or the hosted `core`/`alloc`/`std` closure. Each unit keys every included source
and dependency identity. Loading a larger closure replaces smaller compiled
headers before resolution; it does not append duplicate declarations or mix
type stores. User-shadowed dependency roots disable that closure's compiled
provider. Code generation still partitions eligible objects by native root.
The same bounded store owns all units; source compilation remains the fallback
when a closure cannot be snapshotted. This is a bootstrap packaging boundary,
not a self-hosted package ABI or permission to add OS dependencies to `core`.

The compiler-owned interface model separates exported declarations/contracts
from verified symbolic IR and referenced private support definitions. Persist
logical package/definition identities and structural type records, not C++
objects, pointer graphs or compilation-local IDs. Readers remap references into
consumer-owned stores and validate lengths, tags, references, compatibility,
content identity and IR before use. Source revisions and source maps remain
available for diagnostics. Constants, default arguments, macros, associated
families, regions, implementation selection and cleanup are dependencies, not
exceptions to the import contract.

The frontend imports declaration/type/region/effect/implementation information
without parsing or checking dependency bodies. Interfaces retain separate
pre-region checking and finalized region implementation databases. Consumer
body checking imports the former; region validation restores the finalized
imported prefix while preserving consumer declarations. Regional implementation
targets must not enter nominal receiver selection before that phase boundary.
Finalization decorates both the implementation target and its interface
arguments in the same declaration-region context.
Imported implementation-owned callable bounds still populate consumer region
context; only target decoration and dependency contract rechecking are skipped.
The pipeline combines imported
symbolic IR with newly checked consumer IR, resolves new instantiations and
performs the required concrete verification. Existing constant evaluation must
be able to consume imported constant bodies before those exports are eligible
for reuse. The backend consumes only admitted IR and emits independently
linkable objects in both profiles; no cross-package optimization is implicit.
Cache eligibility must not silently erase any of these obligations.

The constant evaluator accepts either an existing source declaration or a
checked callable descriptor with resolved parameter/result shapes and borrowed
expression storage. Both paths use the same interpreter, target arithmetic,
default evaluation, unsafe checks and resource budgets. This removes the
source-body requirement from constant calls. `semantics/library` owns the
portable checked-expression arenas, resolved facts, declaration contracts and
header codec. Imported calls retain the source path's declaration eligibility
checks; importing a runtime-only declaration does not make it const-callable.
Const eligibility precedes body availability, since runtime-only imported
declarations intentionally have no constant-expression body.

Expansion can export and import complete indexed macro inventories with private
support rules, imports/reexports, hygiene and token provenance. Logically equal
overlapping inventories deduplicate; conflicting module inventories reject.
The loader exports each source inventory to the host, which merges them through
the same expansion validation instead of replacing earlier modules' exports.
The host validates compiler/configuration/dependency identities and remaps
revision-qualified sources into receiving diagnostics, restoring source bytes
and generation provenance. Compiled rule mounting does not lex dependency
source. This boundary alone does not establish whole-library reuse eligibility.

`pipeline::prepare` seals symbolic IR only after declaration verification,
initialization and loans. Its move-only `PreparedProgram` retains the language
type store and implementation database, not the checked syntax tree.
`pipeline::compile` consumes this state for specialization and concrete
admission; ordinary source compilation uses that same path. This in-memory
boundary does not bypass metadata validation or supply a persistent interface.
Prepared state also retains successful loan-effect summaries. After
specialization, exactly unchanged functions reuse initialization results;
loan results are reused only when the function and its transitive callees
are unchanged. Static-storage users are conservatively reanalyzed. Type IDs
retain their analysis meaning across the specialization store copy; destructor
symbol remapping does not change those facts. New specializations, changed
bodies and consumer-dependent calls are analyzed again. Concrete structural
verification and cleanup planning still run for every function.

`metadata::exportTypeGraph` and `importTypeGraph` encode semantic type/region
records with logical definition/package/symbol references. Imports stage a
candidate store and commit only after validation; archive references never
become cross-build IDs. Structural types remain canonical with existing and
future consumer-created types, and region ancestry/binders remap consistently.
The host resolves logical function/interface/package identities without
mutating the destination during import. Closure ordinals use a separate symbol
domain from source function IDs; static identities have their own domain.
The bootstrap metadata component depends on `types`, `source` and `support`,
not the frontend or LLVM. Declaration/expression encoding belongs to semantics;
symbolic-body encoding belongs to IR. Their shared references use the same
artifact-local type roots and logical symbol domains.

The driver-owned library archive retains revision-qualified source snapshots,
generation mappings, syntax-context binder groups and source-module scopes.
Wire source references are archive-relative; mounting allocates fresh IDs and
restores provenance before imported declarations or macros use it. The envelope
checks format, expected compiler/content/configuration identity and a SHA-256
checksum; its sections still require their owning semantic decoders.
Library discovery snapshots source bytes and the module inventory, including
in-root source links, rather than trusting timestamps. Links outside the
declared library root make that snapshot ineligible; the driver reports the
reason with `--explain` and uses ordinary source compilation. Compiler, target,
profile, checks, features and declared dependency identities participate in its key.
Each native root is scanned and content-hashed once per coordinator snapshot;
larger closures reuse those captured dependency bytes and keys, not filesystem
timestamps or process-global source caches. Archive section decoding avoids
intermediate payload copies, and source mounting remaps provenance without
copying the immutable source-text inventory.
The checked-library coordinator connects these sections through lazy native
providers and a post-resolution pipeline importer. Unused native roots are not
prepared, and user roots retain shadowing priority. Imported declarations and
bodies still pass ordinary specialization and concrete admission.
Preparation preserves already-normalized imported bodies when adapter lowering
has not changed them; imported IR still undergoes structural/type verification,
initialization and loan analysis before sealing consumer preparation. No
serialized analysis result is accepted as an executable-admission proof.
Native object keys include the actual lowered partition and its symbol
references; differing consumer generic instances remain consumer-owned. Native partition verification
failures stop compilation rather than silently switching emission paths.
Coroutine frames use logical body identities. In split emission their body and
unwind callbacks have hidden external linkage, and only the partition owning
the coroutine body emits those definitions; layout-only users emit declarations.
Cold source failures retain their original phase, source spans, related notes
and generated-source provenance when forwarded into consumer diagnostics.

Use the existing content-addressed store, lease/publication/corruption handling
and shared storage budget. Interface/object identities include compiler and
format compatibility, dependency content/facts, target, features, macro inputs
and relevant codegen/runtime policy. Visible implementation-set changes and
failed name lookups participate in invalidation. Unknown dependencies cause a
reported conservative miss; failed checking never publishes a success artifact.
Corrupt or incompatible data is reported and rebuilt, never treated as proof
that a package is valid.

Core-first completion requires two different consumers to reuse one checked
core interface and eligible native objects. Tests must distinguish that from
whole-program cache hits and from merely reusing an object after rechecking
core. Focused acceptance covers clean/warm equivalence, generics, constants,
regions and cleanup, implementation/API/private-body edits, target/profile/
feature changes, corruption, eviction and concurrent publication. Reused
unchanged work and newly required instantiations must be distinguishable in
the evidence. Record cold/warm time, memory and retained bytes; make no speedup
claim before measurement. Runner changes alone do not complete this scope.

## 2. Syntax and checked representations

Source is immutable for a compilation. Tokens retain exact original text and
byte spans, including trivia. A parsed node owns only syntactic information:
kind, children, spelling, annotations, separators and provenance. Type variables,
resolved locals/callees, normalized values and flow facts do not belong in AST
nodes.

The Mettle lexer seed stores token kinds and spans into caller-owned UTF-8
source bytes, without allocating a text string per token. Literal decoding
consumes slices of that validated source; the source owner retains the bytes
while syntax consumers use their spans.
Identifier recognition uses the compiler's pinned Unicode 16.0 XID tables,
independent of the character library's Unicode version. `Token.identifier`
returns NFC bytes on demand, stripping backticks while preserving token/source
spans; the lexer stores no normalized string per token. Canonical decomposition
is pre-expanded in generated data, Hangul is algorithmic, and out-of-order
nonstarter runs use stable counting sort before blocked canonical composition.
`tools/identifier_tables.py` verifies UCD input hashes and reproduces the tables.

The native parser owns the unchanged token list and contiguous node/child-ID
arenas. Nodes carry source/token ranges, an optional operator-token index and
the explicit-semicolon flag; semantic facts remain separate. A reusable child
stack avoids allocating a vector per node. Recovery rolls back incomplete arena
entries before adding an error node, preserving later valid syntax. Comment
newlines are exposed by the cursor without copying or splitting lexer tokens.
Consumers must reject diagnostics or a missing root before semantic compilation.
Structural type nodes retain grouping, ownership/access, optional nesting and
source annotations. Pointer closers and optional suffixes may consume part of
a symbol token through cursor offsets; the original token and its span remain
unchanged, while each node ends at its consumed source position.
Application lookahead caches rejections by opening-token index and newline
suppression context in a lazy bitset. Reusable angle/delimiter stacks exclude
nested expression delimiters from angle matching. A candidate uses the shared
type-argument parser; rejection restores cursor, arenas and diagnostics before
comparison parsing. Failed outer lookahead must preserve viable inner applications.
Generic type arguments retain their type/constant/region form and associated
binding syntax. Callable types retain region binders, modifiers, parameter
access, result and error-effect nodes; grouping controls effect attachment.
Reinterpreting a named argument as a constant expression rolls back its syntax
arena entries before reparsing. Generic expression boundaries are cursor state
and are restored during recovery.
Function declarations retain visibility/modifiers, generic parameters, defaults,
bounds, where constraints and effects as syntax nodes. Generic expression
applications retain their receiver and type/constant/region arguments separately
from runtime call arguments. Expression bodies retain their arrow-token index.
Inline module declarations own nested item bodies rather than flattened scope
copies. External modules have no body; import nodes retain paths, aliases,
grouped names, glob selection and visibility. Shared item dispatch and visibility
parsing preserve enclosing spans; source loading and module identities remain
resolution responsibilities.
Product/union/enum members, interfaces/extensions and associated items, foreign
signatures, patterns, condition chains, match arms/guards, closures, owner/error
forms and interpolations retain dedicated syntax nodes. Slice/group projection
subjects retain their structural type syntax. Attributes and macros retain
balanced token trees; expansion owns matcher/schema validation and hygiene.
The parser does not desugar these forms into library calls or checked facts.
Bodyless interface signatures preserve their terminating newline. Nested blocks
and interpolation holes isolate expression-header and generic-boundary state.

Owner type annotations retain an `Owner` syntax form and resolve in semantics to
the nominal `alloc` library types: `heap T` to `Heap<T>`, `shared T` to `Shared<T>`,
`local shared T` to `LocalShared<T>`, and the corresponding atomic/local `Weak<T>`
handles. Expression constructors and `weak owner` use ordinary checked library
calls, so allocator defaults, methods, dereference projections and destruction
remain library-owned. The loader mounts `alloc` for reserved owner syntax and
reports a structured feature diagnostic when that library is unavailable.
`Heap<T: unsized>` supports ownership-preserving coercion from a sized array
owner to a slice owner and from a sized concrete owner to an erased-interface
owner. `OwnerUnsize` transfers the original allocation and allocator while
attaching slice-count or witness metadata; it never reallocates. Dynamic
`size_of_val`/`align_of_val` and drop use that metadata, and erased witness
tables carry size, alignment and a specialized drop callback. Unsized `Shared`,
`LocalShared` and `Weak` use
a separate count header followed by a metadata-aligned payload in one allocation;
their handles preserve both the fat payload pointer and the thin header pointer,
and the header retains the exact allocation layout for final-weak deallocation.
Droppable structural slice tails use the tail metadata to reach their specialized
element-drop loop. `Shared<Text>.copy_text` and `LocalShared<Text>.copy_text` accept only
validated `Text` views, preserving UTF-8 validity while copying. Pinning does not
follow merely from shared or unique heap ownership; safe pinned owning handles
are a separate S003 obligation.

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
Refreshing generic instances preserves regional/normalized fields while
propagating declaration layout, variant and cleanup metadata.

Diagnostics format `TypeId`s through the types component's source-oriented
display function rather than `TypeStore::name`, which remains an internal
canonical identity. The display reconstructs source forms for views, owners,
callables, sums, tuples and arrays; it omits regions unless a separate
diagnostic explicitly concerns them. The support path formatter chooses short
nominal names unless two names in the same diagnostic collide.

`types/regions` owns compilation-local region identities, declaration binders,
universe ancestry and intersection regions; an unspecified source adds no
constraint to an intersection. A `from` clause on an owner parameter's plain
payload (`heap T from r`) names the parameter's backing region. Names resolve
to identities within each declaration; equal source spellings do not equate independent binders.
Syntax retains each lexical region/source occurrence's span and syntax context.
Semantics binds its spelling and expansion identity, including nested result
sources; only resolved `RegionId`s cross into the type store and region solver.
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
For method bounds that name an extension-owner region, `s` comes from the
receiver's nominal type argument before any covariant shortening of its read
view. A call-site reborrow therefore cannot weaken the bound.
Concurrency properties (Transferable/Shareable/Static) are structural proofs in
`semantics/interface_solver`; immutable statics must be Shareable. Interface
implementation candidates are indexed by interface declaration.
Runtime normalization erases regions only after the semantic region checks;
it never substitutes for those checks. Early callable applicability may compare
temporary region-erased type shapes while retaining both semantic operands;
the regional pass opens their binders and proves the retained contracts before
publication. Slice identities describe element-count metadata and lower through
explicit unsizing, length and checked-index operations.
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
The loader separately records each original and generated source's actual
package-instance identity. The pipeline passes this provenance to resolution,
which interns compilation-local package owners for semantic locality checks.
Module/cache labels are not package owners; absent provenance never proves
locality, and package zero has no special privilege.

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
Native Ref/RefMut accessors are selected on the guard before dereferencing its
payload; the actual machine call still checks arguments and access rights.

Generic declarations use rigid, compilation-owned parameter identities. A
parameter exposes only its declared Copy/Sized, interface and callable rights;
nominal aggregate queries never treat an abstract parameter as a product.
Bound candidates do not suppress visible blanket implementations proven from
those rights; multiple applicable interfaces still require explicit selection.
Read-argument inference substitutes known generic bindings before stripping a
borrow layer, so an explicitly view-valued parameter retains its handle type.
Interface-instance argument fitting normalizes associated types before checking
symbolicity; unresolved fields must not make a concrete nominal argument accept
an unrelated type. Multiple genuinely applicable instances remain ambiguous.
Static source extensions on explicitly instantiated native storage owners use
implementation applicability and substitutions before native dispatch. Builtin
factories without owner arguments retain their existing inference path.
Parsed owner arguments remain owned by the syntax tree while checked node facts
refer to their array-count expressions; resolved owners suppress rebinding, not
syntax retention.
Checking publishes separate call substitutions without rewriting parsed names,
spans or generic argument spellings. Bounds resolve in the callee declaration's
namespace but are proved only from the caller's assumptions and coherent
implementation evidence.

Regional call checking maps explicit method type arguments to the declared
method parameters, not implicit interface/implementation parameters. Constructor
arguments retain their owner-parameter ordering. Interface method contract
checking maps both Self and interface inputs into the implementation method's
region binders before normalizing associated results.

Implementation applicability combines target/interface identity matching with
declared type/const equalities before proving its requirements from caller
evidence. The same constraint helper tests coherence intersections; missing
current implementations do not prove disjointness when downstream
implementations remain possible. Implementation parameters must be determined
by their target, interface inputs or equalities, rather than surviving unresolved
until specialization.
Potential interface candidates match both the target and interface arguments
before checking their constraints; a match on the target alone cannot establish
that a conversion to a different destination exists.

Thin function pointers satisfy the private `core::clone::FunctionPointer`
marker, whose membership the solver derives and coherence treats as closed.
Declared implementations of that marker are rejected. The ordinary library
Clone implementation copies the pointer without changing its complete callable
type or implying Clone for every Copy type.

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
An opaque return publishes its implicit `Sized` contract before its hidden
storage is known. Checking validates every selected hidden source after closure
storage finalization and before publishing the checked module; this does not
make unresolved inference types sized.
Concrete instances discard declaration-only proof metadata.
Closure bodies and callable type contracts preserve qualified carried-region
sources for owned erased values, including owned capture environments; this
transport inventory does not impose a borrowed-result requirement on static
producers or turn every potential input into a declared source.

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
The slice `len()` primitive reads element-count metadata through the verified
`SliceLength` operation, evaluates its receiver once and returns `usize`.
Array/slice counts and compiler-generated array cursors use target-width unsigned
values verified against the full constant magnitude without truncation, including
maximum-length zero-sized arrays.
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
Ordinary concrete erasure and child-to-superinterface upcasts are unaffected.
A sized adapter retains the original handle/metadata under ordinary lifetime
rules and implements the target interface without requiring heap allocation.

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
Block-entry loan availability intersects reaching definitions with origins held
in incoming memory or live SSA values, including their ancestor authority.
Phi operands are SSA uses on their recorded predecessor edges, not ordinary uses
in the merge block. This retires unheld prior-loop outputs without introducing
future definitions or discarding independent stored aliases.
Interprocedural effects include view-storage writes by implicit destructors.
Possible writes and every-normal-return overwrites are distinct. Only definite,
uniquely resolved ordinary-call overwrites release an old stored loan; conditional
writes and caught calls retain it. Effect inputs are captured before updating
destinations so self-writeback preserves its original referent.
Return/writeback disjointness is exported only when tracked partition origins
prove it on every return carrying that result. Definite replacement removes the
old holder authority, not the backing owner's lifetime. Proven replacement
pairs survive derived views within one call epoch; no such proof is applied
when a returned view reaches the call again through storage or a loop Phi.
Exclusive holder borrowing checks its frozen contents so an existing live
child cannot be hidden by replacement.
Indirect or erased mutable calls conservatively union possible view-storage
writes. Analysis-only opaque/typed element paths preserve compatible origins
through unknown aggregate shapes; they are forbidden in executable CFG places.
Generic payload paths retain enclosing field prefixes and payload field types;
logical payload fields must not be interpreted as the wrapper's physical fields.
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
value or destructor obligation. Origin propagation removes impossible payload
storage on edges of an immediate tag test of uniquely resolved precise storage;
independent aliases and SSA values retain their origins, and joins union the
remaining possibilities. Default/native enum storage remains private.
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
ownership rules.

The I06 machine boundary shares operation signatures between checking and IR
verification in `types/machine`. Raw memory operations retain explicit unsafe
requirements: callers establish provenance, extent, alignment, initialized
validity, exclusive access and non-overlap where required. Bytewise copies and
swaps do not manufacture typed reads of uninitialized payloads. Transmutation
checks equal object sizes; target validity and retained provenance remain unsafe
obligations. No runtime provenance registry or informal `noalias` assumption
substitutes for those obligations. Copy operands remain usable unless the source
explicitly transfers them.

The numeric boundary also admits unsafe `f32`/`f64.to_int_unchecked<Int>`.
Checking and IR verification require a concrete native integer target and unsafe
permission. The LLVM adapter emits truncating `fptosi`/`fptoui`, not saturating
casts; the caller establishes finite input and representability of the truncated
integer value. Alias and result-context inference do not weaken that admission.

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

Shared interfaces for the eight initial machine-boundary workstreams. Scope
excludes new targets, portable SIMD, thread libraries, allocator-backed pin
owners and general I09 compile-time programming.

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
  Projected guards retain the original counter authority separately from their
  metadata-bearing payload pointer. Positive counts track shared guards;
  negative counts track exclusive split guards. Projection transfers a token,
  splitting checks count overflow before duplicating one, and each cleanup
  releases exactly one token. Unsafe unguarded borrowing retains the source
  lifetime without incrementing the counter.
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
New component directories enter CMake only with their implementation and
component-owned dependencies. No full qualification matrix starts until the
inventory, fixtures and documentation satisfy the source-freeze gate.

### I11 async state-machine interface plan

The parser desugars async bodies into
`core.future.coroutine(take fn(): T { .. })` and `await` into a poll loop
around `core.intrinsics.coroutine_suspend`, so the closure body is checked and
analyzed as ordinary code; `ir::Exit::Suspend` is the suspension edge and
`ir::Function::coroutine` marks the body. `core.future.CoroutineState<T, C>`
(`AggregateKind::Coroutine`) is laid out by the backend as the body's
persistent cleanup frame through `TypeStore::coroutineLayout`; layout checks
before the backend skip coroutine-dependent types (`types::coroutineDependent`).
Pinned `Future.poll` through `any Future<Output = T>` requires a fixed associated
output. Borrowed dispatch is distinct from the explicit Static heap owner
`alloc.future.Erased<T>` with typed poll/release callbacks and from
`Heap<any Future>`'s general unsizing/drop path. Erased async-interface returns
still need an explicit source future-storage contract. Open items are tracked
in implementation-plan section 8.4.

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
| Threads and async (I10-I11) | Transferable/Shareable/Static are intrinsic properties proved structurally by `semantics/interface_solver.cpp` (`proveConcurrency`), with manual `unsafe extend`/negative `extend X not P` recorded in `interfaces::Database::concurrencyDeclarations`; thread/lock/TLS operations reach pthreads only through the `mettle_rt_thread_*`/`mettle_rt_mutex_*`/`mettle_rt_cond_*`/`mettle_rt_rwlock_*`/`mettle_rt_tls_*` hooks (`runtime/thread.cpp`), while channel selection uses its process-wide generation condition there to sleep without polling. Static TLS descriptors are keyed by their static addresses; TLS values share a per-thread active-key list so thread exit and the hosted main exit destroy them in reverse first-installation order. `std.thread`/`std.sync` and `alloc.arc` are native Mettle modules. `async` bodies are coroutine closures desugared in `syntax/parser/async.cpp`; suspension is `ir::Exit::Suspend`, the state is the backend frame (`backend/llvm/cleanup.cpp`), and its Transferable/Shareable proof includes a scope-based interior recorded by `semantics/captures.cpp`; `std.task` is the separately selected executor |
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
Each instruction also retains its lexical scope index, and functions carry the
source-level inline hint as compiler-owned metadata; CFG verification checks
scope indices before backend emission.
Only the LLVM adapter (`backend/llvm/debug.*`, active under the driver's `-g`)
turns spans into `DILocation`s with line tables built from the loaded sources,
and builds `DISubprogram`, `DILocalVariable` and type metadata (layout offsets
come from `types/layout.h`). The driver supplies the diagnostics provenance
mapping: copied text retains its source offset and macro-produced tokens use
the invocation span. Lexical scope indices become nested DWARF lexical blocks;
local locations end at moves, drops and scope exits and are restored on
whole-place stores. Closure environment fields use captured place names. Type
names use dotted display paths and instantiated TypeStore names. Length-bearing
views expose `data_ptr` and `length`; erased views expose their data pointer,
alignment and a typed witness-table pointer. Optimizer-created inline stacks
are derived from each function's DISubprogram and call-site locations. Sums use
a discriminator and per-variant payload structures in a DWARF variant part;
offsets come from the compiler layout, including overlapping payloads. A final
pass drops locations that would not verify. Without `-g` the adapter emits no
metadata. CodeView/PDB remains open for its separately gated profile.

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
`core.mem` and the by-path interfaces needed by tests never pay for library
loading. `core.ptr` is the intentional exception: its raw-pointer operations
remain compiler-owned, while `library/core/ptr.mt` provides the `NonNull` type.
The loader mounts that source module only for an explicit pointer-module import
or a `NonNull` path, not for intrinsic pointer operations alone. Text literals
reference `core.text`. Detection is lexical and may over-load but never
under-loads. Mounted roots are ordinary modules with
their own source identities, so diagnostics point into library files and bodies
are fully checked. All three builtin tiers, including preseeded macro sources,
share one standard-library package instance in source ownership metadata; their
mount names and layer restrictions remain distinct. A user root module with the
same name shadows the library
(freestanding and test setups define their own `core`); the intentional
`core.ptr` source augmentation adds `NonNull` without replacing compiler-owned
pointer operations. Other library and built-in `core` submodule names do not
collide. Layering is enforced structurally:
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
Product coercions and branch joins normalize associated projections before
strict inference comparison; region relationships and invariance remain
separately enforced.
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

`library/core` requires no allocator, OS or executor. `library/alloc` depends
on core and an explicit allocator; `library/std` adds hosted services.
Library contracts include access/regions, allocation, failure, invalidation and
complexity; they do not depend on compiler C++ AST/type structures.

`runtime` contains the minimal defined low-level support for language operations,
with versioned compiler/runtime ABI contracts and target-specific implementations.
It does not become a hidden universal dependency of core/no-OS output.
The async executor remains a separate opt-in facility.
The current hosted runtime's panic ABI is private compiler support, not a stable
public C ABI. It uses C++ exceptions, a thread-local unwind-depth indicator and
integer panic codes. `std.panic.catch_panic` is a hosted language API layered on
that boundary and returns an owned code/message payload after cleanup. This API
does not establish compatible C-unwind interoperability or a stable public ABI.

Package resolution/build planning (`packages`, planned before compilation and
handed to the loader as source/version/context-specific `Library::packages`
mounts; each package instance gets a unique internal canonical prefix, while
a path headed by a package name resolves to the owning package's root (its own
name) or to a direct dependency alias. The driver owns Git CLI execution; the lock records its immutable
commit and source checksum. Host dependency mounts and feature sets are kept
separate from target mounts. Remote HTTP registries remain unspecified and
unsupported.
Failures carry the `manifest`, `package`, `lock` or `feature` phase.
Documentation, formatting and editor protocol
handling are clients of the compiler, not branches in semantic analysis.
Expose internal library interfaces first; stabilize external APIs only with an
explicit compatibility decision. The native compiler remains independent of
an installed Rust toolchain.

## 9. Incrementality, determinism and testing

Preserve the future query boundary:
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

The boundary suite exercises IR rejection, dominance/phis, independent
initialization, checked-tree lifetime/moves, immutable spelling, in-memory UTF-8
and rejection before verified publication. Frontend/IR/analysis compilation
receives no LLVM includes; the standalone boundary executable has no LLVM
symbol dependency. The separate historical dependency checker is retired.
Qualification is revision-bound evidence (implementation-plan section 9), not
inferred from component counts.

## F-string lowering

The lexer emits `FormatOpen/Piece/HoleOpen/HoleClose/Close` tokens; the parser desugars an f-string into a labelled call chain `core.fmt.message(read [field(hole, piece)...], tail)` (labels `f-string`, `f-string-internal`). The checker (`calls.cpp`, `expressions.cpp`) confines these nodes to `format` argument positions. It unwraps value-yielding groups and macro blocks around recipes or forwarded format parameters, discarding the flow facts of removed wrappers before destroying them; discarded-value blocks remain expressions. No new AST kind, IR or backend work is involved.

Cross-branch inference: a generic call at the tail of an `if`/`else` or `match` arm without an expected type (or an argument of such a call) may leave generic arguments open (`if c { left(a) } else { right(b) }`). `Checker::genericCall` then defers its errors and obligations (`deferredCalls`); `joinDeferred` merges the arm types structurally (`mergePartial`) and `finishDeferred` completes the bindings from the merged type, recomputes the call facts and refines its arguments top-down before the ordinary join. Arguments still open are reported as before.

A hole's type is checked through the `core.fmt.Hole` bound of `core.fmt.field`: one blanket library implementation covers every sized `Display` type and `Text` has its own; when the bound fails, `Checker::interfaceObligation` reports a dedicated "cannot fill an f-string hole" error instead of the generic obligation message.

Dotted-path resolution and generic application (grammar section 13): the parser applies the syntax-only generic-follower rule, including for `a<b>(c)`. A dotted expression chain stays a syntax-only `Field` chain; `dottedPath` (`syntax/ast.h`) flattens such a chain. The checker decides field versus qualified path in `Checker::qualifyDottedPath` (`semantics/names.cpp`), called by the `controlFlow` pre-check walk (which tracks lexical bindings) and over static initializers, before flow analysis and the call graph so both see the qualified call target: a lexically bound root is a value and keeps its field/method meaning (a local named like a type or module shadows it); otherwise the longest prefix whose leading segments are modules, types, interfaces, `Self` or generic parameters is resolved as a path (per-segment generic arguments map to `ownerGenericArguments`/`genericArguments`), and remaining links stay `Field` accesses. This syntax rewrite is done before any checked fact exists. The library loader also mounts a library root named by `core.x`/`alloc.x`/`std.x`.

`lint/lint.{h,cpp}` implements `mettle lint`: the driver compiles through `pipeline::compile` with a checked-module observer, so a lint run reports every front-end and ownership error first; findings are produced only when compilation succeeds. Rules (`unused-binding`, `unused-mutability`, `unused-import`, `unreachable-code`, `unused-outcome`) read `CheckedModule` facts (`find` accessors, `exclusivePlace`, `flow`, closure captures) and `Resolution::importUsed`; `Diagnostic` carries a severity so findings print as `warning[rule]` or, when denied, `error[rule]`. The driver filters out library, dependency and generated-source spans.

`syntax/fingerprint.{h,cpp}` provides the syntax-tree fingerprint used by formatting checks. `syntax/format.{h,cpp}` is the token-based formatter behind `mettle fmt`: it lays out lines from the lexer's tokens (indentation from bracket nesting, normalized horizontal gaps, collapsed blank lines, no line break added or removed) and returns text only after re-lexing it and proving the same token sequence, the same fingerprint and idempotence; it has no LLVM or semantic dependency and the driver owns file I/O (atomic replace, `--check`) and passes declarative-macro expansion as the parse hook.
