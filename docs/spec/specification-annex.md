# Specification annex: selected rules

Normative refinements. Explicit owner decisions take precedence; this annex supersedes earlier unspecified rules.

## 1. Numeric operations and constant evaluation

All primitive integer types use the widths and overflow policy in semantic-rules.
Conversions do not invoke user code. Unsuffixed integer literals default to i32
only after contextual constraints have been solved; conflicting constraints are
errors, not implicit widening.

Float types are IEEE binary32 and binary64. Ordinary arithmetic uses round-to-
nearest, ties-to-even. No implicit contraction/reassociation, flush-to-zero,
finite-only assumption, or disregard of signed zero is permitted. Explicit
fused multiply-add has one rounding; multiplication followed by addition does
not silently acquire that guarantee.

Ordinary float operations do not throw typed errors. Division by zero and invalid
operations produce IEEE infinities/NaNs as applicable. Float equality follows
IEEE rules; a total-order operation is separate. Arithmetic may quiet signaling
NaNs; their payload/sign are not preserved as a language guarantee. Bit
construction/inspection operations preserve supplied bits until an operation
whose contract permits changing them.

Integer-to-float conversions round to nearest, ties-to-even; unrepresentably
large values produce signed infinity. Float widening is exact for finite values.
Float narrowing rounds similarly and overflows to infinity. Float-to-integer
casts truncate toward zero, map NaN to zero, and clamp infinities/out-of-range
values to the destination range. Explicit checked conversions are provided when
clamping is not the requested operation.

Floating literals are rounded directly to the contextual destination type,
without an intervening host double rounding. Do not use the build host's native
floating settings to determine target constants.

Fast-math is an explicit function/module option listing enabled relaxations.
It is not enabled by ordinary release optimization. Code using relaxed arithmetic
is compared with Rust using equivalent relaxations, not default strict code.
Foreign code must restore any process floating environment required by the
selected target ABI before returning to ordinary Mettle execution.

Required constants use checked integer arithmetic in every build profile.
Explicit wrapping/checked/saturating forms retain their stated behavior.
Overflow, invalid shift, zero division, invalid pointer construction or an
unsupported required operation is a const-evaluation diagnostic. Constant folding
of an ordinary runtime expression must instead preserve its runtime profile.

The initial numeric composition surface admits every primitive integer type as
a const parameter, including contextual unsuffixed arguments, checked integer
expressions and full-width substitutions. Literal/range patterns and integer
range iteration preserve the endpoint type; inclusive iteration never increments
past its final endpoint. Required array counts retain their declared integer
type and are checked against compiler resource limits before internal narrowing.
Implementation restrictions do not establish new language-level index contracts.

`value.checked_cast<Integer>()` returns `present(converted)` or `none`.
Integer sources must be in the destination range. Floating sources are truncated
toward zero first; NaN, infinity and a truncated result outside the integer range
return `none`. Ordinary `as` casts retain the clamping policy above.

`@fast_math(...)` on a function or module lists individual relaxations:
`reassociate`, `contract`, `no_nans`, `no_infinities`, `no_signed_zeros`,
`reciprocal`, and `approximate_functions`. Module options apply to functions in
that module and descendants; function options add to them. Unknown, duplicate or
empty options are errors, not an implicit all-relaxations mode. Checked conversion
validity checks remain strict even inside a relaxed function. These options do
not alter literal rounding or enable process-wide flush-to-zero behavior.

## 2. Higher-ranked constraints and associated types

Use declaration-based generic checking. The constraint environment consists of
type equalities, trait/interface obligations, const equalities, outlives edges and
well-formedness obligations. Elaboration expands superinterfaces and associated
constraints without granting additional caller ownership modes.

Unification performs an occurs check. Recursive data types are represented through
their explicit indirections, not an infinite unification substitution.
An unresolved associated projection remains symbolic until a uniquely selected
implementation or a declared equality normalizes it.

Normalize projections under their declared bounds, substitute implementation
parameters capture-avoidantly, and generate obligations for those substitutions.
Do not select between overlapping implementations by compilation order.
A cycle that yields no new justification does not prove an ordinary interface
obligation. Recursive auto-property derivation may use coinduction only for the
explicitly structural Transferable/Shareable/Sized-like property rules.

For `for<region r>`, checking an implementation introduces a fresh rigid region
in a fresh universe. A caller instantiation introduces region variables subject
to the binder and outlives obligations. No variable from an outer universe may
be solved using a younger rigid region that would escape its binder.
After solving, perform a leak check on substitutions and pending obligations.

Associated types with region parameters apply these binder rules at each
instantiation. Equality of two projections requires normalized equality or a
declared constraint; their spelling or similar storage layout is insufficient.

User-declared structural properties respect field types, generic parameters,
negative declarations and unsafe manual implementations. Negative declarations
win over automatic derivation. They do not authorize overlapping ordinary
implementations or constitute a general unrestricted specialization system.

