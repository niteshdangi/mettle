# Core typing and operational rules

Status: selected typing and operational rules, with the ownership model of
section 14; not a formal safety proof.

## 1. Judgments and state

Let Gamma map names to declaration identities, types, capabilities and access
modes. Let Delta map tracked places to initialization state. Let Loans contain
origin, projected place, read/exclusive mode, region and activation state.
Let Effects record typed failure, panic capability and suspension for the CFG.

`Gamma; Delta; Loans |- expression : T => Delta', Loans'` means that evaluation
is valid at that program point and produces T with the stated successor state.
Exceptional successors carry separate states.

A place is a root plus field/tuple/index/dereference projections. Field-sensitive
state is tracked only where object identity and disjointness are established.
Raw pointer equality or inequality is not a sufficient alias proof.

Initialization states are uninitialized, initialized, and path-dependent.
Maintain definitely-initialized and maybe-initialized sets; at a CFG join take
intersection for definite and union for possible initialization. A whole product
is definitely initialized only if every required field is. Moving a field clears
its initialized descendants and whole-object completeness.

Every read, duplication, move or safe borrow requires definite initialization
of the accessed value. Cleanup uses path-specific state, with flags if necessary,
so a maybe-initialized value is never blindly destroyed.

## 2. Value formation and parameter modes

- Copy from place p: require Copy(T), initialized p, and legal read access;
  leave p initialized and produce an independent T.
- Move from p: require owned movable p, initialized p and no conflicting loan;
  clear initialization of p and produce owned T.
- Explicit take from p: use the move rule even if Copy(T).
- Read borrow p: require valid initialized backing storage and no conflicting
  active/reserved access; produce a region-bearing read view, not owned T.
- Exclusive borrow p: require a mutable initialized place and no conflicting
  live access; create the exclusive loan or an eligible reservation.

Ordinary parameters with declaration-known Copy receive independent values;
other ordinary parameters read-borrow. Unconstrained T therefore read-borrows,
including a later Copy instantiation. Implied Copy constraints count as
declaration-known Copy. Generic specialization does not alter ownership
permissions. Explicit read overrides Copy; explicit take requires ownership,
not Copy; explicit mut requires exclusive access.
Named declarations and closure parameters put these modifiers before the
binding. Explicit receivers use `receiver take self: Type` (or read/mut).
Unnamed callable slots keep their existing `[mode] type` form; their identity
and adaptation rules do not change. `format` remains its separately specified
parameter kind, with its own read access.

Native stored outcomes are `Outcome<T, E>`; `throws E` is a callable effect.
The spelling changes neither success/failure alternatives, Copy/drop behavior,
region dependencies, propagation, capture, nor native layout.

Comma-separated if/while conditions short-circuit left to right. Conditional
bindings read-match their inputs and are in scope only in subsequent clauses
and the successful body. Their source temporaries and views live through that
scope and are cleaned up on every failure, branch exit and loop iteration.
The else branch resolves names in the enclosing scope, not the failed chain.

An owned result requires an owned value or a permitted duplication. Returning
a read view as owned non-copy T is invalid. No automatic deep copy, retain,
dynamic type test or ownership upgrade repairs it.

Function-type identity includes parameter access, typed failure, result regions,
and relevant callable capability. Indirect invocation must preserve these
contracts. Compatible adapters require explicit code, not silent mode erasure.

## 3. Scalars and arithmetic

Integer binary arithmetic requires matching operand types after literal
inference; no general implicit narrowing, signedness conversion or truthiness.
Use explicit numeric casts. Overloaded operations use declared interfaces.

For N-bit integers:

| Operation | Checks enabled | Checks disabled |
| --- | --- | --- |
| Add/subtract/multiply overflow | Panic | Result modulo 2^N, interpreted in the destination signedness |
| Negating signed minimum | Panic, except well-formed minimum literal construction | Same minimum bit pattern |
| Division/remainder by zero | Panic | Panic |
| Signed minimum divided/remainder by -1 | Panic | Panic |
| Out-of-range or negative shift count | Panic | Mask count to the N-bit operand's shift width |
| Signed right shift | Arithmetic shift | Arithmetic shift |
| Unsigned right shift | Logical shift | Logical shift |

