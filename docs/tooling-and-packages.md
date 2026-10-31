# Packages, tools and development contracts

Status: selected design. The package-directory `mettle check|build` path is
implemented. The I09 T001 package-instance, Git-source and host/target-context
additions below are implemented, unverified (not yet built). Other commands
and an installed toolchain are not available.
These operations are native equivalents, not Cargo-manifest compatibility.

### Unicode table generation (I07)

`tools/unicode_tables.py UCD_DIR OUTPUT.mt` generates the Unicode 16.0.0
property and case-mapping module used by `library/core/char.mt`. Keep the UCD
input files and the generated `library/core/unicode_data.mt` synchronized with
the version recorded in that module; the Unicode license notice is
`library/core/UNICODE-LICENSE.txt`. The generator validates the release headers
in the versioned UCD files. `UnicodeData.txt` itself has no release header, so
its version is identified by the companion files in the same UCD distribution.
Case folding data is version-checked but is not used as lower/uppercase
mapping: those mappings come from `UnicodeData.txt` and unconditional
`SpecialCasing.txt`.

### Emitted-program sanitizers (I10/I11)

Status: implemented and verified on macOS arm64 (`probe.sanitizers`). `mettle build`, `mettle run`
and `mettle test` accept `--sanitize address` or `--sanitize thread` for
single-file and package inputs. The driver instruments emitted LLVM/object
code, links the matching instrumented `alloc`, `panic`, `sys` and `thread`
runtime, and includes the sanitizer set in its build-cache key. `address,thread`
is rejected with a driver diagnostic because the runtimes cannot be combined.
Sanitized object output must be linked by its consumer with the matching
compiler-rt option and runtime.

Although `undefined` is a recognized sanitizer name, it currently produces a
clear unsupported-feature diagnostic. Mettle defines checked integer overflow
itself, and this backend does not yet emit UBSan checks for other undefined
operations; linking the UBSan runtime alone would not instrument emitted code.
Do not treat this mode as UBSan or cross-target qualification; the ASan and
TSan probes run on macOS arm64 only.

### 1.1. Implemented subset (I09 T001)

`mettle check|build DIR_OR_Mettle.toml` plans the package in the `packages`
component, then compiles the selected executable target with each resolved
dependency library mounted as a public root module named after the package
(`-` becomes `_`). Inside a dependency's own submodules, reach other packages
with `import package.name`.

- Manifest: `[package] name/version/language="mettle-1"`, `[targets.NAME]`
  (`kind`, `source`; defaults `src/main.mt` executable, `src/lib.mt` library),
  `[dependencies]` (version string/array, or `{path, git, rev|tag|branch,
  version, optional, default_features}`), `[build-dependencies]` with source,
  version and explicit features resolved for the host, `[features]`
  (`feature`, `dep:x`, `x/f`; optional dependencies imply a feature),
  `[registry] path` (root only) and parsed but unused `[dev-dependencies]`.
  Unknown keys are errors.
- Versions: SemVer requirements (`^`, `~`, comparators, `*`, comma
  intersections, arrays as unions). Highest non-yanked version wins; a
  lock-recorded version is preferred (even if yanked). Incompatible versions
  of one package can coexist; each exact source/version/context has a distinct
  package identity, internal module root and linked symbol namespace.
- Local registry: `<registry>/<name>/<version>/Mettle.toml` plus sources; a
  `YANKED` file yanks a version. Select with `--registry DIR` (repeatable,
  before the manifest `[registry]`). No remote HTTP registry fetch exists;
  `--offline` prevents Git fetching and uses only already-cached commits.
- Git sources: `{ git = URL, rev = REV }`, `{ git = URL, tag = TAG }` or
  `{ git = URL, branch = BRANCH }` use the system `git` CLI. Mirrors and
  detached checkouts live under the configured Mettle cache's `sources/git`;
  the lock records the resolved commit, not a moving selector. Offline mode
  uses the locked commit only when it is already present in that store. A
  dirty or mismatched cached checkout is rejected.
