# Library naming review: proposal

Status: proposal only. No source, test or ledger file has been changed. Rule
applied: i13-library.md "Mettle must not read like a Rust copy: use native names
and syntax, and never add a second compatibility copy of a type." Decision D21
(library-surface.md section 9) is the existing native table; this proposal
extends it and needs an owner amendment of that table before any batch lands.

## How counts were taken

Counts are `grep -rIoE '\bNAME\b'` match totals (not distinct files), excluding
`__pycache__`.

- lib: `library/**/*.mt`, including definitions, call sites, comments and imports.
- tests: `tests/**` (`.mt`, `.py`, `.md`).
- ex: `examples/**` (all text). Zero for every name below unless stated.
- docs: `docs/**/*.md` excluding `docs/baseline/`.
- ledger: lines of `docs/baseline/v1-operations.csv` matching the name. These rows
  carry `mettle_path` and `evidence_test`, so a rename edits them (the Rust
  identity stays the catalog key, per baseline-mapping.md).
- code: `bootstrap/**` and `tools/**` (`.cpp`, `.h`, `.py`).

Caveats. Method names are matched by word, so definitions of same-named methods
on unrelated types are included (for example `or_panic` counts Option and Outcome
together; `as_ref` also counts the `AsRef` interface). `tests` for `or_panic` is
dominated by the `expect-error:` fixture directive and is unusable; `ok` and
`err` are too generic to count by word, so call counts (`.ok(`, `.err(`) are
given instead. Per-name call-site counts that cannot be separated are marked
"mixed". Every batch ends with a mechanical rewrite plus a ledger/doc edit; none
needs new tests, because each is a pure rename covered by the existing
operation tests (a rename test would be bookkeeping, forbidden by AGENTS.md).

## Findings that shape the proposal

1. The language already names the owner forms natively: `heap T`, `shared T`,
   `local shared T`, `weak T`, `local weak T`, `pinned heap|shared|local shared T`
   (language-grammar.md section 3). `bootstrap/types/type.cpp` `ownerSpelling`
   prints `alloc::boxed::Box` as `heap`, `alloc::arc::Arc` as `shared`,
   `alloc::rc::Rc` as `local shared`. So `Box`, `Arc`, `Rc` are only the nominal
   library paths behind native syntax, and they are the sole spelling users meet
   when they need an explicit allocator (`Box<T, A>`; 224 two-parameter uses of
   Box/Arc/Rc in library and tests).
2. `Box`, `Rc`, `Arc`, `Weak`, `Pinned` (both `alloc::boxed|rc|arc::`),
   `Cell`, `RefCell`, `Ref`, `RefMut`, `UnsafeCell`, `MaybeUninit`,
   `ManuallyDrop`, `PhantomPinned` and `Pin` are matched by spelling in the
   bootstrap compiler (`regions.cpp`, `type.cpp`, `machine_types.cpp`, 22
   `"alloc::..."` and about 30 `"core::..."` literals). Renaming any of them is a
   library plus compiler change; V1-required rule in AGENTS.md ("Until I15")
   applies, so those batches need owner approval as a V1 naming decision.
3. The library already contains Rust/native duplicates, which is the clearest
   violation of the "no second copy" rule and the cheapest to fix:
   - `core.num.from_str_radix` is a pass-through to `parse_radix`
     (num.mt:2832).
   - `Outcome` has both `unwrap_err`/`expect_err` and `failure_or_panic`/
     `failure_or_panic`.
   - `T?` and `Outcome` have both `as_view` and `as_ref` with identical bodies.
   - `String` has both `as_str` (string.mt:88) and `as_text` (string.mt:500).
   - Two parse interfaces: `core.text.FromStr` (`from_str`, char/float/bool/int
     `from_str`) and `core.num.FromText` (`from_text_radix`).
4. Mixed vocabulary on `Outcome`: `is_success`/`is_failure` but `is_ok_and`,
   `is_err_and`, `ok`, `err`, `map_failure`, `inspect_err`. `T?`: `is_present` but
   `is_some_and`, `then_some`.

