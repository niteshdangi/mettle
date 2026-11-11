# Frozen-baseline native mapping policy

## 1. Scope and authority

Rust 1.99.1 stable, edition 2024, is the capability reference, not a source
language accepted by Mettle. The versioned core/alloc/std contracts are normative
requirements by reference only for operations without an explicit native
authority assignment in section 7. Assigned operations use their standalone
Mettle specification; the reference remains identification/provenance data.
Unassigned operations keep their requirements until migration is complete.

The mapping is a design obligation, not generated bindings and not permission to
link Rust into the mandatory native toolchain. Implement equivalents independently.
Do not copy upstream implementations or substantial documentation without their
applicable licensing and attribution.

Keep all public paths as catalog identities until source-definition evidence
proves they are reexports of the same item. Equal names, signatures, or page text
alone do not establish canonical identity. A canonical operation may still have
multiple public exposure obligations.

Owner amendment (2026-11-09): deprecated APIs are excluded from required scope.
Their reference records and inherited deprecation metadata remain in the frozen
inventory for audit, not as implementation obligations. All reference profiles
remain in the post-V1 applicability review; V1 still gates only Linux x64.
See [the reconciled worklist](post-v1-worklist.md).
Nightly-only APIs are outside the automatic baseline;
explicitly accepted native facilities remain required regardless of that status.
Const stability is a separate dimension from runtime call stability.

## 2. Total default rule

For assigned operations, use the native signature and operation contract in
section 7. The following default remains only for unassigned operations.

For each applicable non-deprecated stable item not in the replacement table below, reserve a
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
| Result<T,E> | Stored Outcome<T, E>; Ok/Err become success/failure |
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

Owner amendment D30: native `alloc` Map defaults to deterministic hashing and
requires no hidden OS entropy. This deliberately differs from a randomized
hosted default. Applications handling untrusted keys explicitly select a
randomized builder; the capability remains required. Do not describe the
deterministic default as collision-attack resistant.

Owner amendment D31: general borrowed-or-owned identities map to
`BorrowedOrOwned<region r,B>`. Existing slice `Cow<region r,T>` is the alias
for `BorrowedOrOwned<region r,[T]>`, preserving one underlying type/implementation.
This resolves the generic identity collision without reinterpreting T as both
an element type and a borrowed payload type.

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

## 7. Native operation authority

Owner decision (2026-11-09): replace reference-owned operation contracts with
standalone native specifications before removing their documentation references.
The assignments below change specification authority, not API scope,
implementation state or qualification. Frozen reference identities and signatures
remain available for audit. The normative native definition must preserve every
selected caller guarantee; a signature or implementation conflict reopens the
affected item, rather than weakening its contract.

For an assigned operation, retained declaration fields are native specification
data under T01-T16, not a dependency on an external language checker. In
particular, a function/method with `const_stability=stable` must support required
constant evaluation under the native constant and memory rules. Runtime
stability or a printed `const` qualifier alone does not grant that eligibility.
This preserves exact per-member flags without duplicating thousands of flags
in prose. Named constants retain their separately specified values and types.
Any actual conflict with native evaluation remains an explicit mapping defect.

The [native value specification](native-value-contracts.md) owns exactly these
inherent operation identities, including shared/exclusive-view specializations
and reexports. Numeric suffixes on archived duplicate anchors are exposure
identities, not additional native method names.