- `Mettle.lock`: `version = 2` plus `[[package]]` entries (`id`, name,
  version, `source` = `root`/`path+REL`/`registry+REL`/`git+URL#COMMIT`,
  `checksum`, resolved `features`, dependency-instance IDs). Checksum is
  SHA-256 over sorted relative paths,
  sizes and contents of `*.mt` and `Mettle.toml` (hidden, `target`, `build`
  skipped). Registry and Git checksum mismatches always fail; other drift is
  re-locked, or fails under `--locked`/`--frozen`. Missing lock fails under
  `--locked`.
- Flags: `--bin NAME`, `--features a,b`, `--no-default-features`,
  `--registry DIR`, `--locked`, `--offline`, `--frozen`.
- Limits: remote HTTP registries are not implemented because no registry
  protocol is specified; no registry/account is created. Host and target
  package instances resolve features independently. Host dependency mounts are
  exposed only while compiling host build programs and procedural macros;
  package build-script output directories still need isolation when the same
  package is selected in both contexts. Optional build-dependencies are
  rejected. Library-only roots cannot be built.
  Build scripts (T002) and the content-addressed build cache
  (T003) follow; both are implemented and verified on macOS arm64 (Release
  and Debug).
  Existing package tests are in `tests/packages.py`; the new
  `coexisting_versions`, `git_source` and `host_target_separation` cases are
  implemented but unverified (not yet built).

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

### Procedural macros (L056)

Status: implemented and verified on macOS arm64 (tests `procedural_macro` and
`procedural_macro_failure` in `tests/packages.py`).

A package declares host-program macros in `Mettle.toml`:

```toml
[macros.make_fn]
source = "macros/make_fn.mt"   # a Mettle program, relative to the package
api = 1                        # required extension API major version
```

`api` is required; a major version the compiler does not support is a
`feature` diagnostic before any program is built or run. A package may declare
macros and no library target. Procedural macro names are global to the package
graph (a duplicate is a `package` error); a lexically visible declarative
`macro` of the same name shadows it. An invocation `make_fn!(...)` (any
delimiter) is recognized in every source of the build, before parsing, like a
declarative one.

Each program is compiled for the host (cached like any program) and run once
per distinct invocation in its package directory. The compiler writes a
versioned, line-based request (`mettle-macro 1.0`, the macro name and one
`tok KIND SPACED TEXT` line per argument token; the index is the token's
identity) to its standard input and reads `mettle:` lines from its standard
output: `text=` appends generated source, `error=` fails the invocation,
`rerun-if-changed=`, `rerun-if-env-changed=` and `reproducible` declare the
input contract. Escaping and the full format are in
`compiler/expansion/procedural.h`; the library side is `std.macros`
(`read_invocation`, `emit`, `fail`, `depends_on_file`, `depends_on_env`,
`reproducible`). The generated text is re-lexed and re-parsed, nested macros in
it are expanded, and every generated token is attributed to the invocation, so
diagnostics in generated code point at the `name!(...)` use. A program
failure, a protocol violation, a reported error or text that does not lex is a
`macro` diagnostic at the invocation.

Caching follows the build-script rule: a macro reruns on every build unless it
declared `reproducible`; it is then reused only while its binary, request,
declared files/directories and environment variables are unchanged
(`--explain` shows `rerun (...)` or `reused`). Undeclared inputs therefore
always force a rerun. Each response text is part of the consumer's build key,
so a changed external input changes the output while an unchanged expansion
reuses the cached compile. Tests: `tests/packages.py` (`procedural_macro`,
`procedural_macro_failure`), fixtures in `tests/packages/proc-macro`.
Known gaps: macros are not namespaced per package; no definition-site,
fresh-identity or span-carrying token constructors or per-token diagnostics
(an error points at the whole invocation); the program-side token API exposes
tokens as text, not a structured tree; attribute and derive macros are not
supported; only `name!(...)` invocations; no project isolation policy.

