# Packages, tools and development contracts

Selected package/tool contracts and implemented subsets are distinguished below.
Recorded verification is macOS arm64 unless stated otherwise; it does not
qualify the gated Linux host. An installed toolchain remains unavailable.

### Unicode table generation (I07)

`tools/unicode_tables.py UCD_DIR OUTPUT.mt` generates the Unicode 17.0.0
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

Implemented (`probe.sanitizers`): `mettle build`, `mettle run`
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
The emitted backend does not provide UBSan or cross-target qualification.

### 1.1. Implemented subset (I09 T001)

`mettle check|build DIR_OR_package.mettle` plans the package in the `packages`
component, then compiles the selected entry with each resolved
dependency library mounted as a public root module named after the package
(`-` becomes `_`). Dependency aliases resolve from every module using the same
`import name` spelling for local, registry and Git sources. Explicit local
bindings take precedence; `package.name` remains an optional root qualifier.

- Manifest: root `name`/`version`, optional `mettle-version` (minimum compiler
  SemVer), `kind` (`"executable"` by default or `"library"`), `emit` and `entry`
  (default `"src/main.mt"`). An entry map must define `main`; its values are
  executable path strings or objects with `kind`, `path`, `emit`. Root `kind`
  and `emit` cannot accompany an entry map. At most one entry is a library;
  dependencies import its public API. No separate library-root file is required.
  Ordinary builds select `main`; `--entry NAME` selects another entry. There
  is no `targets` block or per-package `language` selector.
  `dependencies` accepts version strings/arrays, explicit relative/absolute
  path strings, or objects with `path, git, rev|tag|branch, version, optional,
  features, default_features`. `build-dependencies` resolves sources, versions and
  explicit features for the host. `features` contains
  (`feature`, `dep:x`, `x/f`; optional dependencies imply a feature),
  `registry { path: ... }` (root only). Root `dev-dependencies` activate for
  test/benchmark builds, never ordinary builds; they cannot be optional.
  Unknown keys are errors.
- Versions: section 1 defines requirements and selection. Each exact
  source/version/context has a distinct module root and linked symbol namespace.
- Local registry: `<registry>/<name>/<version>/package.mettle` plus sources; a
  `YANKED` file yanks a version. Select with `--registry DIR` (repeatable,
  before the manifest `registry` block). No remote HTTP registry fetch exists;
  `--offline` prevents Git fetching and uses only already-cached commits.
- Git selectors (`rev`, `tag`, `branch`) use the system `git` CLI, with mirrors
  and detached checkouts in cache `sources/git`. Offline builds require the
  locked commit there and a matching recorded selector. Changing selectors
  requires an unlocked update even when they resolve to the same commit.
  Dirty or mismatched cached checkouts are rejected.
- `lock.mettle`: `version: 3` plus a `packages` list of objects (`id`, name,
  version, `source` = `root`/`path+REL`/`registry+REL`/`git+URL#COMMIT`,
  `checksum`, resolved `features`, dependency-instance IDs, and `git_selectors`
  for Git packages). Version 2 locks remain readable but require one unlocked
  build to migrate before `--locked` or `--frozen` builds.
  Nested Git path sources use `path+git+URL#COMMIT/REL`, independent of the
  cache location. Checksum is
  SHA-256 over sorted relative paths,
  sizes and contents of `*.mt` and `*.mettle`, excluding generated `lock.mettle`
  files (hidden, `target`, `build` skipped). Registry and Git checksum mismatches always fail; other drift is
  re-locked, or fails under `--locked`/`--frozen`. Missing lock fails under
  `--locked`. The lock records the active feature/development context; changing
  that graph can require an unlocked update before a frozen build.
- Flags: `--entry NAME`, `--features a,b`, `--no-default-features`,
  `--registry DIR`, `--locked`, `--offline`, `--frozen`.