## Summary table

Counts are lib / tests / docs / ledger rows (examples are 0 throughout).
"Needs compiler" means bootstrap spelling tables change.

| # | Current | Proposed | lib | tests | docs | ledger | Batch | Needs compiler |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `is_some_and` | `is_present_and` | 1 | 4 | 2 | 1 | B1 | no |
| 2 | `is_ok_and` / `is_err_and` | `is_success_and` / `is_failure_and` | 1 / 1 | 4 / 4 | 2 / 2 | 2 / 2 | B1 | no |
| 3 | `then_some` | `then_present` | 1 | 5 | 3 | 1 | B1 | no |
| 4 | `map_failure` | `map_failure` | 3 | 13 | 3 | 3 | B1 | no |
| 5 | `inspect_err` | `inspect_failure` | 1 | 4 | 2 | 2 | B1 | no |
| 6 | `unwrap_err`, `expect_err` | merge into existing `failure_or_panic`, `failure_or_panic` | 3 / 1 | 15 / 3 | 3 / 3 | 1 / 1 | B1 | no |
| 7 | `from_str_radix` (free fn) | delete; use `parse_radix` | 2 | 673 | 1 | 12 | B1 | no |
| 8 | `T?`/`Outcome` inherent `as_ref` | delete; keep `as_view` | 2 defs | mixed | mixed | 8 | B1 | no |
| 9 | `String.as_str` | delete; keep `as_text` | 4 defs total of `as_str` (1 on String) | mixed | mixed | 5 | B1 | no |
| 10 | `Outcome.ok()` / `err()` | `success_value()` / `failure_value()` | 1 def each | 3 / 3 calls | 4 / 2 | 2 / 4 | B2 | no |
| 11 | `or_failure` / `or_failure_with` | `or_failure` / `or_failure_with` | 2 / 2 | 7 / 6 | 3 / 3 | 2 / 3 | B2 | no |
| 12 | `or_panic` | `or_panic` | 54 | 367 | 7 | 3 | B3 | no |
| 13 | `or`, `_else`, `_default` | `value_or`, `value_or_else`, `value_or_default` | 2 / 2 / 2 | 5 / 6 / 6 | 4 / 4 / 4 | 4 / 2 / 3 | B3 | no |
| 14 | `unwrap_unchecked`, `unwrap_err_unchecked` | `value_unchecked`, `failure_unchecked` | 2 / 1 | 3 / 2 | 5 / 2 | 2 / 2 | B3 | no |
| 15 | `push_str` | `push_text` | 38 | 34 | 1 | 1 | B4 | no |
| 16 | `write_str` (`fmt.Write`) | `write_text` | 280 | 42 | 1 | 4 | B4 | no |
| 17 | `FromStr` / `from_str` | `FromText` / `from_text` (after renaming num `FromText` to `FromTextRadix`) | 24 / 16 | 46 / 30 | 4 / 0 | 27 / 1 | B4 | no (1 code ref) |
| 18 | `to_str` (CStr/OsStr/Path) | `to_text` | 10 | 42 | 2 | 6 | B4 | no |
| 19 | `Descending` | `Descending` | 18 | 42 | 4 | 29 | B5 | no |
| 20 | `Condition` | `ConditionVariable` | 13 | 8 | 3 | 18 | B5 | no |
| 21 | `Cow` (slice alias) | `BorrowedOrOwnedSlice` | 5 | 58 | 14 | 0 (catalog row key is Rust) | B5 | no, needs D31 amendment |
| 22 | `Box` | `Heap` | 250 | 1281 | 28 | 196 | B6 | yes |
| 23 | `Arc` | `Shared` | 216 | 158 | 20 | 142 | B6 | yes |
| 24 | `Rc` | `LocalShared` | 146 | 101 | 13 | 137 | B6 | yes |
| 25 | `RefCell` / `Ref` / `RefMut` | `CheckedCell` / `CheckedRead` / `CheckedMut` | 27 / 13 / 13 | 109 / 33 / 21 | 15 / 6 / 9 | 61 / 33 / 33 | B7 | yes |

