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
  (T003) follow; both are implemented and verified on macOS arm64 (Release
  and Debug).
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
macros and no library target. Macro names are global to the package graph (a
duplicate is a `package` error); a file-local declarative `macro` of the same
name shadows it. An invocation `make_fn!(...)` (any delimiter) is recognized in
every source of the build, before parsing, like a declarative one.

Each program is compiled for the host (cached like any program) and run once
per distinct invocation in its package directory. The compiler writes a
versioned, line-based request (`mettle-macro 1.0`, the macro name and one
`tok KIND SPACED TEXT` line per argument token; the index is the token's
identity) to its standard input and reads `mettle:` lines from its standard
output: `text=` appends generated source, `error=` fails the invocation,
`rerun-if-changed=`, `rerun-if-env-changed=` and `reproducible` declare the
input contract. Escaping and the full format are in
`compiler/expansion/procedural.h`; the library side is `std::macros`
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
panic locations must add positions to the key), library sources by content, and probed-but-absent paths as absent. A
hit copies the stored artifact and skips checking, lowering, code generation and
linking; any miss does the full build, which is the same code path as a clean
build, so incremental and clean results agree byte for byte (the driver links
inside a private directory with fixed object and output names, so no
temporary name reaches the executable). CTest builds use a cache in the build
tree, never the user's. Reuse is whole-program: an edit
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

`mettle fmt FILE... [--check]` is implemented and verified: it
works on the token stream (`syntax/format.{h,cpp}`) and changes only whitespace.
Indentation is 4 spaces per bracket level (a line continued inside brackets, after
a trailing operator or starting with `.` gets one more level); spacing is
normalized after `,` `;` `:`, around `=`, comparison/compound-assignment/`=>`/`->`/`??`,
inside one-line `{ }` and removed around `::`, `.` and inside `()`/`[]`; other
gaps (`<`, `-`, `&`, ...) keep one space or none as written. Trailing whitespace
goes, blank-line runs collapse to one (none after `{` or before `}`), the file
ends in one newline. Line breaks are never added or removed; comments, text
literals, multi-line raw text and f-strings keep their bytes, and declarative
macro bodies keep their gaps. Each result is re-lexed and re-parsed and must have
the same token sequence, the same syntax-tree fingerprint and be a fixed point;
otherwise the file is reported and left untouched. Files that define
declarative macros are parsed after expansion for both fingerprints. Over the
source corpus every formatted run case still passes and formatted fail cases
report the same phase, line and message (columns may move). `--check` prints each file
that would change with its first differing line and exits 1 without writing;
otherwise changed files are replaced atomically (temporary file and rename).

`mettle lint FILE|PACKAGE [--allow|--warn|--deny RULE]... [build options]` is
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
ignored. Attributes on imports and on products/impls, line breaking of findings
and machine-readable output are not implemented.

Target, profile, feature, package/workspace and lock/offline selections are
shared options. Unknown or unavailable requested capabilities fail explicitly;
partial compiler milestones cannot count unsupported programs as passed tests.

Implemented and verified: `check`, `build`, `run`, `test`, `bench` and `fmt`
(plus `clean`, `migrate` and the inspection commands). `lint` is implemented
and verified (test `lint_reports_semantic_findings`). `doc` and doctests are implemented and verified
(see section 4).