### Incremental builds and the build cache (T003)

`mettle build` (executables and objects) keys its output by a SHA-256 over: the
compiler identity (version, runtime target, size and mtime of the compiler and
runtime library), emit/profile/overflow policy/target/linker/sysroot, the
output's file name (the linker embeds it as the code-signature identifier),
enabled features, mounts, link libraries, and every source the load step read.
User sources count by token stream (comments, spacing and blank lines do not
matter; sound while no source position reaches the output, so debug info or
panic locations must add positions to the key), library sources by content,
and probed-but-absent paths as absent. A
hit copies the stored artifact and skips checking, lowering, code generation and
linking; any miss does the full build, which is the same code path as a clean
build, so incremental and clean results agree byte for byte (the driver links
inside a private directory with fixed object and output names, so no
temporary name reaches the executable). CTest builds use a cache in the build
tree, never the user's. Reuse remains whole-program: an edit
to any loaded source (including a dependency package or generated file)
recompiles; unloaded files, comments and layout do not. Finer
per-module parse and per-dependency-package analysis/object reuse remain open.
Builds hold an RAII lease for the active whole-program key while compiling,
materializing or publishing; age/byte pruning preserves leased entries, and
`clean` refuses to remove a store with live leases. Lease behavior is
implemented, unverified (not yet built). Storage design:
performance.md section 5.1.1. Flags: `--cache-dir DIR`,
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

`mettle fmt FILE... [--check]` is implemented and verified: it
works on the token stream (`syntax/format.{h,cpp}`) and changes only whitespace.
Indentation is 4 spaces per bracket level (a continuation after a comma or
trailing operator, or starting with `.`, gets one more level where applicable);
spacing is
normalized after `,` `;` `:`, around `=`, comparison/compound-assignment/`=>`/`->`/`??`,
inside one-line `{ }` and removed around `.` and inside `()`/`[]`; other
gaps (`<`, `-`, `&`, ...) keep one space or none as written. Trailing whitespace
goes, blank-line runs collapse to one (none after `{` or before `}`), the file
ends in one newline. Line breaking is implemented and verified on macOS arm64
(`fmt_normalizes_layout_only`): it targets 100 bytes and breaks after commas in
call, parameter, generic and collection lists, constructors and match arms,
and after binary operators. Chained member calls are not broken, since a line
starting with `.` does not continue an expression. Continuation indentation follows the bracket
nesting and continuation rules above. It leaves files with macro
definitions/invocations, f-strings or multiline tokens, and lines with comments,
unwrapped. Long unbreakable segments may exceed the width; when wrapping
changes the parse it falls back to the unwrapped layout. Comments, text
literals and macro gaps remain intact. Each result is re-lexed and re-parsed and must have
the same token sequence, the same syntax-tree fingerprint and be a fixed point;
otherwise the file is reported and left untouched. Files that define
declarative macros are parsed after expansion for both fingerprints. In the
prior formatter verification, every source-corpus run case passed and
formatted fail cases reported the same phase, line and message (columns may
move); this expanded wrapping implementation has not been built or tested.
`--check` prints each file
that would change with its first differing line and exits 1 without writing;
otherwise changed files are replaced atomically (temporary file and rename).

`mettle lint FILE|PACKAGE [--format human|json] [--allow|--warn|--deny RULE]... [build options]` is
implemented and verified. It runs the same front end as `check`
(parse, expansion, resolution, typing, ownership; any error is reported as usual
and no lint runs) and then semantic lints over the checked program, never over
raw text. Findings are structured diagnostics with spans and expansion
provenance, printed as `warning[RULE]` (or `error[RULE]` when denied) followed by
a count; findings in the standard library, dependency packages and generated code
are not reported. The exit status is 1 when a denied finding exists, otherwise 0.
Rules (stable kebab-case names):

