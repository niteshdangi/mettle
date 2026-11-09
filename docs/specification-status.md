# Documentation completion gate

Status: closed for the pre-implementation specification baseline.
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
| Syntax | [core grammar](core-grammar.md), [full grammar](language-grammar.md) |
| Ownership, typing and cleanup | [core semantics](core-semantics.md), [semantic rules](semantic-rules.md) |
| Advanced mechanisms and memory | [advanced contracts](advanced-contracts.md), [annex](specification-annex.md), [memory model](memory-and-concurrency.md) |
| Libraries and ABI | [library/ABI](library-and-abi.md), [mapping](baseline-mapping.md), [surface](library-surface.md) |
| Packages and tools | [tooling](tooling-and-packages.md) |
| Toolchains and profiles | [pins](toolchain-pins.json), [profiles](reference-profiles.md), [platform contracts](platform-contracts.md) |
| Performance and release | [performance protocol](performance.md) |
| Capability obligations | [107-row inventory](capabilities.csv) |

## Completion evidence

[baseline/validation.json](baseline/validation.json) must pass for the current
operation-manifest digest with no failures. Re-run the
[baseline validator](baseline/README.md#inputs-and-reproduction) after
specification changes; that document owns inventory counts, provenance,
interpretation and validation boundaries.

A contradiction or unavailable native construct reopens this gate. Missing
implementation does not remove the selected contract.

## Deliberately separate evidence

This gate checks specification consistency, not parser/example execution,
native API typechecking, all-target cfg expansion, layout/ABI, memory safety,
toolchain installation, supported platforms or measured adoption/performance.
Those require implementation/release evidence. Licensing and public registry
governance remain owner decisions before publication; native builds require
neither Rust nor a compulsory sandbox, permission framework or executor.
