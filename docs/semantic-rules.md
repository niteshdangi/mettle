# Core typing and operational rules

Status: selected operational refinement of [core-semantics.md](core-semantics.md),
not a formal safety proof.

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

For an omitted function result, introduce one result variable for the
declaration, not one per call. Constrain it from reachable explicit returns and
normal body completion. Bare returns/fallthrough contribute `Unit`; established
divergence contributes `Never`. Use the existing joins and coercions, not an
automatic union or numeric conversion. An explicit `: T` instead fixes the
expected result. `Unit` is the type and `()` its value, never a type spelling.
Solve recursive result components together; unresolved cycles require
annotations rather than a `Unit`/`Never` default. Call-site context cannot supply
a missing declaration result. Error effects and ambiguous returned-view sources
remain explicit contracts under core-semantics section 8.

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
as are tuples/fixed arrays. Named product/enum types retain explicit opt-in.
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
`core.ops.IndexRange` (`fn index_range(start: usize, end: usize): read
Self.Output from self`) or `IndexRangeMut`; an absent upper bound is passed as
`usize.MAX` and `..=b` as `b + 1`. Outside indexing, `a..`, `..b`, `..=b`
and `..` are `core.iter.RangeFrom`, `RangeTo`, `RangeToInclusive` and
`RangeFull` values; only `RangeFrom` iterates.

The compiler recognizes the interfaces by canonical path, like `core.ops.*`:
`core.iter.Iterator` (`type Item; mut fn next(): Self.Item?`),
`core.iter.OwnedIterable` (`fn into_iter(receiver self: take Self)`),
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
`fn iter<region r>(receiver self: read Self from r): Self.Iter<region r>`; the loop
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
`fn open(path: read path.Path)` is legal; afterwards the nearest binding wins and
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

`List<T, A = Global>` is contiguous and growable; `Map<K,V,A = Global>` and
`Set<T,A = Global>` are hash-based with unspecified iteration order;
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

## Primary comparison sources

- https://doc.rust-lang.org/1.99.1/reference/expressions/operator-expr.html
- https://doc.rust-lang.org/1.99.1/reference/expressions.html
- https://doc.rust-lang.org/1.99.1/reference/destructors.html
- https://rustc-dev-guide.rust-lang.org/borrow_check/two_phase_borrows.html
- https://doc.rust-lang.org/nomicon/subtyping.html