Counts for rows 22-24 include the `into_boxed_*` sibling names only where noted
below; those are separate rows (`into_boxed_str` 1/3/1/1, `into_boxed_slice`
13/10/1/2, `into_boxed_path` 7/2/0/1 lib/tests/docs/ledger).

## Batches (one commit each, ordered by value/risk)

### B1. Delete duplicates and finish the success/failure/present vocabulary

Highest value, lowest risk. Library-only, no compiler change, no behavior change.
Total touched: roughly 25 library lines and about 750 test mentions (673 of them
the single `from_str_radix` to `parse_radix` rewrite).

- Rows 1-9. Why: each name either reuses Rust's `some`/`ok`/`err` words next to a
  sibling already renamed (`is_present`, `is_success`, `is_failure`), or is a
  second copy of an existing native operation (`parse_radix`, `failure_or_panic`,
  `as_view`, `as_text`). Rewrites are exact; no semantic change.
- Conflicts checked: `is_present_and`, `is_success_and`, `is_failure_and`,
  `then_present`, `map_failure`, `inspect_failure`: no existing definition or
  use anywhere in library/tests/docs. `failure_or_panic`/`failure_or_panic` already
  exist (2 mentions each), so row 6 deletes the `_err` pair rather than
  renaming. `then_present` mirrors the `present(...)` constructor.
- Row 8 caveat: `as_ref` as a call on options cannot be separated from the
  retained `AsRef` interface method (mixed: lib 93, tests 108). Delete only the
  inherent definitions in option.mt and outcome.mt, then fix the call sites the
  compiler reports. `as_mut` stays (no `as_view_mut` is warranted).
- Ledger/docs: baseline-mapping.md lines for `option::Option::is_some_and`,
  `then_some`, `result::Result::...` change from "Same member names" to the new
  names; native-value-contracts.md tables follow.

### B2. Option/Outcome conversions

Small blast radius (call sites: tests only, 3 to 7 each).

- Row 10: `ok()` to `success_value()`, `err()` to `failure_value()`. Why: `ok`/`err`
  name Rust constructors that Mettle spells `success`/`failure`. Not `ok()`
  or `err()` because they would shadow the constructors in reading and
  pattern position. `success_value`/`failure_value` appear only as test local
  variable names (6 and 10 mentions) so a method of that name is safe; shadowing
  a local with a method is not possible.
- Row 11: `or_failure(e)` to `or_failure(e)`, `or_failure_with(f)` to `or_failure_with(f)`.
  Why: names the result (`Outcome` failure) instead of `Ok`. No collision with
  `or`/`or_else` (which still mean option-or).

### B3. Extraction vocabulary: `or_panic` family (largest call-site count; decide as a unit)

Rename the whole family together or not at all; a half-renamed set is worse than
either.

- `or_panic()` to `or_panic()`; `or*` to `value_or*`; `unwrap_unchecked` to
  `value_unchecked`; `unwrap_err_unchecked` to `failure_unchecked`;
  `failure_or_panic` to `failure_or_panic` (it is the surviving form after B1).
  `or_panic(message)` and `failure_or_panic(message)` stay (see keep-list).
- Why: "or_panic" is Rust wrapper jargon with no meaning once `T?` and `Outcome`
  are plain language forms. `or_panic` states the failure mode at the call site
  and pairs with `value_or`; `value_or` is the established name in C++
  `std::optional` and reads as plain English.
- Cost: `or_panic` 54 lib / 367 tests / 7 docs / 3 ledger / 7 code (the 7 code hits
  are `tools/` and test-runner strings; panic message text
  "called `or_panic` on an absent value" must change with it, and tests asserting
  that message need the matching edit). This is the single largest rewrite in
  the proposal; if the owner prefers to defer, B1, B2 and B4 are independent of it.
