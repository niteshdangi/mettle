# Reconciled post-V1 contract worklist

Owner decisions, 2026-11-09: exclude all deprecated APIs from required scope;
retain all eight [reference profiles](../spec/platform-contracts.md#8-reference-profiles) after V1. The
Linux-only V1 gate is unchanged. This supersedes earlier requirements to
implement deprecated stable contracts, not their frozen reference provenance.

## Exact inventory partition

Inputs and their SHA-256 identities are recorded in
[post-v1-summary.json](../baseline/post-v1-summary.json). This snapshot accounts
for 159,995 stable exposures and all **106,125 stable canonical records**:

| Disposition | Canonical records | Meaning |
| --- | ---: | --- |
| V1 obligations | 13,295 | Existing selector/ledger membership; not proof of completed I13 |
| Post-V1 contextual obligations | 41,151 | Declarations and implementation relations outside that selector |
| Attached implementation members | 50,190 | Methods/associated types owned by implementation obligations, not separate implementations |
| Attached inherent blocks | 684 | Structural containers owned by type declarations; their methods remain obligations |
| Namespaces | 176 | Module containers, not ordinary callable operations |
| Excluded deprecated | 629 | All stable exposures of the identity are deprecated, including inherited deprecation |
| **Total** | **106,125** | No stable canonical ID lost |

Of the attached implementation members, 17,100 belong to V1 implementation
obligations and 33,090 to post-V1 ones. They are retained acceptance requirements,
not removed behavior.

The earlier estimate of 92,830 "deferred operations" merely subtracted the V1
ledger from the raw canonical total. It was not an independent-work count.

## What the post-V1 obligations contain

These categories partition the **41,151 contextual obligations**, before
per-profile source-cfg applicability and native implementation review:

| Category | Records | Examples / work |
| --- | ---: | --- |
| Architecture | 13,153 | Intrinsic declarations, vector types and associated contracts; feature guards, ABI and instruction semantics |
| OS extensions | 780 | Platform-specific filesystem and other service contracts, extension interfaces and their implementations |
| Trait implementations outside the above categories | 24,585 | Generic blanket, concrete and auto-property relations; preserve bounds, substitutions and associated members |
| Other library declarations | 2,633 | Types, methods, constants, macros, functions and interfaces outside the V1 selector |

There are 27,043 implementation relations across all categories. A category is
where the reference exposes the contract, not an effort rating or a claim that
each record needs new handwritten code. For example, allocator-related
declarations outside the V1 selector may already have native equivalents under
explicitly accepted allocator contracts. They must be mapped, not assumed absent.

## Shared code versus distinct acceptance work

The post-V1 contextual obligations group into **32,355 declaration work units**:

- **27,491** units are not represented by the current V1 selector.
- **4,864** units share implementation source declarations with V1; their
  additional type/profile contexts still need mapping and evidence.

An implementation shares a work unit only when its verified reference source
file and span, exact signature and implemented trait identity match. This
captures repeated exposures of one blanket implementation, such as a generic
conversion or borrowing implementation shown on many type pages. Signatures
with different bounds/substitutions, absent source provenance, or differing
source locations are not merged. Unresolved trait aliases are conservatively
kept distinct rather than guessed equivalent.

All canonical contexts remain in the ledger. A shared work unit means potential
shared implementation code, never a blanket per-type pass. Integer/float widths,
CPU features, unsafe invariants and associated types are not discarded.
Implementation members point to their owning implementation via `covered_by`;
their exact signatures and exposure URLs remain available.

## How to use the ledger

Generate using [the existing operation tool](../../tools/v1_operations.py):

```sh
python3 tools/v1_operations.py --remaining
python3 -m unittest discover -s docs/baseline -p 'test_v1_operations.py'
```

The [full gzip CSV](../baseline/post-v1-worklist.csv.gz) is UTF-8. Filter
`disposition=post-v1-obligation` for contextual obligations; group by `work_unit`
for implementation planning. Follow `covered_by` to include member acceptance
cases. `exposure_urls` and `availability` preserve exposure-specific reference
links and the union of displayed conditions; consult the linked frozen records
for each condition's context. The union is not a synthesized cfg predicate.

`recorded_v1_status`, `mettle_path` and `evidence_test` copy the existing V1
ledger without upgrading evidence. Empty values mean **unreviewed**, not
unimplemented. No historical Darwin evidence is promoted to Linux or another
profile. Regeneration refuses a V1 ledger whose IDs differ from its selector.

## Remaining review and implementation gates

This formalizes the inventory denominator, not an exact missing-code total.
The following work is still open:

1. **Profile applicability:** audit enclosing source/macro cfg against every
   reference profile. The current V1 selector still has historical Darwin
   assumptions. Retain Linux-only and other-platform-only records; do not label
   them inapplicable using that selector's rendered-condition shortcut.
   Contracts outside all eight profiles remain candidates until source evidence
   establishes exclusion. Missing SDKs/runners block qualification, not scope.
2. **Native mapping and state:** for each work unit and its contexts, identify
   owning native files and distinguish missing, partial and implemented work.
   Existing code outside the V1 ledger is not assumed absent.
3. **Acceptance/evidence:** record exact source revision, target, required
   fixtures, unsafe invariants and execution/ABI/sanitizer evidence. A shared
   generic implementation must cover all retained bounds, types and profiles.
4. **Supporting obligations:** reconcile accepted native replacements,
   supporting protocols and source-only branches with this documentation-derived
   inventory. They are not automatically exhausted by these counts.
   Standalone contract assignments are tracked in
   [the native authority register](baseline-mapping.md#7-native-operation-authority);
   the native chapters do not migrate unassigned post-V1 contracts or discharge
   implementation evidence.
5. **Non-operation work:** retain A009's Rust bridge, profile bootstrap/runtime/
   debug/unwind qualification, I15 self-hosting and I16 independent backend as
   separate work packages. None is measured by subtracting operation rows.

Do not claim these units are equally sized, all missing, fully applicable, or
qualified. Any further semantic deduplication or scope exclusion needs source
evidence; a genuinely new reduction needs an owner decision.
