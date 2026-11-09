# I13 library work package

Gated profile: `linux-x64` (Linux x86-64 host/target, owner decision
2026-11-08). I01-I12 receipts retain their macOS-host/Darwin and recorded
cross-target scopes, not Linux-host qualification. LNX (implementation-plan
section 8.0) precedes further I13 closure.
All non-library I13 rows are closed within their recorded scope. The 18 library
areas remain partial: L003, L005, L009, S005-S014, S019-S021, S024-S025.

## Handoff (start here in a new session)

Latest operation ledger (2026-11-09): **10,454 evidenced, 35 declared,
2,801 missing, 5 not applicable** of 13,295 records. Declared means implemented
but not behaviorally verified per type/profile. Subset/source-cfg reconciliation
and Linux applicability review remain open; no area is closed by these batches.
The 35 declared records comprise 20 conversion-blanket exposures and fifteen
callable-adapter Clone/ToOwned records.

### Source-only backlog reconciliation (2026-11-09)

Before the focused verification below, all **2,846 remaining canonical IDs**
matched the existing source worklist.
The 2,811 missing records comprise **1,405 interface implementation relations,
1,009 method/interface-method exposures and 397 other declaration records**,
not 2,811 independent missing functions. They have 1,803 case-sensitive family
keys; neither records nor family keys measure coding effort.

The first source-location pass partitions every remaining record as follows.
Candidates are not compiled declarations or verified contract equivalents;
no CSV status or evidence was upgraded.

| Review queue | Records | Required follow-up |
| --- | ---: | --- |
| Existing native declaration candidates | 837 | Check signatures, substitutions, views, const support and behavior; includes seven native free-function candidates. |
| Shared blanket candidates | 107 | Check each type's bounds and source/target shape, reusing the existing implementation where applicable. |
| Inherited slice/text exposures | 100 | Reconcile 67 shared operation names and receiver forwarding, not duplicate methods on each exposing owner. |
| Compiler-owned APIs or derived properties | 648 | Review exact built-in operation/property support and const behavior before adding library code. |
| No same-owner source candidate found | 955 | Review 605 interface relations and 350 methods for renamed, forwarded or blanket equivalents before declaring code absent. |
| Other contract/declaration-shape review | 164 | Reconcile associated items, variants, fields, macros, free functions and unmatched type shapes. |
| Already declared, awaiting evidence | 35 | Supply the exact per-type/profile acceptance evidence. |

Concrete findings and implementation order:
- `NonNull` has 82 missing method exposures for 41 distinct method names with
  no declaration in `library/core/ptr.mt`; the existing `new`, `new_unchecked`,
  `as_ptr` and Clone must not be reimplemented. Reuse compiler-owned pointer
  primitives while preserving unsafe and const contracts.
- Missing ledger rows already have source candidates such as
  `UdpSocket.connect`, `File.sync_all`, slice `as_array`, List's declaration and
  the Iterator interface. `UdpSocket.bind`, `Duration.new` and five String
  constructors have native free-function candidates; matching names alone do
  not establish equivalent errors, overflow, const or ownership behavior.
- Vec's slice-derived and String's text-derived exposures must be handled with
  the shared slice/text implementation and forwarding, not owner-specific copies.
- Prioritize the documented Peekable associated-buffer, Option pinned-view,
  Static/unsized Any, tuple associated-constant and atomic RwLock downgrade
  gaps before their dependent acceptance batches.

This is a complete first-pass partition, not completed semantic reconciliation.
The 955 no-candidate records remain review work, not a confirmed missing-code
count. Source cfg/Linux applicability and focused compile/run evidence remain
open; this pass ran no compiler, build, sanitizer or qualification checks.

### Focused hosted reconciliation (2026-11-09)

