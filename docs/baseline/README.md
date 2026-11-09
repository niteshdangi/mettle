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
the verified archive. The tests cover operation selection and native Unit/Never
mapping. The final validator requires all generated data
and the checked-in specification/facility register.

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

An operation URL identifies an exposure/context. A canonical ID identifies the
source declaration plus signature and owning/implementation context; it is not
a type ABI hash. Reexports retain exposure records but share definition identity.
Different operations generated at the same macro source line remain distinct.
Neither row counts nor canonical counts are a feature-completion percentage.

The inventory contains 35,345 public pages, 123,118 associated records and
82,270 implementation relations: 240,733 records in total. Exact stable, const,
canonical and conditional-family totals live in the generated summaries.
All 34,934 links from the archived all.html catalogs are cross-checked; modules
and other omitted catalog categories are obtained from archive enumeration.

## Contract interpretation

[Native library surface](../library-surface.md) supplies T01-T16 and the
conditional-family boundaries. Those rules apply recursively to every matching
shape; the per-record rule list is a discovery/index aid, not a syntactic
translation program or a waiver for a shape a regular expression did not flag.
The contract URL incorporates unchanged operation semantics; native rules
override only the explicitly selected ownership, syntax and facility differences.

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
[specification-status.md](../specification-status.md).

`audit-pages.jsonl` is historical evidence from the earlier partial web pass;
it is not the current denominator or source of generated classifications.
Upstream source/docs remain subject to their own licenses; this project has not
selected a publication license or copied their library implementations.