| Rule | Reports |
| --- | --- |
| `unused-binding` | a `let`/`var`/pattern binding that is never read, assigned or captured (names starting with `_` and `let _ =` are exempt) |
| `unused-mutability` | a `var` that is never reassigned, mutably borrowed or used as a `mut` receiver; use `let` |
| `unused-import` | an `import` name (or glob) no lookup went through; `pub` imports are exempt |
| `unreachable-code` | the first statement of a block after a statement that never completes |
| `unused-outcome` | an expression statement whose value is an `Outcome` (for example a bare `capture f()`); handle it, `try` it or write `let _ =` |

Levels are `allow`, `warn` (default) and `deny`. `--allow|--warn|--deny RULE`
set a rule, the rule name `warnings` sets the default for every rule (`--deny
warnings` makes all findings fail). The `@allow(RULE, ...)`, `@warn(...)`,
`@deny(...)` and `@forbid(...)` attributes on a function override the flags inside
that function; `RULE` may be spelled with `-` or `_`, and unknown names are
ignored. Attributes on imports and on products/extensions and line breaking of
findings are not implemented. JSON findings are implemented and verified on macOS arm64: one JSON object per line on stdout, ordered as human findings, with
`code`, `level` (`warn` or `deny`), `span` (`file`, zero-based byte `begin`
and exclusive `end`), and `message`. No suggestion field is emitted because
the current rules do not provide structured suggestions. Front-end failures
remain human diagnostics on stderr; denied findings still return status 1.

Target, profile, feature, package/workspace and lock/offline selections are
shared options. Unknown or unavailable requested capabilities fail explicitly;
partial compiler milestones cannot count unsupported programs as passed tests.

Implemented and verified: `check`, `build`, `run`, `test`, `bench` and `fmt`
(plus `clean` and the inspection commands). The T007 runner
extensions in section 4 are implemented and verified on macOS arm64. `lint` is implemented and
verified (test `lint_reports_semantic_findings`). `doc` and doctests are
implemented and verified (see section 4.1).

```
mettle run   FILE|PACKAGE [build options] [-- ARGS...]
mettle test  FILE|PACKAGE [FILTER...] [--exact] [--include-ignored | --ignored]
             [--jobs N] [--timeout SECONDS] [--format human|json] [build options]
mettle bench FILE|PACKAGE [FILTER...] [--exact] [--include-ignored]
             [--format human|json] [build options]
mettle doc   [PATH...] [-o DIR] [--private] [package options]
mettle test  FILE|PACKAGE --doc [FILTER...]
```

`run` builds through the ordinary build path and cache into a private temporary
directory (nothing is written beside the sources), starts the program with the
arguments after `--` and the caller's standard streams, and exits with its
status; a program ended by a signal produces a message and status 128 plus the
signal number. `test` and `bench` use the debug and release profile
respectively unless `--profile` is given; the other build options apply.

## 4. Tests and executable documentation

Test functions use @test; filtering selects fully qualified names. The runner
reports pass/fail/ignored, process termination and infrastructure failure
separately. Test ordering is not a language guarantee. `--jobs` selects test
concurrency; a deterministic seed option is not yet provided.

