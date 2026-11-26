# Mettle contributor and agent rules

At session start and after every context reset, read `AGENTS.md` before editing.
Other documents and summaries are not substitutes. Reuse that read until this
file changes.

## ANY CODE WRITTEN SHOULD BE BEST-IN-CLASS

## Tautological abstractions, tests, compiler passes, language features, and wrappers are considered harmful. Every addition must introduce meaningful functionality, enforce an invariant, improve correctness, or reduce complexity. Otherwise, avoid it.

## No type of bloat is allowed be it Tests / Docs / Code / Code Comments. If you know its a bloat and is not needed, cut that immediately

## Whenever working on task if you know you dont need any checklist verification for that then absolutely dont do that. If you changes affects one system run targeted checks only. No Broad builds/ checks should be ran. If you know a thing is going to waste time, immediately stop it, and work in most efficient & fastest way without compromising quality of project.

## Code Comments are not allowed 

## ALWAYS RUN TESTS / BUILDS IN THE MOST EFFICIENT WAY: size the work first (item count x per-item time / cores), use incremental builds and caches, parallelize across cores (`xargs -P`, `--jobs`, `ctest -j`), report results incrementally, and narrow to the affected set. Never run a serial loop over many builds.

## NEVER DO ANYTHING THAT WASTES TIME. Always prefer the fastest and most efficient approach while keeping the highest quality.

## NEVER SKIP A KNOWN ISSUE OR BUG. If you see a failing test, wrong diagnostic, crash or defect in code, whether or not your change caused it, fix it properly (root cause, no workaround) in the same task. Do not note it and move on, do not label it "pre-existing" or "unrelated" as a reason to leave it. If it truly cannot be fixed in the task, say so explicitly with the root cause and what blocks it, and get the owner's decision; never leave it silently.

## COMPILER OR LANGUAGE FIX FIRST. When the language or compiler cannot express what a correct library, API or test needs (a rejected construct, a missing capability, a wrong diagnostic), fix the compiler or language properly instead of working around it in library code, names or tests. Use a workaround only with the owner's explicit approval, and record why. This applies even before I15 when the defect blocks a correct design (C++ compiler change limits above still require a correctness or soundness justification).

## NEVER INTRODUCE CEREMONY. No process, checklist, test, wrapper, ledger entry, progress log, receipt or step that exists only to be performed, recorded or satisfied, rather than to catch a defect or enforce an invariant. Do not maintain bookkeeping documents or external API inventories. Keep reproducible build inputs, behavioral tests and useful diagnostic output. If something already exists that only adds ceremony or wastes time, remove it instead of working around it.

## SPEED TARGET: Rust parity. Anything Mettle does (compile, check, library build, tests, tools, runtime) should be as fast as the equivalent in Rust, or faster. Measure against Rust before accepting a time as normal, and treat a slower result as a defect to fix at its root cause.

## NEVER OVER EXPAND ANY TASK MORE THAN WHATS NEEDED and what was the task

## If I asked something to be done, DONOT STOP AFTER ACKNOWLEDGING, OR DOING HALF WORK FROM ABOVE WITHOUT DOING FULL TASK WHAT I ASKED. If you know its not done then dont stop without completing that task properly. Below Rules are AI generated, if some rule wastes time for a task which can skip some rules below then skip it. 

Read [CONTRIBUTING.md](CONTRIBUTING.md) and the normative
[code quality standard](docs/process/code-quality.md) before changing this repository.
These rules apply to compiler, runtime, libraries, tools, tests and documentation.
The [compiler architecture](docs/process/compiler-architecture.md) owns component
responsibilities and phase contracts; CMake owns the current component targets
and dependencies. Update both with architectural changes.

- Preserve the selected language contracts; unsupported is not invalid.
- Keep LLVM types/includes out of source, syntax, semantics and compiler-owned IR.
  The driver and LLVM adapter are the compiler's LLVM integration boundary.
- Use the pinned tools, C++20 and repository formatting. No unapproved toolchain
  upgrade, dependency, language feature, public ABI or license decision.
- Own resources with RAII; preserve source spans and explicit error phases.
  Never publish code recovered from an invalid tree or an unchecked IR.
- Never introduce limits, thresholds, budgets or other restrictions in code,
  tooling, tests, benchmarks, process or release gates unless they follow
  established practice, with documented precedent and a concrete correctness,
  safety, representation or resource justification. Do not invent numerical
  acceptance thresholds or promote agent-selected policies into project
  requirements. If a restriction is nonstandard, stricter than established
  practice or lacks verified precedent, obtain an explicit owner decision
  before implementing it.
- Keep library layers `core -> no allocator/OS`, `alloc -> core`,
  `std -> alloc/core`; executor selection stays optional.
- Add focused behavioral regression tests for changed behavior. Do not weaken
  assertions, ownership rules, overflow policy or fixtures to make a test pass.
- Follow established compiler testing practice: source compile/run pass/fail
  cases, focused algorithm unit tests, and applicable codegen/link/ABI probes.
  Reuse the existing runners; no new test framework or custom testing DSL.
- Never add tests for file or directory inventories, repository layout, CMake
  wiring, checker existence/removal or policy wording. Do not replace a removed
  check with a test of the same bookkeeping. Removing checks alone does not
  justify a build, CTest run or qualification matrix; require a concrete
  behavioral regression or affected executable contract before testing.
- For code changes, build, run CTest and the applicable checks in the
  standard's validation matrix; format C++ with the pinned `clang-format`.
- Unsafe/memory changes require documented invariants and sanitizer evidence.
  Exceptions to a check require narrow scope, rationale and recorded follow-up.
- Until substantive self-hosting, change the C++ compiler only for V1-required
  features, correctness/soundness fixes or measured performance work; no
  C++-only refactors or polish.
- Keep changes surgical, preserve other people's work, and do not claim a
  milestone, target, safety property or speedup without current evidence.
- Always provide a best-effort ETA when asked, stating assumptions and
  uncertainty; never respond that you have no ETA. Cover the whole requested
  scope, including integration, validation and commit/push; explicitly label
  estimates that cover only a sub-batch.
- At the end of every task that changes repository files, commit and push the
  task's validated changes to the current branch unless the owner asks otherwise.
  For long tasks, also commit and push each coherent validated batch rather than
  accumulating unfinished changes until milestone closure. Exclude unrelated
  changes and report any commit or push failure. An owner-requested WIP checkpoint
  must identify known failures and unrun checks without promoting acceptance.
- Do not publish, choose a license, initialize/amend Git history or
  configure paid services without the owner's explicit request.

## Implementation and validation

- Read the affected specifications before compiler changes. Plan AST, type, IR,
  ownership, runtime and backend interfaces together before changing shared
  headers; batch dependent implementations with one source writer.
- Check the current revision and worktree before editing. Preserve other work
  and finish an active integration batch before opening dependent work.
- Use incremental checks and focused behavioral regressions. Reuse passing
  results while their inputs, tools and configuration are unchanged.
- Trace a failure's root cause before another speculative fix. Never weaken
  assertions, ownership rules or timeouts to manufacture a passing result.
- Run release qualification only after implementation, fixtures and
  documentation are ready. Source changes invalidate affected results, not
  every unrelated passing check. Do not compete heavy builds with timed runs.
- Obtain owner approval for genuine scope expansion. Distinguish implemented,
  verified and unsupported behavior without maintaining separate status ledgers.