- Conflicts: `or_panic`, `value_or*`, `value_unchecked`, `failure_unchecked` are
  all unused today. Do not use bare `value()` (collides with the public `value`
  fields of `Descending`/`Wrapping` in reading and with the `value` pattern binders).
- Related, optional: `Rc/Arc.try_unwrap` to `try_into_inner` (lib 5, tests 12,
  docs 2, ledger 4) and `unwrap_or_clone` to `into_value_or_clone` (2/6/1/4).
  Weaker case: Rust-derived but short and descriptive; do only with this batch.

### B4. `str` to `text` (Mettle has no `str`; the type is `Text`)

Library already uses `Text`, `as_text`, `from_text`, `copy_text`, `FromText`.
Left-over `str` members read as Rust.

- `push_str` to `push_text`; `write_str` to `write_text`; `to_str` to `to_text`.
  Why: the argument type is `Text`; sibling names already use `text`.
- `FromStr`/`from_str` to `FromText`/`from_text`. Blocking conflict: `core.num`
  already defines `FromText` (static `from_text_radix`). Sequence: (1) rename
  the num interface to `FromTextRadix`, (2) rename `FromStr` to `FromText`.
  Second conflict: `String` has an inherent `static fn from_text(read Text)` that
  returns `String` without throwing, while the interface method throws
  `Self.Error`; the `FromText` impl for `String` (string.mt:944) must call a
  renamed inherent (suggest the existing `copy_text`) or the inherent is
  removed. Resolve before starting; this row is the only one in B4 that needs
  design, so it may be split into its own commit.
- `write_str` is the `core.fmt.Write` method; library-surface.md section 9 keeps
  the interface name `core.fmt.Write`, not the method name, so the method may be
  renamed. 280 library hits are mostly `f.write_str(...)` inside `fmt` impls;
  mechanical.
- Not proposed here: `from_utf8_lossy`, `from_utf8`, `Utf8Error`,
  `FromUtf8Error`, `to_string_lossy`, `as_mut_str`, `into_boxed_str`.
  They name a concrete encoding (UTF-8, correct, not Rust-specific) or follow the
  `Box` rename; revisit `as_mut_str` (8/5/0/1) and `into_boxed_*` (see B6) with
  the batch they depend on.

### B5. Two standalone type renames and one alias

- `core.cmp.Descending` to `Descending`. Why: `Descending` (comparison wrapper) and
  `core.iter.Reversed` (adapter) differ by two letters and mean different things.
  `Descending` says what the wrapper does for sort/heap order. Zero existing
  uses of the new name.
- `std.sync.Condition` to `ConditionVariable`. Why: abbreviation with no
  precedent in the Mettle table; the table spells words out (`BufferedReader`,
  `OwnedIterable`, `SortedMap`). Methods (`wait`, `notify_one`, `notify_all`)
  stay.
- `alloc.borrow.BorrowedOrOwned<region r, [T]>` alias to `BorrowedOrOwnedSlice<region r, T>`.
  Why: D21/D31 already provide the native `BorrowedOrOwned`; an alias spelled
  with a Rust nickname is the second spelling the working rule forbids. Needs
  owner amendment of library-surface.md section 9 (the table currently lists
  the alias as `BorrowedOrOwned<region r, [T]>`) and 58 test mentions are mechanical. If the
  owner wants the alias retained for catalog identity, keep `Cow` and skip this row.

### B6. Owner nominal types (needs compiler change and owner approval)

- `Box` to `Heap`, `Arc` to `Shared`, `Rc` to `LocalShared`. Modules
  `alloc.boxed`, `alloc.arc`, `alloc.rc` to `alloc.heap`, `alloc.shared`,
  `alloc.local_shared`; the `Weak` and `Pinned` types stay in their modules.
- Why: the language syntax is already `heap T`, `shared T`, `local shared T`, and
  the compiler already prints those names in diagnostics. Making the nominal path
  `Heap<T, A>` / `Shared<T, A>` / `LocalShared<T, A>` removes the only place the
  Rust names leak: explicit-allocator types, `Box<T, A>` and so on. `Weak` is
  kept because the keyword is `weak T`; `local weak` is the Rc form and
  `Weak` under module `local_shared` already disambiguates.
