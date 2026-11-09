# Compiler and library code quality standard

Status: normative repository standard, adopted before I03. It governs new work
and code touched by a change. It does not declare future libraries implemented
or convert test/sanitizer results into a safety proof.

## 1. Non-negotiable priorities

Correct semantics and memory safety precede performance; understandable,
maintainable code precedes cleverness. Prefer the smallest implementation that
fully preserves the contract. Do not introduce abstractions, dependencies,
configuration or speculative optimizations without a concrete need.

Fix bugs caused by a change and their directly coupled call sites. Do not mix
unrelated cleanup into a feature/fix. Existing debt is not permission for new
debt; substantial unrelated debt gets separately recorded work.
Do not impose arbitrary file-length or coverage-percentage targets as a proxy
for correctness.

## 2. Compiler boundaries and invariants

The direction is source/tokens/syntax, resolution/types, compiler-owned CFG and
cleanup, runtime/ABI lowering, then the backend adapter. Each stage consumes
explicitly valid input and preserves source identity/spans needed downstream.
The [architecture contract](compiler-architecture.md) owns the full component
design. CMake declares each current component target and its link dependencies,
discovering sources in the component directory. Source-level boundaries are
review obligations; CMake dependencies alone do not prove include isolation.

- Source, syntax, semantics and compiler-owned IR must not include LLVM or
  backend headers. The driver orchestrates; it does not define typing/ownership.
- LLVM types, aliases and optimization metadata are not the language type system.
  LLVM lowering cannot repair missing language semantics.
- Specify each IR operation's types, effects, initialization and control-flow
  requirements. Validate before emitting executable code; validate LLVM before
  and after optimization.
- Every reachable block must have a valid terminator. Joins must preserve
  initialization, mutability, loans and cleanup obligations as those exist.
- Preserve evaluation order, short-circuiting, tail/discard status and profile
  arithmetic rules. Never introduce overflow poison, hidden clone/retain,
  ownership upgrades or unchecked aliasing assumptions.
- Keep language behavior independent of host integer width, host SDK behavior
  and later generic specialization.
- Recovered/incomplete trees are inspectable data, not runnable programs.
  Compiler resource limits are explicit diagnostics, not silent truncation, and
  follow one policy (`bootstrap/support/limits.h`): depth limits (parser,
  syntax, type nesting) protect the native stack and stay small and fixed;
  count limits (functions, products, locals, CFG blocks, witness slots, source
  and token bytes) are set at 2^22..2^30 so only pathological input reaches
  them and every algorithm behind them must stay near-linear; object sizes are
  bounded by the signed pointer range. Arrays of more than 64 elements (1024
  expanded elements when nested) of non-droppable elements are compact: one
  place with an element type and a length, so only the target address-space
  check (`error[limit]`, "array size exceeds target address space") bounds
  them. Arrays of droppable elements keep one cleanup place per element and
  are capped at 2^16 total elements (`TypeStore::droppableArrayElements`,
  `error[limit]`); this is an implementation limit, not a language rule.
  A specialization type argument longer than 1 MiB when spelled
  (`limits::typeNameBytes`) is reported as `error[limit]`, so polymorphic
  recursion that doubles a type each level stops before the nesting limit's
  exponential cost; this is also an implementation limit.
  At most 100 diagnostics are printed, followed by an
  "N additional diagnostics suppressed" summary.
- Parsed AST nodes carry syntax, not inference variables or resolved slots.
  Checking owns separate read-only facts; CFG owns no syntax pointers.
- Backend emission accepts only the pipeline's verified program. Structural
  CFG verification precedes dataflow; initialization/ownership analysis must
  not be folded into AST lowering or an IR printer.

## 3. C++ implementation style and ownership

Use C++20 and the pinned Clang. `.clang-format` selects LLVM-based formatting,
two-space indentation, spaces rather than tabs, and an 80-column C++ target.
Types/enumerators use UpperCamelCase; functions, locals and members use
lowerCamelCase; macros use UPPER_SNAKE_CASE. Filenames use lowercase/snake_case.
Keep existing domain abbreviations when clear.