This table applies to primitive integer operators, not user-defined overloads.
Explicit wrapping/checked/saturating/overflowing operations have their own
profile-independent contracts. Constant evaluation reports invalid required
constant computations at compile time; it does not execute a runtime panic.
Required constants use checked evaluation in every profile, as specified by
the numeric annex; folding runtime expressions preserves their runtime policy.
`const` items are immutable statics with checked constant initializers; cycles
and non-constant initializers are errors, and integer/bool consts may be used
as patterns.

Integer casts truncate when narrowing and sign/zero-extend when widening as
determined by the source signedness. The signed interpretation of destination
bits is defined, not undefined behavior. Float/integer casts, NaN conversion,
floating rounding and fast-math are specified in
[the numeric annex](specification-annex.md).

Comparisons yield bool. `&&`/`||` require bool and short-circuit. Equal/different
comparisons are not implicitly available for all user types. Unification must
not invent conversions merely to make branches type-check.

## 4. Control flow and generic checking

A binding without an initializer has a declared type and begins uninitialized.
Delayed let initialization is legal only once on each reachable dynamic path.
Var permits replacement and reinitialization. Assignment after an initial let
assignment is rejected even if the earlier value has moved.

An if expression joins branch value types after permitted coercions, with `Never`
coercing to the expected type. An absent else is a unit branch. Loop analysis
reaches a fixed point across back edges; a use after one possibly moving
iteration cannot rely solely on the first iteration's state.

Return first constructs its result then traverses cleanup edges. A result view
must refer to storage valid beyond cleanup. Break/continue traverse the scopes
they leave, not necessarily every enclosing scope.

Omitted function results are inferred once per declaration under section 14.8.1;
call-site context never supplies a missing result.

Check generic bodies once against declarations. Solve type equalities,
capability bounds and region obligations separately from code generation.
Failure to terminate/resource exhaustion is distinct from an unsatisfied bound.
Const parameters affect type identity; equal evaluated parameters unify.

Interface implementation selection must be coherent. An implementation cannot silently
weaken input guarantees or strengthen caller obligations relative to its
interface. Method result/error/region contracts must match the declared contract
or an explicitly specified compatible substitution.

## 5. Loans and two-phase receivers

A loan conflicts when its possibly overlapping place is accessed in an
incompatible way. Read loans coexist with reads. Exclusive active loans permit
access through themselves and soundly derived reborrows, not arbitrary aliases.
Field disjointness is structural; dynamic slice disjointness requires proof or
a checked API.

For eligible compiler-inserted exclusive receiver borrows only:

1. Evaluate receiver place once and create a reservation.
2. Permit read-only access during argument evaluation if it ends by activation.
3. Reject moves, writes and competing exclusive loans overlapping the reservation.
4. At invocation, require all conflicting read loans to have ended, then activate.
5. On argument failure, cancel the reservation and clean up argument values.

Explicit `mut place` borrowing is immediately active. Do not apply reservation
to every explicit mutable reference merely to accept more programs. Nested
reborrows carry parent authority; ending a child restores only permissions that
remain valid under other outstanding loans.

Loan liveness includes downstream views and destructor uses. It is not simply
last textual mention of a variable. Solve liveness across branches and loops;
ending a loan does not move the owner's drop point.

## 6. Regions and variance

Region r denotes a set of valid program points. A returned view from r may be
used only within r and while the access contract remains valid. An outlives
obligation r1:r2 requires r2's uses to be supported by r1.

`from (a, b)` requires backing validity supported by both sources, without
requiring their original regions to be equal. It does not retain either owner.
Named independent regions remain independent unless constraints relate them.

Read views are covariant in their validity region and in covariant payload
positions. Exclusive views are invariant in their payload type and covariant
in a shortened validity region through reborrowing. Interior-mutation cells
are invariant in mutable payload positions. Function inputs are contravariant
and outputs covariant where subtyping applies.

When a method bound names a region parameter of its receiver's nominal type,
that region is taken from the receiver's actual type argument. Covariantly
shortening a read view at the call site limits access through that view; it
does not weaken the method bound's outlives obligation against the nominal
region.

Derive user-type variance structurally; generic occurrences in invariant
positions prevent an unsound widening. Higher-ranked region variables cannot
escape their binder or unify with a shorter local allocation to satisfy a
universal contract. Higher-ranked solving and associated-type normalization
follow the specification annex; these variance rules alone are insufficient.