Ten previously missing operations now have focused Linux debug/release evidence:
File `try_clone`, `sync_all`, `sync_data`, `set_permissions`, and UdpSocket
`local_addr`, `peer_addr`, `try_clone`, `take_error`, `set_read_timeout`,
`set_write_timeout`. The extended `i13_fs_positional_io` and
`i13_net_tcp_peek_incoming` fixtures and existing `net_loopback` fixture pass
both profiles through the owning hosted runner at unchanged limits. They check
shared file cursors and independent handle cleanup, synchronization success and
unchanged file state, permission bits, unconnected-peer failure, duplicate socket
traffic, empty pending-error queries, zero-timeout rejection, timeout removal
and blocking receive expiration. `sync_data` currently uses `fsync`; these tests
do not establish a data-only cost or persistence beyond OS guarantees.

Evidence uses the existing Linux Release compiler with a byte-identical native
snapshot of the current library and fixtures, not a rebuilt or newly qualified
compiler. No full suite or sanitizer run was performed for this test-only batch.

Contract review also confirms partial UDP surfaces that remain missing:
`bind`, `connect` and `send_to` accept only one SocketAddr rather than the
selected generic address input; connected `send`/`recv` reuse stream helpers
that skip zero-length datagrams; and `net_error` translates WouldBlock to
TimedOut without checking nonblocking mode. Consequently `send`, `recv`,
`recv_from` and `set_nonblocking` are not credited from passing blocking
loopback cases. The ten credited records reduce the open count to **2,836**;
the rest of the source-only partition still requires contract resolution.