- Limits: remote HTTP registries are not implemented because no registry
  protocol is specified; no registry/account is created. Host and target
  package instances resolve features independently. Host dependency mounts are
  exposed only while compiling host build programs and procedural macros;
  their build-script outputs use separate writable package views. Optional build-dependencies are
  rejected. Compiled Mettle interface output (`emit: "package"`) requires the
  self-hosted compiler and reports `error[feature]`; source libraries work today.
  Evidence: `tests/packages.py` cases `coexisting_versions`, `git_source`,
  `host_target_separation` (Release); T002/T003 passed Debug and Release.

### Build scripts (T002)

`build { script: "build.mt" }` names a Mettle program (compiled for the host
with the hosted `std`, cached like any other program) that runs with the
package directory as its working directory before consumers compile. Its
environment adds `METTLE_OUT_DIR` (`target/mettle/out` in the package),
`METTLE_PACKAGE_DIR`, `METTLE_PACKAGE_NAME`, `METTLE_PACKAGE_VERSION`,
`METTLE_TARGET`, `METTLE_PROFILE` and `METTLE_FEATURES`. `METTLE_TARGET` is
the host target for host dependencies and the selected target otherwise. Stdout lines
`mettle:KEY=VALUE` are the only way to affect the build:
`module=NAME=FILE` mounts a generated file as root module `NAME`, also
available by that name inside its owning dependency package,
`feature=NAME` enables that `@cfg(feature = ...)` value for the package,
`link-lib=NAME` adds `-lNAME`, and `rerun-if-changed=PATH`,
`rerun-if-env-changed=VAR` and `reproducible` form the input contract below.
Other lines are ignored; an unknown `mettle:` line is a `build` error. Generated
files are ordinary sources of the compile, so they are hashed by content and
participate in dependency analysis before consumers compile. Scripts run with
ordinary host capabilities and are never sandboxed, but their execution,
decisions and outputs are visible with `--explain`.

Git packages execute host tools in writable checkout-shaped copies beneath the
root package's `target/mettle/package-work`, not in the immutable source cache.
Each copy preserves package-relative paths, tracked contents/modes and Git
metadata; `METTLE_PACKAGE_DIR` and the working directory name its package root,
and `METTLE_OUT_DIR` remains that root's `target/mettle/out`.
Host and target views are separate. Builds and clean serialize shared output
slots with `target/mettle-package-work.lock`; generated files never become the
authority for source identity or lock contents.

Reuse follows section 2's host-execution contract, including the script binary,
target/profile/features, declared input hashes/variables and generated-file hashes.

### Procedural macros (L056)

Implemented; evidence: `procedural_macro` and `procedural_macro_failure` in
`tests/packages.py`.

A package declares host-program macros in `package.mettle`:

```text
macros {
    make_fn {
        source: "macros/make_fn.mt"
        api: 1
    }
}
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
`bootstrap/expansion/procedural.h`; the library side is `std.macros`
(`read_invocation`, `emit`, `fail`, `depends_on_file`, `depends_on_env`,
`reproducible`). The generated text is re-lexed and re-parsed, nested macros in
it are expanded, and every generated token is attributed to the invocation, so
diagnostics in generated code point at the `name!(...)` use. A program
failure, a protocol violation, a reported error or text that does not lex is a
`macro` diagnostic at the invocation.

Reuse follows section 2, including the binary, request and declared inputs.
`--explain` reports `rerun (...)` or `reused`; response text enters the consumer's
build key. Fixtures: `tests/packages/proc-macro`.
Known gaps: macros are not namespaced per package; no definition-site,
fresh-identity or span-carrying token constructors or per-token diagnostics
(an error points at the whole invocation); the program-side token API exposes
tokens as text, not a structured tree; attribute and derive macros are not
supported; only `name!(...)` invocations; no project isolation policy.

### Incremental builds and the build cache (T003)

`mettle build` (executables and objects) keys its output by a SHA-256 over: the
compiler identity (version, runtime target, compiler sanitizer mode, and paths
and SHA-256 digests of the compiler and ordinary/address/thread runtime archives),
emit/profile/overflow policy/target/linker/sysroot, the
output's file name (the linker embeds it as the code-signature identifier),
enabled features, mounts, link libraries, and every source the load step read.
User sources count by token stream (comments, spacing and blank lines do not
matter; sound while no source position reaches the output, so debug info or
panic locations must add positions to the key), library sources by content,
and probed-but-absent paths as absent. A whole-build hit copies the stored
artifact and skips checking, lowering, code generation and linking; a miss runs
the same whole-build path as a clean build. CTest builds use a cache in the
build tree, never the user's. Whole-build reuse remains available for
objects without `-g`, and for executables without `-g` or explicit native
link libraries. Executables using `@link` or build-script `link-lib` bypass
whole-build reuse because the linker may resolve changed library contents.

Eligible `mettle build` debug executable builds additionally cache one object
per resolved dependency package. The loader records package-instance ownership
and carries it through IR specialization. Non-generic, owner-unambiguous
package functions and statics go in their package object; generic instances,
synthesized helpers and owner-ambiguous items stay in the root object, as does
the executable entry wrapper. Cross-object references are emitted as external
declarations with stable package-instance symbols. Release builds,
`--emit object`, debug-info/sanitizer/harness/freestanding/package-context
builds, and builds with global assembly or uncertain/generated inputs use the
single-object fallback.

Each package key includes its instance identity, exact source checksums,
resolved dependency object keys, compiler identity, target, profile, features
and codegen-affecting options. The source set is deliberately conservative:
all loaded library source digests participate. Cached objects are checksum
verified; corruption causes a rebuild. A package-object hit skips that
dependency's LLVM lowering and object emission, but parsing, expansion,
checking and specialization still run for the whole program. Package objects
are staged and hashed without the store lock, then batch-published and pruned
under one lock per build, not one lease/lock per package. A concurrent eviction
can therefore turn a lookup into a safe miss, but cannot change build output.
The whole-build key retains its existing live lease; `clean` refuses to remove
a store with live leases.

Evidence: `object_cache_integrity` covers root-only edits, clean/incremental
output equality and corrupt-object regeneration (Release).
`--no-cache` disables
both whole-build and package-object caches. Storage design: performance.md
section 5.1.1. Flags: `--cache-dir DIR`, `--no-cache`,
`--cache-limit-kib N`, `--cache-max-age-days N`, `--explain`;
`METTLE_CACHE_DIR`; `mettle clean [PACKAGE] [--dry-run]`.

## 1. Manifest and identity

Use `package.mettle` and `lock.mettle` as the manifest/lock names. Both use
Mettle's data format, read by `bootstrap/packages/data.{h,cpp}`. A manifest is
optional for direct source-file builds. TOML manifests/locks are not accepted.
A package declares a lowercase ASCII name, SemVer version, entry paths,
dependencies and optional named features. Package names use
`[a-z][a-z0-9_-]*`; source identity remains separate from the display name.

Illustrative manifest:

```text
name: "example"
version: "0.1.0"

