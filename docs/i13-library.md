# I13 library work package

Repo: /Users/niteshkumar/Projects/mettle-lang, main at `940637d`. I01-I12 are
closed for the macOS ARM64 host and Darwin ARM64 target only. You own I13's
library work and the compiler changes it needs, except pinned owners (S003),
erased async methods (L048/L053) and the language/ABI/target probe rows, which
the orchestrator handles.

## Read first
- AGENTS.md, CONTRIBUTING.md, docs/code-quality.md
- docs/library-surface.md: sections 1-3, 6.1 (the V1 subset), 9 (Mettle names)
  and 10-13
- docs/implementation-plan.md, the I13 paragraphs (~line 1390)
- docs/capability-coverage.md

## Goal (definition of done)
Every operation in the V1 subset (docs/library-surface.md section 6.1, roughly
2,900 operation families plus 1,760 trait/type pairs) has both of these:
1. **A compiled native declaration** in library/{core,alloc,std}, using Mettle
   names from section 9 (List/Map/Set/SortedMap, OwnedIterable,
   BidirectionalIterator, Reader/Writer, `T?`, `(T throws E)`, ...).
2. **Behavioral evidence:** a passing test that calls the operation and checks
   its result, including its panic/failure, boundary and drop-count cases where
   it has them. Integer, float and atomic families must be checked at every
   width, but each family is still one row.

Gate only on macOS ARM64/Darwin; Linux and Windows are excluded by the owner.
Record an operation that does not apply to this target as not-applicable,
never as passed.

## Deliverables
1. **`tools/v1_operations.py`:** a small generator that applies the section 6.1
   rule to `docs/baseline/operations.jsonl.gz` and writes
   `docs/baseline/v1-operations.csv`.
   - Input records are JSON lines with `canonical_id`, `contract` (Rust doc
     URL), `context`, `deprecated`, `availability`, ...
   - Output columns: canonical_id, family, Rust contract, Mettle path, status
     (missing/declared/evidenced/not-applicable/blocked) and evidence test.
   - Status and evidence must survive regeneration.
   - No hashing, receipts or gates.
2. **Library code** that closes the missing rows.
3. **Tests:**
   - Language-level cases: `tests/source/run/i13-<area>-*.mt`; rejection cases
     go in `tests/source/fail/`.
   - Hosted programs: `tests/std/*.mt`, using the directives in `tests/std.py`.
   - Extend existing i13-* files where it fits naturally; never duplicate cases.
4. **I13 status update** in docs/capability-coverage.md and
   docs/implementation-plan.md, using the counts from the CSV. Claim nothing
   for the milestone until every row is evidenced or not-applicable.

## Known gaps to fix first
After fixing each one, restore the test that was weakened to work around it.
- SplitWhitespace over an owned String lacks next_back. `string_text.mt:54` was
  weakened to use next.
- Text split_whitespace and encode_utf16 lack next_back.
- char.encode_utf16 is missing the form that writes into a `mut` buffer slice.
- trim_matches, trim_start_matches and trim_end_matches don't accept closure
  patterns.
- char.is_ascii_whitespace is missing.
- List.retain takes `fn`, not `mut fn`, so stateful predicates are rejected.
  `i13_slice_collections` works around this with a keep field.
- by_ref().take_n consumes the view. The iter-followup test was rewritten.
- `heap Text` has no constructor (Rust `Box<str>` from `&str`/`String`).
- The filter+map drop-count case was replaced by filter_map in
  iterator_adapter_drop_count.

After these, work through the subset area by area, in this order:
1. collections, entries and drain;
2. iterator adapters;
3. text and char;
4. owners and cells;
5. sync, atomics and mpsc;
6. hosted fs, io, process, net, env, time and thread;
7. macros;
8. mem and ptr functions.

## Compiler changes
You may change the compiler (compiler/**, runtime C++) when a V1 operation needs
it. Follow the C++ compiler scope in docs/implementation-plan.md section 8:
V1-required features and correctness/soundness fixes only, no C++-only tuning
or refactors. Keep the module boundaries in compiler/modules.json, format with
the pinned clang-format, and add a focused source run/fail regression for each
compiler fix. Never weaken an API or a test to avoid a compiler fix.

Compiler work also in your scope:
- **Integer literals don't infer `usize` from a library Index impl:** `list[0]`
  on List/VecDeque defaults to `i32` and finds no `Index<i32>`; built-in slices
  already infer `usize`. The argument type comes from `inference.value(right)` in
  `Checker::operatorCall` (compiler/semantics/operators.cpp); an unresolved
  integer-literal variable should take the index type of the receiver's sole
  integer Index implementation. Then drop the `0usize` suffixes in
  tests/source/run/i13-text-whitespace-splits-boundaries.mt (~lines 352-415).
- **Sanitized hosted-std compile time:** 37 s against a 30 s probe bound
  (Release is 2.7 s). Diagnose before changing anything.

## Owner rules
- **Mettle must not look like Rust.** Use Mettle names and syntax (section 9),
  and never add a second compatibility copy of a type.
- **No bloat:** no extra frameworks, DSLs, receipts or documentation padding.
- **No test-weakening:** never raise test timeouts, weaken assertions or delete
  failing cases to make a test pass.
- **Diagnose, don't guess.** After two failed fixes for the same issue, stop
  and write down the root cause before trying again.
- **Subagents:** only model gpt-6-luna.
- **Git:**
  - Never touch the untracked `.vscode/`.
  - Work on branch `lib/i13` in a worktree:
    `git worktree add ../mettle-wt/lib-i13 -b lib/i13 main`
  - Commit small, coherent batches with the trailer
    `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.
  - The owner merges.

## Commands
Run from the worktree root, after configuring your own build directory once
with `python3 tools/build.py --configuration Release`.

- **Build:**
  `.tools/macos-arm64/cmake/CMake.app/Contents/bin/cmake --build build/macos-arm64/Release --parallel 10`
- **Source suites:**
  `python3 tests/source.py run build/macos-arm64/Release/mettle /tmp/libout`
  and the same command with `fail` instead of `run`.
- **Std programs:**
  `python3 tests/std.py build/macos-arm64/Release/mettle /tmp/stdout tests/std`
- **Full suite:**
  `.tools/macos-arm64/cmake/CMake.app/Contents/bin/ctest --test-dir build/macos-arm64/Release -j6`
  (about 7 minutes)
- **Sanitizers:** for memory or unsafe changes, compile the program with
  `--sanitize address`. For threads and sync, use `--sanitize thread`.
  `--sanitize undefined` is rejected by design.

Run focused tests while iterating. Run the full suites once per batch, before
committing.
