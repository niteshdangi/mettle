# I13 library work package

Repo: /Users/niteshkumar/Projects/mettle-lang, main at `940637d`. I01-I12 are
closed for the macOS ARM64 host and Darwin ARM64 target only. You own I13's
library work and the compiler changes it needs.

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

## `libs` continuation ledger (2026-10-31)

The owner requested work in this checkout, with Luna subagents, no worktrees
and no commits. Those instructions override the older Git directions above.
The acceptance inventory remains `baseline/v1-operations.csv`: 3,966 families,
3,964 missing and 2 not-applicable; source additions do not establish compiled
declarations or behavioral evidence. The table below tracks this continuation,
not the complete milestone. Existing changes to this work package are preserved.

| Task / owning files | Implementation state and remaining work | Required fixtures / verification |
| --- | --- | --- |
| Collections / `library/alloc/{vec,vec_deque,hash_map,btree,binary_heap}.mt` | Partial: mutable predicates, Map/Set custom builders, cross-builder comparison/algebra, defaults and Deque exact-size iterators added. Slice disjoint mutable access and additional trait contexts remain open. | `tests/source/run/i13-collections-*.mt`, `i13-hash-map-custom-builder-collisions.mt`; uncompiled. |
| Iteration and optional/outcome values / `library/core/{iter,slice,option,outcome}.mt` | Partial: Zip reverse alignment/length, adapter forwarding, stateful callbacks, optional insertion/zip, borrowed optional/outcome iteration and reverse slice splitting added. Optional slice/pin views, stable sorting and disjoint slice access remain missing. | Existing iterator, slice and optional/outcome `i13-*` fixtures extended; no current execution. |
| Text / `library/core/{text,char}.mt`, `library/alloc/string.mt` | Partial: UTF-8 buffer encoding returning mutable Text, mutable text operations, stateful TextPattern search/trim and borrowed ownership protocols added. Pattern-owning `*_by` split/match iterators (char or `char` predicate: `split_by`, `rsplit_by`, `splitn_by`, `rsplitn_by`, `split_terminator_by`, `rsplit_terminator_by`, `split_inclusive_by`, `matches_by`, `rmatches_by`, `match_indices_by`, `rmatch_indices_by`), `Text`/`String` `get_unchecked(_mut)`, and String `AddAssign`/`Add`/`ExtendItems<char>`/`FromItems<char>`/`From<char>` added. The existing Text-separator `split`/`matches` family still takes `Text` only; `FromStr`/`parse`, Clone/Debug/Send/Sync iterator rows and `Text` internal callers of `find` with a `read Text` argument need compiler review. | `i13-char-encode-utf8-*`, `i13-text-pattern-search-closures.mt`, `i13-string-borrowed-ownership.mt`, `i13-text-closure-split-*.mt`, `i13-text-get-unchecked-ranges*.mt`, `i13-string-operators-and-extend.mt`; source review only. |
| Owners / `library/alloc/{boxed,rc,arc}.mt` | Partial: empty weak handles, weak cloning and borrowing/default protocols added; Box shared pointer access made read-only. Owning pin APIs require compiler support. Downcast, non-null conversions and additional forwarding/conversion protocols remain open. | `tests/source/run/i13-empty-weak.mt`; empty raw round trips, live weak cleanup, ZST/alignment added; native cleanup and sanitizer execution required. |
| Comparison / `library/core/cmp.mt` | Partial: `Ord.min/max/clamp` defaults added and invalid clamp bounds now panic; remaining trait/type pairs require review. | `tests/source/run/i13-order-*.mt`; tie, boundary and invalid-bound cases uncompiled. |
| Numeric wrappers / `library/core/num.mt` | Partial: 31 missing Wrapping trait families have source implementations; integer-only operations use private concrete protocols for all twelve widths, avoiding unproved primitive operator bounds. Broader scalar/value inventory remains source-mapped only. | `tests/library/num.mt`, `i13-wrapping-div-zero-panics.mt`, `i13-wrapping-rem-zero-panics.mt`; width, signed MIN/-1 and shift-count cases unrun. |
| Hosted time / `library/std/time.mt` | Partial: checked subtraction, wall-clock constructors/accessors and checked range conversion added; full hosted inventory remains open. | `tests/std/time_basic.mt`; no native execution. |
| Hosted services / `library/std/{ffi,io,thread}.mt` | Partial: OsString leak, buffered accessors, OS error constructors, error variants and current Thread identity added. Error payloads, stream locks, metadata times and remaining I/O traits need implementation. | Existing hosted fixtures extended; error variants alone do not establish errno classification. |
| Synchronization / `library/std/sync` | Partial: lock/guard value protocols, poison-preserving exclusive access, consuming once initializers and mutable condition predicates added. TryIter now resumes after a temporary empty queue. Full guard/atomic/width inventory remains open, including atomic writer downgrade. | `tests/std/{sync_primitives,sync_channel,i13_lock_protocols,i13_lock_exclusive_poison,i13_once_consuming_initializers}.mt`; native race, panic and sanitizer evidence still required. |
| Memory/pointers and macros | Partial source audit: core memory/pointer intrinsics and fixtures exist, but `mem.take`, `ptr.eq` and `NonNull` remain missing. Standard macro/native-equivalence declarations and ManuallyDrop trait pairs require reconciliation; the procedural macro host API is not that inventory. | Existing source/probe infrastructure; implement missing APIs and identify native-equivalence fixtures before closure. |
| Source freeze | Open; depends on all implementation, acceptance-fixture and documentation tasks, including the complete operation inventory. | Do not begin the full qualification matrix until dependencies close. |
| Qualification | Blocked on the selected compiler host/toolchain. `tools.bootstrap.host_platform()` rejects Windows AMD64; no `.tools`, `build`, or compiler binary exists here. | Required macOS ARM64/Darwin build, CTest, source profiles, sanitizer and target/ABI checks remain unrun. |