## 7. Pattern ownership and outcomes

An ordinary match grants read access to selected payloads; a mutable match
grants reborrows; a consuming match transfers chosen payloads after its guard
succeeds. Guard failure must leave the scrutinee eligible for later arms.
Remaining initialized owned fields drop according to the selected scope.

An optional T? has absent and present(T) states; (T?)? has three distinguishable
state shapes. Injection adds only the level demanded unambiguously by context.
Explicit present is required when the requested level would be ambiguous.

An outcome has distinct success(T) and failure(E) variants even when T equals E.
Capture catches only the typed failure of its expression. Propagation transfers
the error through ordinary cleanup; no hidden conversion or error erasure.
Explicit mapping supplies a different error type.

`??` evaluates its RHS only for absence. A consuming optional expression can
yield its owned payload; borrowing access cannot produce a new owned non-copy
payload. Optional chaining preserves access mode and does not retain owners.

## 8. Replacement and unwind restoration

Ordinary replacement evaluates RHS first, then resolves the destination exactly
once. If either fails, unwind the completed operands; no rollback of their
side effects is promised.

Once replacement begins, its lowering owns a pending replacement value and the
exclusive right to initialize the destination. Destroy the old initialized
value, tracking field cleanup so it cannot be destroyed twice.

On successful old-value cleanup, install the pending replacement. If old-value
cleanup panics and unwinding remains possible, finish old field cleanup, install
the pending replacement with a non-throwing store, mark the destination
initialized, and continue the original unwind. If another destructor panics
during that unwind, abort.

Thus a catch outside the operation can observe a valid replacement, not an
uninitialized referenced destination. A local leaving scope may immediately
drop the installed value during outer cleanup. This is not transactional
replacement and does not promise preserving the old value.

Hosted `std.panic.catch_panic` is a recovery boundary for source-level panics.
The panicking function first completes its ordinary initialized-place cleanup;
only then does the boundary return `CatchResult.Panicked` with the panic code
and message. Its message is an owned payload whose text view is valid until
the payload is dropped. A panic raised while running a panic hook, or a second
panic during cleanup, aborts rather than becoming a nested recovery result.
Recovery does not roll back other closure side effects. Freestanding/abort
execution has no unwind recovery boundary.

The store cannot invoke user code, allocate, throw or call an overloaded
assignment operator. Existing live aliases cannot access the destination during
the exclusive operation. Pinned destinations require a compatible in-place
replacement contract and may not be replaced through an ordinary movable path.

Require exceptional CFG cases for externally borrowed storage, aggregate fields
and catch scopes.

## 9. Native temporary scope table

| Construct | Unmoved temporary destruction point |
| --- | --- |
| Ordinary expression statement | Statement end, reverse construction order |
| Explicit call arguments/defaults | Enclosing statement end; moved arguments become callee-owned |
| Plain if/while condition | After condition evaluation, before entering selected body |
| Conditional pattern input | After selected success body; before else on failure |
| Each short-circuit boolean operand | After evaluating that operand |
| Match scrutinee | Enclosing statement end, after selected arm |
| Match guard ordinary temporaries | Guard completion before arm body/next arm |
| Block-tail temporaries | After tail evaluation, before enclosing block locals drop |
| Direct borrowed let initializer | Enclosing binding block when the defined extension applies |
| RHS of ?? not selected | Never constructed |
| Optional-chain receiver temporary | Enclosing statement end; not extended by chaining |
| Captured typed-outcome payload | Owned by outcome once transferred; other operands retain their scopes |

Direct borrowed initialization extends an explicitly borrowed temporary operand,
and corresponding direct tuple/array/product initializer positions, into the
binding's block. It does not inspect a callee body, extend an arbitrary
view-returning call, or promote mutable/destructible data to static storage.

Scopes are assigned after syntax desugaring with source-level provenance retained.
A value moved into a result is no longer an unmoved temporary. Destructuring
assignments require their own temporary binding block, preserving RHS completion
before per-destination assignments.

## 10. Required adversarial obligations

In addition to the core corpus, require:

- A catch outside a function replacing an externally borrowed value observes
  initialized replacement storage after its old destructor panics.
- A second panic during old-field cleanup aborts without executing the store
  as though unwind had completed normally.
