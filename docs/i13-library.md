# I13 library work package

Repo: /Users/niteshkumar/Projects/mettle-lang, main at `93df8a1` plus uncommitted
I13 work. I01-I12 are
closed for the macOS ARM64 host and Darwin ARM64 target only. All non-library
I13 rows are closed. What remains is library work: the 18 `P` rows in
docs/capability-coverage.md (L003 L005 L009 S005-S014 S019-S021 S024 S025).

## Handoff (start here in a new session)
The previous attempt (`origin/libs`, 23.6k lines) was never compiled against
main and was discarded. Its useful compiler fixes are in `02d2cd0`. Do not
merge or cherry-pick from it; write each lane fresh against current main.

**Execution model.** One orchestrator owns the compiler: it builds, changes
compiler/** and runtime C++, runs ctest, and merges lanes. Lane agents
(`gpt-6-luna` only) write library code and tests in their own worktree. They
do not build, check, execute tests or commit. The orchestrator can check their
library directory with its own binary:

    M=/Users/niteshkumar/Projects/mettle-lang/build/macos-arm64/Release/mettle
    $M check --library-dir $PWD/library FILE.mt
    $M build --library-dir $PWD/library FILE.mt -o /tmp/x && /tmp/x

The orchestrator batches focused checks across coherent deliveries, not the full
suites or CTest. A lane that needs a compiler change stops and reports a
minimal repro (a short `.mt` file plus the error) to the orchestrator. It must
not work around the compiler by weakening an API or a test.

**Lanes** (independent file sets; patches only, no commits authorized):
1. Collections: vec, vec_deque, linked_list, binary_heap (S006, S010).
2. Maps/sets: hash_map, btree, collections (S008, S009).
3. Iterators: core/iter (S011), then slice (L009).
4. Text: core/text, char, alloc/string (S007).
5. Numbers/format: num, float, fmt, cmp, hash (L003, L005, S012, S013).
6. Owners/alloc: arc, rc, boxed, alloc (S005, S014).
7. Hosted: std thread, sync, fs, path, net (S019-S021, S024, S025).

**Current validation cadence (owner decision, 2026-11-01):** use only
focused checks and necessary incremental builds during implementation.
The orchestrator owns all builds and execution. Permit two new full
build/validation runs: after ten of the eighteen partial capability areas
are complete, and at full I13 library completion. A few implemented operations
do not close an area: its applicable selected declarations, behavioral evidence,
inventory and documentation must be complete. Earlier bounded batch freezes
do not authorize another broad run. Final milestone qualification remains
subject to the complete source-freeze and quality gates.

**Deadline stop (2026-11-01, 13:04:39 IST / 07:34:39 UTC):** the owner's
40-minute execution budget expired with zero of the eighteen whole areas
code-complete or qualified. Implementation stopped; no extension or new full
qualification was started. The earlier 79-record floating supporting-trait
receipt remains evidence only for its pinned inputs. Rc Vec-to-slice conversion
is integrated and passed a native Debug execution with a non-Clone allocator;
Release, compiler sanitizers, emitted sanitizers and reconciliation are pending.
Map and collection deliveries remain unintegrated artifacts.

The Any Static/unsized admission changes are partial. A focused callable
regression demonstrated that display type names are not unique semantic
identities. The newly authored display-name/ODR identity lowering was removed,
not declared sound; the existing hash lowering remains an unresolved blocker.
The native compiler binary still contains the rejected prototype and does not
match current backend source, so its Any passes are not current-source evidence.
The valid failing regression is retained. Further work requires rebuilding,
correct identity lowering, profile/sanitizer/codegen/package checks and complete
operation/source-cfg reconciliation. Allocator-clone compatibility, pointer and
iterator prerequisites, owner conversions, collection integration, and hosted
thread/synchronization/filesystem/network work also remain open.

**Lessons from the discarded branch** (each caused errors there):
- Reserved words cannot be identifiers: `var copy read mut take shared heap
  local weak pinned success failure present none interface`, among others; see
  `isReservedWord` in compiler/syntax/token.cpp. Use backticks for a public
  name (`` `var` ``, `` `success` ``) or rename locals and fields.
- An explicit receiver (`receiver self: ...`) cannot combine with `mut`/`take`.
- Every name used needs an import (`import package.core.fmt` and so on);
  duplicate bindings (an import and a local fn of the same name) are errors.
- Do not add a second form of an existing method (for example two `pop_if`
  or two `fmt.write`); extend or replace the existing one.
- `format` parameters take f-strings: `fmt.write(mut w, f"{value}")`.
- Check coherent integrations before taking another delivery; avoid large
  unaudited patches rather than rebuilding after every small edit.

## Read first
- AGENTS.md, CONTRIBUTING.md, docs/code-quality.md
- docs/library-surface.md: sections 1-3, 6.1 (the V1 subset), 9 (Mettle names)
  and 10-13
- docs/implementation-plan.md, the I13 paragraphs (~line 1390)
- docs/capability-coverage.md

## Current integration state

Native `Bound`/`RangeBounds`, borrowed unsized Text endpoints, exact/fused
iterator protocols, size hints and mixed-end adapters are implemented with
focused Debug/Release evidence. The compiler repairs preserve nominal generic
argument and tuple component regions, recheck view-bearing generic interface
bounds after region inference, and recover associated-inferred argument regions.
Conditional-static and distinct invariant-region negatives reject at the
interface obligation; a valid shared-region/static case also passes. These are
supporting protocols, not complete S011 or I13 closure.

Pinned targeted clang-tidy, the compiler algorithm executable and
`compiler.boundaries` pass. The instrumented compiler/algorithm targets build;
instrumented algorithms, boundaries and five exact regional negatives pass.
Current regional normalization inputs pass instrumented algorithms, boundaries,
six focused positive programs in both profiles and three exact safety negatives.
Six collection/resource programs also pass emitted ASan in both profiles,
including deque destructor-panic restoration, invalid Vec ranges/splice cleanup,
heap append comparison-panic recovery and unchecked slice splits. Pinned
targeted static analysis passes for both changed compiler files. Older broader
receipts are not substituted for current-input evidence. No new full
qualification run has been started.

The collection iterator/append/slice delivery and guarded deque drain are
integrated but not fully verified. Nested coherence now passes its disjoint
positive and genuine-overlap negative, including compiler sanitizers. Pinned
Future forwarding selects the owner's projection rather than borrowing its view
handle. Regional normalization preserves nominal arguments and fields when
associated types resolve; generic assumptions retain their declared regions,
and cross-region interface arguments are decorated for contract comparison.
Borrowed Box collection and five related regional/associated cases pass both
profiles, with three exact safety negatives. Collection/slice operations,
iterator hints, Vec ranges and deque boundary/drop/unwind cases have focused
passing receipts, including the emitted-ASan resource checks above. Native take consumes
Copy values too: fixture counters use independent copied bindings, and range
bounds use indices rather than stored values. Numeric,
map/hasher/range, general Cow/array/Future, services and thread/sync follow-up
patches remain queued for integration; their runtime and inventory blockers are
not waived. The S006 slice-Cow-to-List conversion now has focused evidence.
All eighteen capability areas remain partial.

The current L005 batch has focused passing evidence for decimal `FromStr`
at both float widths, including halfway rounding, long sticky mantissas,
subnormals, finite maxima, overflow/underflow and grammar rejection.
Fixed-precision Display/Debug passes tie-even rounding, carry, signed and
integral zero fractions, padding, very small values and writer failure.
Native f32/f64 MIN/MAX resolve in runtime and static contexts with exact-bit
checks. Runtime algebraic operations preserve the selected strict IEEE behavior;
extension parsing now distinguishes `const fn` from associated constants.
Six focused cases pass through the instrumented compiler, and five float
programs pass emitted ASan in both profiles; the expanded parsing fixture has
its own current compiler/emitted-ASan receipts. Algorithms, component boundaries
and targeted static analysis pass. No full qualification run is added.
The corrected 301-record audit exposed missing constant values and 92 selected
stable const-callable methods whose floating/method evaluation is unsupported.
All 28 selected f32/f64 constant values now pass typed static/runtime assertions
and local immutable-binding inference, including exponent/radix metadata,
precision thresholds and IEEE exceptional values. Metadata retains u32/i32
types rather than inheriting the float owner's type; NaN payload is not promised.
The existing native static initializer handles these values and exact
width/type mismatch negatives pass. Current compiler and emitted-ASan checks
pass in both profiles.

The 92 selected stable const-callable records (80 distinct f32/f64 call forms)
now have focused Debug/Release acceptance. The evaluator preserves exact IEEE
bits through constructors, endian byte conversions, source const-function frames
and static storage, including signaling/quiet NaN payloads and negative zero.
Contextual binary32 literals avoid intermediate binary64 rounding; alias
factories, 128-bit casts, enum classification and NaN/infinity midpoint edges
pass. Exact wrong-width/array/arity, non-const, clamp-precondition and unsafe-call
negatives pass. Clamp preconditions are VM diagnostics, not adapter exceptions.
The original algebraic const fixture passes without removing assertions.

The coherent compiler batch has native and ASan/UBSan compiler builds,
focused compiler CTest/IR algorithms, pinned static analysis and emitted-ASan
evidence. Ten positive cases and eight negative cases passed the native batch;
the final affected const-method/boundary cases and negatives were rerun under
compiler sanitizers, with emitted ASan for the positive cases. LSP diagnostics
also exercise exact-bit folding and width rejection through the same callback.
Receipts and the 92-ID mapping are retained in
`i13-float-const-current-inputs.json` and the session's
`i13-float-const-clamp-{final,instrumented-final,emitted-final}` artifacts.
This closes the const-callability obligation, not the remaining 301-record
L005 runtime/supporting-trait inventory. L005 and all eighteen areas remain
partial; no new full qualification run is authorized by this batch.

The next L005 supporting-trait batch implements 79 selected records: thirteen
lossless numeric `From` pairs, sixty-four owned/readonly-view arithmetic,
assignment and negation forms, and the two float `ToString` records through
the allocator-layer Display blanket. Focused native and compiler-ASan/UBSan
checks pass for actual generic trait dispatch, integer endpoints, finite
widening, signed zero, NaNs, assignment effects, unsized Text, independent
String ownership and formatting-error panic. Copied float folds and associated
view results retain their regional proofs; invalid region/ownership cases
remain rejected. The same batch rechecks all 28 values and 92 const records.
Emitted-ASan checks pass for the five supporting-trait/conversion/formatting
cases in both source profiles. The current 301-record inventory and scoped
receipts are retained in `i13-L005-float-supporting-acceptance-v3.csv` and
`i13-float-traits-current-inputs.json`.

This is not L005 completion. Collision-safe Any identity, the unsized Any
contract, default comparison RHS-Self disambiguation and complete 301-record
operation/profile coverage remain open. No whole capability area is closed by
the supporting-trait batch.

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

## Current library batch

`tools/v1_operations.py` now generates `docs/baseline/v1-operations.csv` from
the frozen manifest and preserves manually reviewed native paths, statuses and
evidence on regeneration. It retains each canonical substitution and exposure,
grouping integer/float/atomic widths and nominal type/trait pairs into families.
The initial worklist has 13,295 canonical records in 2,442 operation families
and 2,309 implementation families; these are generated worklist counts, not a
qualified denominator or a revision of the selected subset. Scope reconciliation
against the approximate section 6.1 counts and the source-cfg audit remain open.
Blank native paths and `missing` mean not yet mapped in this worklist, not proof
that code is absent. Nine operations (13 baseline exposures), covering List
and deque retention plus the text/char follow-up, currently carry reviewed
focused execution evidence. Five Windows-only
implementation records are not-applicable on Darwin. No other operation is
automatically credited from a name match. Unknown rendered target conditions
are blocked; inherited/source-only cfg branches still need the owning audit.

The S006 retain follow-up implements mutable-callable predicates for
`List.retain` and `retain_mut`. Both visit in order, allocate nothing and
compact in linear time. A cleanup guard preserves the kept prefix and
unvisited suffix on predicate or element-destructor panic, excluding an element
before its destructor runs so recovery cannot drop it twice. Allocation and
capacity are unchanged. The exclusive receiver keeps the raw-pointer guard's
allocation live and stable; its initialized ranges are documented in
`library/alloc/vec.mt`.

Focused Debug/Release source executions pass in
`tests/source/run/i13-list-stateful-retain.mt`, including stateful visitation,
empty/all/none cases and zero-sized values with destructors. The original
stateful drop-count case is restored in `tests/alloc/i13_slice_collections.mt`.
`tests/std/collection_panic_safety_vec.mt` checks both retain variants after
callback/destructor panic, multiple compaction holes, remaining contents,
exact destruction counts and reuse. On the retain-only input, Release CTest
passed 24/24 (including both source suites and alloc/std), the documentation
validator passed, and the three changed programs passed emitted ASan.
The instrumented compiler/runtime build and ASan/UBSan detector startup passed,
as did instrumented `backend.cleanup-source`; instrumented `library.alloc`
exceeded its unchanged 900-second suite timeout. Its chained focused checks did
not run, so instrumented validation remains incomplete. The timeout is not
waived or raised. S006 remains partial.

The integrated S010 deque follow-up adds read `retain` and stateful
`retain_mut`, with linear, allocation-free wrapped-ring compaction. Its cleanup
guard excludes removed slots before destruction and restores retained/unvisited
values after callback or destructor panic. Focused Debug/Release source
execution and the hosted panic/drop-count program pass. Head, capacity and
allocation remain fixed; zero-sized values and repeated cleanup are covered.
The guard's initialized-range and ring-order invariants are documented in
`library/alloc/vec_deque.mt`.

The integrated S007 text follow-up restores backward/mixed whitespace splitting
over Text and owned String, and backward UTF-16 iteration. It adds
`char.is_ascii_whitespace` and the selected buffer-writing `char.encode_utf16`,
whose returned initialized prefix borrows the supplied buffer. The accidental
no-argument char convenience is replaced, not duplicated; Text's UTF-16
iterator remains. Focused Debug/Release boundary cases and the owned String
program pass. The small-buffer regression catches the specified panic and checks
its code/message and unchanged destination rather than treating any crash as
success.

Before the compiler follow-up, consolidated Release CTest passed 24/24 for the
integrated S006/S007/S010
batch, including both source profiles and alloc/std suites. All ten changed
source/alloc/hosted programs passed emitted ASan. The ASan/UBSan compiler and
runtime passed the List and deque hosted panic/cleanup programs through the
existing `tests/std.py` check with unchanged bounds. Narrow instrumented source
runs for List, deque and small-buffer char each exceeded the unchanged
60-second build bound; their instrumented source-profile checks remain
incomplete. These timeouts and the earlier full instrumented alloc timeout
are not waived, raised or reported as sanitizer passes. Those results are
historical, not qualification of the subsequent compiler changes.

The S011 follow-up restores the original `by_ref().take_n()` view-reuse and
owned filter+map drop-count cases. Mutable-view Iterator/BidirectionalIterator
forwarding preserves `Item = I.Item` and `by_ref`'s selected `mut Self` result;
no wrapper return type or ownership exception is added. Both compiler blockers
were confirmed under LLDB and repaired at their owning boundaries:

- The interface method-contract checker substituted owner types but left Self's
  view in the implementation's rigid region binder. It now rebinds owner regions
  into the provided method's context before normalization.
- Region-phase implementation selection compared raw and region-decorated Item
  type identities using the runtime callable shape predicate. It now uses
  decorated callable bounds and the region solver, retaining the separate
  erased ABI/capability check and higher-ranked proof.

The restored iterator fixture, new compiler regressions
`iterator-associated-item-through-callable-bound.mt` and
`mutable-view-interface-associated-result.mt`, and owned iterator drop-count
executable pass focused native checks. Existing higher-ranked, callable and
region/interface rejection cases still reject as specified. S011 remains
partial; this does not establish all-adapter or operation-subset closure.
The current native Iterator explicitly requires Sized, so erased/unsized
iterator forwarding is not covered by this repair. That existing native
restriction is not evidence that the selected unsized operation is invalid.

The two new-fixture formatter failures are repaired without reindenting the
tests to match incorrect output. Syntax-derived hints distinguish generic angle
closers from trailing binary operators and match-arm separators from continued
expressions. Both original fixtures now pass `mettle fmt --check`; the existing
package formatter test covers peer arms in let/return/wrapped matches, generic
fields, unspaced comparisons, macro preservation and fixed points. Preexisting
grouped-import/else-layout differences in older library files remain a narrow
orchestrator-owned formatting follow-up, not a reason for whole-file churn.

The original unoptimized Debug-sanitized char compile completed diagnostically
in 309.21 seconds with no sanitizer report. Samples show active macro loading
and semantic checking, not sanitizer startup failure. The follow-up uses the
repository-supported Release-sanitized configuration with the same pinned
toolchain and both ASan/UBSan enabled; this changes compiler optimization, not
Mettle source profiles or test bounds. Its build and detector startup pass, as
do six focused source cases (12 Debug/Release executions), including all three
that exceeded the original 60-second bound with the unoptimized compiler.
The historical Debug-sanitized timeouts remain unqualified; no compiler tuning,
timeout increase, disabled instrumentation or speedup claim is substituted for
evidence.
The later follow-up has focused static-analysis evidence; consolidated Release
CTest remains deferred to the owner's two full-run gates. This is not I13
qualification.

### S006 List follow-up

List-owned operations have one behavioral program,
`tests/source/run/i13-list-operations.mt` (capacity/reserve/shrink including
allocation failure, insert/remove/swap/truncate, drain, split_off/append,
resize, dedup variants, sorts, pop_if, extract_if, splice, boxed/leaked
conversion, accessors, raw pointers, `set_len`, repeat, drop counts, boundary
panics, `From` conversions from deque/heap/String/Text/slices/arrays/boxed
slices, slice-Cow borrowed-copy/owned-move conversion, cross-allocator
`==`/`<=`, borrowed `ExtendItems<read T>`, and slice `starts_with` through List
deref, plus `from_parts`/`into_parts` for Global and custom allocators with
NonNull round-trip and null-rejection checks) plus
`tests/std/i13_list_from_cstring.mt`. The focused List and Cow programs pass
Release and emitted ASan; `tests/modules.py` covers lazy pointer-builtin
loading. Natural `target.extend(source.iter())` now passes in both source
profiles through argument-directed interface selection, including associated
iterator-item and candidate-local region matching. The generic dispatch
regression also covers distinct argument types; a genuinely ambiguous call
continues to fail in the source-negative suite.
`core.ptr.NonNull` now provides null-rejecting `new`, unsafe `new_unchecked`,
and `as_ptr`; List parts APIs use the wrapper, with null rejection and pointer
round-trip evidence. The compiler loader preserves lazy built-in pointer
operations while mounting the source `NonNull` type only when requested. The
full selected `NonNull` operation inventory and other slice-derived exposures
remain open (the latter with L009). S006 remains partial.

### Integrated follow-up and focused evidence

All eighteen capability areas remain partial. The additional integrated work is:

- Hash/ordered map and set iteration preserves key/value access relationships.
  Stateful retain/extraction callbacks and callback-panic recovery pass focused
  checks, including a 96-entry ordered-tree rebalance case. Unchanged ordered
  traversal advances its successor; removal recomputes its lower-bound cursor.
  Range-bounded ordered extraction still needs the native bounds protocol.
- Tuple comparison/hash covers arities 1-12, including an unsized final field.
  Cyclic module macro indexing no longer reports duplicate definitions.
  Prefix unsized fields remain rejected. Wrapping value/hash/format delegation
  passes an all-integer-width fixture; primitive Clone includes both 128-bit
  integers and both floats. Wrapping Default and owned sum/product folds pass
  all-width empty-identity and overflow checks in both profiles; primitive
  Default includes both 128-bit integers. Arithmetic, bitwise, shift, unary and
  assignment operators now have all-twelve-width Debug/Release evidence,
  including overflow and shift-count boundaries. Four representative
  divide/remainder-by-zero cases retain the native trap contract in both
  profiles. The selected stable `reverse_bits` method is already implemented;
  excluded unstable inherent methods are not new V1 obligations. Borrowed folds
  have the additional focused evidence recorded below.
- Stateful collection/slice callbacks include mutable deduplication, deque
  searches, linked extraction and sortedness with partial-order handling.
  Heap retain evaluates original items once and heapifies an index permutation
  before committing swaps; predicate/comparison panic cannot move/remove heap
  elements. Its linear-time strategy uses linear Global scratch storage after
  the first rejected item. The upward-sift counterexample checks every key's
  visit count, retained pop order and destruction count. Vector dedup guards
  recover initialized contents after callback or removed-element destructor
  panic. Focused source and hosted unwind cases pass, as do all four new/changed
  callback/unwind programs under emitted ASan in both profiles. Both new source
  cases also pass the ASan/UBSan compiler in both profiles at the unchanged
  bounds; four existing allocator collection/sort programs pass focused checks.
- Box/Rc/Arc uninitialized and zeroed slices, initialized-owner conversion,
  empty weak handles and Box mutable raw-pointer access have focused evidence,
  including custom-allocator layout/failure/drop checks. Indexed machine
  initialization now preserves the checked exclusive slice access.
- Path components, byte iteration, remaining views, clone and ancestors support
  mixed-direction traversal without resolving `..` or changing non-Unicode
  bytes. Boundary trimming preserves an unconsumed root. Component is Copy;
  its string view is obtained by value, not by borrowing a temporary component.
  Filesystem access/bounds/EOF and address-parser round trips also pass focused
  hosted checks.
- Condvar predicates accept mutable state and payload access. Timeouts use
  Duration, retain one total budget, release/reacquire even at zero duration,
  and recheck the predicate before declaring timeout. Mutex/RwLock exclusive
  access reports poison while preserving the recoverable mutable view.
  Existing channel timeout call sites are updated; static-capable Once is
  unchanged. Condvar mutex association and atomic rwlock downgrade remain open.

The compiler follow-up preserves existing contracts rather than relaxing them:
loop-local sibling returned views gain disjointness only without cross-invocation
carriage; nullary enum values exclude inactive variant fields from region proofs;
region-carrying nominal results distinguish borrowed storage from carried views.
Origin propagation must not permanently seed a receiver-storage loan while those
carried views are still propagating through its fixed point. Focused escape,
exclusive-alias and invariant-region rejections remain in place.

The earlier follow-up's narrow evidence includes five source cases in both
profiles (clone, nullary enum, path and both map callback cases), eight rejection cases under the
ASan/UBSan compiler, instrumented clone/enum/path executions in both profiles,
and six emitted-ASan programs in both profiles covering owner slices, raw-pointer
access, ordered traversal, paths and map panic recovery. The new threaded
wait/poison/barrier fixture passes emitted TSan in both profiles after the actual
sanitizer detector probes pass. Pinned targeted clang-tidy/clang-format, component
boundaries and the focused compiler-boundaries CTest pass. These are scoped
macOS ARM64 receipts, not an area closure, race-freedom proof or full run.
The new generic operator fixture exposed recursive reconstruction of independent
where bounds while creating solvers that had no equalities or Unpin requirements
to check. A bounded compiler sample records the cause. Solver creation is now
conditional on actual obligations, without removing inference, equality or
Unpin checks. The unchanged 60-second source bound is retained: seven numeric
cases pass both profiles, eight generic-default/equality/Unpin positive cases
pass both profiles, and eight contextual/recursive/equality rejection cases
pass. The instrumented compiler passes the operator regression and three
equality/Unpin positives in both profiles plus those eight negatives.
Incremental normal/instrumented builds, targeted static analysis, formatting,
compiler-boundaries CTest and the instrumented startup/detector checks pass.
`core.ptr.NonNull` is now source-visible with the minimal constructor/pointer
access needed by List parts, and the loader keeps compiler-owned pointer
operations lazy. Most selected `NonNull` operations remain missing, as do the
other prerequisite protocols. The operation CSV credits the tested NonNull
entry points and leaves the broader inventory missing. The six retained Luna
lanes deliver isolated patches without running builds or tests; the orchestrator
owns integration and execution.

### Further operation batch

The following additions have focused native evidence; none closes a capability
area or the selected operation inventory:

- `Sum<Input = Self>` and `Product<Input = Self>` distinguish input from output.
  Consuming `Iterator.sum<S>()`/`product<P>()` support explicit or context-inferred
  output; existing module free functions preserve item-as-output inference.
  Borrowed slice items fold into an independent owned result, and mismatched
  input/output instances are rejected. Wrapping borrowed Sum/Product cover all
  twelve integer widths, including empty identities, overflow and reusable,
  unchanged input arrays, in Debug and Release. Both new fold programs pass
  emitted ASan in both profiles; the existing iterator library program also
  passes both profiles.
- Hash/ordered sets expose stored equal keys, replace the stored owner or insert
  a missing key, and return removed owners without an implicit clone. Copy and
  non-Copy tagged-key cases check duplicate destruction, borrowed queries,
  replacement/take transfer and final drops in both profiles. A live sorted-key
  view rejects replacement. The ownership/drop fixture passes emitted ASan in
  both profiles.
- Rc/Arc Weak Clone includes expired handles: public weak counts are zero after
  the last strong owner, while physical weak bookkeeping keeps the allocation
  until the last weak drop. Allocator evidence checks one payload destruction,
  no resurrection, exact deallocation layout and cloning after expiration.
  Unsized Rc/Arc value traits and Arc hash/display/debug delegation also pass.
  Both allocator/value programs pass emitted ASan in both profiles. Frozen weak
  count records are `B7e3840459f9abc6f9a6dceba` and
  `B1846d3fb37bf1ff17ed8c0e2`; the pinned external source archives were not
  freshly re-audited. Arbitrary allocator Clone compatibility is not assumed.
- Deque append/contains/truncate/resize/Default, linked contains/split_off and
  Global append/Default, and Ord-bounded heap Default pass the new collection
  fixture in both profiles, including wrapped storage, allocation/drop accounting,
  invalid split and clone/destructor unwind. Emitted ASan also passes both
  profiles. Generic linked split rebuilds nodes with a cloned allocator; only
  Global append splices nodes in constant time. Generic-allocator append remains
  blocked on the allocator compatibility contract.
- File positional I/O uses checked signed offsets and retries interruption,
  preserving short/EOF results and the shared cursor. Sparse bytes, offset
  rejection and zero-byte OS access errors pass native and emitted-ASan checks.
  TCP peek checks a possibly short prefix without consuming it; Incoming yields
  success or failure rather than ending on accept failure, and UDP peer address
  is exercised. A no-timeout nonblocking listener preserves WouldBlock instead
  of translating it to TimedOut; configured-timeout behavior is unchanged.
  The loopback program passes native and emitted ASan in both profiles.
- Thread is non-Copy with explicit Clone; ThreadId has value traits. Thread and
  handle Debug operations actually format output, and handle `thread()` views
  borrow the stored Thread. Non-Copy and view-across-join negatives pass.
  New and existing basic/scoped/Arc-race programs pass native checks and emitted
  TSan in both profiles. These receipts are not a race-freedom proof.

The ASan/UBSan compiler passes the borrowed Wrapping, non-Copy key,
further-collection and expired-weak allocator programs in both profiles, plus
the four new type/ownership negatives. These are separate from the eight
emitted-ASan programs and four emitted-TSan programs, each in both profiles.
Baseline/documentation validation and the seven operation-inventory plus six
syntax-inventory Python tests pass. No new full build, CTest suite or
qualification matrix has run.

Borrowed `chain` remains **INCOMPLETE**: a standalone two-Once borrowed-item
reproduction fails ownership checking in `Chained.next`, independently of any
fold. The session preserves that reproduction and a source-freeze prerequisite;
direct borrowed-slice fold evidence does not establish chained-view coverage.

## Known gaps to fix first
Closure trim patterns and owned Text construction are integrated with focused
evidence; they are no longer missing declarations. Remaining prerequisites
include borrowed chained-item propagation, exact-size/fused and unsized iterator
protocols, native range bounds,
NonNull exposure beside compiler-owned pointer intrinsics, collision-safe Any
identity, and the synchronization operations identified above. Complete selected
operation/source-cfg reconciliation remains necessary before closing any area.

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
  - Each lane works on its own branch and worktree, for example
    `git worktree add ../mettle-wt/lib-iter -b lib/iter main`; the
    orchestrator rebases and merges lanes one at a time.
  - Commit small, coherent batches with the trailer
    `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.
  - The owner merges.

## Commands
These are orchestrator commands. Lane agents use only the `--library-dir`
commands in the handoff section. Run from the repository root.

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
