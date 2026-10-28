# Mettle contributor and agent rules

Read [CONTRIBUTING.md](CONTRIBUTING.md) and the normative
[code quality standard](docs/code-quality.md) before changing this repository.
These rules apply to compiler, runtime, libraries, tools, tests and documentation.
The [compiler architecture](docs/compiler-architecture.md) owns component
responsibilities and phase contracts; `compiler/modules.json` owns the current
enforced source/dependency graph. Update both with architectural changes.

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
  Reuse the existing runners; no new test framework, custom testing DSL or
  directory/layout assertions without a concrete functional need.
- Run `python3 tools/check_quality.py`; for code changes also run its
  `--build-dir` gate and the applicable checks in the standard's validation matrix.
- Unsafe/memory changes require documented invariants and sanitizer evidence.
  Exceptions to a check require narrow scope, rationale and recorded follow-up.
- Keep changes surgical, preserve other people's work, and do not claim a
  milestone, target, safety property or speedup without current evidence.
- Do not publish, choose a license, initialize/amend/commit Git history or
  configure paid services without the owner's explicit request.
