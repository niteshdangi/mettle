# Documentation completion gate

Status: **closed for the pre-implementation documentation baseline**. The
source-backed audit and documentation validation pass; implementation, safety,
platform and runtime claims remain outside this gate.

The specification baseline closed before implementation was authorized.
I01 compiler-foundation checks now pass for native macOS host builds and Linux
x86-64 cross-emission/link/execution, outside this documentation gate.
I02 qualifies a scalar source compiler and separate native/source-target evidence;
it does not establish the full grammar, library parity or a release.

## Authority

1. Explicit accepted user decisions and architectural commitments.
2. Selected native rules and routine refinements under delegated authority.
3. Explicitly marked research, proposals and future product decisions.

Rejected identity proposals do not expand scope. The Word blueprint is an earlier
architectural snapshot; subsequent accepted parameter/Copy/ownership decisions
are recorded here. Extended productions supersede their subset counterparts;
the annexes refine older broad descriptions, without overriding user decisions.

## Specification coverage

| Area | Owning documents | Documentation result |
| --- | --- | --- |
| Architecture and release progression | README; decisions; implementation-plan | Independent C++/LLVM V1, substantive self-hosting V1.1, own backend V1.2 |
| Syntax and fixtures | core-grammar; language-grammar; examples | Composed grammar and full-corpus expectations, including colon results, body-based inference, Unit/Never and explicit discard; I02 scalar execution is separate, not full-corpus qualification |
| Ownership, typing and cleanup | core-semantics; semantic-rules | Parameter modes, Copy, CFG state, loans/regions, coercions, dispatch and exceptional replacement |
| Advanced mechanisms | advanced-contracts; specification-annex; memory-and-concurrency | Pinning, consts, macros, coherence, erasure, memory/atomics and borrowed-task epochs |
| Library and ABI | library-and-abi; baseline-mapping; library-surface; baseline artifacts | Recursive operation contracts, source/context identity, stability and explicit supporting-protocol mappings |
| Packages and tools | tooling-and-packages | Resolution/lock/cache, host execution, commands, tests/doctests, LSP and debugger |
| Toolchains and profiles | toolchain-pins.json; reference-profiles; platform-contracts | Immutable source selections and deployment/ABI design references; archive/build evidence is separate |
| Performance and release | performance | Workloads, equivalence rules, statistical/precision plan and release gates |
| Capability ownership | capabilities.csv | All 107 rows specified with owning sections and required later evidence; all not_implemented |

## Completion evidence

The documentation gate closes only when
[baseline/validation.json](baseline/validation.json) reports passed for the current
operation-manifest digest and documentation-input digest, with no failures.
[The reproducible audit](baseline/README.md) defines the inventory boundary and
limitations. Re-run its validator after changing this specification.

The checked inventory contains 35,345 public/documentation pages, 123,118
associated records and 82,270 implementation relations: 240,733 records, not
that many independent stable APIs. All 34,934 archived catalog links are
cross-checked. Both official archives and all 2,976 extracted Rust library
`.rs` files are checksum-verified; 107,873 source attributes are retained.

The validator checks canonical reexports, declaration references, runtime versus
const classification, implementation/interface-member instability, native-rule
and conditional-protocol assignments, all capability owners, grammar reference
closure, function-result/built-in/discard grammar policies, Markdown links/fences
and exact fixture-manifest membership.
It must reject genuinely unmapped supporting declarations rather than treat
every downloaded page as covered.

The contract inventory incorporates unchanged versioned semantics and recursively
specifies their native translation; it is not handwritten, typechecked native
API source. Full source cfg applicability is normative even for branches absent
from the archived HTML. Retaining that graph is not executing it on all targets.
Any discovered contradiction or unavailable native construct reopens the
documentation gate; a missing implementation does not erase the contract.

## Deliberately separate evidence

Documentation completion does not supply:

- Parser conflict/recovery results or execution of the `.mt` examples.
- Native API typechecking, all-target cfg expansion, layout or ABI probes.
- A safety theorem, checked unsafe implementation or async/unwind stress results.
- Supported platforms, reproducible installed toolchain artifacts or bootstraps.
- Passing runtime comparisons, pilot precision results or a validated adoption advantage.

These are implementation/release acceptance gates, not unnamed design choices.
No compulsory Rust toolchain, GC, sandbox, permission framework or executor was
added. Native implementations must be independent of Rust.

Project licensing and registry/public-stabilization governance remain explicit
owner decisions before publication/launch. They do not leave language semantics
undefined and do not authorize selecting a license, creating a registry or
publishing code. Rejected identity research remains rejected.