Headers are self-contained and use `#pragma once`; include the dependencies
required by their interfaces. Avoid global `using namespace`, unnecessary
inheritance, implicit conversions and broad preprocessor conditionals.
Prefer explicit types at API/boundary points and `auto` when the type is evident.

Use values and RAII. Owning dynamic objects use appropriate standard ownership
types, normally `std::unique_ptr`; raw pointers/references are non-owning unless
an external API explicitly transfers ownership. Do not use shared ownership to
avoid deciding who owns an object. Document non-obvious lifetime/invalidation
contracts and checked index/representation conversions.

Expected source failures use structured diagnostics; the LLVM boundary uses its
error API. Small, local parser-recovery exceptions are permitted. Do not swallow
errors, catch-and-continue after an invariant failure, or assert on ordinary
invalid user input. An internal invariant failure must not become a successful
compilation. Preserve preexisting output on a failed build.

Comments explain invariants, safety, trade-offs or surprising behavior, not a
translation of the adjacent statement. Prefer clear names and cohesive helpers.
A switch implementing one AST/IR operation is not split into trivial helpers
merely to satisfy a line-count rule.

## 4. Mettle library and runtime rules

Mettle uses four-space indentation. Type/interface names use UpperCamelCase;
functions, modules and bindings use snake_case; constants use UPPER_SNAKE_CASE.
Fixed primitive spellings such as `i32` and `bool` are unchanged.
Use approved syntax: `: Type` or result inference, `Unit` as a type, `()` as its
value, `Never` for uninhabited results, and explicit intentional discards.
Prefer explicit result annotations for public APIs; do not make them mandatory
where the language permits inference.

`core` requires no allocator, OS or executor. `alloc` depends on `core` and an
explicit allocator; `std` adds hosted services. The optional async runtime is
not imported implicitly. Library dependency enforcement must be added alongside
the module/library implementations; it is currently a design/review obligation,
not a completed automated module-graph check or a Mettle formatter.

Public operations specify ownership/access, returned-view sources, effects,
allocation/retention, failure, panic/cancellation, invalidation and complexity.
Compatibility includes Copy eligibility and default parameter access.
Do not promise a stable native ABI, layout, iteration order or target property
unless its owning contract and evidence establish it.

Follow [library contracts](library-and-abi.md), the
[native operation translation](library-surface.md), and the
[memory model](memory-and-concurrency.md). Native code must not silently erase
the selected operation contract or depend on the reference implementation/toolchain.

## 5. Unsafe, memory and concurrency

Keep unsafe operations and platform intrinsics in the smallest reviewable
boundary with a safe interface where sound. State the reason for unsafety and
the required provenance, extent, alignment, initialization, lifetime, aliasing,
threading and cleanup invariants. Explain which checks establish them.

Test partial initialization, failure/unwind/cancellation, repeated cleanup,
zero-size/alignment cases and invalid external representations as applicable.
Atomics need a documented ordering/happens-before argument; volatile is not
synchronization. FFI needs ABI/layout and ownership/destruction probes.
Do not add `noalias`, `nsw`/`nuw`, unreachable assumptions or equivalent shortcuts
from an informal ownership description.

ASan/UBSan compiler runs are required for new memory/unsafe work and before
ownership-milestone closure. They instrument project C++ code, not the prebuilt
LLVM libraries or automatically every emitted Mettle program. The driver now
has opt-in `--sanitize address|thread` instrumentation for emitted Mettle
programs, verified on macOS arm64 by `probe.sanitizers`.
The emitted-IR backend does not yet provide UBSan instrumentation:
`--sanitize undefined` is rejected rather than promising checks that are not
emitted. ThreadSanitizer, race/model checks and target-specific probes are
required when concurrency is implemented. A passing sanitizer cannot prove the
language memory model sound.
Sanitizer reports use exit status 99 in the selected scripts so compiler-negative
tests expecting ordinary exit status 1 cannot count a report as a passing case.
Sanitizer startup must pass before analysis/test execution; a failed startup is
a failed sanitizer gate, never an exemption or evidence of memory safety.