Finite resource budgets report inconclusive/resource exhaustion separately from
invalid source. Solver caching includes the canonicalized environment and binder
universes; cached success must not leak a local region into another query.

## 3. Closures and parameter patterns

Infer capture places at the narrowest sound projection. Read access captures a
read view; mutation captures an exclusive view; moving out requires owned
capture. Overlapping captured projections merge at their common owning place.
Taking an entire aggregate and a field of it is not two independent captures.

An explicit take closure owns captures. Copyable captures duplicate unless
explicitly taken; shared owners move, not retain. Ownership capture does not
force heap allocation. Regions of borrowed fields still constrain an owned
aggregate capture.

Capture initialization follows first lexical occurrence of the captured place
in the closure body after hygienic expansion. After projection merging, use the
earliest occurrence of any merged child. Destroy captures in that resulting
field order.

Callable capability is inferred from body use: consuming a capture requires
consume-on-call; mutating requires mutate-on-call; read-only repeated use permits
read-on-call. An owned-capture closure can still be repeatedly callable if its
body does not consume captured values.

At function entry, arguments occupy parameter slots in declaration order.
Bind irrefutable parameter patterns left-to-right within each slot. A consuming
binding transfers its component into a local binding; untouched components
remain in the parameter slot. Drop pattern locals in reverse binding order,
then remaining parameter slots in reverse parameter order after body locals.
Every component has exactly one initialization/drop owner.

A failed argument/default evaluation occurs before entry and therefore cleans
caller-side constructed operands, not callee pattern bindings that never existed.
On successful entry, moving the ownership marker to the parameter slot must not
run user code or duplicate destruction.

## 4. Macro recognition and phase rules

Matchers are deterministic token-tree recognizers. Try declaration rules in
order; select the first full match. Ambiguity within a matcher is an error,
not an implementation-dependent choice. A selected expansion that later fails
typing does not cause fallback to another matcher.

Native fragment follow sets at a matcher boundary:

| Fragment | Permitted immediately following token |
| --- | --- |
| expr, stmt | `=>`, `,`, `;`, or the enclosing closing delimiter |
| pat | `=>`, `,`, `=`, `if`, `in`, or closing delimiter |
| ty, path | `=>`, `,`, `=`, `;`, `:`, `>`, `>>`, `{`, `[`, `where`, or closing delimiter |
| ident, literal, tt, block, item | Any token that does not make the enclosing matcher locally ambiguous |

Newline separators in token trees are explicit separator tokens for fragments
that consume native statements; they count as semicolon's follow position
without changing block-tail meaning. A repetition must satisfy the follow rules
between iterations, at its separator, and on every possible exit path.
Optional repetitions cannot have a repetition separator.

Generated identifiers resolve hygienically in the macro definition/expansion
context. A metavariable preserves its captured context. `$capture(identifier)`
in a declarative expansion explicitly creates an invocation-context identifier.
The host token API exposes equivalent definition-site, invocation-site and fresh
identity constructors, each retaining provenance.

Expand cfg conditions before executing disabled attributes/macros. On a retained
item, execute transforming attributes in written order; each receives the output
of its predecessor. Run derive expansions on the resulting item in written order.
Generated items enter the work queue in expansion order. Re-resolve macro names
as declarations become available; unresolved cycles must diagnose a cycle or
resource exhaustion, not silently produce incomplete items.

Declarative macros occupy a namespace distinct from values and types. Explicit
single-name and grouped imports bind macros in that namespace before expansion;
`pub import` reexports them, while a private import does not. Macro import
ambiguity is a name error. Restricted `pub(path)` boundaries apply uniformly to
functions, types, constants, statics and macros; the boundary must name an
enclosing module.

The extension host API is versioned independently from compiler internals.
A plugin declares its required API major version and minimum minor capabilities.
Reject incompatible major versions or unavailable capabilities before executing
it. Never reinterpret an old token/span layout as a new binary object layout.
This is an API protocol rule, not a mandatory sandbox.

## 5. Attributes, layout and assembly

Attribute names resolve in the attribute/macro namespace. Built-ins have fixed
schemas; procedural attributes have versioned token inputs. Duplicate singleton
attributes are errors even when the arguments are identical.

Layout rules:

- align(N) and packed(N) require powers of two in 1..2^29, further bounded by
  the target object's representable alignment. Unsupported target alignments
  diagnose an unsupported layout instead of silently rounding.
- align and packed cannot both appear on one type. A packed type may not
  transitively contain an explicitly alignment-raised type without indirection.
- layout(C) may combine with either align or packed under the target C layout
  rules. An enum integer representation must be a supported integer type.
- Integer enum representation and C layout may combine only where the selected
  target layout rule defines the tag/payload arrangement.
- Native-layout generics do not acquire a stable ABI from accidental equality
  of their current size/offsets.