The standalone module checker also fails on this Windows host because its
filesystem-relative paths use backslashes while the manifest uses slashes;
this is not evidence of a new compiler dependency violation. No toolchain or
target-scope change is authorized by this ledger.

### Request to finish at least 1,000 items

This target is still open. Four supplemental source inventories locate 2,021
distinct canonical IDs (660 collection rows, 476 hosted rows, 372 numeric/value
rows and 532 owner/text rows, with 19 overlaps). They mix preexisting source,
new source, partial implementations, missing APIs and compiler mappings; they
are not 2,021 completed implementations or behavioral receipts. The iteration
work additionally reviewed a 531-row area; that audit is incomplete and is not
included in the source-map total.

- [Collection source map](i13-collections-inventory.csv)
- [Hosted source map](i13-hosted-inventory.csv)
- [Numeric/value source map](i13-numeric-value-inventory.csv)
- [Owner/text source map](i13-owners-text-inventory.csv)

No 1,000-item completion is claimed. Newly written methods, repaired callback
contracts and trait pairs must be compiled and checked across their complete
applicable contexts before acceptance. Width instantiations are not counted as
independent folded families, and neither an auto-property nor a file/name match
closes an implementation obligation. Candidate fixture links identify source
only, not a passing call/assertion for every member of a row.