dependencies {
    parser: "../parser"
    "registry-lib": "1.2"
}
```

For a single custom entry use `entry: "app.mt"`. For multiple programs, use the
same key as a map:

```text
entry {
    main: "src/main.mt"
    format: "tools/format.mt"
}
```

`main` is required in an entry map and selects the default entry.
`mettle build . -o build/app` selects it;
`mettle build . --entry format -o build/format` selects the other program.
Strings and maps are alternative forms of the same key, not simultaneous fields.

A source library needs only `kind: "library"`; its entry still defaults to
`src/main.mt`. For a library and a utility in one package:

```text
name: "geometry"
version: "1.2.0"
mettle-version: "0.0.0"
entry {
    main {
        kind: "library"
        path: "src/main.mt"
        emit: ["static", "shared"]
    }
    inspect: "tools/inspect.mt"
}
```

`kind` selects library versus executable semantics, independently of source
path or whether a function is named `main`. Libraries do not require or emit a
hosted entry wrapper. `pub` controls Mettle API visibility; native callable
exports use the language's explicit ABI/export declarations.
`emit` chooses artifacts: libraries default to `"static"`, executables to
`"executable"`; both also accept `"object"`, `"llvm"`, `"ir"`. Libraries may
request `"shared"` or `"package"` (the latter is a recognized, unsupported
self-hosting capability). `--emit FORMAT` overrides the manifest for one build.
One format writes exactly `-o OUTPUT`. Multiple formats treat OUTPUT as a prefix:
`.a`, `.so` (Darwin `.dylib`), `.o`, `.ll`, `.ir`, or no suffix for an executable.
Every format is staged before publication; a failed emission preserves existing
outputs. Static libraries include the hosted runtime unless freestanding;
native consumers use a compatible C++ linker and matching sanitizer runtime when
instrumented. Shared output requires the installed runtime's target.

`mettle-version` is an optional minimum compiler version, not an edition or the
package's own version. The planner checks the root and every selected dependency
before compilation and diagnoses an unavailable compiler version at that field.
Omitting it imposes no additional minimum.

The `.mettle` data grammar has `key: value` fields and `key { ... }` object
blocks. Bare keys begin with an ASCII letter or `_`, followed by ASCII letters,
digits, `_` or `-`; quoted keys allow arbitrary text. Root object braces are
optional; lists use `[ ... ]`, and object values use `{ ... }`. A newline or
comma separates entries; trailing commas are accepted. Values are strings,
signed 64-bit decimal integers, decimal fractional/exponent numbers, booleans,
`none`, lists or objects. Fractional numbers retain their exact spelling until a
schema consumes them. Comments use `//` and nested `/* ... */`; newlines inside
block comments also separate entries. Strings use Mettle's ordinary double-quoted
text escapes, including `\u{hex}` and ASCII `\xHH`. Source must be valid UTF-8;
duplicate decoded keys, raw string control characters, unknown escapes and
malformed values are errors with byte spans. Nesting/source/value-count bounds
use the compiler's existing resource-limit policy. No calls, substitutions,
includes or environment lookup are evaluated.

A dependency string beginning `./`, `../`, or an absolute path denotes a local
package. Other strings must be valid version requirements; there is no
file-existence-based guessing. Additional source/feature options use an object,
for example `parser { path: "../parser", features: ["text"] }`.

Imports discover supporting modules from `name.mt` or `name/main.mt`, relative
to the importing module, without a separate file of `pub module` declarations.
Matching both source forms is an ambiguity error. Intermediate directories can
group modules without their own entry file. Existing explicit module declarations
remain available; visibility and public reexports still control the package API.

Locks contain the root followed by packages in deterministic identity order,
with exact versions, source/commit identities, checksums, features and dependency
IDs. The lock reader rejects unknown fields, duplicate package identities and
references to absent identities. `--locked`, `--offline` and `--frozen` retain
their existing meanings.

Dependency sources are local paths, configured registries, or Git identities.
Git requirements resolve to an immutable commit in the lock, not a moving tag.
Registry packages lock their archive digest; path packages record their resolved
location and content-input identity for builds, without pretending local edits
are immutable published versions.

Version requirements support exact, caret, tilde, wildcard and comma-separated
comparator intersections; arrays denote unions. Ordering follows SemVer;
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

The compiler-provided `core`, `alloc` and `std` tiers share one standard-library
package instance for implementation ownership. Application and dependency
instances remain distinct; tier visibility and layering rules are unchanged.

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

Build records distinguish host and target triples, compiler source/build ID and
version, package compiler requirements, dependency identities, cfg/features, optimization, overflow/
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

