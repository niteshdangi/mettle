# Packages, tools and development contracts

Status: selected design. Only the subset in section 1.1 is implemented
(`mettle check|build` on a package directory); other commands and an
installed toolchain are not available.
These operations are native equivalents, not Cargo-manifest compatibility.

### 1.1. Implemented subset (I09 T001)

`mettle check|build DIR_OR_Mettle.toml` plans the package in the `packages`
component, then compiles the selected executable target with each resolved
dependency library mounted as a public root module named after the package
(`-` becomes `_`). Inside a dependency's own submodules, reach other packages
with `import package::name`.

- Manifest: `[package] name/version/language="mettle-1"`, `[targets.NAME]`
  (`kind`, `source`; defaults `src/main.mt` executable, `src/lib.mt` library),
  `[dependencies]` (version string/array, or `{path, version, optional,
  default_features}`), `[features]` (`feature`, `dep:x`, `x/f`; optional
  dependencies imply a feature), `[registry] path` (root only) and parsed but
  unused `[dev-dependencies]`. Unknown keys are errors. `git` and
  `build-dependencies` are rejected as unsupported.
- Versions: SemVer requirements (`^`, `~`, comparators, `*`, comma
  intersections, arrays as unions). Highest non-yanked version wins; a
  lock-recorded version is preferred (even if yanked); conflicts backtrack
  chronologically and report each requirement with its requiring package.
- Local registry: `<registry>/<name>/<version>/Mettle.toml` plus sources; a
  `YANKED` file yanks a version. Select with `--registry DIR` (repeatable,
  before the manifest `[registry]`). No network fetch exists; `--offline` only
  changes the diagnostic.
- `Mettle.lock`: `version = 1` plus `[[package]]` entries (name, version,
  `source` = `root`/`path+REL`/`registry+REL`, `checksum`, resolved
  `features`, dependencies). Checksum is SHA-256 over sorted relative paths,
  sizes and contents of `*.mt` and `Mettle.toml` (hidden, `target`, `build`
  skipped). Registry checksum mismatches always fail; other drift is
  re-locked, or fails under `--locked`/`--frozen`. Missing lock fails under
  `--locked`.
- Flags: `--bin NAME`, `--features a,b`, `--no-default-features`,
  `--registry DIR`, `--locked`, `--offline`, `--frozen`.
- Limits: all packages share one flat module namespace, so one version per
  package name and no coexisting majors; no git/remote registries,
  host/target feature separation or build-dependencies; library-only roots
  cannot be built. Build scripts (T002) and the content-addressed build cache
  (T003) follow; both are implemented but unverified (not yet built).
  Tests: `tests/packages.py`.

### Build scripts (T002)

`[build] script = "build.mt"` names a Mettle program (compiled for the host
with the hosted `std`, cached like any other program) that runs with the
package directory as its working directory before consumers compile. Its
environment adds `METTLE_OUT_DIR` (`target/mettle/out` in the package),
`METTLE_PACKAGE_DIR`, `METTLE_PACKAGE_NAME`, `METTLE_PACKAGE_VERSION`,
`METTLE_TARGET`, `METTLE_PROFILE` and `METTLE_FEATURES`. Stdout lines
`mettle:KEY=VALUE` are the only way to affect the build:
`module=NAME=FILE` mounts a generated file as root module `NAME`,
`feature=NAME` enables that `@cfg(feature = ...)` value for the package,
`link-lib=NAME` adds `-lNAME`, and `rerun-if-changed=PATH`,
`rerun-if-env-changed=VAR` and `reproducible` form the input contract below.
Other lines are ignored; an unknown `mettle:` line is a `build` error. Generated
files are ordinary sources of the compile, so they are hashed by content and
participate in dependency analysis before consumers compile. Scripts run with
ordinary host capabilities and are never sandboxed, but their execution,
decisions and outputs are visible with `--explain`.

A script is rerun on every build unless it declares `reproducible` (its output
is a function of the declared files and variables, its compiled binary and
the target/profile/features). Undeclared inputs therefore always force a rerun;
a rerun that regenerates unchanged tokens still reuses the compiled program.
The contract is recorded in the build cache and rechecked (input hashes,
variable values, hashes of every generated file) before reuse.

### Incremental builds and the build cache (T003)