Review corrected ordinary division/shift semantics in the first Wrapping draft,
the UTF-8 encoder's return type, allocator defaults that unnecessarily required
Clone, and heuristic hosted fixture links. Condition-variable timeout handling
rechecks the predicate after reacquisition, matching the reference
[wait_timeout_while loop](https://doc.rust-lang.org/src/std/sync/poison/condvar.rs.html#390-410);
the low-level timeout flag alone does not determine the predicate result. None
of these source reviews substitutes for the blocked native checks above.

Implementation stopped at the owner's wrap-up request. All changes remain
uncommitted in `libs`; no worktree or compiler/runtime C++ changes were made.
The source-freeze and 1,000-item tasks remain open.

### Second `libs` batch (2026-10-31, subagents)

Seven source-only subagent passes, same constraints as above: no compiler,
worktree or commit, and no native execution. Every addition is implemented but
unverified; no CSV row moves out of missing. Counts stay at 3,966 families,
3,964 missing and 2 not-applicable.

| Area | Added (source and fixtures, unrun) | Open |
| --- | --- | --- |
| Slice | `get_disjoint_mut`, `get_disjoint_unchecked_mut`; `i13-slice-get-disjoint-mut.mt`. Stable `sort*` already exists in `alloc/vec.mt` (earlier "missing" wording was stale). | Optional slice/pin views; `List.get_disjoint_mut`; sort drop-count and panic fixtures. |
| Iterators | `Iterator.sum/product/min/max` methods; `Stepped` exact-size and bidirectional; `i13-iter-sum-extrema-stepped-reverse.mt`. | Adapter Clone/Debug/Default/Send/Sync (closure Clone unresolved); `FusedIterator`. |
| Text / String | `*_by` closure split/match iterators, `Text.get_unchecked(_mut)`, `String` `Add`/`AddAssign`/`ExtendItems`/`FromItems`/`From<char>`; six `i13-text-*`/`i13-string-*` fixtures. | The `Text`-separator `split`/`matches` family calls `find` with `read Text` into `mut P` (may not compile); `FromStr`/`parse`, iterator trait rows, `TryFrom`, `Drain`. |
| Owners | `downcast` on `Box`/`Rc`/`Arc<any Any>`; `Rc.as_ptr`, `Weak.as_ptr`, `Rc: Error`; `i13-owner-downcast.mt` (assumes `heap any Any` is `Box<any Any>` and `rc.new` coercion, unconfirmed). | `mem.take`, `ptr.eq`, `NonNull`, `Box` non-null conversions and forwarding impls, `ManuallyDrop` pairs: `mem`/`ptr`/`ManuallyDrop` are compiler intrinsics (`compiler/semantics/machine*.cpp`). Implemented-unverified (nothing compiled): `ptr.eq` is a compiler operation; `mem.take`, `NonNull` and the ManuallyDrop Clone/PartialEq/Eq/PartialOrd/Ord/Hash/Default/Debug/Deref/DerefMut impls are declared in `library/core/storage.mt` and reached through `core.mem.take`/`core.ptr.NonNull` by an alias in `Resolution::lookup` and the library mounter. Open: `NonNull.map_addr`, `NonNull` `From<&T>/<&mut T>` and niche layout for `Option<NonNull<T>>`. Fixtures: `tests/source/run/i13-ptr-eq-*`, `i13-mem-take-*`, `i13-nonnull-core-operations`, `i13-manually-drop-trait-pairs`, `tests/source/fail/machine-ptr-eq-requires-matching-pointees`. |
| Option / Outcome / float | `cloned`/`copied` for mut-view optionals and outcomes, `Outcome.or`, f32/f64 `algebraic_*`; `i13-float-algebraic-and-mut-optional-copies.mt` (`present(mut x)` syntax unproven). | Integer families are compiler-built (`compiler/types/machine.cpp`), coverage per row unchecked; float associated constants blocked by `consteval` rejecting floats; `to_int_unchecked`; cmp/hash/convert pairs unreviewed. |
| Sync | Debug/Display/Error for `PoisonError`, `TryLockError` and the mpsc error types; `Shareable` rwlock guards; `i13_sync_error_text.mt`. Atomics are compiler builtins (`machine-atomic-*`); remaining sync types already cover their rows. | `RwLockWriteGuard.downgrade` needs a `runtime/thread.cpp` primitive; `SendTimeoutError` error impls; race and sanitizer evidence. |
| Collections | `ExactSizeIterator` for hash Map/Set and sorted-map iterators; `From<[T; N]>` for List, Deque, LinkedList, Map, Set, SortedMap, SortedSet, BinaryHeap; `List.insert_mut/concat/join`, `PeekMut.pop`; LinkedList bidirectional exact-size iterators, `append/split_off/remove/retain/retain_mut/contains/extract_if`, `Cursor`/`CursorMut`; five `i13-collections-*` fixtures (some use unconfirmed `.into()` syntax). | Iterator `Default`; BTree range/`entry`; `splice`/`drain_sorted`; Deque Reader/Writer/BufRead; hash `Map` index; remaining trait contexts. |
| Hosted net/thread/ffi/time | `time`: derives, Add/Sub/Mul/Div and assign forms, `Duration` Debug; `net`: IP constants, Eq/Ord/Hash/Clone, bit operators and From conversions; `thread`: `ThreadId`/`Thread` derives; `ffi`: `CString`/`CStr` accessors and Clone/Default/Eq/Hash/Debug; tests `time_operators`, `time_overflow_panics`, `net_value_traits`, `ffi_cstring_traits`, `thread_id_traits`. | `FromStr` (no core interface); `CString.into_raw/from_raw` (no capacity handoff); `OsStr`/`OsString` traits; `Thread`/`Scope` Debug. Inventory CSV has no rows for these trait impls. |
| Hosted io | `Stdout/StderrLock` (no cross-thread exclusion), `Stdin.read_line/lines`; `i13-stdio-lock-and-lines.mt`. | `StdinLock` BufRead (shared buffer); `io::Error` payloads; errno classification. |
| Hosted fs/path/env/process | No edits: all listed operations already declared. Added `i13-fs-sync-clone-permissions.mt`. | `Metadata.accessed/created` need the C++ `mettle_rt_stat` extended. |

All seven passes are in; all remains unrun.

### Third `libs` batch, collections (2026-10-31)

Source only, unrun. Added: `BinaryHeap.drain_sorted`/`into_iter_sorted` with
exact-size iterators; `SortedMap: Index<Q>`; `Default` for hash-map owning
iterators and `DequeIntoIter`; `Writer`/`Reader`/`BufRead` for `Deque<u8>`
(in `library/std/io.mt`, since `alloc` cannot name std traits); fixtures
`tests/source/run/i13-collections-sorted-heap-index.mt` and
`tests/std/deque_io_pipe.mt`. Audit: BTree `range`/`range_mut`/`entry`/
`first_entry`/`last_entry`, `List.splice`, hash `Map: Index`, hash `get_disjoint_mut`
and `List` slice inheritance (`get_disjoint_mut`, `rsplit`) were already present;
the collections CSV rows for them are stale. Open: `Default` for slice-backed
iterators (needs `SliceIter` Default in `core/slice.mt`), BTree `splice`-style
bulk replace (not a Mettle V1 name), Send/Sync review rows, `FromStr`-free
remaining trait contexts.

### Owners/ffi/thread follow-up (2026-10-31, source only, unrun)

Added: `Box` Iterator/Bidirectional/ExactSize/Hasher/Future forwarding,
`FromItems`, `From<[T; N]>`, `TryFrom<Box<[T]>>` for fixed arrays,
`into_non_null`/`from_non_null(_in)` (coded against `core.ptr.NonNull<T>` with
`new_unchecked`/`as_ptr`; unresolved until the compiler type lands); Box
Reader/Writer/Seek/BufRead forwarding appended to `std/io.mt`; `Rc`/`Arc`
`<[T]>` `FromItems`, `From<[T; N]>`, `TryFrom`; `CString.into_raw/from_raw`;
`OsStr`/`OsString` Eq/Ord/Hash/Debug/Clone/Default/Borrow/AsRef/ToOwned/`From<String>`;
`CStr`/`CString` Ord; `Scope`/`JoinHandle`/`ScopedJoinHandle` Debug. Fixtures:
`i13-box-forwarding`, `i13-owner-downcast-zst-aligned`, `i13-rc-arc-slice-conversions`,
`ffi_raw_and_os_string_traits`, `thread_debug`. Still open: Box `Fn*` (callable
capabilities are language-level, not library interfaces), `AsMut` (no core
interface), `into_pin`/`pin`, `Arc<File>` Reader/Writer/Seek, `Rc<[T; N]>` from
`List`, ExtendItems on `Box`.

### Third `libs` batch (2026-10-31, ten subagents, compiler/runtime included)

Same constraints: nothing compiled or run, no commit, no worktree, counts in
`baseline/v1-operations.csv` unchanged (3,966 families, 3,964 missing, 2
not-applicable). Unlike earlier batches this one edits compiler and runtime C++,
which are the highest-risk changes: a blind error in `core` breaks every build.

| Area | Added (unrun) | Open / risk |
| --- | --- | --- |
| Compiler mem/ptr | `ptr.eq` in `compiler/types/machine.cpp` and `backend/llvm/lower.cpp`; `library/core/storage.mt` with `mem.take`, `NonNull`, `ManuallyDrop` Clone/Eq/Ord/Hash/Default/Debug/Deref; alias in `resolution/resolve.cpp`/`load.cpp`; tests incl. one fail case. | `NonNull` `map_addr`, `From<&T>`, `Option<NonNull>` niche; an error in `storage.mt` breaks all of `core`. |
| Numeric | Float `MAX/MIN/EPSILON/INFINITY/NAN/...` and integer `BITS` constants (`machine_types.cpp`, `numeric.cpp`); `bit_width`, `highest_one`, `carrying_*`, `borrowing_sub`, `checked_signed_diff`, signed `abs`; int `From`/`TryFrom` + `TryFromIntError`; `to_int_unchecked`. 289 audit rows appended to `i13-numeric-value-inventory.csv`. | Integer `format_into`, float `FromStr`, consteval float values, `clang-format` not run. |
| fs stat | `mettle_rt_stat` returns ten values (atime, Darwin birthtime); `Metadata.accessed/created`. | `i13-fs-metadata-times.mt` not registered anywhere. |
| RwLock | Own mutex/condvar rwlock replaces `pthread_rwlock_t`; atomic `downgrade`; `SendTimeoutError` impls. | Writer-waiting reader deadlock if a reader re-locks; race/sanitizer evidence. |
| io | `io::Error` is no longer `copy` (optional `heap any Any` payload, `get_ref/get_mut/into_inner/downcast`); 24 more errno mappings; `StdinLock: BufRead` over a global buffer with a runtime mutex. | Non-copy `Error` may break other uses; `static mut`/generic static `new<T>` unverified. |
| Collections | `BinaryHeap.drain_sorted/into_iter_sorted`, `SortedMap: Index`, iterator `Default`, `Deque<u8>` Reader/Writer/BufRead (in `std/io.mt`). BTree `range/entry`, `splice`, hash `Map: Index`, `get_disjoint_mut` were already present (CSV stale). | `SliceIter` `Default` (done in slice pass); Send/Sync review. |
| Macros / traits | `fmt.string`, `dbg`, more `Clone/Default/Ord/Hash` pairs, Message/Reverse fmt; macro mapping comment in `std/macros.mt`; five fixtures. | `Message` Clone/Copy, `ops.Range` rows, `matches` fixture; `make<(i32,u8,bool)>()` and `dbg` syntax unconfirmed. |
| Owners / ffi | Box iterator/Hasher/Future/Reader/Writer/Seek/BufRead forwarding, `FromItems`, array `From`/`TryFrom`, `into_non_null/from_non_null` (guessed `NonNull` API); Rc/Arc slice conversions; `CString.into_raw/from_raw`; OsStr/OsString and thread-handle traits. | Box `Fn*`, `AsMut` (no interface), `pin`/`into_pin`, `Arc<File>` I/O; `NonNull` API names must match `storage.mt`. |
| Slice / iter | `FusedIterator`, adapter `Clone/Default/Debug`, `SliceSplitMut` bidirectional, sort drop-count/panic test. | Whether closures can be `Clone` is unconfirmed; optional slice/pin views live in `option.mt`. |
| Text / parse | `core/from_str.mt` (`FromStr`, `parse`, `Text.parse_as`), `split`/`matches` no longer pass `read Text` to `mut P`, iterator Clone/Debug, `IndexRangeMut`, char<->int conversions, `TryFrom<List<u8>>` for `String`. | Literal-into-`mut P` `find` calls unproven; `Text.parse` not unified with `FromStr`; float parse rounding on slow path. |

Everything above is unverified. The first macOS ARM64 build must compile the
`core` library before any of it can be trusted; expect fixes after that run.