Runner extensions in this T007 work are implemented and verified on macOS
arm64 (test `test_json_timeout_and_modules`). `@test` marks a function in any module of the selected package with no
parameters and result `Unit`, or `Unit throws E` (returning the failure fails
the test). Inline and file modules (`module name`) are included; displayed
names are fully qualified, such as `network.connect`. `@ignore` /
`@ignore("reason")` skips a test unless `--include-ignored` (run everything) or
`--ignored` (run only ignored tests) is given; `@should_panic` /
`@should_panic("text")` passes only when the test panics (exit status 101) or is
ended by a signal, and the text, when given, must occur in its captured output.
The user's root `main` is not the entry of a test build and need not exist; the
compiler generates the entry. Each test runs in its own process of the same
executable (a hidden selector argument), `--jobs N` of them at a time
(default: hardware concurrency), with standard input empty and both output
streams captured. Output follows stable collection order, which is not a
language guarantee. The human format remains the default and reports
pass/fail/ignored, termination, timeout and infrastructure
failure separately: `failed` is a returned failure, panic or missing expected
panic; `terminated` is a signal or unexpected exit status; infrastructure
failure means a process could not start or the harness selector did not match.
Human test lines are `test NAME ... ok|FAILED|TERMINATED|TIMED OUT|ERROR|ignored`;
the final `test result:` line reports passed, failed, ignored, terminated,
infrastructure failures, timed out and filtered counts. `--timeout SECONDS`
bounds each test and doctest process;
there is no default timeout. On expiry the runner kills the process group and
reports `timed out`. The exit status is 1 unless all selected tests pass.
Positional filters select by substring of the fully qualified name (`--exact`:
equality).

`--format json` writes newline-delimited JSON events instead of human output.
Each suite has a `suite` event (`event`, `name`, `total`, `filtered`), one `test`
event per selected or ignored entry (`event`, `name`, `outcome`, `duration_ns`,
`output`, `message`), then a `summary` event. Field order is fixed as listed.
Test outcomes are `passed`, `failed`, `ignored`, `terminated`,
`infrastructure_failure` and `timed_out`; captured stdout/stderr, including
panic text, is in `output`, while `message` carries the runner's explanation or
ignore reason. Test summary fields, in order, are `event`, `passed`, `failed`,
`ignored`, `terminated`, `infrastructure_failures`, `timed_out` and `filtered`;
benchmark summary fields are `event`, `measured`, `failed`, `ignored` and
`filtered`. Benchmark entries use the `measured` outcome. Build/CLI diagnostics
remain on stderr. A normal `test` command reports its unit-test and doctest
suites separately when both contain examples.

`@bench fn name()` (no parameters; any result, or a fallible result) in any
package module is run by `bench` one process at a time. Names are fully
qualified. The harness doubles the iteration count until one sample takes at
least 10 ms, then measures 11 samples of that many calls with the monotonic
`std.time` clock inside the process. Human output prints the median, minimum
and maximum nanoseconds per iteration with the iteration count. JSON reports a
`measured` outcome, wall-clock `duration_ns` and the captured raw iteration and
sample-nanosecond line in `output`. Each call's result passes through
`core.hint.black_box(value)`, an identity the optimizer cannot see through,
so a benchmark keeps its work by returning it; inputs that must not be
constant-folded go through `black_box` too. There is no benchmark handle or
per-iteration setup. Results from `bench` do not replace the performance
protocol's registered metrics. A returned failure from a fallible benchmark is
ignored. A deterministic seed option and benchmark handles are not provided.

Panic expectations match the declared contract. Aborting profiles need subprocess
isolation to observe an expected panic; abort is not an unwind caught in-process.
Cleanup/cancellation tests observe completed teardown, not merely a request.
Benchmark runners do not weaken the performance protocol's registered metrics.

### 4.1. Documentation comments, `mettle doc` and doctests

Status: documentation generation and doctests were previously verified on
macOS arm64 (packages cases `doc_writes_deterministic_html`,
`doctests_run_isolated_examples`). Resolved reference links and dependency
package pages are implemented, unverified (not yet built).

`///` documents the item that follows it (before or between its attributes) and
`//!` the enclosing file or inline module. The lexer already keeps comments as
tokens, so no syntax change is needed; `compiler/documentation` reads them from
the token stream. Text is markdown reduced to paragraphs, `#` headings,
`-`/`*` lists, `` `inline code` `` and fenced blocks.

