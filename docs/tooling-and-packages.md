# Packages, tools and development contracts

Status: selected design, not available commands or an installed toolchain.
These operations are native equivalents, not Cargo-manifest compatibility.

## 1. Manifest and identity

Use Mettle.toml and Mettle.lock as the working manifest/lock names. A package
declares a lowercase ASCII name, SemVer version, language revision, source roots,
targets, dependencies and optional named features. Package names use
`[a-z][a-z0-9_-]*`; source identity remains separate from the display name.

Illustrative manifest:

```toml
[package]
name = "example"
version = "0.1.0"
language = "mettle-1"

[targets.app]
kind = "executable"
source = "src/main.mt"

[dependencies]
parser = { path = "../parser", features = ["text"], default_features = false }
```

Dependency sources are local paths, configured registries, or Git identities.
Git requirements resolve to an immutable commit in the lock, not a moving tag.
Registry packages lock their archive digest; path packages record their resolved
location and content-input identity for builds, without pretending local edits
are immutable published versions.

Version requirements support exact, caret, tilde and comparator intersections.
An array of requirement strings denotes their union. Ordering follows SemVer;
prereleases require explicit prerelease selection. Resolve deterministically to
the highest compatible non-yanked candidate subject to the complete constraints,
backtracking when needed. A locked yanked release remains usable unless policy
explicitly forbids it. Dependency cycles that require cyclic compilation fail
with the package path, not an arbitrary resolver cutoff.

Features are additive named sets enabling optional dependencies, dependency
features and declared cfg facts. Unify features for the same package source/
version in the same build context; separate host tools, target libraries and
inactive development dependencies. An executable's test dependencies cannot
silently enable features in an ordinary release build.

Different incompatible dependency versions may coexist with distinct type
identities. Same spelling is not same package/type. Native-linking providers
declare a unique link identity; reject incompatible duplicate providers rather
than linking an unpredictable one. Patch/override selections are explicit
workspace configuration and enter the lock.

Lock entries include exact source/version/commit/content identities, dependency
edges and selected resolver format. Target and resolved features enter build
records/cache keys. Reject a checksum mismatch. `--locked` rejects required lock
changes; `--offline` forbids fetching missing artifacts; `--frozen` combines both.
Never silently fall back to another source after verification failure.

Registry namespace, account governance, credentials and publication policy are
owner decisions before public service launch. No registry/account is created
by this specification. Local and configured-private-source packages do not
depend on those future product decisions.

## 2. Compilation and build execution

Build records distinguish host and target triples, compiler source/build ID,
language revision, dependency identities, cfg/features, optimization, overflow/
panic/float policy, allocator/runtime selection, linker/sysroot and environment
inputs. Generated sources retain generator provenance and content hashes.

Build programs and procedural extensions may run native host code with ordinary
file/network/tool capabilities. Execution is visible in the build plan/log;
there is no compulsory sandbox or application permission framework.
Optional project policy can request isolation or decline untrusted execution.

External host execution is rerun by default. It is cacheable only under an
explicit reproducible-input contract covering tool identities, files,
environment and other observations. Untracked clocks/network/randomness cannot
be assumed deterministic. Output hashes still permit downstream reuse when a
rerun produces unchanged output. Pure compiler-owned token expansion can use
its normal input-derived cache.

Build outputs declare generated files, cfg values, link libraries/search paths
and permitted command-line metadata. A generated input participates in dependency
analysis before consumers compile. No silent source rewriting or private
compiler-object ABI is granted to an extension.

Incremental reuse requires matching all semantic/codegen inputs. Separate
parse/name/type/ownership/instantiation/backend dependencies so editing a comment
need not recompile unrelated code. An optimization must not reuse stale loans,
generic bounds, macro results or ABI layout.

## 3. Selected command operations

| Command | Contract |
| --- | --- |
| mettle check | Resolve and check selected targets; no executable-generation claim |
| mettle build | Check and emit selected artifacts with target/profile/lock metadata |
| mettle run | Build one selected executable, then pass program arguments after `--` |
| mettle test | Build and run selected tests/doctests with filtering and machine-readable results |
| mettle bench | Run explicitly selected benchmark workloads; preserve raw measurements and configuration |
| mettle fmt | Syntax-preserving formatting; `--check` reports drift without rewriting |
| mettle lint | Native diagnostic rules; structured findings and source/expansion provenance |
| mettle doc | Public/API documentation, source links and cross-package references |

Target, profile, feature, package/workspace and lock/offline selections are
shared options. Unknown or unavailable requested capabilities fail explicitly;
partial compiler milestones cannot count unsupported programs as passed tests.
No actual command above exists yet.

## 4. Tests and executable documentation

Test functions use @test; filtering selects fully qualified names. The runner
reports pass/fail/ignored, process termination and infrastructure failure
separately. Test ordering is not a language guarantee. A deterministic seed and
concurrency selection are recorded when requested.

Panic expectations match the declared contract. Aborting profiles need subprocess
isolation to observe an expected panic; abort is not an unwind caught in-process.
Cleanup/cancellation tests observe completed teardown, not merely a request.
Benchmark runners do not weaken the performance protocol's registered metrics.

Documentation fences distinguish ordinary examples, runnable native examples,
no_run examples, ignored platform examples and compile_fail cases with the
expected checking phase. Hidden setup lines remain available to the compiler
and provenance output. A compile_fail ownership example must not pass because
its syntax was malformed. Unsupported target examples are reported inapplicable,
not successful execution.

## 5. Editors and debugging

The language server and compiler share parsing, resolution and checked type/
region information. Required operations: diagnostics, completion, hover,
definition/reference navigation, rename, symbols, signature help and formatting.
Source edits invalidate the affected analysis; incomplete editor trees are not
executable programs.

Hover, signature help and generated API documentation expose the resolved
signature, including an inferred result when source omits `: Type`. Unresolved
analysis reports that state rather than guessing a result from callers.

Rename observes namespaces, public paths and hygienic expansion identity.
Generated identifiers are edited at their source/generator only when the mapping
is unambiguous. Diagnostics include primary/related spans and the expansion
chain rather than blaming unrelated user code for an extension failure.

Emit target-appropriate DWARF or CodeView/PDB for sources, scopes, fields,
variants, monomorphizations, inlining and addressable locals. Describe native
optional/outcome, owners, slices, erased values and async states to the debugger.
Moved/uninitialized values must not be presented as live valid values.
Optimization may eliminate values; report optimized-out rather than inventing
their contents. Static region analysis does not require runtime region objects.

Optional Rust bridges build as separate interoperability packages with explicit
Rust toolchain/ABI adapters. They do not introduce a mandatory rustc dependency
into native Mettle builds.

## 6. Comparison and evidence

Rust already provides mature package/build/test/editor/debugger workflows.
These are parity requirements, not Mettle's claimed unique language identity.
Feature resolution, caching and richer debug output affect build cost/artifact
size; no inherent application-speed improvement follows from their spelling.
Implementation acceptance needs resolver fixtures, invalidation tests, compiler/
editor agreement, debugger probes and executable documentation on real targets.