- Cost: `Box` 250/1281/28/196, `Arc` 216/158/20/142, `Rc` 146/101/13/137
  (lib/tests/docs/ledger) plus code: `bootstrap/semantics/regions.cpp:81-87`,
  `bootstrap/types/type.cpp:60-65` and about 22 `"alloc::boxed|arc|rc::..."`
  literals. Method names derived from the type
  (`into_boxed_slice`, `into_boxed_str`, `into_boxed_path`, `into_boxed_c_str`,
  `into_boxed_os_str`, `into_boxed_bytes`: 62 mentions in library/tests) would
  become `into_heap_slice`, ... in the same commit.
- Conflicts: `Shared` already exists as a private type in `std/sync/mpsc.mt`
  (`type Shared<T>`), 25 whole-word `Shared` mentions in lib are mostly comments;
  rename that private type (for example `Channel`) first. `Heap` has two prose
  mentions, no definitions; it does not clash with `BinaryHeap`. `LocalShared`
  is unused.
- Tests already write `heap T`/`shared T` in 224 sites and `Box<...>` in 1281
  mentions; the surface change is mostly sed over `Box<` and `Box.`.
- Risk: compiler change in the type printer and region machinery. Out of scope
  for I13 library-only work unless the owner classifies it as V1-required
  naming (AGENTS.md "Until I15"). Do last.

### B7. Cell family (needs compiler change; lowest priority)

- `RefCell` to `CheckedCell`, `Ref` to `CheckedRead`, `RefMut` to `CheckedMut`.
  `Cell`, `UnsafeCell`, `OnceCell` stay.
- Why: `Ref`/`RefMut` mimic Rust reference-guard names while Mettle's borrow
  vocabulary is `read`/`mut`; `Ref` is easily misread as a plain view. The type's
  defining property is that borrow rules are checked at run time.
- Conflicts: `ReadGuard`/`WriteGuard` already exist for `RwLock`, which is why
  they are not reused. `CheckedRead`/`CheckedMut` unused.
- Cost: `RefCell` 27/109/15/61, `Ref` 13/33/6/33, `RefMut` 13/21/9/33
  plus code 43/43/40 (bootstrap and tests/backend `machine` references; the
  matches are `AggregateKind::RefCell` enumerators plus
  `machine_types.cpp:111-114` spelling literals; only the string literals need to
  change). Methods `borrow()`/`borrow_mut()` stay (keep-list).
- Weakest case in the proposal; the name is a judgment call. Skip unless the
  owner wants the cell family to match the owner family renames.

## Keep list (already good; do not rename)