`mettle fmt FILE... [--check]` works on the token stream
(`syntax/format.{h,cpp}`) and changes only whitespace. Base formatting has
recorded verification; the expanded wrapping described below remains unverified.
Indentation is 4 spaces per bracket level (a continuation after a comma or
trailing operator, or starting with `.`, gets one more level where applicable);
spacing is
normalized after `,` `;` `:`, around `=`, comparison/compound-assignment/`=>`/`->`/`??`,
inside one-line `{ }` and removed around `.` and inside `()`/`[]`; other
gaps (`<`, `-`, `&`, ...) keep one space or none as written. Trailing whitespace
goes, blank-line runs collapse to one (none after `{` or before `}`), the file
ends in one newline. Expanded line breaking targets 100 bytes and breaks after commas in
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
declarative macros are parsed after expansion for both fingerprints. Prior source-corpus checks preserved run results and fail phases/messages/lines
(columns may move). Expanded wrapping has not been built or tested.
`--check` prints each file
that would change with its first differing line and exits 1 without writing;
otherwise changed files are replaced atomically (temporary file and rename).

`mettle lint FILE|PACKAGE [--format human|json] [--allow|--warn|--deny RULE]... [build options]`
is implemented (`lint_reports_semantic_findings`). It uses the front end of `check`
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
findings are not implemented. JSON emits one object per line on stdout, in human
finding order, with
`code`, `level` (`warn` or `deny`), `span` (`file`, zero-based byte `begin`
and exclusive `end`), and `message`. No suggestion field is emitted because
the current rules do not provide structured suggestions. Front-end failures
remain human diagnostics on stderr; denied findings still return status 1.

Target, profile, feature, package/workspace and lock/offline selections are
shared options. Unknown or unavailable requested capabilities fail explicitly;
partial compiler milestones cannot count unsupported programs as passed tests.

Implemented commands: `check`, `build`, `run`, `test`, `bench`, `fmt`, `clean`,
inspection commands, `lint` and `doc`; their scoped evidence and gaps are
recorded in the relevant sections.

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

Evidence: `test_json_timeout_and_modules`. `@test` marks a function in any
module of the selected package with no
parameters and result `Unit`, or `Outcome<Unit, E>` (returning the failure fails
the test). Inline and file modules (`module name`) are included; displayed
names are fully qualified, such as `network.connect`. `@ignore` /
`@ignore("reason")` skips a test unless `--include-ignored` (run everything) or
`--ignored` (run only ignored tests) is given; `@should_panic` /
`@should_panic("text")` passes only when the test panics (exit status 101) or
aborts with SIGABRT; unrelated signals do not satisfy the panic expectation.
The text, when given, must occur in its captured output.
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

Evidence: package cases `doc_writes_deterministic_html`,
`doctests_run_isolated_examples` and `doc_resolves_dependency_links_and_warns`.

`///` documents the item that follows it (before or between its attributes) and
`//!` the enclosing file or inline module. The lexer already keeps comments as
tokens, so no syntax change is needed; `bootstrap/documentation` reads them from
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
retain their imports and module context without modifying package files.
Harness builds make test-bearing ancestor modules package-visible; ordinary
builds retain their declared visibility. Each
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
input/output; UTF-16 positions). Evidence: `language_server`. It supports full
and ranged text synchronization with
`publishDiagnostics` (each open document is analyzed by the compiler front end
on its in-memory text; editing a document re-analyzes the open documents that
read it; parse errors still produce diagnostics), `hover`, `definition`,
hierarchical `documentSymbol`, `formatting` (the `mettle fmt` layout) and
`prepareRename`/`rename`. Navigation and rename use a token-based index so they
work on incomplete source; source files read through the configured provider
are indexed alongside open documents. Completion offers visible lexical
declarations and keywords, and uses checked receiver types to narrow member
suggestions when available. Signature help tracks the active argument and
indexed declaration parameters. References include uniquely resolved local,
parameter and member occurrences. Checked facts provide inferred expression
hover and inferred named-function result signatures. Checked match-arm and
closure pattern bindings participate in local navigation. Same-file member
references and definitions use checked receiver/callee facts.

Rename refuses ambiguous or unsafe cases (fields, variants, modules, `main`,
reserved words as new names); local and parameter renames stay within their
scope and update `name:` argument labels.
Uniquely resolved qualified cross-file uses participate in references and
rename edits under the same declaration-ambiguity checks.

