# Frozen library contract inventory

This is specification data, not a Mettle standard library or an implementation
of Rust. Reference: Rust 1.99.1, edition 2024, source commit
`58cf8f9c35b355199727627d07ae34a4e2846d67`. The official distribution is dated
October 15, 2026; its rustdoc build identifies October 13, 2026.

## Inputs and reproduction

Use Python 3.9 or later, with only its standard library. The source and docs
archives, expected hashes and version identities are recorded in
[sources.json](sources.json). No installed rustc or network access is required
once those archives are available.

Extract the official archives into a working directory outside the project.
Pass the extracted `share/doc/rust/html` and `lib/rustlib/src/rust/library`
directories, not their installer package roots:

```sh
python3 docs/baseline/audit.py \
  --docs-root /path/to/extracted/share/doc/rust/html \
  --source-root /path/to/extracted/lib/rustlib/src/rust/library \
  --docs-archive /path/to/rust-docs-1.99.1-x86_64-unknown-linux-gnu.tar.xz \
  --source-archive /path/to/rust-src-1.99.1.tar.xz
python3 -m unittest discover -s docs/baseline -p 'test_*.py'
python3 docs/baseline/validate.py
```

Run from the project root. All commands fail on detected inconsistencies.
The first also checks the extracted library source set and its contents against
the verified archive. The tests cover operation selection and native Unit/Never mapping; the
validator requires generated data and the specification/facility register.

### Reconciled post-V1 scope

Owner amendment (2026-11-09): exclude deprecated APIs from required scope and
retain all reference profiles for post-V1 applicability review.
Preserve this frozen reference inventory unchanged. Generate the derived ledger
and input-hashed summary with:

```sh
python3 tools/v1_operations.py --remaining
python3 -m unittest discover -s docs/baseline -p 'test_v1_operations.py'
```

`--remaining` reads, but does not rewrite, `v1-operations.csv`; it rejects stale
V1 membership. Outputs are [post-v1-worklist.csv.gz](post-v1-worklist.csv.gz)
and [post-v1-summary.json](post-v1-summary.json).
The gzip CSV is UTF-8 and deterministic. Do not hand-edit derived outputs.
Update the [worklist explanation](../process/post-v1-worklist.md) and milestone counts
when inputs change. The ledger retains every stable canonical ID and exposure
URL, exact signatures, conditions, owning dependencies and recorded V1 evidence.
Blank evidence is not a missing-code claim. Reexports share a canonical row;
implementation members remain attached acceptance obligations.

Source file/span, exact signature and trait identity can group implementation
code into one work unit without removing its distinct type/exposure contracts.
No grouping discharges per-type/per-profile tests or proves applicability.
Deprecated-only identities are explicitly excluded; a non-deprecated exposure
keeps a shared identity required. Modules and inherent blocks are structural,
not additional ordinary operations. See the explanation for unresolved work.

**Case-insensitive filesystems:** the archive contains case-distinct Hexagon
declarations. Ordinary extraction may overwrite one with another. The auditor
enumerates the archive itself and restores mismatches to a hashed
`rust-doc-exact-overrides` directory beside docs-root. Keep the original archive;
auditing a filesystem glob alone is insufficient.

## Artifacts and identities

| Artifact | Meaning |
| --- | --- |
| public-items.csv | Public exposure/documentation pages, including modules, derives, attributes and keywords |
| associated-items.csv | Fields, variants, methods, associated types/constants, including repeated implementation contexts |
| implementations.csv | Interface/inherent/auto-property relations, not additional ordinary functions |
| redirects.csv | Archived path redirects; declaration fragments remain significant |
| operations.jsonl.gz | Full declaration records, source spans, stability evidence, parent/implementation/interface-member links, canonical IDs and recursive native contract assignments |
| source-constraints.jsonl.gz | Source cfg/cfg_attr, stability, const, feature and layout attributes, with file/line/offset/hash provenance |
| source-provenance.json | Archived page and directly referenced source-file hashes |
| audit-summary.json | Inventory totals, input identities, extraction failures and explicitly absent implementation evidence |
| supporting-protocols.json | Native equivalents for stable contracts with experimental default/sealed/compiler-controlled supporting declarations |
| validation.json | Current consistency checks and exact operation-manifest digest |

An operation URL identifies an exposure/context; a canonical ID identifies the
source declaration, signature and owning/implementation context. Reexports
share definition identity. Different macro-generated operations remain distinct.
These counts are not feature-completion percentages or ABI identities.

The inventory contains 35,345 public pages, 123,118 associated records and
82,270 implementation relations: 240,733 records in total. Exact stable, const,
canonical and conditional-family totals live in the generated summaries.
All 34,934 links from the archived all.html catalogs are cross-checked; modules
and other omitted catalog categories are obtained from archive enumeration.

## Contract interpretation

[Native library surface](../library/library-surface.md) supplies T01-T16 and the
conditional-family boundaries. Those rules apply recursively to every matching
shape; the per-record rule list is a discovery/index aid, not a syntactic
translation program or a waiver for a shape a regular expression did not flag.
The [native authority register](../process/baseline-mapping.md#7-native-operation-authority)
assigns standalone contracts to migrated operations. Their contract URLs retain
provenance, not semantic authority. For unassigned operations, the contract URL
still incorporates the selected semantics until a complete native specification
replaces it. Native ownership, syntax and facility differences remain explicit.

Runtime stability is one of stable, unstable, language_documentation or
external_implementation. It incorporates direct source attributes, enclosing
public path, implementation/interface and interface-member context. Const
stability is independent. A stable trait does not stabilize its nightly methods;
a stable default-allocator call does not promise every allocator instantiation.
Canonical stable exposures can explain an experimental alias spelling without
stabilizing that spelling on its otherwise ineligible target.

Source cfg forms are preserved, not flattened into a false conjunction of every
attribute in a file. Applicability follows the declaration's enclosing module/
macro expansion graph under the frozen sources. This inventory does not execute
that graph for every target. Unrendered cfg branches remain normative source
requirements when applicable, not a claim that the HTML count enumerates every
possible source expansion.

Experimental APIs and third-party dependency implementation types are retained
and classified, not automatically added to the stable native requirement.
Explicit native allocator/thread-property/scoped-task commitments remain in
force independently.

## Validation boundary

Validation checks record/CSV membership, declaration-link closure, source/page
identity, runtime-versus-const stability, reexports, case-distinct names,
interface-member inheritance, supporting-protocol assignments and the project
documentation's grammar references, capability owners, links and declared
fixture expectations. It does not freeze grammar spelling, milestone counts
or membership of every example in an expectations manifest.

It does **not** typecheck native declarations, prove the ownership/memory model,
compile all cfg expansions, run the Mettle fixtures, certify target
support or measure performance. These remain implementation/release gates in
[status.md](../process/status.md).

Upstream source/docs remain subject to their own licenses; this project has not
selected a publication license or copied their library implementations.