The [native optional/outcome specification](native-value-contracts.md) now owns
its explicitly assigned operation contracts. Its
[source-review findings](native-value-contracts.md#9-acceptance-and-remaining-surfaces)
retain callback-capability, exclusive-view duplication, Debug extraction and
constant-evaluation reconciliation as existing I13 obligations. This
documentation-only migration does not upgrade the ledger's scoped receipts or
mark those surfaces verified.

Additional native definitions and exact assignment boundaries are in
[the authority register](baseline-mapping.md#7-native-operation-authority).
[Core reconciliation findings](native-core-library-contracts.md#153-observed-reconciliation-work)
and [collection findings](native-collection-contracts.md#12-exact-coverage-and-remaining-work)
record existing implementation gaps; D30/D31 resolve the default hash policy
and general borrowed-or-owned identity without upgrading implementation receipts.

The following batch receipts record status at the time of each batch; current
operation statuses are maintained in [the ledger](baseline/v1-operations.csv).

| 2026-11-09 batch | Implementation and focused Linux evidence | Remaining obligation at batch time |
| --- | --- | --- |
| Shared unzip | One `Iterator.unzip` over `Default + ExtendItems`, independent of collections in core. `i13-iter-consumers` passes native/emitted-ASan debug/release: empty input, heterogeneous ordered output, non-Copy movement/drops. Only unzip credited. | Destination-specific allocation/destructor-panic contracts. Declaration checking needs `Self: Iterator<Item = (A, B)>`, explicit `Self.(Iterator).next` and explicit output arguments; equality-only `Self.Item` and result-tuple inference remain unsupported. |
| Conversion blanket | Coherence matches target **and interface arguments** before requirements. Disjoint-destination regression fails old/passes repaired compiler; genuine overlap and unconstrained downstream cases reject. One `TryFrom<U> for T where U: Into<T>` covers direct user Into; TryInto delegates. Ten directly tested rows evidenced; 192 TryFrom + 192 TryInto exposures declared. | Per-type/profile evidence for all 384 exposures; emitted owner-conversion ASan compile hit unchanged 60 s bound and remains unverified. |
| Adapter Clone | Field-wise Clone for Mapped, Filtered, FilterMapped, MappedWhile, FlatMapped, Flatten, Cloned, Copied, TakenWhile, SkippedWhile, Inspected, Cycled; ToOwned reuses it, phantom outputs gain no Clone bound. Value-trait fixture passes native/emitted-ASan debug/release, checking independent partially consumed Flatten/Cloned/Copied positions, ToOwned and Cycled wraparound. Nine rows evidenced, fifteen callable-adapter rows declared. | Peekable Clone: buffer remains `<associated.0>??` even with `Iterator<Item = T>` or a typed helper. Unbuildable attempt removed; original API unchanged. |

Conversion validation: incremental compiler build, `compiler.boundaries`,
`compiler.modules-memory`, pinned clang-tidy and generic/inference/float
conversion fixtures pass. The integer fixture hit its 60 s release-compile
bound; 514 assertions moved unchanged to `i13-integer-conversion-interfaces`,
leaving 2,365 operators in the original fixture. Both pass both profiles at
unchanged bounds. The unzip batch used the existing Linux Release compiler
with current `--library-dir` and installed `libxml2.so.2` via `LD_LIBRARY_PATH`;
no compiler/runtime/package change. Conversion compiler inputs were synchronized
without reverting unrelated checkout documentation.

**Open prerequisites:**
- Lazy coherent per-module core loading: product comparison without importing
  `core.cmp` currently mounts all core (~7 s/build across 963 import-free cases).
- Defer Static admission for view-bearing types to region checking: erased
  typing rejects `read T from static` and `Holder<region static>`; retaining
  static there breaks type equality. Blocks Any for ~35 iterator/guard/drain
  types. Collision-safe identity itself is fixed (2026-11-08), not a blocker.
- Clone for arrays (element construction), cells, ManuallyDrop and collection/
  slice/text iterators; Send/Sync for vec::IntoIter and sorted iterators;
  ReadDir, Scope and ScopedJoinHandle lack reference-derived thread properties.
- Inline throwing try_for_each closures, tuple associated constants
  (`char::UNICODE_VERSION`), Option pinned projections, unsized/erased iterator
  forwarding, allocator Clone compatibility, Condvar mutex association and
  atomic RwLockWriteGuard downgrade. Borrowed `Chained.next`, native range
  bounds, exact/fused protocols and minimal NonNull are integrated with scoped
  evidence below, not complete operation closure.
- Source builds use ~2 GB each; 16 CTest workers exhaust a 23 GB WSL and can
  push `i13-text-whitespace-splits-boundaries` (~45 s alone) over 60 s. Preserve
  bounds; limit concurrency rather than crediting OOM/timeouts.

**Execution and owner cadence (2026-11-01).** One orchestrator owns compiler/**,
runtime C++, integration, all builds and tests. Lanes (`gpt-6-luna` only) write
library/tests in separate worktrees, return patches, and do not build, check,
execute or commit. Stop for a compiler blocker with a minimal `.mt` repro and
error; never weaken the API. Independent lanes: collections (S006/S010), maps/
sets (S008/S009), iterators then slices (S011/L009), text/char (S007), numeric/
format/cmp/hash (L003/L005/S012/S013), owners/alloc (S005/S014), hosted
(S019-S021/S024/S025). Integrate coherent deliveries before taking another.
Only focused checks/necessary incremental builds during implementation; two
new full runs are authorized: after 10 of 18 whole areas complete and at full
library completion. Area completion requires selected declarations, behavior,
inventory and docs; final qualification also requires source freeze/quality.

**Historical limits (not current passes):**
- 2026-11-01 13:04:39 IST / 07:34:39 UTC: 40-minute budget expired with zero
  whole areas complete/qualified; no extension/full run. Rc Vec-to-slice with
  non-Clone allocator passed native Debug only; Release/compiler and emitted
  sanitizers/reconciliation pending. Map/collection artifacts were unintegrated.
- That session's display-name/ODR Any prototype was rejected and removed; its
  stale binary passes do not qualify source. The later collision-safe identity
  repair supersedes the hash blocker, not unsized/Static admission gaps.
- Discarded `origin/libs` (23.6k lines) was never compiled against main. Useful
  compiler repairs are in `02d2cd0`; do not merge/cherry-pick that branch.

Lane pitfalls: escape reserved public names (see `isReservedWord`); explicit
`receiver self:` cannot combine with mut/take; import every used name without
duplicate bindings; extend existing methods instead of adding compatibility
copies; `fmt.write` takes an f-string (`f"{value}"`).

## Read first
- AGENTS.md, CONTRIBUTING.md, docs/code-quality.md
- docs/library-surface.md: sections 1-3, 6.1 (the V1 subset), 9 (Mettle names)
  and 10-13
- docs/implementation-plan.md section 8.5
- docs/capability-coverage.md

## Current integration state

All evidence below is revision/profile scoped; older broader runs do not
qualify later compiler edits. All eighteen areas remain partial.

- Regional/associated normalization preserves nominal arguments, tuple/field
  regions, generic assumptions and cross-region contracts; view-bearing bounds
  are rechecked after inference. Current instrumented algorithms/boundaries,
  six positive programs in both profiles and three exact safety negatives pass;
  five earlier regional negatives also pass. Nested Box coherence accepts the
  disjoint case and rejects genuine overlap. Pinned Future forwarding selects
  the owner's projection rather than borrowing its view handle.
- Bound/RangeBounds with borrowed unsized Text endpoints, exact/fused hints,
  mixed-end adapters and borrowed chaining have focused Debug/Release evidence.
  Conditional-static/invariant negatives reject at the interface obligation;
  a valid shared-region/static case passes. These do not close S011.
- Six resource programs pass emitted ASan in both profiles: deque destructor-
  panic restoration, invalid Vec ranges/splice cleanup, heap append comparison-
  panic recovery and unchecked slice splits. Targeted pinned static analysis
  passes both changed compiler files. Collection/append/guarded-drain work is
  integrated, not fully qualified; queued deliveries require fresh integration
  and inventory checks, not credit from an older handoff.
- L005 decimal parsing at both widths covers halfway/sticky/subnormal/maximal
  values, overflow/underflow and grammar errors. Fixed-precision Display/Debug
  covers tie-even/carry/zero/padding/tiny values and writer failure. MIN/MAX and
  all 28 constant values have typed static/runtime bit checks and immutable-local
  inference; metadata retains u32/i32 types and NaN payload is not promised
  except where the exact-bit const contract requires it. Parsing/formatting and
  current constants have focused compiler/emitted-ASan checks in both profiles.
- All 92 stable const-callable float records (80 forms) pass focused native,
  compiler-ASan/UBSan and emitted-ASan acceptance: exact IEEE bits, NaN payloads,
  negative zero, endian bytes, source const frames, static storage, contextual
  binary32 literals (no binary64 double-round), aliases, 128-bit casts,
  classification and midpoint edges. Wrong-width/array/arity, non-const,
  unsafe-call and clamp-precondition negatives reject; clamp failure is a VM
  diagnostic. Original algebraic assertions remain. Driver/LSP use the same
  LLVM-free callback. Receipts: `i13-float-const-current-inputs.json`,
  `i13-float-const-clamp-{final,instrumented-final,emitted-final}`; final batch
  includes ten positives/eight negatives and affected sanitizer reruns.
- Another 79 L005 records cover thirteen lossless From pairs, 64 owned/read-view
  operators and two ToString records via the alloc Display blanket. Native and
  compiler-ASan/UBSan generic dispatch, endpoints, IEEE values, assignments,
  unsized Text, independent String ownership and formatting-error panic pass;
  five programs pass emitted ASan in both profiles. Regional/ownership negatives
  still reject. The batch rechecks all 28 values and 92 const records. Mapping/
  receipts: `i13-L005-float-supporting-acceptance-v3.csv`,
  `i13-float-traits-current-inputs.json`. Complete 301-record runtime/profile
  closure, unsized/Static Any and default comparison RHS-Self remain open.

Collision-safe Any identity (2026-11-08): `bootstrap/types/identity.cpp` encodes
canonical nominal paths, callable binder size/result sources/relations, static
and bound-region positions while erasing free regions. `type_id` is the address
of an identity-named link-once hidden byte, not a hash. Function-pointer generic
arguments add an identity hash to instance symbols because display names omit
binders. Both-profile fixtures: `i13-any-callable-source-identity`,
`i13-any-type-identity-structure`, `i13-any-static-identity`,
`erased-read-argument-erases-referent`; package cases:
`type_id_survives_public_reexport`, `debug_info`, `incremental_reuse`,
`debugger_workflow`.

Linux 2026-11-09 integration adds all-width integer/f32/f64 programs; integer
BITS/abs/carry/borrow/bit/signed-diff operations and operators with integer shift
counts; conversions/TryFromIntError; array comparisons; reference-shaped Result
copied/cloned; time ordering; Clone for std values, tuples 1-12, outcomes,
Reverse and NonNull; io/ErrorKind/ExitStatus Display; 147-type blanket/property
evidence. Compiler fixes cover 128-bit from_bytes alignment, u8 ASCII,
vertical-tab whitespace, float fract/midpoint/clamp, quoted/generic parameter hygiene
and unresolved borrow-origin projections. Unqualified interface calls, expected-
type into/try_into, unsuffixed indices and unescaped `from` are integrated.
The earlier Result copied/cloned shape question is superseded by this batch;
its per-operation evidence remains governed by the ledger.

Option/Result Linux 2026-11-08: Option insert/zip/slice/iter/iter_mut and Result
or/iter/iter_mut reuse exact/fused/double-ended slice iterators. Both-profile
operation and six panic cases pass; operations also pass emitted ASan (62 Option,
52 Result records credited). Option as_pin_ref/as_pin_mut (four records) still
fail region solving through either get_ref or into_inner_unchecked. Neighbouring
mem.take, ManuallyDrop new/into_inner/take/drop evidence, array.from_fn and Ord
min/max/clamp remain to reconcile; library mem needs a loader coexistence path.

## Goal (definition of done)
Every operation in the V1 subset (docs/library-surface.md section 6.1, roughly
2,900 operation families plus 1,760 trait/type pairs) has both of these:
1. **A compiled native declaration** in library/{core,alloc,std}, using Mettle
   names from section 9 (List/Map/Set/SortedMap, OwnedIterable,
   BidirectionalIterator, Reader/Writer, `T?`, `(Outcome<T, E>)`, ...).
2. **Behavioral evidence:** a passing test that calls the operation and checks
   its result, including its panic/failure, boundary and drop-count cases where
   it has them. Integer, float and atomic families must be checked at every
   width, but each family is still one row.

Gate only on `linux-x64` (Linux x86-64 host and target; owner decision
2026-11-08). macOS ARM64 is no longer gated and Windows remains excluded.
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

`tools/v1_operations.py` preserves reviewed native paths/status/evidence and
canonical substitutions/exposures. Its 13,295 records group into 2,442 operation
and 2,309 implementation families; these provisional counts are not the
qualified denominator. Blank paths/missing are unmapped, not proof of absent
code. Unknown rendered target conditions are blocked; inherited/source-only cfg
still needs audit. Five Windows-only exclusions recorded on Darwin require
Linux applicability review. Latest statuses are in the handoff above.

**Retain/text/iterator integration contracts:**
- List retain/retain_mut: stateful predicates, ordered linear allocation-free
  compaction, fixed allocation/capacity; guard preserves kept/unvisited ranges
  on callback/destructor panic and excludes a removed value before destruction.
  Deque retain/retain_mut applies the same guarantees to wrapped ring order
  with head/capacity/allocation fixed. Invariants live in vec.mt/vec_deque.mt.
- Text/String whitespace splitting supports reverse/mixed traversal; UTF-16
  iteration supports reverse traversal. char.encode_utf16 writes into a supplied
  buffer and returns its borrowed initialized prefix, replacing the accidental
  no-argument convenience. Small-buffer failure checks panic identity/message
  and unchanged destination, not any crash.
- Mutable-view Iterator/BidirectionalIterator forwarding preserves `Item =
  I.Item` and `by_ref`'s `mut Self` result. Method checking rebinds owner regions
  into the provided method; region selection uses decorated callable bounds and
  solver proofs, retaining separate erased ABI and higher-ranked checks. Native
  Iterator's Sized restriction leaves unsized forwarding open.
- Formatter hints distinguish generic closers from operators and match-arm
  separators from continued expressions. Original new fixtures pass fmt;
  grouped-import/else layout in older files remains an orchestrator follow-up.

**Historical macOS ARM64 receipts (not Linux qualification):**

| Batch | Passing scope | Unverified/failed scope |
| --- | --- | --- |
| Retain-only | `i13-list-stateful-retain.mt`, restored `tests/alloc/i13_slice_collections.mt`, `collection_panic_safety_vec.mt`: stateful/empty/all/none/zero-size/drop/panic/reuse; Debug/Release, Release CTest 24/24, docs and three emitted-ASan programs. Compiler/runtime build, detectors, `backend.cleanup-source` pass. | Instrumented `library.alloc` hit unchanged 900 s bound; chained checks did not run. |
| S006/S007/S010 before compiler follow-up | Release CTest 24/24; ten changed programs emitted ASan; compiler-ASan/UBSan List/deque hosted panic checks. Deque fixed storage, zero-size/repeated cleanup covered. | Narrow instrumented List/deque/char source compiles hit unchanged 60 s bound; not passes. |
| Iterator/compiler follow-up | Restored by_ref/take_n and owned filter-map drop cases; `iterator-associated-item-through-callable-bound.mt`, `mutable-view-interface-associated-result.mt`, owned drop executable; existing callable/higher-ranked/region negatives. Formatter original fixtures/package fixed points pass. Release-sanitized build/detectors and six cases (12 profiles) pass; targeted static analysis. | Original Debug-sanitized char compile took 309.21 s with active semantic work/no report, not a startup failure. Earlier timeouts remain unqualified; no bounds/instrumentation changed. Consolidated CTest deferred to owner gates. |

Release-sanitized is the supported compiler-optimization configuration with the
same pinned ASan/UBSan toolchain, not a change to source profiles or a speed claim.

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

Prior macOS ARM64 integrations (focused receipts only):
- Hash/ordered map/set iteration retains key/value relationships; stateful
  retain/extraction and callback-panic checks include 96-entry tree rebalance.
  Unchanged traversal advances a successor; removal recomputes lower bound.
  Range-bounded extraction still needs integration with native bounds.
- Tuple comparison/hash covers 1-12, including unsized last field; unsized prefix
  rejects. Cyclic macro indexing avoids duplicate definitions. Wrapping value/
  hash/format/default and owned/borrowed folds cover all twelve integer widths,
  empty identities and overflow. Arithmetic/bitwise/shift/unary/assignment has
  Debug/Release boundary evidence; four divide/remainder-zero cases retain traps.
  Primitive Clone/Default includes 128-bit values; Clone includes both floats.
  Stable reverse_bits exists; excluded unstable methods are not V1 obligations.
- Stateful slice/collection callbacks cover mutable dedup, deque search, linked
  extraction and partial-order sortedness. Heap retain visits original elements
  once and heapifies an index permutation before committing; predicate/compare
  panic cannot move/remove elements. Linear Global scratch begins at first
  rejection. The upward-sift counterexample checks visits/pop order/drops.
  Vector dedup guards recover initialized contents after callback/destructor
  panic. Four callback/unwind programs pass emitted ASan in both profiles; two
  new source cases also pass compiler ASan/UBSan at unchanged bounds; four
  existing allocator/sort programs pass focused checks.
- Box/Rc/Arc uninitialized/zeroed slices, initialized conversion, empty weak and
  Box mutable pointer access have layout/failure/drop evidence with custom
  allocators; indexed machine initialization preserves exclusive slice access.
- Path components/bytes/remaining views/Clone/ancestors preserve non-Unicode
  bytes and `..`, trim boundaries without losing an unconsumed root and support
  mixed ends. Component is Copy and gives its string view by value.
- Condvar mutable predicates use Duration with one total budget, release/reacquire
  at zero and recheck before timeout; Mutex/RwLock exclusive access preserves
  recoverable poisoned views. Channel call sites use Duration; static Once
  remains. Mutex association and atomic downgrade remain open.

Compiler fixes retain loans through carried-view propagation: loop-local sibling
results are disjoint only without cross-call carriage; inactive enum fields do
not create region obligations; nominal results distinguish storage from carried
views. Escape/exclusive/invariant negatives remain. Five source cases in both
profiles, eight sanitizer negatives, instrumented clone/enum/path and six
emitted-ASan owner/pointer/map/path programs pass. Threaded wait/poison/barrier
passes emitted TSan after detector probes. Pinned formatting/static analysis,
component boundaries and focused CTest pass, not race freedom or area closure.

Generic proof elaboration now creates solvers only for actual equality/Unpin
obligations, avoiding recursive reconstruction without removing proofs. At the
unchanged 60 s bound: seven numeric cases and eight generic-default/equality/
Unpin positives pass both profiles; eight contextual/recursive/equality negatives
reject. Compiler sanitizers pass operators, three equality/Unpin positives and
the eight negatives; incremental builds, detectors and targeted quality pass.
Minimal source-visible NonNull and lazy pointer loading are covered under S006;
most NonNull operations and remaining prerequisites stay open.

### Further operation batch

Historical macOS ARM64 focused evidence; no whole-area/operation closure:

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

Historical borrowed-chain blocker: the standalone two-Once case failed in
`Chained.next`, independently of folds; direct slice folds did not cover it.
The later regional integration has focused chaining passes (Current integration
state); full operation/frozen-input qualification remains open.

## Known gaps to fix first

Finish LNX (implementation-plan section 8.0), review every Darwin-inapplicable
record for Linux and close the handoff prerequisites. Closure trim patterns,
owned Text, borrowed chaining, bounds/exact/fused protocols, minimal NonNull and
collision-safe identity are integrated with scoped evidence, not missing
mechanisms or full-area passes. Reconcile all selected operations/source cfg.

Then close areas in order: collections/entries/drain; adapters; text/char;
owners/cells; sync/atomics/mpsc; hosted fs/io/process/net/env/time/thread;
macros; mem/ptr.

## Compiler changes
You may change the compiler (compiler/**, runtime C++) when a V1 operation needs
it. Follow the C++ compiler scope in docs/implementation-plan.md section 8:
V1-required features and correctness/soundness fixes only, no C++-only tuning
or refactors. Keep the component boundaries in CMake, format with
the pinned clang-format, and add a focused source run/fail regression for each
compiler fix. Never weaken an API or a test to avoid a compiler fix.

Remaining compiler follow-up: diagnose sanitized hosted-std compile time
(~37 s versus a 30 s probe bound; Release ~2.7 s) before changing anything.
Unsuffixed library index inference is integrated in the Linux batch, not a
missing feature.

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
  - No commits are authorized for the current lanes; the owner merges.

## Commands
Orchestrator only; run from the repository root. Lanes do not execute commands.

- **Build:**
  `.tools/linux-x86_64/cmake/bin/cmake --build build/linux-x86_64/Release`
  (configure once with the command in README "Linux host build")
- **Source suites:**
  `python3 tests/source.py run build/linux-x86_64/Release/mettle build/library-source-out`
  and the same command with `fail` instead of `run`.
- **Std programs:**
  `python3 tests/std.py build/linux-x86_64/Release/mettle build/library-std-out tests/std`
- **Full suite:**
  `.tools/linux-x86_64/cmake/bin/ctest --test-dir build/linux-x86_64/Release -j2`
- **Sanitizers:** for memory or unsafe changes, compile the program with
  `--sanitize address`. For threads and sync, use `--sanitize thread`.
  `--sanitize undefined` is rejected by design.

Run focused tests while iterating; full runs require the owner gates above.
