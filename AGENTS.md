# Mettle contributor and agent rules

Read [CONTRIBUTING.md](CONTRIBUTING.md) and the normative
[code quality standard](docs/code-quality.md) before changing this repository.
These rules apply to compiler, runtime, libraries, tools, tests and documentation.
The [compiler architecture](docs/compiler-architecture.md) owns component
responsibilities and phase contracts; CMake owns the current component targets
and dependencies. Update both with architectural changes.

- Preserve the selected language contracts; unsupported is not invalid.
- Keep LLVM types/includes out of source, syntax, semantics and compiler-owned IR.
  The driver and LLVM adapter are the compiler's LLVM integration boundary.
- Use the pinned tools, C++20 and repository formatting. No unapproved toolchain
  upgrade, dependency, language feature, public ABI or license decision.
- Own resources with RAII; preserve source spans and explicit error phases.
  Never publish code recovered from an invalid tree or an unchecked IR.
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
- Do not publish, choose a license, initialize/amend/commit Git history or
  configure paid services without the owner's explicit request.

## Milestone execution gates

These gates govern implementation order and validation timing; they do not
weaken the quality standard or authorize dropping a selected contract.

1. Before compiler edits, read the owning milestone and specifications and
   reconcile its acceptance inventory with the existing task ledger. Record each
   requirement's implementation state (missing, partial or implemented),
   verification scope/revision, remaining work, owning files, required fixtures
   and documentation. Do not equate implemented with verified. For I06, start
   with the inventory in `docs/implementation-plan.md` section 8.3.
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

Keep the repository inventory and task ledger synchronized at phase changes and
after a context reset. These are execution rules, not an automated tool lock;
checking the gate before a long command remains the executing agent's duty.
