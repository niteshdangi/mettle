# Capability coverage

## Baseline and evidence

Reference: Rust 1.99.1 stable, edition 2024, pinned source commit
`58cf8f9c35b355199727627d07ae34a4e2846d67`. The official source/documentation
archive hashes and reproduction instructions are in
[baseline/README.md](baseline/README.md) and
[baseline/sources.json](baseline/sources.json).

[capabilities.csv](capabilities.csv) assigns specification owners to all 107
requirements. Its `implementation_status` is the specification-freeze snapshot;
current progress belongs to the [implementation plan](implementation-plan.md)
and revision-bound receipts. Library declarations do not cover the separate
language/compiler/ABI/tooling requirements.

## Row interpretation

- `id`: persistent requirement identity, L001-L060, S001-S031, A001-A009, T001-T007.
- `rust_capability` / `mettle_direction`: capability and native design.
- `layer` / `phase`: dependency layer and earliest development phase, not a reduced V1 commitment.
- `status`: specified means a selected native contract exists, directly or by explicit frozen-baseline incorporation.
- `specification`: owning document/section links, separated by `|`.
- `implementation_status`: not_implemented at specification freeze; no current checking/execution evidence is implied by this snapshot.
- `required_evidence`: mandatory later positive/negative or integration evidence, not a passing result.

## Library operation inventory

The source-backed inventory records 35,345 public/documentation pages, 123,118
associated items and 82,270 implementation relations: 240,733 exposures/contexts.
It preserves reexports, runtime/const distinctions, experimental APIs, generated
properties and source cfg evidence. Counts are not independent stable APIs.
Exact classifications/canonical totals are in
[audit-summary.json](baseline/audit-summary.json).

The auditor verifies both archives and the complete extracted Rust library source
file set, enumerates case-sensitive archive names, and cross-checks every archived
all.html link. The validator checks declaration closure, reexport identity,
implementation/interface-member stability, native-rule assignments and named
conditional supporting protocols. Its result binds to the operation manifest
digest in [validation.json](baseline/validation.json).

[baseline-mapping.md](baseline-mapping.md) and
[library-surface.md](library-surface.md) specify recursive native operations,
standalone authority assignments and an explicit fallback for unmigrated
contracts. A contract assignment
does not mean its native declaration has compiled. Source cfg predicates retain
their enclosing module/macro context; unrendered applicable source branches are
still obligations. No executed all-target expansion or per-item native coherence
check is claimed.

Generate the I13 [worklist](baseline/v1-operations.csv) with
`python3 tools/v1_operations.py`. Latest ledger (2026-11-09): **8,988 evidenced,
399 declared, 3,903 missing, 5 not applicable** of 13,295 canonical records,
grouped into 2,442 operation and 2,309 implementation families. Subset/source-cfg
reconciliation and Linux applicability review remain open; the five Windows-only
exclusions were recorded on Darwin. Missing/unmapped is not proof of absent
code; declarations/name matches are not behavioral passes.