- A default argument borrowing an earlier argument cannot let that borrow escape
  beyond its actual backing owner.
- Receiver reservation accepts reading a length but rejects mutation/reallocation
  of that same receiver during argument evaluation.
- A copied read view keeps its loan live even after the original view's last use.
- Same-typed success/error payloads and nested optional absence remain distinct.
- A mutable view cannot be widened through a covariant-looking wrapper.
- A required constant's arithmetic cannot silently change a type's layout between
  development and release profiles.

These are specification obligations, not passing-test receipts.

## 11. Coercion sites and method selection

Implicit coercions are limited to expected-type sites: annotated initializers,
arguments, returns, aggregate fields/elements and branch joins. They may shorten
a view under its variance/outlives rules, reborrow exclusive access as read,
unsize an eligible view/owner, upcast an erased interface to a superinterface, or
convert a function item/noncapturing closure to a compatible function pointer.
`Never` may coerce to the expected type. Optional injection follows section 7.
Safe function pointers may be used where an otherwise identical unsafe-call
pointer is required, not the reverse.

No general implicit numeric conversion, payload clone, retention, boxing,
borrow-to-owned conversion or conversion of typed failure accompanies coercion.
Ordinary argument borrowing follows the declared mode, not a user-defined
conversion selected to repair a mode error. Explicit casts have the numeric,
pointer, representation and ABI preconditions of their particular operation.

Method search constructs receiver candidates from the receiver type, successive
sound native/user-declared dereference targets, and permitted final unsizing.
For each candidate T, consider T, read T, then mut T. Do not dereference a raw
pointer implicitly or invent exclusive access through an ordinary shared owner.

At each candidate, consider inherent methods, then applicable interface methods
visible under the bounded lookup of section 13.2. Multiple applicable interface methods at the same priority are
ambiguous; import order cannot decide. Select a method, then enforce its
ownership, mutability, visibility and unsafe-call obligations. An unavailable
move or mutable loan is an error, not permission to fall back to another method.

Use `T.(Interface).method(receiver, arguments)` for explicit disambiguation.
Static associated functions do not acquire a receiver by being spelled after
an object. Dereference coercion can execute the declared user's
projection method, whose behavior is not a compiler-inserted clone/retain.
Cycles/resource exhaustion diagnose rather than changing search precedence.

There is no general overload selection by argument count/default availability;
constructor shape selection (section 13.4) is the only exception.
Same-named inherent methods require provably disjoint receiver instantiations;
overlapping declarations cannot win by where-clause specificity.
Operator interfaces use their declared receiver/operand modes and the same
coherent implementation selection, with the specified operand sequencing.

## 12. Aggregate and iteration completion

Native optionals/outcomes are Copy exactly when every possible payload is Copy,
as are tuples/fixed arrays. Named product/enum types retain explicit opt-in;
a generic `copy` type whose fields are Copy only when its unbounded type
parameters are Copy (`copy type Descending<T> { value: T }`) is Copy exactly when
all its type arguments are.
Zero-sized values have no payload bytes but retain initialization, alignment,
destructor multiplicity and ownership obligations. A zero-sized destructor
still executes once for each initialized owned value.

A for loop obtains the corresponding consuming/read/exclusive iterator from its
input mode, stores that iterator for the loop, and repeatedly mutably invokes
next until absence. It does not clone the collection or yielded elements.
Break, typed failure and unwind clean up remaining initialized iteration state
at the appropriate scope. Iterator-associated regions constrain the loop body
and any yielded views.

Range indexing `read base[a..b]` (also `a..`, `..b`, `..`, `a..=b`; bounds are
`usize`) borrows a subslice of an array or slice, panicking when out of range or
`a > b`; `mut base[..]` needs a mutable place. Other bases use
`core.ops.IndexRange` (`fn index_range(start: usize, end: RangeEnd): read
Self.Output from self`) or `IndexRangeMut`. The upper bound is passed as
`RangeEnd.Unbounded`, `RangeEnd.Exclusive(b)` or `RangeEnd.Inclusive(b)`;
no arithmetic is performed to translate it. Implementations enforce their own
bounds, including at `usize.MAX`.
Outside indexing, `a..`, `..b`, `..=b`
and `..` are `core.iter.RangeFrom`, `RangeTo`, `RangeToInclusive` and
`RangeFull` values; only `RangeFrom` iterates.