| Name | Why keep |
| --- | --- |
| `Weak` (alloc.arc/rc) | Plain English, matches the keyword `weak`; disambiguated by module. |
| `Pinned`, module `Pin` | `pinned T` is native syntax; `Pinned` is the owner's nominal form; `Pin` is a helper module, not a type. |
| `Cell`, `OnceCell`, `UnsafeCell` | Short, descriptive; `UnsafeCell` is compiler-recognized and reads as what it is. |
| `Mutex`, `RwLock`, `MutexGuard`, `Barrier`, `Once`, `OnceLock`, `PoisonError` | Universal OS/threading terms (POSIX, C++, Java). `OnceLock` pairs with `OnceCell` (same shape, thread-safe); renaming it alone would break that pair. `iter.Once` and `sync.Once` live in different modules. |
| `BorrowedOrOwned` | Already native (D21). |
| `Phantom`, `PhantomPinned` | `Phantom<T>` is already shortened from `PhantomData`; `PhantomPinned` is compiler-recognized with 75 test uses and no clearly better word. |
| `Wrapping`, integer `wrapping_*`, `checked_*`, `saturating_*`, `overflowing_*`, `algebraic_*` | Arithmetic-semantics vocabulary shared by C++/Swift/Zig-style libraries; compiler-owned intrinsics with about 27000 mentions; no `Saturating` type exists. |
| `Reversed`, `Mapped`, ... adapter names | Defined by the D21 table. |
| `NonNull`, `MaybeUninit`, `ManuallyDrop` | `NonNull` kept by the D21 table; the other two are accurate descriptive names and compiler-recognized. |
| `Duration`, `Instant`, `SystemTime` | Universal time vocabulary. |
| `PathBuf`, `OsStr`, `OsString`, `CStr`, `CString` | Names track platform concepts and Mettle already has `Path`; a rename adds no clarity. |
| `iter`, `iter_mut`, `into_iter` | They correspond exactly to the retained interfaces `Iterable`, `MutableIterable`, `OwnedIterable` (the `OwnedIterable` method is `into_iter`). Renaming the methods would decouple them from the interface names. |
| `or_panic(message)`, `failure_or_panic(message)` | Plain English assertion; the message argument makes the failure intent explicit; no better short word. |
| `map`, `map_or*`, `and_then`, `or_else`, `filter`, `flatten`, `zip`, `inspect`, `cloned`, `copied` | Method names unchanged by D21 for adapters; `and_then`/`map_or` are not Rust-only (Haskell/Kotlin style) and have no clearer replacement. |
| `as_mut`, `to_owned`, `into_owned`, `into_inner`, `as_deref*` | Tied to retained interfaces (`AsMut`, `ToOwned`, `OwnedType`) or conventional conversion prefixes (`as_`, `to_`, `into_`). |
| `with_capacity`, `reserve`, `shrink_to_fit`, `truncate`, `retain` | Descriptive. |
| `take` (escaped), `replace`, `swap`, `drop` | Mettle has a `take` parameter mode; the escaped method names are accurate and used in `core.mem`. |
| `borrow()`, `borrow_mut()` | Match Mettle's own borrow vocabulary; changing them would collide with `core.borrow.Borrow`/`BorrowMut` (16 `borrow` definitions). |
| `to_string`, `ToString`, `from_utf8*`, `Utf8Error` | Encoding-specific and non-Rust-specific; no better word. |
| `strong_count`, `weak_count`, `downgrade`, `upgrade`, `ptr_eq`, `get_mut`, `make_mut` | Clear single-meaning verbs; `retain()` replaces `clone()` already. |
| `Rc`/`Arc` `retain()` | Already native. |

## Cross-checks and conflicts summary

- No proposed new name is defined or used anywhere in library, tests, docs or
  examples (checked by whole-word grep) except the two flagged: `Shared`
  (private mpsc type, rename first) and `FromText` (num interface, rename first).
  `success_value`/`failure_value` appear as test local variable names only.
- No proposed name is a keyword (`heap`, `shared`, `weak`, `local`, `pinned`,
  `read`, `mut`, `take`, `capture`, `throws`, `success`, `failure`, `present`,
  `none`). `Heap`/`Shared` differ from keywords by case only; the grammar is
  case-sensitive, but diagnostics and docs must keep the keyword spelling for
  the syntax form and the capitalized spelling for the library path.
- `Descending`, `ConditionVariable`, `CheckedCell` do not collide with any type
  named in library-surface.md section 9 or in the I13 area list.
- Ledger and docs: each batch edits `docs/baseline/v1-operations.csv`
  `mettle_path` for the affected rows, `docs/process/baseline-mapping.md` member
  mapping rows (lines about 185-200 for Option/Result), and
  `docs/library/native-*-contracts.md` tables. Catalog keys stay the Rust
  identities; no operation is dropped.

## Recommended order and scope

B1 and B2 first (library-only, nearly free). B4 next (mechanical, one design
step for `FromStr`). B5 any time. B3 only with an explicit owner decision
(largest rewrite, but contained). B6 and B7 only if the owner approves a
compiler spelling change; do B6 before B7 and neither before I15 unless
classified V1-required.