`mettle doc [PATH...] [-o DIR] [--private]` documents every `.mt` file of each
directory (recursively, skipping `target` and dot directories) or each named
file, default `.`. A file that does not lex, expand and parse is reported
(`error[parse]` ...), skipped and makes the exit status 1; documentation is
never produced from an invalid tree. The output (default
`target/mettle/doc` below a single directory argument, else below the current
directory) is static HTML with no font or network use: `index.html`,
one `<module>.html` per file (`net/http.mt` is `net.http`; a directory's
`module.mt` names the directory) and one shared `style.css`. Items are the
`pub` types, enums, unions, interfaces, functions, constants, aliases,
macros, inline modules and implementations (`--private` adds the rest), grouped
and sorted by name; fields, variants and the members of an interface or of an
`extend ... implements ...` need no `pub`, and `@test`/`@bench` functions are
omitted. A signature is the declaration header exactly as written
(whitespace collapsed, no body) with its attributes, so an omitted result is
not guessed. Output is deterministic (no timestamps, stable order, stale files
are not removed). Documentation references use checked name resolution:
`[name]` references and dotted paths in signatures and prose, including inline
code, link to the resolved documented item. Aliases and imports follow the
same visibility and lookup rules as source names. When `mettle doc` receives a
package directory or manifest, dependency packages are included in the site
and cross-package links target their pages. Unresolved or inaccessible
references, and resolved items without generated pages, produce
`warning[doc-link]`. Standalone paths without a package graph cannot resolve
names and report references as unresolved. Source hyperlinks (the page shows
`file:line`) and inferred result types are not provided.
An index page searches deterministic item names using local `search-index.json`,
`search-index.js` and `search.js`; the JS copy allows search when opened from
the filesystem without a local web server. Fenced code remains unlinked.

`mettle test FILE|PACKAGE` also runs fenced examples from every source file in
the selected package (all items, `pub` or not) after its `@test` functions;
`--doc` runs only the examples. Each generated test is overlaid on its original
file while the complete package/module graph is built, so file-module examples
retain their imports and module context without modifying package files. Each
example runs in its own process through the test harness; if the combined build
fails, examples are built one by one so only the broken ones fail. A code line
written `~ code` (or `~`) is compiled but not rendered. The fence info is a
comma/space list: none or `mettle` (run), `no_run` (compiled only), `ignore`
(listed as ignored, not compiled), `should_panic`, `compile_fail` /
`compile_fail(PHASE)` and any other word (`text`, `sh`) for a block that is not
Mettle. A `compile_fail` block passes only when checking rejects it with the
named phase; without a phase, `lex`, `parse` and `feature` (unsupported)
diagnostics do not count, so a malformed or unsupported example cannot pass.
Human results use `Doc-tests FILE`, then
`test PAGE - ITEM (line N) ... ok|FAILED|ignored`, a `, no_run`-style note for
compiled-only and compile_fail passes, and a `test result:` line. JSON results
use the same newline-delimited event format as unit tests. Examples declaring
`fn main()` must return `Unit`.

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

`mettle lsp [--library-dir DIR] [--target TRIPLE] [--freestanding]` runs the
language server (LSP 3.17, JSON-RPC with `Content-Length` framing on standard
input/output; UTF-16 positions). T005 status: implemented and verified on macOS
arm64 (test `language_server`). It supports full and ranged text synchronization with
`publishDiagnostics` (each open document is analyzed by the compiler front end
on its in-memory text; editing a document re-analyzes the open documents that
read it; parse errors still produce diagnostics), `hover`, `definition`,
hierarchical `documentSymbol`, `formatting` (the `mettle fmt` layout) and
`prepareRename`/`rename`. Navigation and rename use a token-based index of the
open documents, so they work on incomplete source. Rename refuses ambiguous
or unsafe cases (fields, variants, modules, `main`, items declared more than
once, reserved words as new names); local and parameter renames stay within
their scope and update `name:` argument labels.

Known gaps: completion, signature help and find-references are not implemented;
hover shows the declared signature rather than an inferred type (the pipeline
exposes no checked side tables); match-arm and closure pattern bindings are not
tracked; member rename and definition match by name, not receiver type; only
open documents take part in navigation; single-file analysis only (no package
mounts); ranges inside macro- or derive-generated sources are reported at the
start of the document with a `path:line:column:` prefix instead of the
expansion chain.

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