`mettle build` (executables and objects) keys its output by a SHA-256 over: the
compiler identity (version, runtime target, size and mtime of the compiler and
runtime library), emit/profile/overflow policy/target/linker/sysroot, enabled
features, mounts, link libraries, and every source the load step read. User
sources count by token stream (comments, spacing and blank lines do not
matter), library sources by content, and probed-but-absent paths as absent. A
hit copies the stored artifact and skips checking, lowering, code generation and
linking; any miss does the full build, which is the same code path as a clean
build, so incremental and clean results agree. Reuse is whole-program: an edit
to any loaded source (including a dependency package or generated file)
recompiles; unloaded files, comments and layout do not. Finer
parse/name/type/ownership/instantiation query reuse inside the compiler remains
open. Storage design: performance.md section 5.1.1. Flags: `--cache-dir DIR`,
`--no-cache`, `--cache-limit-kib N`, `--cache-max-age-days N`, `--explain`;
`METTLE_CACHE_DIR`; `mettle clean [PACKAGE] [--dry-run]`.

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
These are parity requirements, not Mettle's claimed unique language identity;
build speed and build-cache size are the exception, being accepted gates
(performance.md section 5.1).
Feature resolution, caching and richer debug output affect build cost/artifact
size; no inherent application-speed improvement follows from their spelling.
Implementation acceptance needs resolver fixtures, invalidation tests, compiler/
editor agreement, debugger probes and executable documentation on real targets.

## 7. Storage: two separate products

Build-cache size is an accepted gate (performance.md section 5.1), so storage is
specified for both products, which have different owners and must not be mixed.

### 7.1. Compiler-development storage

Address measured candidates first. A prior broad sample was 45.2 GiB in `.tools`
and 3.8 GiB in `build`. The table lists allocated blocks (`du -sk`) observed on
2026-10-30: a point-in-time observation, not an atomic or current inventory.

| Candidate | GiB | Disposition |
| --- | ---: | --- |
| `.tools/linux-x86_64/llvm` | 11.3 | Active pinned LLVM 22.1.3: retain |
| `.tools/linux-x86_64/llvm-21.1.8` | 10.5 | Historical version, not a byte duplicate; audit consumers before retirement |
| `.tools/macos-arm64/llvm` | 7.3 | Active host toolchain: retain |
| `.tools/macos-arm64/llvm-21.1.8` | 7.8 | Historical host version: same retirement audit |
| `.tools/downloads` | 6.6 | Verified archives kept after extraction; choose offline retention before pruning |

The two historical versions and the downloads are about 24.8 GiB of
**candidate**, not guaranteed reclaimable, space; allocated-block reports can
double-count shared or cloned storage and do not prove physical savings. README
records the deliberate preservation of historical toolchains, and inspected
CMake caches use the mutable `llvm` path even for historical `*-llvm21` build
directories, so a directory name alone cannot prove which compiler produced an
artifact.

Lane worktrees are transient source/build storage outside the checkout, not a
fixed table entry or an automatic-pruning candidate: report their size only in an
operational snapshot, and aim for zero lane-owned data once all lanes are merged
and retired. Shared Git metadata is accounted separately, unmerged source and
active builds are protected, and retirement uses the owner-approved Git worktree
operation, never recursive cache deletion.

**Storage audit work package** (operational; it does not wait for an application
artifact store): inventory exact archive/version hashes, active worktree and VM
consumers, historical evidence obligations and offline pins; agree a retirement
list; remove only approved resolved paths; then verify bootstrap, build selection
and evidence access. Sibling-worktree and VM consumers are not yet cleared and no
deletion has been performed.

**Retention policy.** Keep explicitly pinned offline archives; otherwise permit
removal of a downloaded archive only after checksum verification and successful
extraction. Keep the refusal to overwrite unknown installations. Share pinned
tool installations across worktrees when identities match instead of
replicating full LLVM distributions. None of this changes the language or weakens
reproducibility checks.

### 7.2. End-user cache store

I09 owns complete cache identities and immutable local sharing; I12 owns the
user-facing workflow. Distinguish tool installation, dependency sources,
compiled/intermediate/query caches, debug data, scratch and final outputs.
Identities include all semantic, compiler, host/target, SDK, policy,
environment and path-sensitive inputs, and editor and CLI reuse only compatible
checked facts. The store requires byte and age budgets, live-build leases,
atomic publication, corruption recovery, offline pins and explainable eviction.
Shared blobs are never writable through materialized outputs. Debug profiles
account for all symbol files, since moving debug data alone does not reduce
total size. Budget changes must not silently change overflow, panic,
specialization or ABI.

The managed store now exists for build outputs (performance.md section 5.1.1)
and `mettle clean` implements its deletion and accounting. A separate
`mettle storage` report, dependency-source and debug-data pruning, and
live-build leases remain deferred; until then use filesystem reports. Measure
cold/warm retained bytes, peak scratch, rebuild cost and matched runtime behavior
before selecting default budgets or claiming savings.