Known gaps: completion does not prove extension-method applicability or resolve
all incomplete qualified paths; signature help does not substitute generic
arguments or infer callable signatures; overloaded/ambiguous references are
omitted. Member rename remains unavailable for fields, and same-file receiver
facts do not yet disambiguate members across provider-loaded files. Provider
sources are indexed only when encountered by an open document, not through
workspace-wide package discovery. Generated diagnostics map to a user source
span when possible but do not yet expose the full expansion chain as related
information. Source-oriented type display and structured notes/help appear in
published message text (`diagnostic-help-*` cases and `language_server`).

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

I12/T006 evidence: `debug_info` (DWARF) and `debugger_workflow` (batch LLDB,
Release). `mettle build -g`
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
For LLDB, import `tools/debug/mettle_lldb.py` with
`command script import /path/to/mettle/tools/debug/mettle_lldb.py`. It registers
best-effort summaries for native `List`, slices, erased views, `String`, text
views, optionals, outcomes and coroutine states; text reads are capped at 256
bytes. Summaries do not execute program code and report unavailable data rather
than guessing. `tests/packages.py::debugger_workflow` builds a `-g` executable,
imports these summaries into batch LLDB, and checks source breakpoints,
parameters/locals, list and slice lengths, a tagged variant, an erased view and
a suspended coroutine state. It prints a clear skip if LLDB is unavailable.
The comp dir is the root source's directory; without `-g` the adapter emits no
debug metadata. `-g` is explicit (the `debug` profile does not imply it), and
`-g` builds bypass the build cache. On Darwin an executable's DWARF stays in
the temporary object, so the link step runs `dsymutil` to write `OUTPUT.dSYM`
(warning if it is missing); `--emit object` keeps DWARF in the object.
Lexical blocks carry source scopes; named locals start unavailable until
initialized, become unavailable after moves/drops or scope exit, and regain a
location after a whole-place store. Optimizer-generated `inlinedAt` locations
use source subprograms and call-site locations; `@inline`, `@inline(always)`
and `@inline(never)` map to LLVM optimization hints.
Remaining gaps include subprogram parameter/return types, some unsupported
layouts, concrete dynamic types for sized erased values, monomorphization
records and interactive LLDB verification. Windows CodeView/PDB remains open
and is outside this DWARF lane. The `debug_info` case covers basic, coroutine,
scope, move, erasure and release-inlining metadata.

Optional Rust bridges build as separate interoperability packages with explicit
Rust toolchain/ABI adapters. They do not introduce a mandatory rustc dependency
into native Mettle builds.

## 6. Comparison and evidence

The command, package, editor and debugger contracts above are required developer
workflows. Build speed and retained build-cache storage also have measured
release gates in performance.md section 5.1.
Feature resolution, caching and richer debug output affect build cost/artifact
size; no inherent application-speed improvement follows from their spelling.
Implementation acceptance needs resolver fixtures, invalidation tests, compiler/
editor agreement, debugger probes and executable documentation on real targets.

## 7. Storage: two separate products

Build-cache size is an accepted gate (performance.md section 5.1), so storage is
specified for both products, which have different owners and must not be mixed.

### 7.1. Compiler-development storage

Inventory archive/version hashes, worktree/VM consumers, evidence obligations
and offline pins before proposing owner-approved retirement. Directory names
and allocated-block counts alone do not establish artifact identity or physical
savings. Remove only approved resolved paths; verify build selection,
bootstrap and evidence access afterward.

Keep pinned offline archives; other downloads may be removed after checksum
verification and successful extraction. Preserve refusal to overwrite unknown
installations and share toolchains only when identities match. Protect unmerged
source and active builds; retire lane worktrees through owner-approved Git
operations, accounting for shared metadata separately.

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

The build-output store, live leases and `mettle clean` are implemented (section
T003). A separate `mettle storage` report and dependency-source/debug-data pruning
remain deferred; use filesystem reports. Measure
cold/warm retained bytes, peak scratch, rebuild cost and matched runtime behavior
before selecting default budgets or claiming savings.