```
mettle run   FILE|PACKAGE [build options] [-- ARGS...]
mettle test  FILE|PACKAGE [FILTER...] [--exact] [--include-ignored | --ignored]
             [--jobs N] [build options]
mettle bench FILE|PACKAGE [FILTER...] [--exact] [--include-ignored] [build options]
mettle doc   [PATH...] [-o DIR] [--private]
mettle test  FILE --doc [FILTER...]
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
separately. Test ordering is not a language guarantee. A deterministic seed and
concurrency selection are recorded when requested.

Implemented behavior (verified): `@test` marks a function in the root module
of the selected source with no parameters and result `Unit`, or `Unit throws E`
(returning the failure fails the test). `@ignore` / `@ignore("reason")` skips it
unless `--include-ignored` (run everything) or `--ignored` (run only ignored
tests) is given; `@should_panic` / `@should_panic("text")` passes only when the
test panics (exit status 101) or is ended by a signal, and the text, when given,
must occur in its output. The user's `main` is not the entry of a test build and
need not exist; the compiler generates the entry. Each test runs in its own
process of the same executable (a hidden selector argument), `--jobs N` of them
at a time (default: hardware concurrency), with standard input empty and both
output streams captured and shown for non-passing tests. Output is in
declaration order, `test NAME ... ok|FAILED|TERMINATED|ERROR|ignored`, then
`test result: ok|FAILED. N passed; M failed; K ignored; T terminated; I
infrastructure failures; F filtered out`. `failed` is a returned failure, a
panic or a missing expected panic; `terminated` is an end by signal (an
aborting profile's panic) or an unexpected exit status; infrastructure failures
are processes that could not start or a harness mismatch. The exit status is 1
unless all selected tests pass. Positional filters select by substring of the
name (`--exact`: equality); names are the function names of the root module.
No timeout bounds a hung test.

`@bench fn name()` (no parameters; any result, or a fallible result) in the
root module is run by
`bench` in one process at a time. The harness doubles the iteration count until
one sample takes at least 10 ms, then measures 11 samples of that many calls
with the monotonic `std::time` clock inside the process, and the command
prints the median, minimum and maximum nanoseconds per iteration with the
iteration count. The raw samples are not yet stored. Each call's result passes
through `core::hint::black_box(value)`, an identity the optimizer cannot see
through, so a benchmark keeps its work by returning it; inputs that must not be
constant-folded go through `black_box` too. There is no benchmark handle or
per-iteration setup. Results from `bench` do not replace the performance protocol's
registered metrics. A returned failure from a fallible benchmark is ignored.

Limits of the current implementation: tests and benchmarks inside inline or
file modules are rejected (`error[feature]`), machine-readable output does not
exist, and the deterministic seed option is not provided.

Panic expectations match the declared contract. Aborting profiles need subprocess
isolation to observe an expected panic; abort is not an unwind caught in-process.
Cleanup/cancellation tests observe completed teardown, not merely a request.
Benchmark runners do not weaken the performance protocol's registered metrics.

### 4.1. Documentation comments, `mettle doc` and doctests

Status: implemented and verified on macOS arm64 (packages cases `doc_writes_deterministic_html`, `doctests_run_isolated_examples`).

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
directory) is plain HTML with no script, font or network use: `index.html`,
one `<module>.html` per file (`net/http.mt` is `net::http`; a directory's
`module.mt` names the directory) and one shared `style.css`. Items are the
`pub` types, enums, unions, interfaces, functions, constants, aliases,
macros, inline modules and implementations (`--private` adds the rest), grouped
and sorted by name; fields, variants and the members of an interface or of an
`impl ... implements ...` need no `pub`, and `@test`/`@bench` functions are
omitted. A signature is the declaration header exactly as written
(whitespace collapsed, no body) with its attributes, so an omitted result is
not guessed. Output is deterministic (no timestamps, stable order, stale files
are not removed). Not yet provided: cross-module links, package cross
references, source hyperlinks (the page shows `file:line`), inferred result
types and search.

`mettle test FILE` also runs the fenced examples of the root source's
documentation (all items, `pub` or not) after its `@test` functions;
`--doc` runs only them. Each example is a function appended to the source
(a block with its own `fn main()` becomes that function), so it sees the
file's items, and runs in its own process through the test harness; if the
combined build fails, examples are built one by one so only the broken ones
fail. A code line written `~ code` (or `~`) is compiled but not rendered. The
fence info is a comma/space list: none or `mettle` (run), `no_run` (compiled
only), `ignore` (listed as ignored, not compiled), `should_panic`,
`compile_fail` / `compile_fail(PHASE)` and any other word (`text`, `sh`) for a
block that is not Mettle. A `compile_fail` block passes only when checking
rejects it with the named phase; without a phase, `lex`, `parse` and `feature`
(unsupported) diagnostics do not count, so a malformed or unsupported example
cannot pass. Results use the unit-test format: `Doc-tests FILE`, then
`test PAGE - ITEM (line N) ... ok|FAILED|ignored`, a `, no_run`-style note for
compiled-only and compile_fail passes, and a `test result:` line. Limits: only
the root source is scanned, file modules (`module name;`) cannot be built from
the generated copy, and examples declaring `fn main()` must return `Unit`.

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

Status (I12, implemented and verified): `mettle build -g`
emits DWARF 4 through `llvm::DIBuilder` in the LLVM adapter
(`backend/llvm/debug.*`): a compile unit and file per source, a subprogram per
source function (source name; linkage name is the symbol), a line-table
location on every instruction from the IR instruction spans, and a
`DW_TAG_variable`/`DW_TAG_formal_parameter` per named local with basic,
pointer, array and product (members at the compiler layout offsets) types. The
comp dir is the root source's directory, so output is deterministic; without
`-g` output is byte-identical. `-g` is explicit (the `debug` profile does not
imply it), and `-g` builds bypass the build cache. On Darwin an executable's
DWARF stays in the temporary object, so the link step runs `dsymutil` to write
`OUTPUT.dSYM` (warning if it is missing); `--emit object` keeps DWARF in the
object. Gaps: subprogram types lack parameter/return types; locals are
visible from function entry (no lexical scopes, so values before
initialization are garbage); sums, optionals, owners, erased values, fat
pointers and async states are opaque sized structs; no inlining/monomorphization
records, no CodeView/PDB, no moved-value liveness. Evidence: the packages
`debug_info` case, and every host run case built with `-g` runs unchanged and
passes `llvm-dwarfdump --verify`.

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
