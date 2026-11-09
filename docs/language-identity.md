# Rejected identity proposal: verified native programming

Status: rejected adoption proposition, not accepted grammar or V1 scope.
The accepted identity is recorded in [decisions.md](decisions.md) D16-D17;
[adoption-rationale.md](adoption-rationale.md) evaluates adoption separately.

## Decision boundary

The proposal was native programming with integrated refinements, pre/post/frame
conditions, representation invariants and erased proofs. Its proposed advantage
was less effort to establish the same correctness properties without weaker
assumptions or worse runtime. That advantage was not demonstrated: Dafny and
Verus already provide verification, and borrow checking alone proves neither
algorithmic correctness nor concurrent behavior.

Rejection adds no verifier, proof syntax or verification release gate to V1.
Real-time robotics and durable distributed applications were also discussed but
not accepted. Reconsidering any of these directions requires explicit acceptance
and coordinated changes to scope, grammar, semantics, trust model, milestones
and acceptance corpus; it cannot silently replace accepted capabilities.

## Primary sources

- Rust's memory-safety/non-safety distinction:
  https://doc.rust-lang.org/reference/behavior-not-considered-unsafe.html
- Dafny contracts: https://dafny.org/latest/DafnyRef/DafnyRef
- Verus proof/specification/executable modes:
  https://verus-lang.github.io/verus/guide/modes.html