The compiler recognizes the interfaces by canonical path, like `core.ops.*`:
`core.iter.Iterator` (`type Item; mut fn next(): Self.Item?`),
`core.iter.OwnedIterable` (`fn into_iter(receiver take self: Self)`),
`core.iter.Iterable` (`fn iter()`) and `core.iter.MutableIterable`
(`mut fn iter_mut()`), none with parameters. `for x in take v` or an rvalue uses
Iterator directly, else OwnedIterable; `for x in v` uses Iterable; `for x in mut v`
uses MutableIterable, else a mutable view that is itself an Iterator. Ranges and
arrays keep their direct lowering. For other loops the checker records an
iteration plan (mode, protocol, selected method) in a side table and builds a
synthetic elaboration, an iterator binding plus
`loop { match next() { present(x) => body, none => break } }`, that shares the
original body. Ownership, region, capture and lowering passes consume the
elaboration, so cleanup and loans follow ordinary scope rules.
The iterator type of `Iterable`/`MutableIterable` is a region family, for example
`type Iter<region r> = ListIter<T, region r>` with
`fn iter<region r>(receiver read self: Self from r): Self.Iter<region r>`; the loop
borrows the collection for the iterator's region, so mutating it inside the loop
or holding an item past a mutation is rejected. A family may bound itself with its
own region, `type Iter<region r>: Iterator<Item = read Self.Item from r>`; each
implementation's family type must satisfy the bound at the implementation's
region, and generic code over `C: Iterable<Item = i32>` sees the bounded items as
`read i32 from c`. Ownership checks of generic loops run per instantiation.

Generic inference additionally uses the expected type: `let x: Opt<i32> = nothing()`,
`Opt.Nothing` and `Self(..)` in generic statics take their arguments from context.
`_` in a generic argument list is inferred, and inherent statics are callable as
`X.f()` and `X<i32>.f()`. Projections such as `I.(Iterator).Item`
normalize once `I` is known; `I: Iterator<Item = T>` determines `T`, and a
callable bound `F: fn(I.Item): B` determines `B` from the closure body, with
unannotated closure parameters taking their modes from the bound.

Exhaustiveness treats guarded arms as non-covering, unions or-pattern coverage,
and handles finite alternatives/ranges/slices under their actual type. External
nonexhaustive types require a fallback. Reject unreachable duplicate alternatives
according to native diagnostics; no missing case may silently become unsafe
unreachable code.

## 13. Resolution, lookup, construction and inference

Spelling: language-grammar §13 (decisions D18-D22).

### 13.1. Qualified resolution, shadowing and interface selection

Resolve a qualified head once, lexically, nearest scope first. Locals and
parameters may shadow imports and prelude entries. A parameter's own type
annotation is checked before the parameter enters scope, so
`fn open(read path: path.Path)` is legal; afterwards the nearest binding wins and
`path.name` in the body is value access. Namespace or type access through the
hidden import is diagnosed at that use, naming the shadowing declaration and
suggesting an alias such as `import std.path as p`. Never retry another
namespace after member typing fails. Conflicting explicit bindings in one scope
remain declaration errors. Declared modules and package-root bindings are
namespace heads too.

| Resolved head | Meaning of `head.name` |
| --- | --- |
| Module, package or imported namespace | Exported namespace item |
| Type or type parameter | Associated function, constant or enum variant (section 13.3) |
| Value | Field or receiver method |

If `List` resolves to a type, `List.new` is associated access; a permitted local
shadow of the prelude's `List` yields value-member access instead.
`T.(Interface).Item`, `.CONSTANT` and `.function(...)` select an interface item
explicitly. For a type parameter, including interface `Self`, `T.Item` is allowed
when its declared or elaborated bounds identify exactly one associated
declaration named `Item`; aliases and inherited exposures of one projection,
including its type/const/region substitutions, are deduplicated. Two distinct
candidates require explicit selection even if their types happen to be equal,
and concrete-type projections always use the explicit form. Adding a bound that
introduces a second candidate is an intentional source-breaking change: diagnose
both candidates and suggest, for example, `T.(Iterator).Item`; do not preserve
an earlier choice.

### 13.2. Bounded method lookup

