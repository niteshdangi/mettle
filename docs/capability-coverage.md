# Capability coverage

## Baseline and evidence

Reference: Rust 1.99.1 stable, edition 2024, pinned source commit
`58cf8f9c35b355199727627d07ae34a4e2846d67`. The official source/documentation
archive hashes and reproduction instructions are in
[baseline/README.md](baseline/README.md) and
[baseline/sources.json](baseline/sources.json).

[capabilities.csv](capabilities.csv) assigns specification owners to all 107
requirements. Its `implementation_status` is the specification-freeze snapshot;
current progress belongs to the [implementation plan](implementation-plan.md)
and revision-bound receipts. Library declarations do not cover the separate
language/compiler/ABI/tooling requirements.

## Row interpretation

- `id`: persistent requirement identity, L001-L060, S001-S031, A001-A009, T001-T007.
- `rust_capability` / `mettle_direction`: capability and native design.
- `layer` / `phase`: dependency layer and earliest development phase, not a reduced V1 commitment.
- `status`: specified means a selected native contract exists, directly or by explicit frozen-baseline incorporation.
- `specification`: owning document/section links, separated by `|`.
- `implementation_status`: not_implemented at specification freeze; no current checking/execution evidence is implied by this snapshot.
- `required_evidence`: mandatory later positive/negative or integration evidence, not a passing result.

## Library operation inventory

The source-backed inventory records 35,345 public/documentation pages, 123,118
associated items and 82,270 implementation relations: 240,733 exposures/contexts.
It preserves reexports, runtime/const distinctions, experimental APIs, generated
properties and source cfg evidence. Counts are not independent stable APIs.
Exact classifications/canonical totals are in
[audit-summary.json](baseline/audit-summary.json).

The auditor verifies both archives and the complete extracted Rust library source
file set, enumerates case-sensitive archive names, and cross-checks every archived
all.html link. The validator checks declaration closure, reexport identity,
implementation/interface-member stability, native-rule assignments and named
conditional supporting protocols. Its result binds to the operation manifest
digest in [validation.json](baseline/validation.json).

[baseline-mapping.md](baseline-mapping.md) and
[library-surface.md](library-surface.md) specify recursive native operations,
standalone authority assignments and an explicit fallback for unmigrated
contracts. A contract assignment
does not mean its native declaration has compiled. Source cfg predicates retain
their enclosing module/macro context; unrendered applicable source branches are
still obligations. No executed all-target expansion or per-item native coherence
check is claimed.

Generate the I13 [worklist](baseline/v1-operations.csv) with
`python3 tools/v1_operations.py`; it is the only record of per-operation status
(missing, declared, evidenced, not applicable, blocked) and evidence tests.
Missing or unmapped is not proof of absent code; declarations and name matches
are not behavioral passes. Per-area progress and receipts belong to the ledger
and to revision-bound evidence bundles, not to this document.

## Equivalence policy

Native syntax does not weaken the promised safe capability.
Do not silently require allocation, runtime checks, unsafe caller code, erased
types, weaker regions or weaker complexity where the equivalent baseline does
not. An actual conflict is a specification defect and reopens the documentation
gate; an unimplemented contract is an implementation failure.

Different defaults are intentional: ordinary non-Copy parameters borrow,
explicit take consumes even Copy sources, and shared handles move unless
explicitly retained. Compare programs requesting equivalent operations, not
superficially identical spelling.

## Capability status

Per-capability implementation status and evidence fixtures are not kept in this
document. Each row of [capabilities.csv](capabilities.csv) owns its specification
and required evidence; an implementation status change needs a revision-bound
evidence bundle ([implementation-plan.md](implementation-plan.md) section 9).
The frozen CSV `implementation_status` is not a progress indicator.

Acceptance has independent axes: expressibility, sound observable semantics
and measured runtime. A faster unsafe replacement cannot satisfy a safe API;
an equally expressive but slower implementation can fail the runtime gate.
The initial inventory and documentation checks establish none of these runtime
or safety results.

## Unstable-feature register

Not automatically committed: unrestricted overlapping specialization, generalized
const expressions beyond the stable baseline, custom auto traits, unrestricted
negative user-interface implementations and experimental coroutine APIs.
Nightly-only declarations remain visible in the inventory without becoming
stable native requirements.

Default/sealed/compiler-controlled helpers used by stable calls have explicit
[supporting-protocol mappings](library-surface.md#8-conditional-supporting-protocols).
Those mappings preserve valid stable uses, not every experimental implementation
right. Native negative thread properties, allocator control and borrowed scopes
remain accepted independently of similarly named Rust nightly features.

For additions, record a concrete use case, alternatives, interactions, cost,
runtime effects and acceptance. Rejected identity proposals do not expand scope.
