# Decision register and readiness

## Accepted by the user or inherited from the accepted blueprint

| ID | Decision |
| --- | --- |
| D01 | Language name: Mettle |
| D02 | Full agreed Rust baseline capability in V1, not Rust source/ABI compatibility |
| D03 | C++/LLVM V1; substantive self-hosting V1.1; own production backend V1.2 |
| D04 | Static borrowing, explicit ownership, native syntax, no compulsory GC/sandbox |
| D05 | Rust-aligned configurable integer-overflow profile defaults |
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
| D16 | Identity: Mettle must not read like a Rust copy. Its main points are (1) better source readability than Rust, (2) runtime speed matching or beating Rust (D10), (3) faster compilation than Rust, (4) less build-cache storage than Rust/Cargo. Accepted 2026-10-30. Judge the language on the exhibit programs of [implementation-plan.md §8.7](implementation-plan.md#87-experience-track-readability-compile-cost-and-storage), not on punctuation counts or resemblance to another language |
| D17 | Compile time (clean, incremental, check-only) and retained build-cache bytes must beat the frozen Rust/Cargo baseline on the agreed representative workloads: corpus-based like the runtime gate, measured on a qualified runner, with RSS and binary size reported. The compiler-work budget (median retired-instruction ratio at most 1.05, successive growth at most 2.2x) is an additional regression guard. See [performance.md §5.1](performance.md#51-compile-time-and-build-storage-gate) and [§5.2](performance.md#52-compiler-work-regression-guard). Replaces the earlier "no accepted equality gate" for compile time |

The shared-assignment rule supersedes the original v0.21 implicit-retain rule.
The runtime gate supersedes its greater-than-10-percent investigation trigger.
The finalized Word blueprint predates the detailed parameter and copyability
decisions; these source documents carry those subsequent refinements.

## Experience revision (accepted 2026-10-30)

These decisions carry the D16 identity into the source language and library.
They define the current syntax and vocabulary and retain the V1 capability,
ownership, failure and runtime contracts. Implementation and verification
status are tracked in [implementation-plan.md §8.7](implementation-plan.md#87-experience-track-readability-compile-cost-and-storage).

| ID | Decision | Normative section |
| --- | --- | --- |
| D18 | Dots qualify modules, types and values (`import std.io`, `as`); `T.(Interface).Item` selects interface items; lexical shadowing with diagnostics; bounded method lookup (inherent, bounds, prelude, owning package, explicit imports); lowercase variants share one associated namespace with associated functions and constants, and a collision is a declaration error; brace-list imports `import std.io.{Reader, Writer}` and glob imports `import std.io.*` | [semantic-rules.md §13.1-13.3](semantic-rules.md#131-qualified-resolution-shadowing-and-interface-selection), [language-grammar.md §13.1](language-grammar.md#131-dotted-paths-and-imports) |
| D19 | Generic application in expressions is `name<...>` decided by a syntax-only rule: a nonempty generic list followed by one of `( . ) ] } , ;`, an unsuppressed newline or end of file. The `assert(a < b, c > (d))` parse is an accepted, diagnosed quirk | [language-grammar.md §13.3](language-grammar.md#133-generic-application) |
| D20 | `List`, `Map` and `Set` default `A = Global`; constructors are selected by explicit label/arity shape with declaration-checked applicability (`A = Global`), no hidden allocator fallback and no return-type overloading | [semantic-rules.md §13.4](semantic-rules.md#134-constructor-selection) |
| D21 | Native vocabulary (`List`, `Map`, `Set`, `SortedMap`, `SortedSet`, `OwnedIterable`, `MutableIterable`, `BidirectionalIterator`, `FromItems`, `ExtendItems`, `Reader`/`Writer`, `BufferedReader`/`BufferedWriter`, past-participle iterator adapter types, contextual `extend`) with the versioned `experience-1` prelude. Accurate standard words (Iterator, Copy, Clone, Eq, Ord, Hash, Text, String) are kept | [library-surface.md §9](library-surface.md#9-vocabulary-and-the-experience-1-prelude), [language-grammar.md §13.2](language-grammar.md#132-contextual-extend-declarations), [baseline-mapping.md §4](baseline-mapping.md) |
| D22 | Builder inference is local to one named function, solved before capture or escape, with source-span provenance and earliest-conflict diagnostics | [semantic-rules.md §13.5](semantic-rules.md#135-local-builder-inference) |
| D23 | `format` is a parameter kind whose type is the opaque borrowed `core.fmt.Message`; recipes never escape; std owns Writer `write`/`write_line` | [library-surface.md §10.1](library-surface.md#101-format-parameters-and-corefmtmessage), [language-grammar.md §13.5](language-grammar.md#135-format-parameters-and-interpolated-text) |
| D24 | `print`/`eprint` take `format` parameters and panic on ordinary failure; a stdout broken pipe terminates quietly (SIGPIPE by default, status 141 when EPIPE is observed) | [library-surface.md §10.2](library-surface.md#102-convenience-output-and-broken-pipes) |
| D25 | Reusable lending lines (`read_line_into`, `read_bytes_line_into`) and Copy-valued `[u8].bytes()` | [library-surface.md §11](library-surface.md#11-lending-lines-and-byte-iteration) |
| D26 | One closure introducer: `fn(x) => expr` and `fn(x) { ... }`; no `(x) =>` form | [language-grammar.md §13.4](language-grammar.md#134-closures-and-call-arguments) |
| D27 | Named arguments follow positional ones, labels change neither access nor evaluation order, and call sites omit `mut` for declaration-known mutable parameters (style, not a mode change) | [core-semantics.md §9](core-semantics.md#9-evaluation-order), [language-grammar.md §13.4](language-grammar.md#134-closures-and-call-arguments) |
| D28 | `KeyView<Q>` lets `Map.get` take borrowed keys such as Text without allocation | [library-surface.md §12](library-surface.md#12-borrowed-keys-and-path-input) |
| D29 | `path.PathInput` and std `write_path` accept and display native paths without lossy conversion; a bare-interface `read`/`mut` parameter permits unsized implementors | [library-surface.md §12](library-surface.md#12-borrowed-keys-and-path-input), [language-grammar.md §3](language-grammar.md#3-type-expressions) |

## Routine selections made under delegation

- Explicit take invalidates its source even for Copy; ordinary Copy passing
  leaves the source usable. No runtime byte clearing is implied.
- let/var, declaration-known access modes, static initialization, and
  destructor-constrained partial moves follow the documented core rules.
- Result inference solves recursive dependencies or requests annotations;
  callable types/bodyless declarations retain explicit results. Error effects
  and ambiguous borrow-source relationships are not inferred from bodies.
  The result delimiter applies consistently to methods, closures and foreign
  signatures. These refinements supersede the earlier mandatory-arrow grammar.
- Operand and assignment sequencing preserve the Rust-aligned model, including
  the initial primitive/overloaded compound-assignment distinction.
- `.mt`, `copy type`, `Copy`, and labeled `Type(...)` calls are working grammar
  conventions, not public compatibility promises.
- Single-file scalar native execution on Linux x86-64 is the first source
  compilation milestone (I02); products, ownership and generics follow without
  shrinking V1.
- C++20, CMake, Ninja, Clang, and fixture-driven tests are the initial toolchain
  direction. toolchain-pins.json selects immutable source commits; I01 adds
  archive locks, installed artifact identities and verified native macOS
  Debug/Release builds with Linux target execution.
- specification-annex.md selects numeric conversions, higher-ranked solving,
  closure/pattern cleanup, macro phases, layouts, assembly and dispatch rules.
- memory-and-concurrency.md selects validity/provenance/atomic contracts and
  poll-scoped borrowed-task execution epochs, without claiming a safety proof.
- language-grammar.md composes the extended productions; reference-profiles.md
  selects deployment/SDK, ABI, linker, Wasm and freestanding design baselines.
- library-surface.md and its source-backed operation inventory specify native
  library contracts, including sealed/default/compiler-controlled protocols.
- tooling-and-packages.md selects manifest/resolver, cache, test/doctest,
  formatting, editor and debugger contracts.
- performance.md selects paired log-ratio intervals, family-wise error control,
  a 0.5-percent precision target and separate pilot/release samples.

## Implementation and product gates

- Owner decision (2026-10-31): Linux and Windows execution is excluded from all
  gates run on the macOS development machine; the owner runs those targets on a
  separate machine. Milestone closures here state their macOS host/Darwin
  target scope and do not claim Linux or Windows execution.
- Owner decision (2026-11-08), superseding the gated-profile part of the entry
  above: the macOS ARM64 development machine is no longer available. Remaining
  work (I13-I14) gates on the `linux-x64` reference profile: a Linux x86-64
  compiler host targeting x86_64-unknown-linux-gnu, run under WSL2 on the owner's
  Windows machine or a maintained Linux environment. Owner amendment
  (2026-11-09): remove the Ubuntu-release/glibc-version requirement; qualify the
  installed host and record its actual versions. macOS ARM64 is no longer gated;
  its I01-I12 receipts remain
  evidence for that profile only and do not transfer. Windows x64
  (MSVC/PE/CodeView) stays ungated: selecting it would be a scope expansion
  requiring a separate owner decision. See implementation-plan section 8.0.

| Work | Blocks | Resolution |
| --- | --- | --- |
| Grammar conflict/separator validation | Claim of parser-ready full grammar | I02-I05 check implemented scalar, product, composition and generic syntax; future constructs remain gated by their owning milestones |
| Scalar lowering | Full scalar operation matrix | I02 executes the selected i32/bool/Unit subset and profile failures; other widths/floats remain I06 |
| CFG joins, loans, temporary/drop table | Sound ownership compiler | I03-I05 check implemented move/loan/drop transitions and exceptional paths; passing cases are not a full soundness proof |
| Exceptional replacement and recovery | Safe panic catch around resources | I03 native cleanup probes validate replacement restoration before resumed access; hosted `std.panic.catch_panic` is implemented and verified on macOS arm64 (`tests/std/panic_catch.mt`) |
| Native declarations and full source cfg expansion | Implemented library parity | Typecheck/execute each applicable native contract, including source branches absent from rendered docs |
| LLVM/compiler/sysroot artifact locks | Reproducible native build | I01 records archive/tool/sysroot identities and same-environment clean rebuilds; cross-machine/release reproducibility remains later work |
| Linux x86-64 runner | First-target execution evidence | I01-I05 cross-emitted source and cleanup objects link and execute under the actual Linux kernel; Linux-host compiler qualification remains separate |
| Generic/interface/region checker | Advanced type-system claims | I05 solver, coherence, region and dispatch cases pass native/sanitized and Linux target qualification within the recorded scope |
| Memory/provenance and async containment | Unsafe/async safety claim | Model/review and execute the selected mechanisms |
| OS/SDK/WASI/board execution | Supported-target claims | Probe selected reference profiles and publish release evidence |
| Benchmark pilot and fixed release experiment | Runtime release verdict | Apply the specified plan with actual controlled measurements |
| Compile-time and build-storage measurement | Compile-time and build-cache claims (D17) | Qualified-runner corpus measurement per [performance.md §5.1](performance.md#51-compile-time-and-build-storage-gate) |
| Experience track (D18-D29) | Claim that every syntax, lookup and inference obligation is complete | [Implementation-plan.md §8.7](implementation-plan.md#87-experience-track-readability-compile-cost-and-storage) records verified work and the remaining R1 blockers |
| Project license | Public open-source licensing/distribution | Separate owner decision; no invented approval |
| Registry governance and public stabilization | Public service/compatibility promises | Owner decisions before launch; selected pre-implementation syntax is not a public stability guarantee |

## Documentation and implementation boundary

The specification pack covers core and advanced rules, composed grammar,
examples, all 107 capability owners, the pinned library operation contracts,
toolchain/profile selections, tooling and the measurement/release plan.
[specification-status.md](specification-status.md) defines the completion gate
and binds its evidence to the current validation result.

The original documentation task closed before implementation was authorized.
I01 implements the compiler foundation; I02 qualifies a scalar source compiler
with native macOS and Linux target execution/diagnostic evidence. Closing the documentation
gate does not prove a parser conflict-free, declarations coherent, the memory
model sound, targets supported or runtime competitive. Nor does it choose the
project license or revive a rejected language-identity proposal.

No arbitrary calendar dates or staffing estimates are included. Estimate from
measured prototype progress and actual team capacity. Do not create a public
repository, install tools, choose a legal license, or reserve domains merely
because a planning document lists them.

## Proposed (not accepted): declarative macro surface

Status: proposed for owner review; implemented unverified in I09 (L055).

- Definitions use the documented working form `macro name { (matcher) => { expansion }; }`;
  invocations are `name!(...)`, `name![...]` or `name!{...}`. Definitions are
  order independent and scoped to their inline module within a source file.
  Qualified invocation of public definitions across file modules and package
  dependencies is implemented but unverified; explicit macro imports and
  reexports remain unimplemented.
- Fragment kinds are `expr stmt pat ty path ident literal tt block item`
  (the spelling of the specification-annex follow-set table).
- Hygiene: identifiers an expansion binds (`let`, `var`, `for`, closure
  parameters) are unique per expansion; `$capture(name)` is the explicit capture.
- An `expr` fragment substitutes as one parenthesized operand.
- Expansion depth is limited to 256 and reports the expansion path.