Inherent methods have priority. Interface candidates come only from:
declared or elaborated generic bounds; the selected versioned prelude;
interfaces declared in the receiver type's owning package; and explicit
interface imports in the lexical scope. An interface found elsewhere in the
dependency graph is not a candidate, even if currently unique. Package
ownership is the resolved package identity, never a module-name heuristic, and
the native-library catalog records it for candidate selection.

Lookup uses indexed declaration metadata and the existing coherence and
visibility checks; several applicable candidates diagnose and require explicit
selection. Adding an unrelated external interface and implementation therefore
adds no candidate. Changes to the owner's interfaces, selected prelude,
explicit imports or declared bounds remain compatibility events and invalidate
the corresponding resolution queries. Std-owned writers see std's Writer
methods without an import; a custom type implementing an external Writer needs
the import, an explicit Writer bound or explicit selection.

### 13.3. Associated namespace and variants

A type has one associated namespace shared by associated functions, associated
constants and lowercase enum variants. A collision among them is a declaration
error. A declaration audit resolves each collision explicitly. `none`, `present`,
`success` and `failure` are
grammar-owned constructors for native optionals/outcomes, not unqualified
library-enum variants; user and library enums require qualification.

### 13.4. Constructor selection

`List<T, A = Global>` is contiguous and growable; `Map<K,V,S,A = Global>` and
`Set<T,S,A = Global>` (hash builder S defaults per D30) are hash-based with unspecified iteration order;
`SortedMap`, `SortedSet`, `LinkedList` and `Deque` remain explicit
alternatives. Empty ordinary construction allocates no storage.

| Call | Contract |
| --- | --- |
| `List<i32>()` | Zero-argument init, applicable only when `A = Global` |
| `List<i32, Arena>(allocator: take arena)` | Named-allocator init consumes the supplied allocator |
| `List<i32, Arena>()` | Error: there is no implicit Arena value |
| `String(text)` | Explicit UTF-8 copy into globally allocated owned storage |
| `String(text, allocator: take arena)` | Same copy using the supplied allocator |

Constructors are selected by explicit argument-label/arity shape with
declaration-checked applicability constraints; defaults cannot create
overlapping shapes. Never select by inferred return type, implicit conversion
or failure effect. Capacity and fallible factories stay separate operations;
general function overloading remains unsupported. Type arguments are inferred
from supplied arguments before defaults apply, and an explicitly selected
allocator type cannot fall back to Global. Generated field construction applies
only when no custom init exists; a custom init hides storage fields, and partial
failure drops initialized fields under the existing rules.

Declaration-checked conditional applicability under type equality, including
proof of `A = Global`, is a required constructor-checker capability, not a
`Global()` default placed in an arbitrary `A`.

### 13.5. Local builder inference

Gather constraints within one named function; nested function or closure bodies
do not infer the types of captured builders. Typed call parameters and local
uses may constrain a builder, which is solved before capture, return or escape;
call sites in other functions never determine a declaration's inferred result.
Process provenance by source span, applying hard type constraints before
literal fallback. Unsuffixed integers default to `i32` only after contextual
constraints are exhausted; unresolved generic parameters get no default. Branch
constraints participate regardless of traversal order. On conflict report the
earliest incompatible use in that order and the earlier constraint that fixed
the type. Matching numeric types, explicit narrowing/signedness conversions and
declaration-known ownership and error contracts are unchanged. Probe existing
support first; add solver work only for a demonstrated unresolved case.

## 14. Core semantics: ownership model, evaluation and cleanup

Settled constraints, ownership operations, accepted decisions and the semantic
acceptance corpus that the typing rules above refine.