| Reference owner/member | Native operation and specification |
| --- | --- |
| `option::Option::is_some`, `is_none` | `is_present`, `is_none`; [queries](native-value-contracts.md#2-optional-queries-and-projections) |
| `option::Option::as_ref`, `as_mut`, `as_pin_ref`, `as_pin_mut`, `as_slice`, `as_mut_slice`, `iter`, `iter_mut`, `as_deref`, `as_deref_mut` | Same member names; [projections](native-value-contracts.md#2-optional-queries-and-projections) |
| `option::Option::unwrap`, `expect`, `unwrap_unchecked`, `unwrap_or`, `unwrap_or_else`, `unwrap_or_default` | Same member names; [extraction](native-value-contracts.md#3-optional-extraction-and-mutation) |
| `option::Option::take`, `replace`, `insert`, `get_or_insert`, `get_or_insert_with`, `get_or_insert_default`, `take_if` | Same member names, escaped `take`; [mutation](native-value-contracts.md#3-optional-extraction-and-mutation) |
| `option::Option::map`, `map_or`, `map_or_else`, `map_or_default`, `and_then`, `or_else`, `is_some_and`, `is_none_or`, `ok_or`, `ok_or_else`, `filter`, `inspect`, `and`, `or`, `xor`, `zip`, `unzip`, `flatten`, `transpose`, `copied`, `cloned` | Same member names; [transformations](native-value-contracts.md#4-optional-transformations) |
| `primitive::bool::then_some`, `then` | Same member names; [eager/lazy conditional construction](native-value-contracts.md#4-optional-transformations) |
| `result::Result::is_ok`, `is_err` | `is_success`, `is_failure`; [queries](native-value-contracts.md#5-stored-outcome-queries-and-projections) |
| `result::Result::as_ref`, `as_mut`, `iter`, `iter_mut`, `as_deref`, `as_deref_mut` | Same member names; [projections](native-value-contracts.md#5-stored-outcome-queries-and-projections) |
| `result::Result::ok`, `err`, `unwrap`, `expect`, `unwrap_err`, `expect_err`, `unwrap_or`, `unwrap_or_else`, `unwrap_or_default`, `unwrap_unchecked`, `unwrap_err_unchecked` | Same member names; [extraction](native-value-contracts.md#6-stored-outcome-extraction) |
| `result::Result::map`, `map_err`, `map_or`, `map_or_else`, `map_or_default`, `and_then`, `or_else`, `is_ok_and`, `is_err_and`, `and`, `or`, `inspect`, `inspect_err`, `copied`, `cloned`, `flatten`, `transpose` | Same member names; [transformations](native-value-contracts.md#7-stored-outcome-transformations) |

Receiver modes, payload bounds, effects, complexity, failure and regions come
from that native specification; its
[constant and profile rules](native-value-contracts.md#8-constant-evaluation-and-profile-applicability)
replace reference-owned constant-callability requirements for assigned methods.
This is an operation-level assignment, not a blanket assignment for every
member or implementation of Option/Result. Separate iterator declarations and
trait/collection implementations use the additional assignments below, not the
inherent-method table.

### Library assignments

The following selectors bind explicitly specified operations to their native
definitions. Apply stable, nondeprecated eligibility and each actual target
predicate before matching. Match an operation's owner, member, overload and
implementation context, not merely a module/type prefix. Canonical reexports
share the resulting authority.

| Operation selector | Native authority |
| --- | --- |
| Protocol members, scalar helpers, text/slice/array operations, named iterator constructors/adapters/consumers, pointer/storage/cell/pin operations, operators, formatting/type queries, poll/wake/atomics and C-string operations explicitly enumerated in the core boundary | [Core member groups](native-core-library-contracts.md#152-native-authority-boundary), with their owning sections 2-14 |
| Optional/outcome `Iter`, `IterMut`, `IntoIter`: `next`, `next_back`, `size_hint`, `len`, fused behavior, stated Clone eligibility and owned cleanup | [Zero-or-one iterator types](native-core-library-contracts.md#6-iterator-protocols-and-constructors); inherited consumers/adapters retain their separately specified bounds |
| Layout/allocator, unique/shared/weak owners, collections and entries, String/CString, borrowed-or-owned and allocating slice operations explicitly enumerated in the collection boundary | [Collection member groups](native-collection-contracts.md#12-exact-coverage-and-remaining-work), with their owning sections 1-11 and decisions D30-D31 |
| I/O, OS strings/paths, files, environment/processes, time, threading/synchronization/channels and address/network members explicitly named by the hosted selectors and their runtime clauses | [Hosted member selectors](native-hosted-contracts.md#101-operation-selectors-for-integration), with the exclusions in section 10 |
| Descriptor/handle/socket transfers, OS string representations and filesystem/process/network/thread extensions explicitly named by the OS selectors and their runtime clauses | [OS member selectors](native-os-contracts.md#81-integration-selectors), with the exclusions in section 8 |

A group assigns only a member with a native runtime definition, including its
signature translation, access/regions, effects, failure, cost and unsafe
conditions. A coverage heading, generic protocol law or `Type.*` abbreviation
does not assign an unlisted type-specific operation. In particular, unspecified
error-code mappings, initialization helpers and source-only branches keep their
fallback. These assignments establish specification ownership, not a completed
per-canonical implementation audit.

### Machine assignments

The [native machine specification](native-machine-contracts.md) additionally
owns these explicit function identities, including canonical reexports:

| Catalog function identities | Native specification |
| --- | --- |
| x86/x86-64 `_blcfill_u32/u64`, `_blci_u32/u64`, `_blcic_u32/u64`, `_blcmsk_u32/u64`, `_blcs_u32/u64`, `_blsfill_u32/u64`, `_blsic_u32/u64`, `_t1mskc_u32/u64`, `_tzmsk_u32/u64`, `_bextri_u32/u64` | [Bit helpers](native-machine-contracts.md#3-integer-bit-helpers), including wrapping results, constant-control checks and TBM requirements |
| x86/x86-64 `__cpuid`, `__get_cpuid_max`, `_mm_extract_si64`, `_mm_extracti_si64`, `_mm_insert_si64`, `_mm_inserti_si64`, `_mm_stream_ss`, `_mm_stream_sd`; x86-64 `cmpxchg16b` | [Queries and transfers](native-machine-contracts.md#4-machine-queries-and-specialized-transfers), with the common access/feature and store-fence rules in sections 1-2 |
| wasm32 `i8x16`, `u8x16`, `i16x8`, `u16x8`, `i32x4`, `u32x4`, `i64x2`, `u64x2`, `f32x4`, `f64x2`, `memory_size`, `memory_grow`, `unreachable` | [WebAssembly constructors, memory and trap operations](native-machine-contracts.md#6-webassembly-operations) |

These are function assignments only. They do not assign every architecture
type, implementation, intrinsic or source-only branch. The other ISA-family
rules in that chapter constrain future assignments but do not replace their
individual contract review. In particular, a vendor link is not proof that all
native safety, immediate and feature requirements have been reconciled.

Language copying, retention, evaluation and cleanup are independently specified
by [core semantics](core-semantics.md) and its owning refinements. Their former
external design-source links are not normative fallbacks.
The [specification gate](specification-status.md) records migration boundaries.

### Remaining migration

The following reference-owned surfaces remain blockers to complete reference
removal. Apply the [V1 priority rules](specification-status.md#v1-priority-and-deferred-migration)
to schedule them: complete reference removal is not a V1 prerequisite, while
contract conflicts affecting selected V1 operations still block their acceptance.

- Unlisted numeric-buffer formatting, peek/initialization/spare-storage writers,
  push/entry/cursor helpers and other members outside the native selectors.
- Type-specific implementation relations, compiler facilities and supporting
  protocol substitutions not completely defined by the assigned native rules.
- Slice Cow alias eligibility for the existing non-Clone borrowed/read extension;
  D31 does not authorize silently narrowing that native behavior.
- Uncommon OS error-code classifications and extension members/aliases outside
  the hosted and OS definitions.
- Architecture instruction/register/feature tables outside the function
  assignments above, plus source-only cfg branches.
- Other applicable post-V1 declarations and supporting protocols retained by
  [the reconciled worklist](post-v1-worklist.md).

For each operation, write the native signature and every caller-observable
contract, bind its canonical/exposure identities to a specific native section,
and check the assignment against the retained declaration, constant and target
constraints. Type/trait names or a chapter about the same facility are not
coverage evidence. A shared implementation work unit still needs each retained
type/profile contract.

Benchmark comparator definitions, actual Rust-bridge requirements and frozen
provenance are separate from operation specification. Removing contract
dependencies does not remove those facts or comparison gates.
