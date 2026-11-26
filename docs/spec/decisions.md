# Language and product decisions

## Accepted by the user or inherited from the accepted blueprint

| ID | Decision |
| --- | --- |
| D01 | Language name: Mettle |
| D02 | Native language and library capabilities are defined by the Mettle specifications, not Rust source/ABI compatibility |
| D03 | C++/LLVM V1; substantive self-hosting V1.1; own production backend V1.2 |
| D04 | Static borrowing, explicit ownership, native syntax, no compulsory GC/sandbox |
| D05 | Configurable integer-overflow checks: enabled in debug, disabled in release unless overridden; required constants always use checked evaluation |
| D06 | Shared handles move by default; additional owners require explicit retention |
| D07 | Known copyable ordinary parameters receive values; non-copy resources borrow |
| D08 | Generic defaults use declaration-known constraints; unconstrained T borrows |
| D09 | Named structs/enums explicitly opt into Copy; built-in aggregates are structural |
| D10 | Runtime must match or beat Rust per agreed workload; builds and memory are measured per D17 |
| D11 | Routine decisions are delegated; do not stop for approval after every item |
| D12 | Every material comparison explains Rust behavior, likely faster option and uncertainty |
| D13 | Function results use optional `: Type`, not `->`; omission infers from body returns/tails, not callers. Explicit annotations remain checked contracts, including for public definitions. |
| D14 | `Unit` is a predeclared type name, not a keyword; `()` is its sole value, not a second type spelling. Omitted results may infer Unit but do not default to it. |
| D15 | `Never` is the predeclared uninhabited type, replacing the lowercase built-in spelling; it remains distinct from Unit. Prefer `let _ = expression` for intentional non-Unit discard; semicolon semantics remain unchanged. |
| D16 | Identity: Mettle must not read like a Rust copy. Priorities: source readability, runtime matching or beating Rust (D10), faster compilation and less build-cache storage (D17). Judge complete programs, not punctuation counts. |
| D17 | Compile time (clean, incremental, check-only) and retained build-cache bytes must beat the frozen Rust/Cargo baseline on the agreed workloads, on a qualified runner, with RSS and binary size reported; a compiler-work regression guard also applies ([performance.md §5.1-5.2](../process/performance.md#51-compile-time-and-build-storage-gate)). Replaces the earlier "no accepted equality gate" for compile time |

These decisions supersede v0.21 implicit retention, the 10-percent slowdown
trigger and the Word blueprint's earlier parameter/copyability rules.

## Experience revision (accepted 2026-10-30)

D18-D29 retain V1 capability, ownership, failure and runtime contracts.

| ID | Decision | Normative section |
| --- | --- | --- |
| D18 | Dots qualify modules, types and values; `T.(Interface).Item` selects interface items; lexical shadowing with diagnostics; bounded method lookup; one associated namespace for functions, constants and lowercase variants; brace-list and glob imports | [semantic-rules.md §13.1-13.3](semantic-rules.md#131-qualified-resolution-shadowing-and-interface-selection), [language-grammar.md §13.1](language-grammar.md#131-dotted-paths-and-imports) |
| D19 | Generic application in expressions is `name<...>`, decided by a syntax-only follower rule; the `assert(a < b, c > (d))` parse is an accepted, diagnosed quirk | [language-grammar.md §13.3](language-grammar.md#133-generic-application) |
| D20 | `List`, `Map` and `Set` default `A = Global` (hash collections also carry a hash builder `S`, D30); constructors are selected by explicit label/arity shape with declaration-checked applicability; no hidden allocator fallback and no return-type overloading | [semantic-rules.md §13.4](semantic-rules.md#134-constructor-selection) |
| D21 | Native vocabulary (`List`, `Map`, `Set`, `SortedMap`, `SortedSet`, `OwnedIterable`, `MutableIterable`, `BidirectionalIterator`, `FromItems`, `ExtendItems`, the `Reader`/`Writer` family, past-participle iterator adapter types, contextual `extend`) with the versioned `experience-1` prelude; accurate standard words are kept | [library-surface.md §9](../library/library-surface.md#9-vocabulary-and-the-experience-1-prelude), [language-grammar.md §13.2](language-grammar.md#132-contextual-extend-declarations) |
| D22 | Builder inference is local to one named function, solved before capture or escape, with source-span provenance and earliest-conflict diagnostics | [semantic-rules.md §13.5](semantic-rules.md#135-local-builder-inference) |
| D23 | `format` is a parameter kind whose type is the opaque borrowed `core.fmt.Message`; recipes never escape; std owns Writer `write`/`write_line` | [library-surface.md §10.1](../library/library-surface.md#101-format-parameters-and-corefmtmessage), [language-grammar.md §13.5](language-grammar.md#135-format-parameters-and-interpolated-text) |
| D24 | `print`/`eprint` take `format` parameters and panic on ordinary failure; a stdout broken pipe terminates quietly (SIGPIPE, or status 141 when EPIPE is observed) | [library-surface.md §10.2](../library/library-surface.md#102-convenience-output-and-broken-pipes) |
| D25 | Reusable lending lines (`read_line_into`, `read_bytes_line_into`) and Copy-valued `[u8].bytes()` | [library-surface.md §11](../library/library-surface.md#11-lending-lines-and-byte-iteration) |
| D26 | One closure introducer: `fn(x) => expr` and `fn(x) { ... }`; no `(x) =>` form | [language-grammar.md §13.4](language-grammar.md#134-closures-and-call-arguments) |
| D27 | Named arguments follow positional ones; labels change neither access nor evaluation order; call sites omit `mut` for declaration-known mutable parameters (style only) | [core-semantics.md §9](semantic-rules.md#149-evaluation-order), [language-grammar.md §13.4](language-grammar.md#134-closures-and-call-arguments) |
| D28 | `KeyView<Q>` lets `Map.get` take borrowed keys such as Text without allocation | [library-surface.md §12](../library/library-surface.md#12-borrowed-keys-and-path-input) |
| D29 | `path.PathInput` and std `write_path` accept and display native paths without lossy conversion; a bare-interface `read`/`mut` parameter permits unsized implementors | [library-surface.md §12](../library/library-surface.md#12-borrowed-keys-and-path-input), [language-grammar.md §3](language-grammar.md#3-type-expressions) |
| D30 | Owner-selected deterministic `alloc` Map default: no hidden OS entropy and no default collision-resistance promise; untrusted-key applications select a randomized builder | [native collection contracts §8.3](../library/native-collection-contracts.md#83-hash-map) |
| D31 | General borrowed-or-owned values use `BorrowedOrOwned<region r,B>`; the slice `Cow` alias is removed, so slices spell `BorrowedOrOwned<region r,[T]>`. Owner amendment 2026-11-11 separates `core.borrow.OwnedType` storage identity from `ToOwned` copying | [native collection contracts](../library/native-collection-contracts.md) |
| D32 | Named parameter access precedes the binding (`mut item: Item`, `take view: read Item from r`), including closure and explicit-receiver declarations. Owner accepted 2026-11-09 | [semantic-rules.md §2](semantic-rules.md#2-value-formation-and-parameter-modes) |
| D33 | `Outcome<T, E>` names native stored success/failure values; `throws E` is reserved for callable effects. Owner accepted 2026-11-09 | [language-grammar.md §3](language-grammar.md#3-type-expressions) |
| D34 | If/while headers accept comma-separated boolean conditions and `let pattern = expression` clauses, evaluated once left to right with short-circuiting. Owner accepted 2026-11-09 | [language-grammar.md §6](language-grammar.md#6-expressions-errors-and-control-flow) |

## Routine selections made under delegation

- R01: Explicit take invalidates its source even for Copy; ordinary Copy passing
  leaves the source usable. No runtime byte clearing is implied.
- R02: let/var, declaration-known access modes, static initialization, and
  destructor-constrained partial moves follow the documented core rules.
- R03: Result inference solves recursive dependencies or requests annotations;
  callable types/bodyless declarations retain explicit results. Error effects
  and ambiguous borrow-source relationships are not inferred from bodies.
  The result delimiter applies consistently to methods, closures and foreign
  signatures. These refinements supersede the earlier mandatory-arrow grammar.
- R04: Operand evaluation is left-to-right; ordinary assignment evaluates the
  replacement before its destination. Primitive compound assignment uses
  RHS-before-destination ordering; overloaded compound assignment follows
  receiver-then-argument evaluation, fixed at declaration checking.
- R05: `.mt`, `copy type`, `Copy`, and labeled `Type(...)` calls are working grammar
  conventions, not public compatibility promises.
- R06: The first executable target is Linux x86-64; development subsets do not
  reduce the selected language contracts.
- R07: C++20/CMake/Ninja/Clang, existing fixture runners; toolchain-pins.json fixes
  source IDs; archive and installed-artifact locks identify build inputs.
- R08: specification-annex.md selects numeric conversions, higher-ranked solving,
  closure/pattern cleanup, macro phases, layouts, assembly and dispatch rules.
- R09: memory-and-concurrency.md selects validity/provenance/atomic contracts and
  poll-scoped borrowed-task execution epochs, without claiming a safety proof.
- R10: language-grammar.md composes the extended productions; reference-profiles.md
  selects deployment/SDK, ABI, linker, Wasm and freestanding design baselines.
- R11: library-surface.md and the native operation-family specifications define
  library contracts, including sealed/default/compiler-controlled protocols.
- R12: tooling-and-packages.md selects manifest/resolver, cache, test/doctest,
  formatting, editor and debugger contracts.
- R13: performance.md selects paired log-ratio intervals, family-wise error control,
  and separate pilot/release samples. The owner removed the fixed percentage
  precision target on 2026-11-26; uncertainty and performance requirements remain.

## Platform and product boundaries

The gated compiler host and target are Linux x86-64, using WSL2 or maintained
Linux. Historical macOS results do not qualify Linux. Windows MSVC/PE/CodeView
support requires its own implementation and target checks.
Licensing, registry governance and public stabilization require explicit owner
decisions; selected syntax is not a public stability guarantee.

## Documentation and implementation boundary

Specification completion does not prove parser/coherence/
memory-model correctness, target support or performance, choose a license or
revive rejected identity proposals. Estimates require measured progress/capacity;
plans do not authorize publication, installation, licensing or domain reservation.

## Proposed (not accepted): declarative macro surface

Owner acceptance remains proposed; implementation does not imply approval
of this surface.

- Definitions use the documented working form `macro name { (matcher) => { expansion }; }`;
  invocations are `name!(...)`, `name![...]` or `name!{...}`. Definitions are
  order independent and scoped to their inline module within a source file.
  Qualified public invocation, imports and reexports require separate support.
- Fragment kinds are `expr stmt pat ty path ident literal tt block item`
  (the spelling of the specification-annex follow-set table).
- Hygiene: identifiers an expansion binds (`let`, `var`, `for`, closure
  parameters) are unique per expansion; `$capture(name)` is the explicit capture.
- An `expr` fragment substitutes as one parenthesized operand.
- Expansion depth is limited to 256 and reports the expansion path.
