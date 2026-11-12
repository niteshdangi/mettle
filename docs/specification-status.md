# Documentation completion gate

Status: closed for the pre-implementation specification baseline.
Standalone native-operation migration is partial; the original closure included
reference-owned operation contracts and does not certify their replacement.
Implementation and release qualification are tracked in the
[implementation plan](implementation-plan.md).

## Authority

1. Explicit accepted user decisions and architectural commitments.
2. Selected native rules and routine refinements under delegated authority.
3. Marked research, proposals and future product decisions.

The Word blueprint is an earlier snapshot. Accepted decisions govern later
parameter, Copy and ownership rules. Extended grammar supersedes subset
productions; annexes refine broad descriptions. Rejected identity research
does not expand grammar or V1 scope.

## Specification coverage

| Area | Owner |
| --- | --- |
| Architecture and release progression | [decisions](decisions.md), [implementation plan](implementation-plan.md) |
| Syntax | [grammar](language-grammar.md) |
| Ownership, typing and cleanup | [semantic rules](semantic-rules.md) |
| Advanced mechanisms and memory | [advanced contracts](advanced-contracts.md), [annex](specification-annex.md), [memory model](memory-and-concurrency.md) |
| Libraries and ABI | [library/ABI](library-and-abi.md), [native value contracts](native-value-contracts.md), [mapping authority](baseline-mapping.md#7-native-operation-authority), [surface](library-surface.md) |
| Core and allocation operation definitions | [native core contracts](native-core-library-contracts.md), [native collection contracts](native-collection-contracts.md) |
| Hosted and OS operation definitions | [native hosted contracts](native-hosted-contracts.md), [native OS contracts](native-os-contracts.md) |
| Architecture operation definitions | [native machine contracts](native-machine-contracts.md) |
| Packages and tools | [tooling](tooling-and-packages.md) |
| Toolchains and profiles | [pins](toolchain-pins.json), [profiles](reference-profiles.md), [platform contracts](platform-contracts.md) |
| Performance and release | [performance protocol](performance.md) |
| Capability obligations | [107-row inventory](capabilities.csv) |

## Completion evidence

[baseline/validation.json](baseline/validation.json) must pass for the current
operation-manifest digest with no failures. Re-run the
[baseline validator](baseline/README.md#inputs-and-reproduction) when changing
the operation inventory or its audit logic. For authored documentation-only
changes, check affected links and the changed contracts; do not rebuild the
compiler or rescan the entire operation inventory. The receipt does not certify
subsequently authored contracts. The baseline README owns inventory counts,
provenance, interpretation and validation boundaries.

A contradiction or unavailable native construct reopens this gate. Missing
implementation does not remove the selected contract.

## Standalone contract migration

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

### V1 priority and deferred migration

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

## Deliberately separate evidence

This gate checks specification consistency, not parser/example execution,
native API typechecking, all-target cfg expansion, layout/ABI, memory safety,
toolchain installation, supported platforms or measured adoption/performance.
Those require implementation/release evidence. Licensing and public registry
governance remain owner decisions before publication; native builds require
neither Rust nor a compulsory sandbox, permission framework or executor.
