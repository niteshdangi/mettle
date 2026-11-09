# Frozen-baseline native mapping policy

## 1. Scope and authority

Rust 1.99.1 stable, edition 2024, is the capability reference, not a source
language accepted by Mettle. The versioned core/alloc/std contracts are normative
requirements by reference for operations without an explicit native replacement.
This fixes a requirement even before a handwritten Mettle API page exists.

The mapping is a design obligation, not generated bindings and not permission to
link Rust into the mandatory native toolchain. Implement equivalents independently.
Do not copy upstream implementations or substantial documentation without their
applicable licensing and attribution.

Keep all public paths as catalog identities until source-definition evidence
proves they are reexports of the same item. Equal names, signatures, or page text
alone do not establish canonical identity. A canonical operation may still have
multiple public exposure obligations.

Stable deprecated operations remain in the parity inventory, with deprecation
metadata preserved. Nightly-only APIs are outside the automatic baseline;
explicitly accepted native facilities remain required regardless of that status.
Const stability is a separate dimension from runtime call stability.

## 2. Total default rule

For each applicable stable item not in the replacement table below, reserve a
native library item with the same relative module/item name under the equivalent
core, alloc or std layer. Preserve its documented observable operation, return
alternatives, failure and panic conditions, unsafe preconditions, bounds,
complexity guarantees and target conditions.

Translate types and parameter modes using section 3. Apply that translation
recursively to associated items, callbacks, iterator types, generic constraints
and implemented interfaces. A spelling collision with a keyword uses the native
escaped identifier syntax, not loss of the operation.

This is a deterministic contract-preserving default mapping, not a statement
that the resulting declaration has passed coherence or lifetime checking.
Any contradiction, unavailable native construct or changed caller guarantee is
an explicit mapping conflict. Keep it unresolved until specified; do not make
the default rule a blanket "covered" stamp.

## 3. Type and mode translation

| Reference concept | Native contract |
| --- | --- |
| Primitive integers/floats/bool | Corresponding fixed-width scalar and explicit conversions |
| char | Unicode scalar type, not a byte or grapheme |
| str / owned String | Text / String with UTF-8 invariants |
| shared/exclusive references | read/mut views carrying corresponding regions |
| raw pointers | ptr<read T>/ptr<mut T> and original unsafe preconditions |
| owned by-value T input | Explicit consuming parameter; no default read-borrow substitution |
| Copy scalar input | Value input; no needless invalidation unless source contract consumes an owner |
| &self / &mut self / self | fn / mut fn / take fn with preserved receiver contract |
| Box<T> | heap T and corresponding allocator/unsized/pinning operations |
| Arc<T> / Rc<T> | shared T / local shared T |
| weak ownership | weak T / local weak T |
| Pin<P> | Pinned owner/view with equivalent address-stability obligations |
| Option<T> | T?; None/Some become none/present without flattening |
| Result<T,E> | Stored T throws E; Ok/Err become success/failure |
| Send / Sync | Transferable / Shareable with the native derivation rules |
| Fn / FnMut / FnOnce | Read/mutate/consume-callable capabilities |
| associated types/constants | Native associated declarations and where equalities |
| generic lifetimes/HRTBs | Named regions and for<region ...> binders |
| dyn Trait / impl Trait | any Interface / some Interface in permitted positions |
| macro/intrinsic | Native expansion/intrinsic with the same operation contract |

A Result-returning library operation initially returns a stored outcome. A
throwing convenience entry point may expose the same failure alternatives, but
cannot erase the ability to store, inspect or transform the result.
Future output types retain that distinction.

Non-Copy by-value inputs explicitly consume even though ordinary native resource
parameters borrow. A concrete Copy source argument may be duplicated explicitly
before a consuming call. Generic source-body mode cannot vary based on an
undeclared Copy instantiation.

Returned views keep all receiver/input dependencies, including multiple
independent regions. A source unsafe operation cannot become safe merely by
changing its spelling; a source safe operation cannot require unsafe caller
code merely to compensate for an incomplete native checker.

## 4. Explicit replacements and exceptions

Retaining a shared/weak owner maps to retain, not generic bit-copy or implicit
assignment. Deep payload cloning remains a distinct capability.

Native optional/outcome construction, matching, propagation and projection
replace wrapper syntax. Their map, fallback, transpose, iteration and extraction
operations remain required even where surface syntax makes common cases shorter.

Language operator interfaces map to the native operator protocol rather than
exposing Rust desugaring as source syntax. Indexing must preserve reference versus
owned result contracts and checked failure behavior.

Compiler-controlled layout, drop, type identity, reflection and intrinsic
facilities map to native compiler queries. They do not reuse Rust type IDs,
mangling, metadata, compiler-private objects or trait-object ABI.

Rust-specific implementation details, compiler attributes and diagnostic names
are not automatically public Mettle APIs. Their stable user-visible capability
needs an equivalent native facility. Tooling maps to documented Mettle command
operations, not to source compatibility with Cargo manifests.

The native vocabulary of library-surface.md section 9 maps some Rust baseline
items (`Vec` to `List`, `HashMap` to `Map`, `HashSet` to `Set`, `BTreeMap` and
`BTreeSet` to `SortedMap` and `SortedSet`, `IntoIterator` to `OwnedIterable`,
`DoubleEndedIterator` to `BidirectionalIterator`, `FromIterator` to
`FromItems`, `Extend` to `ExtendItems`, `Read`/`Write`/`BufReader`/`BufWriter`
to `Reader`/`Writer`/`BufferedReader`/`BufferedWriter`, and the iterator
adapters to their past-participle names). The catalog keeps the baseline path
as the identity and records the native name as its mapping; a rename never
drops an operation, and a reexport still refers to one native declaration.
The default rule's "same relative item name" applies to everything outside that
vocabulary. These native names are the Mettle exposure for the corresponding
Rust baseline identities.

## 5. Target conditions

Carry configuration formulas separately from API stability. An operation that
exists only on Unix does not become required on Windows; it remains required
on each accepted applicable Unix profile. Architecture intrinsics require the
matching architecture and feature contract.

For core-only profiles exclude hosted services because the profile lacks those
services, not because those APIs were overlooked. Alloc facilities are applicable
when the profile supplies an allocator. WASI capabilities are those provided
by the selected WASI interface, not all POSIX services.

## 6. Audit evidence and acceptance

For implementation acceptance, each operation needs a checked native declaration
and semantic evidence covering signatures, ownership, failure, allocation,
threading, layout and unsafe requirements. Representative tests alone do not
prove that every item was mapped.

The [baseline inventory](baseline/README.md) owns provenance, runtime/const
stability and reproduction. Conditional supporting protocols are defined in
[library-surface section 8](library-surface.md); implementation members inherit
their interface member's stability. Metadata and documentation consistency
alone do not establish native typechecking, target applicability or execution.
