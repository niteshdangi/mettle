# Specification status and capability coverage

## Documentation completion gate

Status: closed for the pre-implementation specification baseline. No specification
document certifies implementation, qualification, performance or a safety proof;
those claims need revision-bound evidence.
Standalone native-operation migration is partial; the original closure included
reference-owned operation contracts and does not certify their replacement.
Implementation and release qualification are tracked in the
[implementation plan](implementation-plan.md).

### Authority

1. Explicit accepted user decisions and architectural commitments.
2. Selected native rules and routine refinements under delegated authority.
3. Marked research, proposals and future product decisions.

The Word blueprint is an earlier snapshot. Accepted decisions govern later
parameter, Copy and ownership rules. Extended grammar supersedes subset
productions; annexes refine broad descriptions. Rejected identity research
does not expand grammar or V1 scope.

### Specification coverage

| Area | Owner |
| --- | --- |
| Architecture and release progression | [decisions](../spec/decisions.md), [implementation plan](implementation-plan.md) |
| Syntax | [grammar](../spec/language-grammar.md) |
| Ownership, typing and cleanup | [semantic rules](../spec/semantic-rules.md) |
| Advanced mechanisms and memory | [advanced contracts](../spec/advanced-contracts.md), [annex](../spec/specification-annex.md), [memory model](../spec/memory-and-concurrency.md) |
| Libraries and ABI | [library/ABI](../library/library-and-abi.md), [native value contracts](../library/native-value-contracts.md), [mapping authority](baseline-mapping.md#7-native-operation-authority), [surface](../library/library-surface.md) |
| Core and allocation operation definitions | [native core contracts](../library/native-core-library-contracts.md), [native collection contracts](../library/native-collection-contracts.md) |
| Hosted and OS operation definitions | [native hosted contracts](../library/native-hosted-contracts.md), [native OS contracts](../library/native-os-contracts.md) |
| Architecture operation definitions | [native machine contracts](../library/native-machine-contracts.md) |
| Packages and tools | [tooling](../spec/tooling-and-packages.md) |
| Toolchains and profiles | [pins](../toolchain-pins.json), [profiles](../spec/platform-contracts.md#8-reference-profiles), [platform contracts](../spec/platform-contracts.md) |
| Performance and release | [performance protocol](performance.md) |
| Capability obligations | [107-row inventory](../capabilities.csv) |

### Completion evidence

[baseline/validation.json](../baseline/validation.json) must pass for the current
operation-manifest digest with no failures. Re-run the
[baseline validator](../baseline/README.md#inputs-and-reproduction) when changing
the operation inventory or its audit logic. For authored documentation-only
changes, check affected links and the changed contracts; do not rebuild the
compiler or rescan the entire operation inventory. The receipt does not certify
subsequently authored contracts. The baseline README owns inventory counts,
provenance, interpretation and validation boundaries.

A contradiction or unavailable native construct reopens this gate. Missing
implementation does not remove the selected contract.

### Standalone contract migration

Core-language copying, retention, evaluation and cleanup use native rules.
Optional/outcome methods and additional library/machine families now have
standalone native definitions;
their exact operation assignments are in
[the authority register](baseline-mapping.md#7-native-operation-authority).
This is specification work, not a new implementation receipt.

Reference-owned contracts remain for unassigned operations. In particular,
unlisted library/implementation members, uncommon OS error mappings and
instruction/register tables are not closed by a family heading.
Removing their references before defining and checking native signatures,
effects, failure, complexity, unsafe invariants, constants and target conditions
would reopen specification coverage. Benchmark and frozen-provenance references
are intentionally separate.

#### V1 priority and deferred migration

The remaining migration is scheduled by the existing
[I13-I17 scope](implementation-plan.md#85-workflow-profiles-and-v1-i12-i14),
not by the number of external references:

| Work | Required timing |
| --- | --- |
| Contradictory or incomplete contracts for the selected V1 subset, its supporting protocols and Linux target branches | Resolve before the affected I13 acceptance or I14 qualification. A recorded reference fallback may supply an unassigned contract; conflicting native rules still require reconciliation. |
| D30 Map builders and D31 BorrowedOrOwned/Cow bounds | Preserve the accepted policies. Reconcile declarations and fixtures before qualifying affected V1 operations; retain non-Clone borrowed/read Cow usage and explicit randomized-builder selection. These are open implementation/type-checking obligations, not completed by the native chapters. |
| Contracts and applicability belonging only to the retained post-V1 subset and other profiles | Track with I17; implement earlier only when an existing V1 or I15/I16 dependency requires them. |
| Exhaustive standalone replacement of otherwise specified reference-owned contracts | Defer until needed for the owning operation; retain the explicit authority fallback in the meantime. |
| Cosmetic reference removal | Defer. Preserve frozen provenance, benchmark comparisons and actual interoperability requirements. |

This scheduling does not move an existing V1 obligation to I17 or make complete
reference removal an I14 gate. The
[remaining-work gates](post-v1-worklist.md#remaining-review-and-implementation-gates)
retain source-cfg, implementation-state and evidence review. Unresolved scope or
an unavailable native construct remains a blocker for the affected acceptance
gate; documentation edits do not resolve it.

### Deliberately separate evidence

This gate checks specification consistency, not parser/example execution,
native API typechecking, all-target cfg expansion, layout/ABI, memory safety,
toolchain installation, supported platforms or measured adoption/performance.
Those require implementation/release evidence. Licensing and public registry
governance remain owner decisions before publication; native builds require
neither Rust nor a compulsory sandbox, permission framework or executor.

## Capability coverage

### Baseline and evidence

Reference: Rust 1.99.1 stable, edition 2024, pinned source commit
`58cf8f9c35b355199727627d07ae34a4e2846d67`. The official source/documentation
archive hashes and reproduction instructions are in
[baseline/README.md](../baseline/README.md) and
[baseline/sources.json](../baseline/sources.json).

[capabilities.csv](../capabilities.csv) assigns specification owners to all 107
requirements. Its `implementation_status` is the specification-freeze snapshot;
current progress belongs to the [implementation plan](implementation-plan.md)
and revision-bound receipts. Library declarations do not cover the separate
language/compiler/ABI/tooling requirements.

### Row interpretation

- `id`: persistent requirement identity, L001-L060, S001-S031, A001-A009, T001-T007.
- `rust_capability` / `mettle_direction`: capability and native design.
- `layer` / `phase`: dependency layer and earliest development phase, not a reduced V1 commitment.
- `status`: specified means a selected native contract exists, directly or by explicit frozen-baseline incorporation.
- `specification`: owning document/section links, separated by `|`.
- `implementation_status`: not_implemented at specification freeze; no current checking/execution evidence is implied by this snapshot.
- `required_evidence`: mandatory later positive/negative or integration evidence, not a passing result.

### Library operation inventory

The source-backed inventory records 35,345 public/documentation pages, 123,118
associated items and 82,270 implementation relations: 240,733 exposures/contexts.
It preserves reexports, runtime/const distinctions, experimental APIs, generated
properties and source cfg evidence. Counts are not independent stable APIs.
Exact classifications/canonical totals are in
[audit-summary.json](../baseline/audit-summary.json).

The auditor verifies both archives and the complete extracted Rust library source
file set, enumerates case-sensitive archive names, and cross-checks every archived
all.html link. The validator checks declaration closure, reexport identity,
implementation/interface-member stability, native-rule assignments and named
conditional supporting protocols. Its result binds to the operation manifest
digest in [validation.json](../baseline/validation.json).

[baseline-mapping.md](baseline-mapping.md) and
[library-surface.md](../library/library-surface.md) specify recursive native operations,
standalone authority assignments and an explicit fallback for unmigrated
contracts. A contract assignment
does not mean its native declaration has compiled. Source cfg predicates retain
their enclosing module/macro context; unrendered applicable source branches are
still obligations. No executed all-target expansion or per-item native coherence
check is claimed.

Generate the I13 [worklist](../baseline/v1-operations.csv) with
`python3 tools/v1_operations.py`; it is the only record of per-operation status
(missing, declared, evidenced, not applicable, blocked) and evidence tests.
Missing or unmapped is not proof of absent code; declarations and name matches
are not behavioral passes. Per-area progress and receipts belong to the ledger
and to revision-bound evidence bundles, not to this document.

### Equivalence policy

Native syntax does not weaken the promised safe capability.
Do not silently require allocation, runtime checks, unsafe caller code, erased
types, weaker regions or weaker complexity where the equivalent baseline does
not. An actual conflict is a specification defect and reopens the documentation
gate; an unimplemented contract is an implementation failure.

Different defaults are intentional: ordinary non-Copy parameters borrow,
explicit take consumes even Copy sources, and shared handles move unless
explicitly retained. Compare programs requesting equivalent operations, not
superficially identical spelling.

### Capability status

Per-capability implementation status and evidence fixtures are not kept in this
document. Each row of [capabilities.csv](../capabilities.csv) owns its specification
and required evidence; an implementation status change needs a revision-bound
evidence bundle ([implementation-plan.md](implementation-plan.md) section 9).
The frozen CSV `implementation_status` is not a progress indicator.

Acceptance has independent axes: expressibility, sound observable semantics
and measured runtime. A faster unsafe replacement cannot satisfy a safe API;
an equally expressive but slower implementation can fail the runtime gate.
The initial inventory and documentation checks establish none of these runtime
or safety results.

### Unstable-feature register

Not automatically committed: unrestricted overlapping specialization, generalized
const expressions beyond the stable baseline, custom auto traits, unrestricted
negative user-interface implementations and experimental coroutine APIs.
Nightly-only declarations remain visible in the inventory without becoming
stable native requirements.

Default/sealed/compiler-controlled helpers used by stable calls have explicit
[supporting-protocol mappings](../library/library-surface.md#8-conditional-supporting-protocols).
Those mappings preserve valid stable uses, not every experimental implementation
right. Native negative thread properties, allocator control and borrowed scopes
remain accepted independently of similarly named Rust nightly features.

For additions, record a concrete use case, alternatives, interactions, cost,
runtime effects and acceptance. Rejected identity proposals do not expand scope.