`tests/backend/memory.py` checks the emitted atomic code with the pinned TSan
runtime. It first requires a clean startup and an actual intentional-race report
with exit status 99. A test-only copy of emitted LLVM receives `sanitize_thread`
function attributes and is instrumented at `-O1`; original IR and source hashes
are retained. Independent C++ thread cases exercise release/acquire publication,
acquiring failed CAS and a sequential-consistency store-buffering litmus, with
an enumerated SC model excluding the forbidden outcome. This is not a complete
memory-model proof or blanket TSan coverage of the compiler, libraries or
uninstrumented emitted programs. Native thread implementation still requires
its own race/failure validation when it lands.

Historical I06 ASan/UBSan requalification found and repaired an erased-type-store
reference invalidated by interning in `checkInterfaceContracts`;
`generic-iteration-through-family-bounded-protocols` guards that failure.
The 26-suite run, 15,000 mutation runs and emitted threaded checks are historical
macOS evidence, not current qualification. Retired `mutex_poison.mt` recovery
checks now reside in `tests/std/i13-sync-mutex-rwlock.mt`.

LLVM 21.1.8 ASan stalled before `main` on macOS 27.0.1 during dyld/malloc
initialization. The matching
[upstream fix](https://github.com/llvm/llvm-project/pull/182943) was
[backported to LLVM 22](https://github.com/llvm/llvm-project/pull/188913).
LLVM/Clang/compiler-rt are now pinned together to 22.1.3, which includes that
backport; CMake/Ninja and language contracts are unchanged.
The historical compatibility gate passed nine suites, including actual ASan
heap-overflow and UBSan signed-overflow detector reports with exit status 99.
`abort_on_error=0` selects that exit behavior on Darwin; `halt_on_error=1` and
nonrecovering instrumentation remain enabled. The 15-second startup guard and
ordinary negative-test expectations remain unchanged.
Clean-build/tool/runtime hashes and logs are recorded by `tools/build.py`.
Do not silently substitute host runtimes, disable ASan, inject a private dyld
shim, or change toolchain pins without an explicit compatibility decision.

## 6. Diagnostics and behavioral tests

Use the existing compiler fixture runners and the test categories below.
Each regression must exercise an observable native contract, with acceptance,
rejection or execution expectations appropriate to the changed behavior.
Do not introduce a bespoke framework or mirror another project's suite layout.

The categories below describe test intent; they do not prescribe new directories,
frameworks, fixture DSLs or empty suites.

| Test intent | Appropriate check |
| --- | --- |
| Compile pass/fail | Small source cases accept or reject for the intended language reason, not an unrelated parse/type failure |
| Run pass/fail | Compile/link/execute and check defined results, traps, side effects or cleanup |
| Diagnostics/UI | Check the relevant failure and span; use reviewed normalized output expectations when presentation itself is the feature |
| Compiler algorithm unit tests | Directly exercise meaningful invariants such as type constraints, CFG validity and dataflow |
| Codegen/IR and link/ABI integration | Check transformation/representation/calling behavior when that capability exists; avoid incidental register, block or symbol numbering |
| Library unit/integration/doctests | Check real public contracts and executable examples as the libraries/documentation tooling are implemented |

Build/style checks, sanitizer runs and performance experiments are separate
validation categories. Do not count a formatting or module-policy check as
language/compiler semantic coverage. Infrastructure unit tests are limited to
meaningful behavior of code we actually maintain, such as rejecting a dependency
cycle or a private-header import; do not generate tests for every helper or rule.

Diagnostics identify phase, source location and actionable cause. Distinguish
malformed source, name/type/ownership failures, unsupported features, resource
limits, I/O/link failures and compiler defects. A valid but unimplemented
construct is not an invalid V1 feature.

Each behavioral change or bug fix needs a focused regression: acceptance and
native execution where appropriate, rejection at the intended phase, and the
edge case that caused the problem. An ownership rejection does not pass merely
because parsing failed. Tests compare behavior, diagnostics and artifact effects,
not constants/getters, incidental formatting or source line counts.

Use existing CTest/Python fixture infrastructure. Keep pure checks deterministic;
control seeds and record inputs for randomized/model tests. Do not add a test
framework to avoid a simple fixture. Tests must not require installed Rust for
ordinary Mettle development; Rust remains an optional comparator/interop tool.
Source cases are one file each in `tests/source/run` (accepted programs, executed per
profile) and `tests/source/fail` (rejected programs); leading `// key: value` lines configure
the expected exit status, profiles, flags, timeout and diagnostics (`tests/source.py` documents
them). The runner executes cases in parallel (`-j`, default every core), so `source.run` and
`source.fail` reserve that many CTest processors; a case timeout bounds each command, and
`--timeout-scale` stretches it on slow or loaded hosts without editing cases. Case names are
file names, hence unique. `tests/probes.py` keeps the checks that are not plain programs
(token/syntax inspection, LLVM fast-math flags).
Negative cases (source and multi-file module) require the intended message, phase and
exact line and column on one diagnostic, not merely somewhere in the output. Hosted panic expectations
require SIGABRT, not an arbitrary fatal signal.
Do not weaken assertions, timeouts, overflow, cleanup or ownership rules to
manufacture passing results.

Keep cases minimal and name them after their behavior or regression. Explain
non-obvious failure mechanisms and target restrictions. Reuse an existing case
or runner instead of duplicating a test at every layer. Add a new suite only
when an implemented capability needs a distinct execution mechanism.
No tests merely freezing folder/file names, a directory tree, file lengths,
class organization, trivial accessors or standard-library behavior. No coverage
quota, automatic test-per-function policy, generic "architecture compliance"
framework or test added just to validate the wording of this standard.

## 7. Required validation by change

| Change | Required evidence |
| --- | --- |
| Every change | Pinned formatting; affected CMake component build |
| Compiler/runtime C++ | Incremental build and applicable CTest fixtures |
| Memory/unsafe/ownership | Above plus ASan/UBSan build and relevant boundary/cleanup regressions |
| Language behavior or IR/backend | Debug/Release source-profile checks; Linux source execution when target behavior/lowering is affected |
| Library/API | Applicable access/failure/invalidation/complexity cases, native contract mapping and layer restrictions; target/ABI cases when relevant |
| Milestone/release closure | Clean reproducible builds, current source/tool/sysroot/artifact identities and the owning milestone's complete target gates |
| Performance | Equivalent contracts/datasets and the registered performance protocol; separate compiler time/memory from program runtime |

Build, sanitizer, reproducibility and target checks are different evidence
scopes; none substitutes for another.

## 8. Dependencies, suppressions and review

Prefer the standard library and existing pinned dependencies. New dependencies
need a concrete purpose, compatible layering/license, exact version/content
identity, supported platforms and a justified cost. Do not auto-upgrade tools,
add network access to ordinary checks, or edit generated baseline reference
signatures/provenance to conceal a native mapping problem.

New project warnings are errors. Static analysis uses the committed safety
check set, not every available style opinion. System/vendor code is outside the
owned-source diagnostic scope. Suppressions must be narrow, justified adjacent
to the invariant, and reviewed; global disables or weakening the check set need
an explicit recorded decision. Temporary exceptions identify an owner/reason
and exit condition. Do not silently grandfather a new failure.

Review semantics, failure/cleanup, complexity, portability and tests before
cosmetics. No feature or public contract is complete because code exists or
metadata lists it. Report missing/unqualified work honestly.
The [performance protocol](performance.md) controls speed claims; early P01
results are not runtime-parity evidence. Publication, licensing and paid
infrastructure remain separate owner decisions.