Status (I12/T006, partial; the current DWARF changes for lexical scopes,
moved-value liveness, erased witness types and inlining are implemented,
unverified (not yet built). Earlier `debug_info` assertions passed on macOS
arm64; the LLDB workflow and current summaries are implemented, unverified):
`mettle build -g`
emits DWARF 4 through `llvm::DIBuilder` in the LLVM adapter
(`backend/llvm/debug.*`): a compile unit and file per source, a subprogram per
source function (source name; linkage name is the symbol), a line-table
location on every instruction from the IR instruction spans, and a
`DW_TAG_variable`/`DW_TAG_formal_parameter` per named local with basic,
pointer, array and product (members at the compiler layout offsets) types.
The metadata describes captured places by name, generic products with their
instantiated Mettle spelling, and length-bearing pointers as
`{data_ptr, length}`. Erased pointers expose `{data_ptr, alignment, witness}`;
the witness member points to a DWARF description of the metadata marker,
alignment, method slots and parent witnesses in the runtime table. The current
runtime table does not carry a concrete type descriptor for sized erased
values, so LLDB cannot recover their concrete dynamic type from it.
Tagged sums use a DWARF variant part with the physical discriminator and
per-variant fields at offsets from the shared payload storage. Explicit integer
enum representations use their actual discriminants; transparent enums retain a
product-like description. Macro
tokens use the invocation location in line tables. A coroutine future's state
(`core.future.CoroutineState`) exposes its `state` resume discriminator as a
DWARF variant part (`start`, `await #N (line L)`, `running`, and `done`), with
captured environment and output fields and per-suspension fields for
scope-initialized locals. The LLDB summary renders `state = await #N (line L)`.
These coroutine changes are implemented, unverified (not yet built); the
existing `debug_info` assertions have prior macOS arm64 evidence, but the
current changes and interactive LLDB behavior remain unverified.

For LLDB, import `tools/debug/mettle_lldb.py` with
`command script import /path/to/mettle/tools/debug/mettle_lldb.py`. It registers
best-effort summaries for native `List`, slices, erased views, `String`, text
views, optionals, outcomes and coroutine states; text reads are capped at 256
bytes. Summaries do not execute program code and report unavailable data rather
than guessing. `tests/packages.py::debugger_workflow` builds a `-g` executable,
imports these summaries into batch LLDB, and checks source breakpoints,
parameters/locals, list and slice lengths, a tagged variant, an erased view and
a suspended coroutine state. It prints a clear skip if LLDB is unavailable.
This workflow and the current summary changes are implemented, unverified (not
run on this lane); prior macOS arm64 checks covered List length/capacity and
String text display, while the coroutine summary has not been checked
interactively.

The comp dir is the root source's directory; without `-g` the adapter emits no
debug metadata. `-g` is explicit (the `debug` profile does not imply it), and
`-g` builds bypass the build cache. On Darwin an executable's DWARF stays in
the temporary object, so the link step runs `dsymutil` to write `OUTPUT.dSYM`
(warning if it is missing); `--emit object` keeps DWARF in the object.
Lexical blocks carry source scopes; named locals start unavailable until
initialized, become unavailable after moves/drops or scope exit, and regain a
location after a whole-place store. Optimizer-generated `inlinedAt` locations
use source subprograms and call-site locations; `@inline`, `@inline(always)`
and `@inline(never)` map to LLVM optimization hints. These changes and their
new `debug_info` assertions are implemented, unverified (not yet built).
Remaining gaps include subprogram parameter/return types, some unsupported
layouts, concrete dynamic types for sized erased values, monomorphization
records and interactive LLDB verification. Windows CodeView/PDB remains open
and is outside this DWARF lane. The `debug_info` case covers basic, coroutine,
scope, move, erasure and release-inlining metadata.

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