### 14.1. Settled architectural constraints

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
- The debug profile enables integer overflow checks by default; the release
  profile disables them. `--overflow-checks on|off` overrides that default.
  Checked arithmetic panics
  on overflow, while unchecked add/subtract/multiply use the destination width.
  [The scalar rules](this document#3-scalars-and-arithmetic) define exceptional
  arithmetic and shifts; required constants use checked evaluation.
- Performance claims require [the measurement protocol](../process/performance.md).
  Syntax choices, optimizations and backend reuse alone establish no speed result.

### 14.2. Ownership operations

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

### 14.3. Initial semantic examples

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

### 14.4. Accepted decision: ordinary parameter values

Parameter mode selection is defined in
section 2.
Named parameters put explicit access before the binding (`read value: T`,
`mut value: T`, `take value: T`), independently of borrowed types after `:`.
Thus `take view: read T from r` transfers the view value while retaining its
original backing-storage lifetime and access restrictions.
Copyable values can avoid indirection; borrowing can avoid large byte copies.
Neither establishes the fastest ABI.

The rule mandates no physical register, stack slot, pointer, or memory copy.
ABI lowering may optimize representation only while preserving source-visible
behavior, including aliasing, address identity where exposed, and foreign calls.

Adding copyability may change default parameter semantics and is therefore a
potential source/API compatibility break.

#### 14.4.1. Accepted decision: generic parameter defaults

The operational owner is semantic-rules §2. Implied Copy constraints select the
same value default as explicit Copy bounds; adding either can change access
semantics and break compatibility. Mode selection requires no allocation,
retain or runtime capability test. Specialization may optimize representation,
not change observable aliasing or value/snapshot behavior.

### 14.5. Accepted decision: copyability eligibility

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

### 14.6. Routine rules selected under design delegation


#### 14.6.1. Explicit consumption

`take` consumes an owned source place even if its type is copyable. A `take`
parameter applies this contract without requiring a repeated call-site marker.
Ordinary copyable assignment and ordinary copyable value parameters still copy.
Taking a temporary transfers that temporary's value.

This preserves the blueprint's explicit consuming contract. Consumption does not
erase bytes, invalidate earlier independent copies, or create a security boundary.
Taking from a borrowed place is not permission to leave its owner's storage
uninitialized; use a sound replacement/extraction operation instead.

#### 14.6.2. Bindings, places, and initialization

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

### 14.7. Loans and access validity

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
moves, or active exclusive loans. section 5 specifies activation
and exceptional argument cleanup; it is not a license to waive alias checks.

Statically validated loans require no runtime borrow counter; checked splitting
and interior-mutability containers may have runtime costs.

### 14.8. Returned values and regions

`: T` returns a value: move owned non-copy state or duplicate a value under a
declared Copy capability. A read parameter cannot become an owned resource
without an explicit ownership-producing operation.

#### 14.8.1. Optional result annotations

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

#### 14.8.2. Borrowed results

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

### 14.9. Evaluation order

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

Call arguments are positional-then-named (`call_argument`, language-grammar section
14.9). Named arguments may reorder the remaining parameters; duplicate labels,
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
destination place once, then replace its old value. Destructuring assignment first
evaluates its RHS, then performs component assignments left to right. It is not
transactional; interruption may leave earlier component assignments completed.

Compound assignment uses a declaration-based distinction:
known primitive operands evaluate RHS before the destination; overloaded cases
follow receiver-then-argument call evaluation with the applicable implicit
receiver reservation rules. Monomorphization must not change that order.
Do not casually lower compound assignment into ordinary assignment, duplicate
destination evaluation, or introduce a copy requirement.

Pure independent work may reorder when observable effects are preserved.
Defaults execute only when omitted, without a runtime argument dictionary.

### 14.10. Destruction and failure edges

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

The exceptional-CFG obligations are in this document. Externally borrowed
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

### 14.11. Temporary scope baseline

Assign every materialized temporary a destruction scope in typed IR. For the
initial core, call-argument temporaries live through the call and ordinarily to
the enclosing statement boundary; a reference returned from such an argument
cannot outlive its backing temporary.

Provide declaration-based temporary lifetime extension for direct borrowed
initializers where the language explicitly assigns the temporary to the binding's
enclosing block. Do not infer arbitrary extensions by looking into callees.
Declaring a named owner first is the general explicit alternative.

this document supplies the scope table for conditions, short-circuit
operands, guards/scrutinees, tails, optionals, capture and defaults. Drop timing
is observable and cannot change solely for performance.

### 14.12. Semantic acceptance corpus

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

### 14.13. Specification refinements and implementation gate

Owning refinements:

- this document supplies the typing/state framework, CFG joins, receiver
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

### 14.14. Contract authority

The native rules in this document and its owning refinements specify copying,
retention, argument and assignment evaluation, temporary lifetimes and cleanup.
External language behavior is not a fallback for an unspecified native rule.
An uncovered interaction is a specification gap requiring an explicit decision.
