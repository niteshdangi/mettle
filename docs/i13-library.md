# I13 library work package

Gated profile: `linux-x64` (see [implementation-plan.md](implementation-plan.md)
section 8.0). The 18 library areas are L003, L005, L009, S005-S014, S019-S021 and
S024-S025. Per-operation status lives in the generated ledger
([v1-operations.csv](baseline/v1-operations.csv)); this document holds only the
definition of done and the working rules.

## Definition of done

Every operation in the V1 subset ([library-surface.md](library-surface.md)
section 6.1) has both:

1. **A compiled native declaration** in `library/{core,alloc,std}` using the
   Mettle names of library-surface section 9 (`List`, `Map`, `Set`, `SortedMap`,
   `OwnedIterable`, `BidirectionalIterator`, `Reader`/`Writer`, `T?`,
   `Outcome<T, E>`, ...).
2. **Behavioral evidence:** a passing test that calls the operation and checks its
   result, including panic/failure, boundary and drop-count cases where they
   exist. Integer, float and atomic families are checked at every width but
   remain one row each.

Operations that do not apply to the gated target are recorded as not applicable,
never as passed. Required-constant eligibility (T08) is part of an operation's
declaration and is evidenced separately from runtime behavior.

## Evidence rules

- Evidence is bound to a source revision and profile. An older run does not
  qualify a later compiler or library edit.
- Declared means implemented but not behaviorally verified per type and profile.
  Declarations and name matches are not passes.
- Shared implementations (blankets, slice/text forwarding) are written once, but
  each retained type and profile contract still needs its own evidence.
- A compiler repair needs a focused source run or fail regression. Memory and
  unsafe changes also need an ASan/UBSan compiler run and an emitted
  `--sanitize address` run; threads and sync need `--sanitize thread`.
  `--sanitize undefined` is rejected by design.

## Working rules

- Mettle must not read like a Rust copy: use native names and syntax, and never
  add a second compatibility copy of a type.
- No test weakening: never raise a timeout, weaken an assertion or delete a
  failing case to make a run pass. Limit concurrency instead of crediting OOM or
  timeout results.
- After two failed fixes for the same issue, stop and write down the root cause
  before another attempt.
- Compiler and runtime changes are allowed only where a V1 operation needs them:
  V1-required features and correctness or soundness fixes, no C++-only tuning or
  refactors (implementation-plan.md section 8).
- Language-level cases go in `tests/source/run/i13-<area>-*.mt` and
  `tests/source/fail/`; hosted programs in `tests/std/` using the directives of
  `tests/std.py`. Extend existing i13 files where natural; never duplicate cases.

## Area order

After LNX (requalification on `linux-x64` and review of every non-Linux
applicability record): collections/entries/drain; adapters; text/char;
owners/cells; sync/atomics/mpsc; hosted fs/io/process/net/env/time/thread;
macros; mem/ptr.

## Read first

`AGENTS.md`, `CONTRIBUTING.md`, [code-quality.md](code-quality.md),
[library-surface.md](library-surface.md) sections 1-3, 6.1, 9 and 10-13, and
[capability-coverage.md](capability-coverage.md).
