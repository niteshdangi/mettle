# Mettle core semantics

Status: selected semantics, refined by [semantic-rules.md](semantic-rules.md);
not implementation evidence or a safety proof. [core-grammar.md](core-grammar.md)
defines the initial subset; [language-grammar.md](language-grammar.md) extends it.
Specification fixtures are in `../examples/core/`.

## 1. Settled architectural constraints

- Unique resources and shared ownership handles move by default.
- Another shared owner requires an explicit retain operation.
- Bitwise duplication, retention, deep cloning, moving, and borrowing are
  distinct operations. Bitwise duplication cannot invoke user code or retain.
- Resource parameters borrow for reading by default; `mut` requests exclusive
  access and `take` requests ownership transfer.
- Ordinary copyable parameters receive values by default. Non-copy resources
  read-borrow by default. An explicit read-borrow form remains available for
  copyable types using an explicit read parameter mode.
- Calls do not repeat the signature's ownership mode. Public declarations must
  determine access through direct, generic, interface, and closure calls.
- Borrowing alone creates no owner, allocation, clone, or retain.
- Generic bodies use declared capabilities. Specialization must not grant
  undeclared duplication or retention permissions.
- Shared handles use atomic counts; local shared handles use non-atomic counts.
  Neither silently changes mode.
- Ordinary integer overflow follows Rust-aligned, configurable profile defaults.
- Runtime parity is measured against equivalent Rust workloads. Syntax choices,
  optimizations, and LLVM reuse alone establish no speed result.

## 2. Ownership operations

| Operation | Semantic effect | Ownership-related work |
| --- | --- | --- |
| Move | Transfer a non-copy value; source becomes unavailable until legally reinitialized | No clone or retain; moving a large value may still copy bytes |
| Bitwise duplicate | Produce another value when its type grants duplication | No user-defined work; cost depends on representation and optimization |
| Read borrow | Grant non-owning access within a validity contract | No owner-count change |
| Exclusive borrow | Grant access excluding conflicting accesses, with reborrowing rules | No owner-count change |
| Retain | Create another shared owner of the same payload | Update the appropriate reference count unless soundly eliminated |
| Deep clone | Construct another value according to a type-defined operation | Explicit, potentially allocating or expensive |

A shared handle is not bitwise duplicable: duplicating its bits cannot substitute
for a correctly accounted additional owner. An aggregate does not acquire
implicit retention simply because one of its fields is a shared handle.

## 3. Initial semantic examples

For an owned, non-copy `String`:

```text
let a = String("hello")
let b = a
inspect(b)             // Read borrow; b remains usable.
inspect(a)             // Reject: a was moved.
```

For a shared owner `first`:

```text
let second = first
inspect(first)         // Reject: first was moved.
let third = second.retain()
inspect(second)        // Both owners remain usable.
inspect(third)
```

No clone or retain may be inserted to make the rejected examples compile.

## 4. Accepted decision: ordinary parameter values