The transparent layout/newtype ABI and additional library/harness/codegen
attributes are defined in library-surface.md.

`cfg` is a boolean expression over named target facts and declared package
features using `all`, `any`, and `not`. Unknown target fact names are errors;
undeclared package features are configuration errors. Conditional fields affect
layout and public API identity.

`export_name` and `link_name` accept one constant string, forbid embedded NUL,
and must satisfy the target object format. `target_feature` accepts a list of
recognized feature names. Calls require established feature availability unless
a compiler-generated runtime dispatch guard establishes it.

`diagnostic` accepts a known diagnostic/lint identifier and one of allow, warn,
deny. It cannot suppress type errors, unsafe validity requirements or required
capability checks. `nonexhaustive` applies to enums/structs and has module/package
boundary semantics; it is not a switch disabling internal exhaustiveness.

Assembly operand syntax:

```text
asm!(templates...,
     name = in(register_class) input,
     name = out(register_class) destination,
     name = lateout(register_class) destination,
     name = inout(register_class) input => destination,
     name = inlateout(register_class) input => destination,
     name = const constant_expression,
     name = sym symbol_path,
     clobber_abi("C"),
     options(...))
```

An explicit register string may replace a register class. `_` discards an output.
Read inputs before assembly executes, evaluate destination places once, and
establish declared outputs only after normal completion. Early outputs may
clobber registers before all inputs are consumed; late outputs promise otherwise.
Register conflicts, reserved registers, and operand type/class mismatches are
compile-time errors.

Use the frozen baseline's supported per-target register names/classes and
template-modifier tables as the initial instruction-interface inventory. These
are target facilities. Record deviations in
the target manifest; do not silently omit a promised stable target operation.

Supported options have explicit contracts: nomem, readonly, preserves_flags,
nostack, noreturn, pure, raw, and target syntax selection. pure requires nomem or
readonly and an observable output; pure+noreturn and nomem+readonly are invalid.
Unspecified memory/flag effects remain conservative. Incorrect unsafe options
violate the caller's contract; a compiler must not infer them from an assembly
string it does not understand.

Provide global assembly and naked-function assembly variants. Naked functions
have no compiler-created frame/prologue/epilogue and must implement the declared
ABI themselves. Assembly that unwinds needs an explicitly supported unwind form
and target metadata; ordinary inline assembly cannot unexpectedly unwind.

## 6. Versioned baseline incorporation

Frozen instruction/register tables, target C ABI facts and per-operation
contracts remain normative input for unmigrated operations under
[baseline-mapping.md](../process/baseline-mapping.md). Operations assigned to a standalone
native specification in its section 7 use that specification as authority;
their frozen records remain audit provenance.
Conflicts with native rules reopen mapping; incorporation is not qualification.

## 7. Coherence, erasure and opaque types

An ordinary interface implementation is permitted when either its interface or
its implementing nominal type is defined by the current package. Transparent
aliases do not create a new local type. For foreign interfaces, uncovered generic
parameters before the first local type cannot be used to circumvent that rule.
Use explicit local wrapper/adapter types for otherwise foreign pairs.

Two ordinary implementations that can apply to the same substitution overlap
and are rejected. Test overlap under the declared constraints and permitted
downstream implementations, not merely the implementations currently imported.
No priority-by-import-order or unrestricted specialization is implied.

An erased interface value contains the required data/dispatch metadata but does
not acquire an implicit heap owner. A borrowed erased value retains its region;
heap erasure explicitly owns its storage. The native representation is not a
stable foreign ABI.

A dispatchable method must have a supported receiver, no caller-selected type
or const parameters, and no use of unbound Self in its public inputs/outputs.
Receiver/associated types needed by the method must be fixed in the erased
interface contract. A method explicitly constrained to sized concrete Self is
unavailable through erasure but may coexist in the interface.
`Future.poll` is dispatchable through `any Future<Output = T>`: the output
binding is fixed, and its pinned mutable receiver does not move the erased
payload. This does not make arbitrary consuming or pinned receivers dispatchable.

Generic region parameters do not by themselves require monomorphized dispatch.
Associated type families that cannot be represented in a fixed erased signature
require an explicit adapter; do not silently box their results.
An erased async method declares its returned future-storage/erasure contract.
Concrete async interface methods retain concrete state with no mandatory heap
allocation; requesting dynamic dispatch is a separate operation.

Each opaque return declaration introduces a distinct hidden concrete type.
All return paths must select that same type after substitution. Its captures
include referenced generic types/consts and regions that the declared return
contract permits. The checker diagnoses a hidden borrowed dependency that is
not admitted by that contract.

## 8. Runtime implications

Compare equivalent numeric modes, layout/assembly promises, dispatch and scoped
task lifetimes under [performance.md](../process/performance.md). Region solving requires
no runtime region objects. Capture destruction follows the deterministic order
specified in section 3.