The 399 declared records include 384 conversion-blanket exposures and fifteen
callable-adapter Clone/ToOwned records awaiting per-type/profile evidence.
Focused unzip, conversion and adapter receipts, the unverified owner-conversion
ASan compile and Peekable projection blocker are recorded once in
[the work package](i13-library.md#handoff-start-here-in-a-new-session).
All eighteen library areas remain partial.

## Equivalence policy

Native syntax does not weaken the promised safe capability.
Do not silently require allocation, runtime checks, unsafe caller code, erased
types, weaker regions or weaker complexity where the equivalent baseline does
not. An actual conflict is a specification defect and reopens the documentation
gate; an unimplemented contract is an implementation failure.

Different defaults are intentional: ordinary non-Copy parameters borrow,
explicit take consumes even Copy sources, and shared handles move unless
explicitly retained. Compare programs requesting equivalent operations, not
superficially identical spelling.

## I13 macOS ARM64 acceptance inventory

Historical scope: macOS ARM64 compiler host/Darwin ARM64 target, source/fixture
inventory at `0eea2fa` with later recorded updates; the inventory itself ran no
builds/tests. Its receipts do not qualify Linux/Windows. Current `linux-x64`
gates and LNX are in implementation-plan section 8.0.

`E` means an implementation and a representative repository fixture are
present, with a macOS ARM64 pass recorded in the implementation plan or test
history; it does not mean every stable operation is closed. `P` means a
documented implementation or operation/profile gap remains. `U` means an
implementation exists but no macOS ARM64 pass is recorded for it; a reusable
fixture may already exist. `M` means no implementation was found. Evidence
paths are repository paths; source-negative cases are noted as such.
`tests/packages.py::name` names an existing integration test. The status of a
capability is not inferred from the frozen CSV's `implementation_status`.

| ID | State | Existing evidence | Owning implementation / remaining work |
| --- | --- | --- | --- |
| L001 | E | `tests/source/run/machine-integer-widths-literals-and-conversions.mt` | `compiler/types`; complete target-boundary composition remains I13. |
| L002 | E | `tests/source/run/overflow-checks-explicit-on.mt`; `tests/source/run/overflow-checks-explicit-off.mt` | `compiler/backend/llvm`; close every exceptional operand/width on the frozen inputs. |
| L003 | P | `tests/source/fail/machine-explicit-overflow-operations-preserve-width.mt`; `tests/source/run/i13-numeric-wrapping-operators.mt`; `tests/source/run/i13-numeric-wrapping-div-zero.mt`; `tests/source/run/i13-numeric-wrapping-rem-zero.mt`; `tests/source/run/i13-numeric-wrapping-div-assign-zero.mt`; `tests/source/run/i13-numeric-wrapping-rem-assign-zero.mt` | `compiler/types/machine.cpp`, `library/core/num.mt`; wrapping operators have all-width focused evidence and representative zero-divisor trap cases; complete the stable checked/wrapping/saturating/overflowing operation matrix. |
| L004 | E | `tests/source/run/short-circuit.mt` | `compiler/semantics`, `compiler/lowering`; retain no-effect evidence for all lazy forms. |
| L005 | P | `tests/source/run/machine-floating-ieee-rounding-and-saturating-casts.mt`, `i13-numeric-float-from-str-boundaries.mt`, `i13-format-float-precision.mt`, `i13-numeric-float-finite-bounds.mt`, `i13-numeric-float-constants-next.mt`, `i13-numeric-float-const-methods-next.mt`, `i13-numeric-float-const-boundaries.mt`, `i13-numeric-float-supporting-traits-next.mt`, `i13-numeric-float-from-impls-next.mt`, `i13-numeric-float-operators-next.mt`, `i13-numeric-float-to-string.mt`, `i13-to-string-formatting-error.mt` | Scoped parsing, precision, all 28 values and 92 const records retain their evidence. The 79-record supporting-trait batch passes native/compiler-ASan/UBSan generic dispatch, IEEE/assignment, conversion, unsized Text and formatting-failure checks. Unsized/Static Any, comparison default-Self and complete operation/profile closure remain open. |
| L006 | E | `tests/source/run/unicode-scalar-and-byte-literals.mt` | `compiler/syntax`; add no invalid-scalar/escape acceptance beyond the existing negative corpus. |
| L007 | E | `tests/source/run/generic-products-enums-aliases-and-owner-methods.mt` | `compiler/syntax`, `compiler/semantics`; one-element tuple and cleanup combinations remain operation-level checks. |
| L008 | E | `tests/source/run/fixed-array-rest-patterns-and-borrowed-subarrays.mt` | `compiler/semantics`, `compiler/instances`; close zero-length and all const-length combinations. |
| L009 | P | `tests/library/slice_iterable.mt`; `tests/source/run/i13-slice-stateful-callbacks.mt`; `tests/source/run/i13-slice-split-search-double-ended.mt`; `tests/source/fail/array-rest-does-not-permit-overlapping-mutation.mt` | `library/core/slice.mt`, `compiler/semantics`; stateful search/sort/split callbacks and partial-order sortedness have focused evidence; full stable slice operation and checked disjoint-split closure is outstanding. |
| L010 | E | `tests/source/fail/field-read-before-init.mt` | `compiler/semantics`, `compiler/cleanup`; complete construction/partial-init path matrix. |
| L011 | E | `tests/source/fail/sum-match-must-be-exhaustive.mt` | `compiler/semantics`, `compiler/backend/llvm`; finish layout and active-variant cleanup combinations. |
| L012 | E | `tests/source/fail/machine-union-read-requires-unsafe.mt`; `tests/source/run/machine-union-overlap-safe-write-and-delayed-initialization.mt` (ASan) | — |
| L013 | E | `tests/source/run/unit-never.mt` | `compiler/semantics`; check remaining divergent control-flow combinations. |
| L014 | E | `tests/source/run/machine-raw-pointers-and-unsafe-callable-capabilities.mt`; `tests/source/run/safe-function-item-coerces-to-unsafe-pointer.mt` | — |
| L015 | E | `tests/source/run/slice-metadata-reborrowing-and-unsized-tails.mt`; `tests/source/run/unsized-slice-and-tail-owners-preserve-metadata.mt` (ASan; heap/shared/local shared slices and struct tails) | Heap Text operation closure remains library work (docs/i13-library.md). |
| L016 | E | `tests/source/run/array-dynamic-zero-length-bound.mt`; `tests/source/run/array-layout-pointer-iteration-drop-closure.mt` | — |
| L017 | E | `tests/source/run/aliases-and-static-associated-functions.mt` | `compiler/resolution`; close the full alias identity/use matrix. |
| L018 | E | `tests/source/fail/no-implicit-numeric-widening.mt`; `tests/source/fail/no-implicit-retain-of-shared-owner.mt`; `tests/source/fail/no-implicit-borrow-to-owner-upgrade.mt` | Erasure requested by an expected type annotation is explicit. |
| L019 | E | `tests/source/fail/loop-use-after-move.mt` | `compiler/analysis`; extend move-use coverage across the operation corpus. |
| L020 | E | `tests/source/fail/alias-does-not-grant-copy.mt` | `compiler/semantics`, `compiler/analysis`; constructor/destructor edge matrix remains. |
| L021 | E | `tests/source/fail/immutable-exclusive-borrow.mt` | `compiler/analysis`; complete read-loan lifetime/alias closure. |
| L022 | E | `tests/source/fail/read-to-mut-reborrow.mt` | `compiler/analysis`; complete exclusive reborrow restoration cases. |
| L023 | E | `tests/source/run/mutable-array-rest-is-field-disjoint.mt` | `compiler/analysis`; close all projected/disjoint-place cases. |
| L024 | E | `tests/source/run/two-phase-method-receiver.mt` | `compiler/semantics`, `compiler/analysis`; complete receiver reservation/activation cases. |
| L025 | E | `tests/source/run/index-implementation-with-explicit-regions.mt` | `compiler/semantics`; multi-source results still need stable-operation closure. |
| L026 | E | `tests/source/fail/higher-ranked-callable-bound-rejects-monomorphic-pointer.mt` | `compiler/types`, `compiler/semantics`; complete universe/leak and callback cases. |
| L027 | E | `tests/source/fail/mutable-stored-region-remains-invariant.mt` | `compiler/types`; complete variance closure across nested view types. |
| L028 | E | `tests/source/fail/partial-initialization.mt` | `compiler/analysis`, `compiler/cleanup`; field cleanup evidence remains bounded to existing cases. |
| L029 | E | `tests/backend/cleanup_frame.py`; `tests/backend/cleanup_frame.cpp` | `compiler/cleanup`, `compiler/backend/llvm`; complete exit/failure cleanup traces. |
| L030 | E | `tests/source/run/direct-borrow-temporary-extension.mt` | `compiler/semantics`; complete call-vs-direct initializer lifetime table. |
| L031 | E | `tests/source/run/machine-cell-conflicting-exclusive-guard-panics.mt`; `tests/source/run/machine-cell-refmut-view-writeback.mt` (ASan) | — |
| L032 | E | `tests/source/run/machine-manual-take-and-uninitialized-explicit-destruction.mt` | `compiler/cleanup`; close panic/forget and repeated destruction cases under sanitizers. |
| L033 | E | `tests/source/run/machine-inline-pin-keeps-payload-and-destruction-address-stable.mt`; `tests/source/run/machine-structural-pin-projections-and-pinned-destruction.mt` (ASan) | — |
| L034 | E | `tests/source/run/capture-composes-across-expressions.mt` | `compiler/syntax`; finish the full grammar/precedence corpus. |
| L035 | E | `tests/source/run/sum-or-pattern-bindings.mt` | `compiler/semantics`; complete ownership-sensitive pattern forms. |
| L036 | E | `tests/source/fail/sum-match-must-be-exhaustive.mt` | `compiler/semantics`; complete guards and all variant forms. |
| L037 | E | `tests/source/fail/empty-range-pattern.mt` | `compiler/syntax`, `compiler/semantics`; finish alternative/range boundary combinations. |
| L038 | E | `tests/source/run/conditional-and-irrefutable-patterns.mt` | `compiler/syntax`, `compiler/semantics`; finish divergence/failure-path combinations. |
| L039 | E | `tests/source/run/loan-control-flow.mt` | `compiler/lowering`; finish nested labels and value-producing exits. |
| L040 | E | `tests/source/run/higher-ranked-function-pointers-closures-and-bounds.mt` | `compiler/types`, `compiler/semantics`; complete access-mode/call-contract cases. |
| L041 | E | `tests/source/run/capture-composes-across-expressions.mt` | `compiler/semantics`, `compiler/analysis`; finish capture escape and callable-mode cases. |
| L042 | E | `tests/source/fail/unused-generic-body-is-checked.mt` | `compiler/semantics`, `compiler/instances`; close all declared-specialization contracts. |
| L043 | E | `tests/source/fail/implementation-cannot-strengthen-generic-bounds.mt` | `compiler/semantics`; close the full unsatisfied-obligation matrix. |
| L044 | E | `tests/source/run/associated-families-and-typed-constants.mt` | `compiler/semantics`; finish equality/const/projection operation closure. |
| L045 | E | `tests/source/run/borrowed-parameter-captures-keep-views.mt`; `tests/source/run/async-mut-parameter-writes-reach-the-caller.mt` | — |
| L046 | E | `tests/source/run/constant-array-lengths-are-profile-independent.mt` | `compiler/consteval`, `compiler/instances`; finish value-parameter/layout combinations. |
| L047 | E | `tests/source/run/coherent-implementation-type-and-const-equality-selection.mt` | `compiler/semantics`; complete overlap/coherence cases. |
| L048 | E | `tests/source/run/generic-unsized-bound-dispatches-through-any.mt`; `tests/source/run/generic-mut-receiver-dispatches-through-any.mt`; `tests/source/run/heap-erased-owner-preserves-from-source.mt`; `tests/source/fail/erased-future-without-from-escapes-local.mt` | — |
| L049 | E | `tests/source/fail/opaque-return-paths-share-one-hidden-type.mt` | `compiler/semantics`; finish cross-package identity/capture evidence. |
| L050 | E | `tests/library/ops.mt` | `library/core/ops.mt`, `compiler/semantics`; complete compound-assignment single-evaluation closure. |
| L051 | E | `tests/source/run/two-phase-method-receiver.mt` | `compiler/semantics`; complete inherent/interface collision and explicit qualification cases. |
| L052 | E | `tests/source/run/async-fn-state-machine.mt` | `compiler/syntax`, `compiler/semantics`, `compiler/backend/llvm`; target/cancellation qualification remains. |
| L053 | E | `tests/source/run/async-heap-interface-methods-dispatch-through-any.mt`; `tests/source/fail/async-interface-erased-dispatch.mt`; `tests/source/fail/async-heap-erased-receiver-escapes-local.mt` | — |
| L054 | E | `tests/source/run/const-eval-*.mt`; `tests/consteval/target_width.cpp` | `compiler/consteval`; target width beyond the supported driver targets is covered only by checker unit evidence. |
| L055 | E | `tests/source/run/macro-declarative-expansion.mt`; `tests/source/run/macro-import-reexport.mt`; `tests/source/fail/macro-recursion-limit.mt`; `tests/source/fail/macro-import-ambiguous.mt` | `compiler/expansion`, `compiler/resolution`; macro import paths follow item import rules (module-relative, `super`). Verified macOS ARM64 Release at `0eea2fa`+macro fix. |
| L056 | E | `tests/packages.py::procedural_macro`; `tests/packages.py::procedural_macro_failure` | `compiler/expansion`, `compiler/driver`; per-package namespaces and attribute/derive procedural macros remain out of contract. |
| L057 | E | `tests/source/run/derive-default-and-manual-default.mt`; `tests/source/fail/derive-clone-non-clone-field.mt` | `compiler/expansion`, `compiler/semantics`; close all supported derive/attribute declaration forms. |
| L058 | E | `tests/source/run/cfg-target-and-feature.mt`; `tests/source/fail/cfg-unknown-predicate.mt` | `compiler/expansion`, `compiler/driver`; finish host/target/inactive-branch combinations. |
| L059 | E | `tests/source/run/restricted-visibility-enclosing-module.mt`; `tests/source/fail/restricted-*.mt`; `tests/modules.py` | `compiler/resolution`; restricted item/macro visibility verified macOS ARM64 Release. |
| L060 | E | `tests/packages.py::doc_writes_deterministic_html`; `tests/packages.py::doctests_run_isolated_examples` | `compiler/documentation`, `compiler/driver`; debugger support is separately tracked by T006. |
| S001 | E | `tests/library/option_outcome.mt`; `tests/library/nested_option_extraction.mt` | `library/core/option.mt`; finish nested presence and consuming-extraction operation closure. |
| S002 | E | `tests/library/option_outcome.mt`; `tests/library/nested_outcome_transpose.mt` | `library/core/option.mt`, `library/core/outcome.mt`; transpose verified on macOS arm64. |
| S003 | E | `tests/source/run/pinned-heap-owner-drop-and-unpin-access.mt`; `tests/source/run/pinned-shared-owners-retain-and-drop.mt`; `tests/source/fail/pinned-weak-handle.mt`; `tests/source/fail/pinned-erased-future-without-from-escapes-local.mt` | — |
| S004 | E | `tests/alloc/rc_weak.mt`; `tests/alloc/arc_weak.mt` | `library/alloc/rc.mt`; complete retain/weak/unique-extraction failure cases. |
| S005 | P | `tests/alloc/arc_weak.mt`; `tests/std/arc_races.mt`; `tests/source/run/i13-owner-shared-slices.mt`; `tests/source/run/i13-owner-weak-empty.mt`; `tests/source/run/i13-owner-weak-clone.mt`; `tests/alloc/i13_owner_weak_clone_allocator.mt`; `tests/alloc/i13_owner_arc_traits.mt` | `library/alloc/arc.mt`, `rc.mt`; slice initialization, weak cloning/expired counts, last-weak allocator layout and unsized value traits have focused native/emitted-ASan evidence; Arc-race regression passes emitted TSan; full operation matrix and target race/last-owner qualification remain. |
| S006 | P | `tests/alloc/vec_basic.mt`; `tests/alloc/stable_sort.mt`; `tests/std/collection_panic_safety_vec.mt`; `tests/modules.py::library-builtin-pointer-does-not-load-core`; `tests/source/run/i13-list-stateful-retain.mt`; `tests/source/run/i13-collection-stateful-callbacks.mt`; `tests/source/run/i13-list-operations.mt`; `tests/source/run/i13-list-cow-from.mt`; `tests/source/fail/list-element-view-blocks-list-push.mt` | `library/alloc/vec.mt`, `library/alloc/borrow.mt`, `library/core/ptr.mt`, `compiler/resolution/load.cpp`; stateful retain/dedup and callback/destructor unwind compaction have focused native and emitted-ASan evidence; List-owned operations (reserve/shrink/insert/remove/drain/splice/split_off/append/resize/dedup/sort/extract_if, accessors, raw pointers, `set_len`, `repeat`, `to_vec`) have result, boundary-panic and drop-count evidence. `AsRef/AsMut/Borrow/BorrowMut<[T]>`, List conversions, slice-Cow, cross-allocator comparisons, borrowed `ExtendItems<read T>`, and List-to-slice `starts_with` forwarding pass focused tests. The minimal `core.ptr.NonNull` (`new`, `new_unchecked`, `as_ptr`) now backs `List.from_parts`/`into_parts`; tests cover null rejection and pointer round-trip in Release and emitted ASan. The broader selected `NonNull` operation inventory remains missing. Natural `target.extend(source.iter())` passes both source profiles through argument-directed interface selection; genuine ambiguity remains rejected. Other slice-derived exposures remain with L009. |
| S007 | P | `tests/alloc/string_text.mt`; `tests/alloc/string_boundary_panic.mt`; `tests/source/run/i13-text-whitespace-splits-boundaries.mt`; `tests/source/run/i13-char-encode-utf16-buffer-too-small.mt` | `library/alloc/string.mt`, `library/core/text.mt`, `library/core/char.mt`; backward whitespace/UTF-16 iteration, ASCII whitespace and buffer-writing char UTF-16 have focused evidence; operation closure and current Unicode-table work remain. |
| S008 | P | `tests/alloc/hash_map.mt`; `tests/alloc/hash_collisions.mt`; `tests/source/run/i13-map-callbacks-stateful.mt`; `tests/std/collection_panic_safety_maps.mt`; `tests/source/run/i13-map-set-key-access-replace.mt` | `library/alloc/hash_map.mt`, `library/alloc/collections.mt`; stateful callbacks, panic recovery and non-Copy stored-key replacement/take/drop have focused native/emitted-ASan evidence; complete entry, collision, iterator and stable-operation closure remain. |
| S009 | P | `tests/alloc/btree_stress.mt`; `tests/alloc/sorted_entry.mt`; `tests/source/run/i13-sorted-map-callbacks-stateful.mt`; `tests/std/collection_panic_safety_maps.mt`; `tests/source/fail/btree-range-blocks-map-mutation.mt`; `tests/source/run/i13-map-set-key-access-replace.mt`; `tests/source/fail/i13-sorted-set-key-view-replace.mt` | `library/alloc/btree.mt`; stateful callbacks/rebalance, panic recovery and stored-key get/replace/take/drop have focused native/emitted-ASan evidence; live-key views reject replacement; range-bounded extraction needs native bounds and complete invalidation/operation closure remains. |
| S010 | P | `tests/alloc/deque_list.mt`; `tests/alloc/btree_heap.mt`; `tests/std/collection_panic_safety_vec.mt`; `tests/std/collection_panic_safety_heap.mt`; `tests/alloc/owned_collection_iteration_drops.mt`; `tests/source/run/i13-deque-stateful-retain.mt`; `tests/source/run/i13-collection-stateful-callbacks.mt`; `tests/std/deque_retain_panic.mt`; `tests/source/run/i13-collections-further-ops.mt` | `library/alloc/vec_deque.mt`, `linked_list.mt`, `binary_heap.mt`; stateful callbacks/heap unwind plus deque append/truncate/resize, linked split/Global append and defaults have focused native/emitted-ASan evidence; allocator-compatible linked append, complete operations and iterator/ownership closure remain. |
| S011 | P | `tests/library/iter.mt`; `tests/alloc/collection_iteration.mt`; `tests/alloc/bidirectional_iterator_adapters.mt`; `tests/alloc/iterator_adapter_drop_count.mt`; `tests/source/run/i13-coretraits-iter-followup.mt`; `tests/source/run/iterator-associated-item-through-callable-bound.mt`; `tests/source/run/mutable-view-interface-associated-result.mt`; `tests/source/run/i13-fold-distinct-input-output.mt`; `tests/source/fail/i13-fold-input-output-mismatch.mt`; `tests/source/run/i13-chained-carried-views.mt`; `tests/source/run/i13-iterator-exact-hints-reverse.mt`; `tests/source/run/i13-range-bound-contracts.mt`; `tests/source/run/i13-interface-bound-regional-proofs.mt`; `tests/source/run/i13-box-text-borrowed-parts.mt` | `library/core/iter.mt`; mutable-view reuse, owned filter+map drops, distinct folds, borrowed chaining, exact/fused hints and mixed-end traversal, and borrowed unsized range endpoints have focused profile evidence. Nested Box owned-iteration coherence and borrowed collection now pass focused regressions; current regional/associated normalization has instrumented positive/negative evidence. Unsized/erased iterator forwarding, complete operation inventory and frozen-input qualification remain. |
| S012 | P | `tests/library/fmt.mt`; `tests/library/num.mt`; `tests/source/run/i13-numeric-wrapping-value-format.mt` | `library/core/fmt.mt`, `num.mt`; wrapping delegation has all-integer-width focused evidence; F1 specifiers/Debug holes and complete stable formatting/parsing operations remain. |
| S013 | P | `tests/library/cmp_hash.mt`; `tests/alloc/collection_traits.mt`; `tests/source/run/i13-numeric-tuple-comparison-hash.mt`; `tests/source/run/i13-numeric-wrapping-value-format.mt`; `tests/source/run/i13-numeric-wrapping-folds.mt`; `tests/source/run/i13-numeric-wrapping-borrowed-folds.mt` | `library/core/cmp.mt`, `hash.mt`, `num.mt`; tuple arities 1-12, wrapping value traits and all-width owned/borrowed fold identities/overflow have focused evidence; complete stable comparison/hash/numeric trait closure remains. |
| S014 | P | `tests/alloc/failing_allocator.mt`; `tests/alloc/btree_alloc_failure.mt`; `tests/alloc/custom_allocator_owners_layouts.mt`; `tests/alloc/i13_owner_boxed_slice_allocator.mt`; `tests/alloc/i13_owner_shared_slice_allocator.mt`; `tests/alloc/i13_owner_weak_clone_allocator.mt` | `library/alloc/alloc.mt`; owner-slice and expired weak-clone allocation/layout/failure/drop checks pass; allocator compatibility, complete allocator and owner-path closure remain. |
| S015 | E | `tests/source/run/machine-cell-safe-exchange-and-exclusive-access.mt` | `library/core/borrow.mt`; raw safety, panic and forgetting qualification remains. |
| S016 | E | `tests/source/run/machine-manual-take-and-uninitialized-explicit-destruction.mt` | `library/core/` storage declarations; close partial-init, alignment and unwind cases. |
| S017 | E | `tests/backend/memory.py`; `tests/backend/machine.py` (atomic width/order/CAS matrix) | — |
| S018 | E | `tests/source/fail/manual-transferable-requires-unsafe.mt`; `tests/source/fail/transferable-unbounded-region-projection-rejected.mt` | — |
| S019 | P | `tests/std/threads_basic.mt`; `tests/std/thread_scope.mt`; `tests/std/i13_thread_next_operations.mt`; `tests/source/fail/i13-thread-handle-not-copy.mt`; `tests/source/fail/i13-thread-view-blocks-join.mt` | `library/std/thread.mt`, `runtime/thread.cpp`; non-Copy/Clone/value/Debug and borrowed-handle contracts pass focused native/emitted-TSan checks; full current/name/parallelism/panic-payload coverage, macOS stress and complete operation closure remain. |
| S020 | P | `tests/std/i13-sync-mutex-rwlock.mt`; `tests/std/sync_primitives.mt`; `tests/std/i13_sync_threaded_edges.mt`; `tests/source/fail/i13-sync-mutex-guard-not-transferable.mt` | `library/std/sync/mutex.mt`, `rwlock.mt`; poison-aware exclusive access and guard affinity have focused/emitted-TSan evidence; atomic downgrade and full operation closure remain. |
| S021 | P | `tests/std/sync_primitives.mt`; `tests/std/i13_sync_threaded_edges.mt` | `library/std/sync/condvar.mt`, `barrier.mt`, `once.mt`; mutable predicates/Duration/zero-deadline behavior pass focused/emitted-TSan checks; mutex association, full wake/failure and target stress closure remain. |
| S022 | E | `tests/std/channel_rendezvous_select_timeouts_iterator.mt` | `library/std/sync/mpsc.mt`; full target stress/TSan is not part of this lane and other targets are not qualified. |
| S023 | E | `tests/std/tls_static_init_and_exit_order.mt` | `library/std/sync/tls.mt`; reverse destruction-order and target qualification remain. |
| S024 | P | `tests/std/fs_basic.mt`; `tests/std/path_edges.mt`; `tests/std/i13_path_bytes_and_fs_failures.mt`; `tests/source/run/i13-path-components-ancestors.mt`; `tests/std/i13_fs_positional_io.mt` | `library/std/fs.mt`, `path.mt`, `ffi.mt`; byte-preserving mixed paths and positional I/O cursor/access/EOF/offset checks have focused native/emitted-ASan evidence; complete filesystem/OS-string operation closure remains. |
| S025 | P | `tests/std/net_loopback.mt`; `tests/std/net_ipv6.mt`; `tests/std/i13_net_address_roundtrip.mt`; `tests/std/i13_net_tcp_peek_incoming.mt` | `library/std/net.mt`, `sys.mt`; address parsing, TCP peek/fallible Incoming/nonblocking errors and UDP peer access have focused native/emitted-ASan evidence; async I/O remains unqualified and network operation closure is incomplete. |
| S026 | E | `tests/std/process_roundtrip.mt`; `tests/std/env_args.mt` | `library/std/process.mt`, `env.mt`; child cleanup and complete process/environment closure remain. |
| S027 | E | `tests/std/time_basic.mt` | `library/std/time.mt`; complete duration/clock overflow and adjustment closure remains. |
| S028 | E | `tests/std/panic_catch.mt`; `tests/std/panic_hook_abort.mt` | `library/std/panic.mt`; complete payload/hook/recovery failure closure remains. |
| S029 | E | `tests/library/slice_any_text.mt`; `tests/packages.py::type_id_survives_public_reexport` | `library/core/any.mt`; cross-package identity and erased-owner operation fixtures verified on macOS arm64. |
| S030 | E | `tests/std/async_executor.mt`; `tests/std/async_scope_borrowed.mt` | `library/core/future.mt`, `library/std/task.mt`; async-scope fixtures pass in `library.std` and under emitted ASan/TSan; independent soundness/race review found no blocking issues. |
| S031 | E | `tests/source/run/darwin-arm64-cfg-target-facts.mt`; `tests/source/run/machine-target-direct-guarded-vector.aarch64.mt` | — |
| A001 | E | `tests/backend/machine.py` (scalar, bool and `char` as `uint32_t` round trips and callbacks); `tests/backend/machine_callbacks.c` | — |
| A002 | E | `tests/backend/machine.py` (layout/calling probes); `tests/source/fail/machine-packed-fields-cannot-form-aligned-views.mt` | — |
| A003 | E | `tests/backend/machine.py` (symbol/link probes); `tests/source/run/machine-static-union-enum-and-nested-relocations.mt` | — |
| A004 | E | `tests/backend/machine_unwind.cpp`; `tests/backend/machine.py` | — |
| A005 | E | `tests/source/run/machine-asm-static-symbol-global-and-naked-entry.aarch64.mt`; `tests/backend/machine.py` | — |
| A006 | E | `tests/backend/machine.py` (NEON matrix: 20 shapes, 206 operations); `tests/backend/machine_vectors.c` | — |
| A007 | E | `tests/source/run/machine-pointer-provenance-volatile-and-layout.mt`; `tests/backend/machine.py` | — |
| A008 | E | `tests/backend/machine.py` (`machine-target-freestanding-no-services`) | `compiler/driver`, `runtime`; freestanding debug/release objects have no undefined service symbols and run linked to a C driver on macOS ARM64 (CTest `backend.machine`). |
| A009 | M | — | Owner-deferred to I17 (2026-10-31), not V1: optional Rust bridge package with explicit toolchain/ABI adapters (`tooling-and-packages.md` section 5), respecting the native ABI boundary (`library-and-abi.md` section 7). |
| T001 | E | `tests/packages.py::path_dependency`; `tests/packages.py::registry_resolution` | `compiler/packages`; complete remaining resolver conflict/offline/target-feature cases. |
| T002 | E | `tests/packages.py::build_script`; `tests/packages.py::build_script_untracked_inputs` | `compiler/driver/build_script.cpp`; finish declared-input/platform closure. |
| T003 | E | `tests/packages.py::incremental_reuse`; `tests/packages.py::object_cache_integrity` | `compiler/packages/store.cpp`, `compiler/driver/cache.cpp`; dependency-object reuse is verified on macOS arm64; front-end query separation and measurements move to I14 (owner decision 2026-10-31). |
| T004 | E | `tests/packages.py::fmt_normalizes_layout_only`; `tests/packages.py::lint_reports_semantic_findings` | `compiler/driver`; format/lint command evidence exists; close accepted source/profile combinations. |
| T005 | E | `tests/packages.py::language_server` | `compiler/lsp`; finish incremental diagnostics/rename closure. |
| T006 | E | `tests/packages.py::debug_info`; `tests/packages.py::debugger_workflow` | `compiler/backend/llvm/debug.cpp`, `tools/debug`; expanded workflow/LLDB checks pass on macOS arm64; Windows CodeView/PDB is excluded and not qualified. |
| T007 | E | `tests/packages.py::test_reports_pass_fail_ignored_and_isolates_panics`; `tests/packages.py::bench_reports_timing` | `compiler/driver/execute.cpp`; package-wide collection and doctest cases are evidenced; finish the remaining runner contract. |

Inventory totals: **88 evidenced, 18 partial, 1 missing (A009, deferred to
I17)**. Remaining partial rows are I13
operation-closure obligations. Full operation closure is a separate, still
open obligation: `docs/baseline/audit-summary.json` reports 106,125 canonical
required contracts, and the baseline explicitly says native declarations are
not typechecked and cfg branches are not compiled. No operation-wide macOS
ARM64 declaration/evidence receipt exists in this worktree. V1 requires only
the operation subset of `docs/library-surface.md` section 6.1 (about 2,900
folded operation families and 1,760 trait/type pairs); other applicable
non-deprecated obligations are I17. The 2026-11-09 owner amendment excludes
deprecated APIs and retains all reference profiles after V1. The
[reconciled worklist](post-v1-worklist.md) reports exact inventory partitions
and shared implementation units, not missing-code or qualified-profile totals. See
`docs/library-surface.md` sections 6–8 for applicability and required
supporting-protocol review; do not infer per-operation closure from the
capability-level fixtures above.

Acceptance has independent axes: expressibility, sound observable semantics
and measured runtime. A faster unsafe replacement cannot satisfy a safe API;
an equally expressive but slower implementation can fail the runtime gate.
The initial inventory and documentation checks establish none of these runtime
or safety results.

## Unstable-feature register

Not automatically committed: unrestricted overlapping specialization, generalized
const expressions beyond the stable baseline, custom auto traits, unrestricted
negative user-interface implementations and experimental coroutine APIs.
Nightly-only declarations remain visible in the inventory without becoming
stable native requirements.

Default/sealed/compiler-controlled helpers used by stable calls have explicit
[supporting-protocol mappings](library-surface.md#8-conditional-supporting-protocols).
Those mappings preserve valid stable uses, not every experimental implementation
right. Native negative thread properties, allocator control and borrowed scopes
remain accepted independently of similarly named Rust nightly features.

For additions, record a concrete use case, alternatives, interactions, cost,
runtime effects and acceptance. Rejected identity proposals do not expand scope.