Parameter mode selection is defined in
[semantic-rules.md §2](semantic-rules.md#2-value-formation-and-parameter-modes).
Copyable values can avoid indirection; borrowing can avoid large byte copies.
Neither establishes the fastest ABI.

The rule mandates no physical register, stack slot, pointer, or memory copy.
ABI lowering may optimize representation only while preserving source-visible
behavior, including aliasing, address identity where exposed, and foreign calls.

Adding copyability may change default parameter semantics and is therefore a
potential source/API compatibility break.

### 4.1. Accepted decision: generic parameter defaults

The operational owner is semantic-rules §2. Implied Copy constraints select the
same value default as explicit Copy bounds; adding either can change access
semantics and break compatibility. Mode selection requires no allocation,
retain or runtime capability test. Specialization may optimize representation,
not change observable aliasing or value/snapshot behavior.

## 5. Accepted decision: copyability eligibility

Copyability permits bitwise duplication without custom code, retention, or
allocation. Eligibility does not promise a small representation or cheap copying.

- Primitive scalar values and `Unit` are copyable.
- Arrays and tuples are copyable when every element type is copyable.
- Native optionals/outcomes are copyable when every possible payload is copyable.
- Named structs and enums require explicit opt-in. Every field and every variant
  payload must be copyable under the declaration's generic constraints.
- A type with a user-defined destructor cannot opt in.
- Owned strings, unique heap owners, shared ownership handles, and exclusive
  borrow values are not copyable.
- Read-borrow values are copyable without duplicating the backing payload,
  producing ownership, or extending the backing storage's validity.

The compiler verifies opt-in; declaring it cannot bypass eligibility checks.
Generic aggregates must express their eligibility through declared constraints,
not gain undeclared copying permissions during specialization. Derivation is
specified in library-surface.md; generated bounds must establish each duplicated
field's Copy eligibility under the declaration.

For an opted-in point containing two copyable coordinates, ordinary assignment
duplicates the point and leaves the source usable. The same named type without
opt-in moves on assignment, even though its fields individually qualify.
An aggregate containing a shared owner cannot become Copy: duplicating that
owner requires explicit retention, not a bitwise-copy operation.

Changing a field so an opted-in type is no longer eligible is a compilation
error, not a silent transition to move semantics. Removing the opt-in is an
explicit potential API break, including its effect on parameter defaults.

## 6. Routine rules selected under design delegation

### 6.1. Explicit consumption

`take` consumes an owned source place even if its type is copyable. A `take`
parameter applies this contract without requiring a repeated call-site marker.
Ordinary copyable assignment and ordinary copyable value parameters still copy.
Taking a temporary transfers that temporary's value.

This preserves the blueprint's explicit consuming contract. Consumption does not
erase bytes, invalidate earlier independent copies, or create a security boundary.
Taking from a borrowed place is not permission to leave its owner's storage
uninitialized; use a sound replacement/extraction operation instead.

### 6.2. Bindings, places, and initialization

A place identifies storage: a local, field/tuple projection, supported indexed
element, or dereferenced storage. Ownership and initialization track the place,
not just its source name. Aliasing rules determine when two projections overlap.

`let` allows one initialization per dynamic binding and no subsequent assignment
to that binding. Delayed initialization is permitted when every path proves
exactly one initialization before use. `var` allows later replacement and legal
reinitialization after a move. A fresh loop iteration creates fresh bindings;
shadowing creates a different binding, not implicit destruction of the earlier one.

`let _ = expression` explicitly ignores a result without introducing a binding.
Prefer it for intentional non-Unit discards instead of relying on a terminal
semicolon. The wildcard itself does not move/copy/borrow an existing place;
initializer operations keep their ordinary ownership and error effects, and
fresh temporary results retain statement-end cleanup. Discarding an expression
does not suppress a typed failure or turn an existing owner into a temporary.
A plain place initializer such as `let _ = owner` performs no ownership transfer.

Binding immutability is not deep immutability. An exclusive reference can provide
payload mutation without permitting reassignment of its own immutable binding.
Read references may expose properly encapsulated interior-mutability operations.
Ordinary owned-field mutation requires an appropriate mutable place.

Every read, copy, move, and safe reference creation requires the accessed value
to be initialized. There is no implicit zero initialization. At a control-flow
join, use requires initialization on every reachable incoming path; loop analysis
must account for back edges, break, and continue. Cleanup tracks which initialized
values actually exist along each path.

Moving a field leaves that field uninitialized. Other disjoint initialized fields
remain usable; whole-value use requires complete initialization. Safe partial
moves out of a value with a user destructor are rejected, because its destructor
expects an intact value. Moving its fields during incomplete construction does
not invoke a destructor for a whole value that was never established.

Do not freely move non-copy values through references or arbitrary indexing.
Provide replacement, optional extraction, consuming iteration, and owned
decomposition operations with valid postconditions. Unique heap extraction needs
its own deallocation contract; pinning can forbid extraction.

Conditional cleanup may require runtime initialization flags.

## 7. Loans and access validity

A read loan permits reads but excludes conflicting mutation and invalidation of
the referenced memory, except through specified interior-mutability facilities.
An exclusive loan excludes conflicting access through other paths. Neither
operation creates an owner or extends the owner's destruction scope.

Loan validity follows control-flow uses and reachable derived views, including
uses by destructors, not merely the lexical presence of a reference binding.
End a loan after its last required use when sound; do not destroy the owner early
merely because its current borrow ends.

Reborrowing creates a derived loan whose permissions and validity cannot exceed
the parent. Suspend conflicting parent access until the derived loan ends.
An exclusive reference is non-copyable but can be reborrowed for shorter use.
Read-view duplication copies the loan-bearing view, not its backing object.

Nominal generic values carry loans in their type arguments even when a library
owner stores the payload behind a raw pointer. A raw pointer field alone does
not create a loan. Erasing a loan-carrying payload into an owning interface must
preserve those loans. The erased payload of an owner type carries a lifetime
bound: `heap any I from r` is bounded by `r`, and an owner without `from` holds
no borrow. Each loan the hidden value carries must outlive the bound of the
expected type at the conversion site (binding, argument, field or result).

Allow independently accessible struct fields when disjointness is established.
For slices and dynamic indices, use sound compile-time proofs or checked splitting
APIs; inequality of two arbitrary expressions is not itself a proof. Unknown
overlap is conservatively conflicting, without banning advanced unsafe wrappers.

Method receiver borrowing supports the selected reservation/activation rules
(two-phase borrowing) for appropriate implicit exclusive receivers, such as
appending a vector's current length. Reservation cannot allow conflicting writes,
moves, or active exclusive loans. semantic-rules section 5 specifies activation
and exceptional argument cleanup; it is not a license to waive alias checks.

Statically validated loans require no runtime borrow counter; checked splitting
and interior-mutability containers may have runtime costs.

## 8. Returned values and regions

`: T` returns a value: move owned non-copy state or duplicate a value under a
declared Copy capability. A read parameter cannot become an owned resource
without an explicit ownership-producing operation.

### 8.1. Optional result annotations

Function definitions use `: Type` for an explicit result, or omit the annotation
to infer the result from the body. `->` is no longer a result delimiter.
Parameter types and access modes retain their existing declaration rules.

- An explicit result supplies the expected type; every ordinary exit must fit
  it under the already permitted coercions. It is a checked contract, not a hint.
- For an omitted result, collect constraints from every reachable `return`
  expression and the block tail when normal control reaches it. A bare return
  and reachable fallthrough without a value contribute `Unit`. A discarded
  expression, including a semicolon-terminated tail, contributes no value.
- Diverging paths contribute `Never`, not `Unit`; they do not conflict with a
  returning path. A body with no normal exit infers `Never` only when divergence
  is established independently of an unresolved recursive result.
- Join these constraints under the existing branch/coercion rules. Do not invent
  numeric conversions, unions, optional payloads, ownership upgrades, clones or
  retains to repair conflicting results. Ordinary literal defaults still apply.
  An unconstrained result such as bare `none` requires a type annotation.
- Solve one signature per declaration under its declared generic constraints,
  before using it at call sites. A caller's expected type may instantiate an
  already established generic signature, not determine the function's result.
  Public definitions and methods with bodies may infer; public APIs are
  encouraged, not required, to annotate results. Publish the resolved signature
  in module metadata and invalidate dependents if that signature changes.
- Mutually dependent results form inference components. Solve their body
  constraints together, independent of declaration order. If a component has no
  uniquely determined result, require enough explicit result annotations to
  resolve it. Do not default an unanchored recursive cycle to `Unit` or `Never`,
  guess from a caller, or use later monomorphization to repair it.
- Callable types and bodyless interface/foreign declarations require explicit
  results, including `: Unit`, because there is no body to inspect. An inferred
  implementation must still match its interface's established contract.
- `throws Error` remains explicit and independent of the success annotation.
  `fn parse() throws Error { ... }` may infer its success type, but result
  inference cannot silently introduce, erase or convert an error effect.
  Closure contextual inference remains separately permitted.

`Unit` is the predeclared, Copy, zero-sized unit type; `()` is its only value.
It is not a keyword, a newly named product, `none`, a failure, or `Never`.
`()`, including in nested callable/tuple positions, is not a type spelling.
An omitted result is not shorthand for `Unit`: it infers `Unit` only when the
body's ordinary exits produce unit. Inference changes no runtime representation.
`Never` is the predeclared uninhabited type, not a synonym for `Unit`; no value
can be fabricated to return it.

### 8.2. Borrowed results

`: read T` returns a borrowed view. A single eligible borrowed source permits
source inference. Multiple possible sources require a public relationship such as
`from (a, b)`; the usable result region must be supported by both candidates,
without requiring identical input regions. Receiver and other parameter
ambiguities must not be resolved by inspecting the function body.
Omitting the result annotation does not bypass this rule: an inferred view
result must still have a source relationship determined from the input contracts.
When those contracts leave multiple eligible sources, require an explicit
borrowed result and `from` relationship, even if the body selects only one.

Stored views carry regions in their types. Returning a view never retains a shared
owner implicitly. A view of a local owner cannot escape that owner's storage.
Mutable returned views preserve exclusivity and reborrow constraints. Separate
results may carry independent regions instead of unnecessarily tying them all
together.

Regions require no runtime lifetime object, allocation or retention. Variance,
higher-ranked substitution and associated views are refined in semantic-rules
and specification-annex.

## 9. Evaluation order

Evaluate ordinary operands left to right in source order, including the callee
or receiver before explicit call arguments. Short-circuit operators, conditionals,
matching, and optional fallback evaluate only the selected operands/branches.
Transfers and borrows take effect as their arguments are evaluated; if a later
argument fails, cleanup must account for already-created argument values.

Named explicit arguments evaluate in written order, not parameter declaration
order. Evaluate omitted defaults afterward in parameter declaration order.
Default expressions use declaration-site resolution, not arbitrary caller locals.
Their permitted dependencies and ownership accesses need the signature/default
typing rules; no default implicitly clones or retains another argument.

Call arguments are positional-then-named (`call_argument`, core-grammar section
6). Named arguments may reorder the remaining parameters; duplicate labels,
unknown labels and a positional argument after a named one are errors. A label
names the declared parameter; it adds no second namespace and no overload by
payload type, and it does not change access: `allocator: take arena` still
contains a consuming expression, and a `mut` parameter still requires a mutable
place. The resolved parameter mapping is stored separately from evaluation order.

Preferred call style omits `mut` for declaration-known mutable parameters:
`parse(input, map)`. An explicit `mut place` stays legal, useful when forming or
storing a view or requesting a particular reborrow, and lint does not require
it; a redundancy hint may remove it only where checked access, loans and
evaluation order are equivalent. Keep `take` where intentional consumption
should be visible. This is style guidance, not a change to parameter modes or
borrow checking.

For ordinary assignment, evaluate the replacement value first, then the
destination place once, then replace its old value. This preserves the
Rust-compatible RHS-before-destination rule. Destructuring assignment first
evaluates its RHS, then performs component assignments left to right. It is not
transactional; interruption may leave earlier component assignments completed.

For compound assignment, retain Rust's declaration-based distinction initially:
known primitive operands evaluate RHS before the destination; overloaded cases
follow receiver-then-argument call evaluation with the applicable implicit
receiver reservation rules. Monomorphization must not change that order.
Do not casually lower compound assignment into ordinary assignment, duplicate
destination evaluation, or introduce a copy requirement.

Pure independent work may reorder when observable effects are preserved.
Defaults execute only when omitted, without a runtime argument dictionary.

## 10. Destruction and failure edges

On ordinary scope exit, destroy remaining initialized locals in reverse binding
declaration order. Destroy fields in declaration order, tuple elements in index
order, and array elements from first to last. A user destructor runs before its
fields' automatic cleanup. Destruction uses the concrete payload for erased values.
Moved-out or never-initialized fields are not destroyed.

Finish evaluating a return value before cleaning up the scope it leaves. Owned
parameters remain in the function scope and are cleaned up after body locals,
unless moved; borrowed parameters do not destroy their referents. Pattern-bound
parameter cleanup requires an explicit lowering that does not double-drop the
original parameter storage.

For replacement, after RHS and destination evaluation:

1. If the destination is initialized, begin destruction of its old value.
2. Account for the old value as undergoing cleanup so unwinding cannot drop it
   again; finish its remaining field cleanup if its destructor panics.
3. On normal completion, install the replacement and mark the destination
   initialized.
4. If old-value cleanup panics and unwinding remains possible, complete its field
   cleanup, install the pending replacement with a non-throwing store, mark the
   destination initialized, and continue the unwind.

An outer recovery boundary therefore observes initialized replacement storage.
Outer cleanup may subsequently destroy that installed value if its scope exits.
A second destructor panic during unwinding aborts. This is not transactional
rollback and does not preserve the old value.

The exceptional-CFG obligations are in `semantic-rules.md`. Externally borrowed
destinations and pinned replacement require explicit validation.

If RHS or destination evaluation fails before old-value destruction, unwind
already-created operands according to their scopes. Do not promise rollback:
evaluation may already have mutated or consumed the original value.

Typed-error propagation performs ordinary cleanup, not panic unwinding.
Destructors cannot report recoverable typed errors. A panic during an existing
panic unwind aborts; abort and explicit forgetting do not promise cleanup.
Async suspension is not scope exit; dropping suspended state destroys initialized
state synchronously and cannot run arbitrary async cleanup.

Cleanup requires no tracing collector or per-object registry; unwind paths and
conditional flags may affect code size and execution.

## 11. Temporary scope baseline

Assign every materialized temporary a destruction scope in typed IR. For the
initial core, call-argument temporaries live through the call and ordinarily to
the enclosing statement boundary; a reference returned from such an argument
cannot outlive its backing temporary.

Provide declaration-based temporary lifetime extension for direct borrowed
initializers where the language explicitly assigns the temporary to the binding's
enclosing block. Do not infer arbitrary extensions by looking into callees.
Declaring a named owner first is the general explicit alternative.

`semantic-rules.md` supplies the scope table for conditions, short-circuit
operands, guards/scrutinees, tails, optionals, capture and defaults. Drop timing
is observable and cannot change solely for performance.

## 12. Semantic acceptance corpus

These are specification expectations, not passing-test receipts.

| ID | Scenario | Required outcome |
| --- | --- | --- |
| OWN01 | Assign non-copy owner, then read original | Reject use after move |
| OWN02 | Assign opted-in copyable point, read both | Accept; no retain |
| OWN03 | Explicitly take copyable local, then read it | Reject; no required byte clearing |
| OWN04 | Assign shared handle, read original | Reject; no implicit retain |
| OWN05 | Explicitly retain shared handle, read both | Accept; another owner |
| GEN01 | Return unconstrained read T as owned T | Reject |
| GEN02 | Return take T as T | Accept without Copy bound |
| GEN03 | Instantiate read T with Int | Remain read-borrowed |
| GEN04 | Return Copy-constrained value parameter | Accept duplication |
| INIT01 | Initialize local on only one branch, then read | Reject |
| INIT02 | Initialize delayed let once on every branch | Accept |
| INIT03 | Reassign initialized let | Reject |
| INIT04 | Move var then assign fresh value | Accept when no conflicting loan |
| PART01 | Move one field, access disjoint initialized field | Accept for eligible aggregate |
| PART02 | Use whole aggregate after partial move | Reject until fully initialized |
| PART03 | Move field out of initialized user-destructor value | Reject |
| LOAN01 | Read view live across conflicting mutation | Reject |
| LOAN02 | Mutate after last read-view use | Accept if no derived/destructor use remains |
| LOAN03 | Exclusive borrows of disjoint fields | Accept |
| LOAN04 | Potentially overlapping indexed exclusive access | Require proof or checked splitting |
| LOAN05 | Use parent exclusive view during conflicting reborrow | Reject |
| REGION01 | Return view of local owned string | Reject |
| REGION02 | Return one of two declared sources | Constrain result to both source validities |
| TEMP01 | Store view returned from temporary argument beyond statement | Reject absent specified extension |
| ORDER01 | Calls with side-effecting arguments | Execute in source order |
| ORDER02 | Replacement RHS and destination both have side effects | RHS first; destination evaluated once |
| DROP01 | Move one of several owned locals, then exit | Drop only remaining initialized owners |
| DROP02 | Later call argument throws after earlier owned argument created | Clean up earlier argument exactly once |
| DROP03 | Constructor fails after some fields initialized | Clean up initialized state; no whole-object destructor |
| DROP04 | Old-value destructor panics during replacement | Unwind without double drop or exposing invalid state |
| DROP05 | Destructor panics while another panic unwinds | Abort |

## 13. Specification refinements and implementation gate

Owning refinements:

- `semantic-rules.md` supplies the typing/state framework, CFG joins, receiver
  activation, variance, selected temporary scopes and unwind restoration.
- `language-grammar.md` supplies extended syntax and default/pattern contracts.
- `advanced-contracts.md` supplies pinning, async and macro obligations.
- specification-annex.md supplies higher-ranked solving, parameter patterns,
  closure capture/drop order, coherence, erasure, macros and numeric policy.
- memory-and-concurrency.md supplies unsafe validity/provenance, atomics and
  borrowed-task execution epochs.
- library-surface.md and tooling-and-packages.md supply native operation/
  compiler-facility translation and development-tool contracts.

Validate contract interactions before claiming enforcement; source-level
read/mut spelling alone does not justify LLVM aliasing promises.

## Sources

- Rust standard library, Copy:
  https://doc.rust-lang.org/std/marker/trait.Copy.html
- Rust standard library, Arc:
  https://doc.rust-lang.org/std/sync/struct.Arc.html
- Rust Reference, call expressions:
  https://doc.rust-lang.org/reference/expressions/call-expr.html
- Rust Reference, expressions (places, moves, mutability, evaluation):
  https://doc.rust-lang.org/reference/expressions.html
- Rust Reference, operator expressions (assignment and compound assignment):
  https://doc.rust-lang.org/reference/expressions/operator-expr.html
- Rust Reference, destructors:
  https://doc.rust-lang.org/reference/destructors.html
