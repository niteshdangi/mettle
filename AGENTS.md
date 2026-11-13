# Mettle contributor and agent rules

## ANY CODE WRITTEN SHOULD BE BEST-IN-CLASS

## Tautological abstractions, tests, compiler passes, language features, and wrappers are considered harmful. Every addition must introduce meaningful functionality, enforce an invariant, improve correctness, or reduce complexity. Otherwise, avoid it.

## No type of bloat is allowed be it Tests / Docs / Code / Code Comments. If you know its a bloat and is not needed, cut that immediately

## Whenever working on task if you know you dont need any checklist verification for that then absolutely dont do that. If you changes affects one system run targeted checks only. No Broad builds/ checks should be ran. If you know a thing is going to waste time, immediately stop it, and work in most efficient & fastest way without compromising quality of project.

## Comments in internal code should never be written to explain some code, code should be self understandable, comments only allowed for non-obvious things, that too in max 1 line rarely 2 lines for complex non-obvious things.

## ALWAYS RUN TESTS / BUILDS IN THE MOST EFFICIENT WAY: size the work first (item count x per-item time / cores), use incremental builds and caches, parallelize across cores (`xargs -P`, `--jobs`, `ctest -j`), report results incrementally, and narrow to the affected set. Never run a serial loop over many builds.

## NEVER DO ANYTHING THAT WASTES TIME. Always prefer the fastest and most efficient approach while keeping the highest quality.

## NEVER SKIP A KNOWN ISSUE OR BUG. If you see a failing test, wrong diagnostic, crash or defect in code, whether or not your change caused it, fix it properly (root cause, no workaround) in the same task. Do not note it and move on, do not label it "pre-existing" or "unrelated" as a reason to leave it. If it truly cannot be fixed in the task, say so explicitly with the root cause and what blocks it, and get the owner's decision; never leave it silently.

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
- Do not impose arbitrary restrictive limits. New or tightened limits must follow
  established systems-language/compiler practice, with documented precedent and
  a concrete safety, representation or resource constraint; stricter limits
  require explicit owner approval.
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
- Until I15, change the C++ compiler only for V1-required features,
  correctness/soundness fixes or a measured I14 gate; no C++-only tuning,
  refactors or polish (see implementation-plan section 8).
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

## Milestone execution gates

These gates govern implementation order and validation timing; they do not
weaken the quality standard or authorize dropping a selected contract.

1. Before compiler edits, read the owning milestone and specifications and
   reconcile its acceptance inventory with the existing task ledger. Record each
   requirement's implementation state (missing, partial or implemented),
   verification scope/revision, remaining work, owning files, required fixtures
   and documentation. Do not equate implemented with verified. For I06, start
   with the inventory in `docs/process/implementation-plan.md` section 8.3.
2. Plan AST, type, IR, ownership, runtime and backend interfaces together before
   changing shared headers. Batch their dependent implementations coherently.
   Keep one source writer for shared compiler interfaces; independent work must
   not produce competing headers, objects or source revisions.
3. During implementation, use incremental compile checks, fast hygiene checks
   and focused new/failing regressions. Before each rerun, name the changed
   dependency and the failure or acceptance case it addresses. Reuse passing
   results only while their relevant inputs, tools and configuration are
   unchanged; do not rerun broad passing groups after unrelated local edits.
4. After two failed fixes for the same issue, stop speculative edit/test cycles.
   Trace and record the root cause and why the next change addresses it before
   another attempt. This is a diagnosis trigger, not permission to abort a
   healthy test run, weaken assertions or change timeouts.
5. Do not start a full qualification matrix while known implementation gaps,
   missing acceptance fixtures or incomplete documentation remain. The ledger's
   source-freeze task must depend on all of them and be complete first.
   Finalize documentation, freeze input identities, then run one consolidated
   applicable quality/sanitizer/reproducibility/target sequence. Do not compete
   heavy builds with timed source execution.
6. If a failure requires further source changes, reopen the affected source
   tasks and freeze gate, record which results are invalidated, and rerun the
   affected checks before qualification resumes. Do not repeat an entire matrix
   by ritual, or reuse stale passing receipts as current evidence.
7. Classify newly discovered work against the existing scope. Add evidence and
   dependencies for an existing obligation; obtain owner approval for a genuine
   expansion. Do not silently add an I13 full-operation/all-profile closure
   obligation to an earlier milestone, or silently defer an earlier obligation.
   Report unresolved scope as a blocker, not approval.
8. A completed sub-batch is not a completed milestone. Report missing
   implementation, implemented-but-unverified work, verified scope and concrete
   blockers separately. Mark the milestone done only after its complete gates
   pass. Do not claim an imminent finish, speedup or ETA without evidence.
9. Keep one active integration batch by default. Parallelize only
   dependency-independent work within a shared CPU/memory budget. Resolve shared
   compiler dependencies with the smallest representative end-to-end acceptance
   case before expanding dependent source work; that case is not full acceptance.
10. Finish already-started work before opening new batches. An instruction to
    finish current work covers all in-progress batches unless the owner explicitly
    narrows the scope. If blocked, advance independent existing work or report the
    blocker; do not pile up more work behind the same unresolved dependency.
11. During long-running work, provide status updates at least every 30 minutes
    while execution is active: completed scope, remaining scope, current blocker
    and next action. Use consistent acceptance units; file counts or implemented
    source are not counts of qualified contracts.

At session start and after a context reset, read the owning milestone's existing
handoff and task ledger, check the current revision and worktree, and resume the
recorded next action unless new evidence invalidates it. Do not restart discovery
or passing checks by default. Keep the existing handoff, repository inventory and
task ledger synchronized at phase changes: revision, remaining work, blockers,
reusable evidence/input identities and the exact next command or action. Do not
create a parallel planning document or record every routine tool call.

These are execution rules, not an automated tool lock; checking the gate before a
long command remains the executing agent's duty.
