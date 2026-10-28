# Rejected identity proposal: verified native programming

Status: rejected as the desired adoption proposition in the subsequent discussion.
Retained only as a record of the proposal; it must not drive grammar or V1 scope.
See `adoption-rationale.md` for the current problem-first analysis.

## The proposition

Mettle is for developers who need native programs whose declared correctness
properties can be checked before execution.

Working positioning: "Native code. Declared rules. Checked proofs."

The distinction is not speed, a deployment framework, or shorter Rust spelling.
It is a language that treats a program's intended properties as first-class
declarations and checks selected implementations against them.

Initial audience: authors of parsers, protocol implementations, foundational
collections, numeric transformations, and other libraries where a small wrong
result can propagate widely. This is a proposed audience, not validated demand.

The reason to switch would be substantially lower effort to establish and
maintain explicit correctness properties while preserving native performance.
That benefit must be demonstrated against existing verification options.

## A concrete language-level difference

Illustrative syntax outside the accepted core grammar:

```text
verified fn clamp(value: i32, low: i32, high: i32) -> i32
    requires low <= high
    ensures result >= low && result <= high
{
    if value < low {
        low
    } else if value > high {
        high
    } else {
        value
    }
}
```

The declaration asks for a compile-time proof of the postcondition whenever
the precondition holds and the function returns normally. This particular body
uses comparisons and selection, so it introduces no integer-overflow complication.
It also terminates structurally; that does not establish general termination.

If the upper branch mistakenly returns `value`, the verifier should reject the
proof obligation. A counterexample is value=11, low=0, high=10. This is a wrong
answer despite valid memory accesses and well-typed ordinary arithmetic.

This is not a runtime assertion disguised as a proof. Proven specification-only
expressions are erased. Unproven obligations cannot silently become assumptions.
The range contract is intentionally incomplete: it does not by itself require
preserving every already-in-range input. Stronger intended behavior needs a
stronger specification. Verification does not read the author's mind.

## Coherent language features supporting this identity

1. Refinement types: values carrying checked predicates such as a nonzero
   divisor, a validated byte range, or an index bounded by a particular view.
2. Preconditions, postconditions, and frame conditions: describe permitted
   inputs, guaranteed outputs, and which storage a function may change.
3. Native proof/specification expressions: reusable pure definitions and
   explicit loop invariants, erased from executable code.
4. Representation invariants: types maintain relationships between their
   fields across public operations, with ownership controlling mutation.
5. Explicit verification boundaries: native and foreign dependencies expose
   proven, runtime-validated, or trusted contracts without conflating them.

Units, state transitions, and shape relationships may be useful applications of
the type/contract system, but need not each become a separate special-purpose
language subsystem.

## Static, dynamic, and trusted boundaries

For a verified call, establish its precondition from the caller's verified
context or an explicitly successful validation branch. Input from a file or
network is not valid merely because a function accepts a refined type.

Where static proof is unavailable, an explicit fallible validator can check
a decidable executable predicate and produce a validated value. This costs
runtime work. Pure proof-only predicates are not necessarily executable checks.

Trusted foreign contracts and unsafe assumptions are part of the trust boundary.
Mark them visibly and include them in verification reports; do not describe
assumed dependencies as verified implementations.

Distinguish a counterexample, unsupported verification construct, and solver
timeout/unknown. None may be reported as successful verification. Compiler
resource exhaustion is not proof that a valid program is wrong.

Ordinary Mettle remains available outside verified regions. Verification is not
a new mandatory permission framework or a ban on capabilities in the existing
Rust-parity commitment. Whole-program verified claims require all relevant
boundaries to be accounted for.

## Arithmetic, ownership, failure, and concurrency

Proof semantics must match executable integer widths, overflow profiles, and
floating-point behavior. Mathematical integers cannot silently substitute for
wrapping machine integers. A theorem relying on one profile does not automatically
apply to another.

Specify normal return, typed failure, panic, and divergence separately. A normal
postcondition proves neither no-panic execution nor termination. State those
additional properties explicitly when required.

Leverage ownership for framing and noninterference, but do not pretend ordinary
borrow checking proves arbitrary concurrent algorithms. Atomics, interior
mutability, aliasing, and async cancellation require their own proof rules.

Start verification with pure scalar functions and finite owned data, then expand
only with explicit semantics. This is a verifier implementation sequence, not
permission to reduce the underlying language's V1 capabilities.

## Rust and existing verification languages

Rust's own Reference distinguishes memory/unsafe obligations from undesirable
behaviors such as deadlock and leaks. Our desired contracts go beyond a generic
claim of memory safety.

Dafny already integrates specifications and automated verification. Verus
verifies Rust systems code and erases proof/specification code rather than adding
runtime checks. Therefore "Rust cannot be verified" and "Mettle invented program
verification" would both be false positioning.

The proposed Mettle advantage must instead be a measured combination of native
resource control, integrated contracts, simpler proof authoring, and predictable
interoperation with ordinary code. It must earn that advantage through examples,
not merely include a `verified` keyword.

## Performance and cost

Erased proofs need not add application runtime work. Equivalent Mettle and Rust
implementations should still be compared under the accepted runtime gate.
Optional runtime validation, representation changes, and externally checked
contracts have explicit costs; verification is not blanket "zero overhead."

Proof checking can substantially increase build time and require invariants or
lemmas from authors. This is compatible with measuring compilation separately,
but remains a usability cost, not a free benefit.

A verified source theorem does not prove the production compiler/backend or
hardware correct. Define the trusted base: specification semantics, verifier
translation, solver/proof checker, compiler lowering, libraries, foreign code,
and execution assumptions.

## What would establish a reason to switch?

Use a small set of complete libraries, not toy annotations:

- A binary parser with established bounds and selected format invariants.
- A ring buffer with capacity, index, and element-preservation properties.
- A numeric transformation with profile-correct range guarantees.

Compare ordinary Rust, Rust with Verus where supported, and Mettle under matched
specifications. Measure properties established, proof/specification code,
modification effort, proof checking time, supported constructs, trust assumptions,
diagnostic repair, and runtime.

Success is less effort for the same properties without weaker assumptions or
worse runtime. Failure to demonstrate that means this proposition has not earned
adoption; it is not grounds to mislabel competitors.

## Decision boundary

This proposal changes the language's verification/type-system ambitions and
compiler workload. It is not silently added to V1, nor does it replace the user-
accepted capability requirements. If adopted, revise the feature matrix, grammar,
semantics, proof/trust model, milestones, and acceptance corpus together.

The other discussed identities (real-time robotics and durable distributed
applications) are not accepted language directions and are not added to the plan.

## Primary sources

- Rust Reference, behaviors not classified as unsafe:
  https://doc.rust-lang.org/reference/behavior-not-considered-unsafe.html
- Dafny overview:
  https://dafny.org/
- Dafny reference, contracts and specification constructs:
  https://dafny.org/latest/DafnyRef/DafnyRef
- Verus overview:
  https://verus-lang.github.io/verus/guide/
- Verus specification/proof/executable modes:
  https://verus-lang.github.io/verus/guide/modes.html
