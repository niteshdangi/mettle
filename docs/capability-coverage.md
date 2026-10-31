# Capability coverage

## Baseline and evidence

Reference: Rust 1.99.1 stable, edition 2024, pinned source commit
`58cf8f9c35b355199727627d07ae34a4e2846d67`. The official source/documentation
archive hashes and reproduction instructions are in
[baseline/README.md](baseline/README.md) and
[baseline/sources.json](baseline/sources.json).

The specification has 107 capability requirements with explicit document/section
owners in [capabilities.csv](capabilities.csv). All are specified. Its
`implementation_status` fields retain the specification-freeze snapshot, not
current compiler progress; see the [implementation plan](implementation-plan.md)
and revision-bound qualification receipts for that evidence.
This is specification coverage, not a capability-parity score.
Language/compiler/ABI/tooling requirements are tracked separately from library
declarations; a std catalog alone cannot define a language.

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
unchanged semantics by reference, and explicit differences. A contract assignment
does not mean its native declaration has compiled. Source cfg predicates retain
their enclosing module/macro context; unrendered applicable source branches are
still obligations. No executed all-target expansion or per-item native coherence
check is claimed.

## Equivalence policy

Native syntax may replace Rust syntax, not the promised safe capability.
Do not silently require allocation, runtime checks, unsafe caller code, erased
types, weaker regions or weaker complexity where the equivalent baseline does
not. An actual conflict is a specification defect and reopens the documentation
gate; an unimplemented contract is an implementation failure.

Different defaults are intentional: ordinary non-Copy parameters borrow,
explicit take consumes even Copy sources, and shared handles move unless
explicitly retained. Compare programs requesting equivalent operations, not
superficially identical spelling.

## I13 macOS ARM64 acceptance inventory

Scope is the native macOS ARM64 compiler host and Darwin ARM64 target only.
Linux and Windows are excluded from this lane's gates by the owner and remain
not qualified. This is a source/fixture inventory at revision `0eea2fa`; no
compiler, library, fixture, or test runner was built or executed for this
inventory.

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
| L003 | P | `tests/source/fail/machine-explicit-overflow-operations-preserve-width.mt` | `compiler/types/machine.cpp`, `library/core/num.mt`; complete the stable checked/wrapping/saturating/overflowing operation matrix. |
| L004 | E | `tests/source/run/short-circuit.mt` | `compiler/semantics`, `compiler/lowering`; retain no-effect evidence for all lazy forms. |
| L005 | P | `tests/source/run/machine-floating-ieee-rounding-and-saturating-casts.mt` | `compiler/types`, `library/core/float.mt`; finish NaN, signed-zero, conversion, and per-operation policy closure. |
| L006 | E | `tests/source/run/unicode-scalar-and-byte-literals.mt` | `compiler/syntax`; add no invalid-scalar/escape acceptance beyond the existing negative corpus. |
| L007 | E | `tests/source/run/generic-products-enums-aliases-and-owner-methods.mt` | `compiler/syntax`, `compiler/semantics`; one-element tuple and cleanup combinations remain operation-level checks. |
| L008 | E | `tests/source/run/fixed-array-rest-patterns-and-borrowed-subarrays.mt` | `compiler/semantics`, `compiler/instances`; close zero-length and all const-length combinations. |
| L009 | P | `tests/library/slice_iterable.mt`; `tests/source/fail/array-rest-does-not-permit-overlapping-mutation.mt` | `library/core/slice.mt`, `compiler/semantics`; full stable slice operation and checked disjoint-split closure is outstanding. |
| L010 | E | `tests/source/fail/field-read-before-init.mt` | `compiler/semantics`, `compiler/cleanup`; complete construction/partial-init path matrix. |
| L011 | E | `tests/source/fail/sum-match-must-be-exhaustive.mt` | `compiler/semantics`, `compiler/backend/llvm`; finish layout and active-variant cleanup combinations. |
| L012 | P | `tests/source/fail/machine-union-read-requires-unsafe.mt` | `compiler/semantics`, `compiler/backend/llvm`; sanitizer/validity and overlapping-loan combinations remain open. |
| L013 | E | `tests/source/run/unit-never.mt` | `compiler/semantics`; check remaining divergent control-flow combinations. |
| L014 | P | `tests/source/run/machine-raw-pointers-and-unsafe-callable-capabilities.mt` | `compiler/types`, `compiler/backend/llvm`; target qualification for extent, alignment, provenance and validity is incomplete. |
| L015 | P | `tests/source/run/slice-metadata-reborrowing-and-unsized-tails.mt` | `compiler/types`, `compiler/backend/llvm`; metadata-preserving conversion/owner closure remains incomplete. |
| L016 | P | `tests/source/run/array-dynamic-zero-length-bound.mt`; `tests/source/run/machine-numeric-wide-bounded-array-count-and-zero-array-alignment.mt` | `compiler/types`, `compiler/cleanup`; combine layout, pointer arithmetic, iteration and destruction on the frozen input. |
| L017 | E | `tests/source/run/aliases-and-static-associated-functions.mt` | `compiler/resolution`; close the full alias identity/use matrix. |
| L018 | P | `tests/source/run/machine-numeric-checked-integer-and-floating-conversions.mt` | `compiler/semantics`; prove complete coercion closure without implicit retain, erasure or ownership upgrade. |
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
| L031 | P | `tests/source/run/machine-cell-conflicting-exclusive-guard-panics.mt` | `library/core/borrow.mt`, `compiler/semantics`; panic, forgetting, and safety closure remain. |
| L032 | E | `tests/source/run/machine-manual-take-and-uninitialized-explicit-destruction.mt` | `compiler/cleanup`; close panic/forget and repeated destruction cases under sanitizers. |
| L033 | P | `tests/source/run/machine-inline-pin-keeps-payload-and-destruction-address-stable.mt` | `compiler/types`, `compiler/semantics`; generic/projection/writeback and pinned-owner operation closure remains. |
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
| L045 | P | `tests/source/run/borrowed-parameter-captures-keep-views.mt` | `compiler/semantics`, `compiler/types`; complete lending-family region and operation closure. |
| L046 | E | `tests/source/run/constant-array-lengths-are-profile-independent.mt` | `compiler/consteval`, `compiler/instances`; finish value-parameter/layout combinations. |
| L047 | E | `tests/source/run/coherent-implementation-type-and-const-equality-selection.mt` | `compiler/semantics`; complete overlap/coherence cases. |
| L048 | P | `tests/library/slice_any_text.mt`; `tests/source/fail/async-interface-erased-dispatch.mt` | `compiler/semantics`, `compiler/backend/llvm`; explicit erased async-future dispatch remains unsupported; complete unsized/associated-binding closure. |
| L049 | E | `tests/source/fail/opaque-return-paths-share-one-hidden-type.mt` | `compiler/semantics`; finish cross-package identity/capture evidence. |
| L050 | E | `tests/library/ops.mt` | `library/core/ops.mt`, `compiler/semantics`; complete compound-assignment single-evaluation closure. |
| L051 | E | `tests/source/run/two-phase-method-receiver.mt` | `compiler/semantics`; complete inherent/interface collision and explicit qualification cases. |
| L052 | E | `tests/source/run/async-fn-state-machine.mt` | `compiler/syntax`, `compiler/semantics`, `compiler/backend/llvm`; target/cancellation qualification remains. |
| L053 | P | `tests/source/run/async-blocks-and-closures.mt`; `tests/source/fail/async-interface-erased-dispatch.mt` | `compiler/syntax`, `compiler/semantics`; erased interface future storage/dispatch is explicitly unsupported. |
| L054 | E | `tests/source/run/const-eval-*.mt`; `tests/consteval/target_width.cpp` | `compiler/consteval`; target width beyond the supported driver targets is covered only by checker unit evidence. |
| L055 | E | `tests/source/run/macro-declarative-expansion.mt`; `tests/source/run/macro-import-reexport.mt`; `tests/source/fail/macro-recursion-limit.mt`; `tests/source/fail/macro-import-ambiguous.mt` | `compiler/expansion`, `compiler/resolution`; macro import paths follow item import rules (module-relative, `super`). Verified macOS ARM64 Release at `0eea2fa`+macro fix. |
| L056 | E | `tests/packages.py::procedural_macro`; `tests/packages.py::procedural_macro_failure` | `compiler/expansion`, `compiler/driver`; per-package namespaces and attribute/derive procedural macros remain out of contract. |
| L057 | E | `tests/source/run/derive-default-and-manual-default.mt`; `tests/source/fail/derive-clone-non-clone-field.mt` | `compiler/expansion`, `compiler/semantics`; close all supported derive/attribute declaration forms. |
| L058 | E | `tests/source/run/cfg-target-and-feature.mt`; `tests/source/fail/cfg-unknown-predicate.mt` | `compiler/expansion`, `compiler/driver`; finish host/target/inactive-branch combinations. |
| L059 | E | `tests/source/run/restricted-visibility-enclosing-module.mt`; `tests/source/fail/restricted-*.mt`; `tests/modules.py` | `compiler/resolution`; restricted item/macro visibility verified macOS ARM64 Release. |
| L060 | E | `tests/packages.py::doc_writes_deterministic_html`; `tests/packages.py::doctests_run_isolated_examples` | `compiler/documentation`, `compiler/driver`; debugger support is separately tracked by T006. |
| S001 | E | `tests/library/option_outcome.mt`; `tests/library/nested_option_extraction.mt` | `library/core/option.mt`; finish nested presence and consuming-extraction operation closure. |
| S002 | E | `tests/library/option_outcome.mt`; `tests/library/nested_outcome_transpose.mt` | `library/core/option.mt`, `library/core/outcome.mt`; transpose verified on macOS arm64. |
| S003 | P | `tests/source/run/native-heap-owner.mt`; `tests/alloc/box_rc_traits.mt` | `library/alloc/boxed.mt`; unsized owner payloads and pinned owning handles are unsupported. |
| S004 | E | `tests/alloc/rc_weak.mt`; `tests/alloc/arc_weak.mt` | `library/alloc/rc.mt`; complete retain/weak/unique-extraction failure cases. |
| S005 | P | `tests/alloc/arc_weak.mt`; `tests/std/arc_races.mt` | `library/alloc/arc.mt`; full operation matrix and current target race/last-owner qualification remain. |
| S006 | P | `tests/alloc/vec_basic.mt`; `tests/alloc/stable_sort.mt`; `tests/std/collection_panic_safety_vec.mt`; `tests/source/fail/list-element-view-blocks-list-push.mt` | `library/alloc/vec.mt`; complete reserve/insert/drain/invalidation closure. |
| S007 | P | `tests/alloc/string_text.mt`; `tests/alloc/string_boundary_panic.mt` | `library/alloc/string.mt`, `library/core/text.mt`; operation closure and current Unicode-table work remain. |
| S008 | P | `tests/alloc/hash_map.mt`; `tests/alloc/hash_collisions.mt`; `tests/std/collection_panic_safety_maps.mt` | `library/alloc/hash_map.mt`, `library/alloc/collections.mt`; entry, collision, ordering and complete stable-operation closure remain. |
| S009 | P | `tests/alloc/btree_stress.mt`; `tests/alloc/sorted_entry.mt`; `tests/std/collection_panic_safety_maps.mt`; `tests/source/fail/btree-range-blocks-map-mutation.mt` | `library/alloc/btree.mt`; complete ordered range/mutation invalidation and operation closure remain. |
| S010 | P | `tests/alloc/deque_list.mt`; `tests/alloc/btree_heap.mt`; `tests/std/collection_panic_safety_vec.mt`; `tests/std/collection_panic_safety_heap.mt`; `tests/alloc/owned_collection_iteration_drops.mt` | `library/alloc/vec_deque.mt`, `linked_list.mt`, `binary_heap.mt`; complete operation and iterator/ownership closure remains. |
| S011 | P | `tests/library/iter.mt`; `tests/alloc/collection_iteration.mt`; `tests/alloc/bidirectional_iterator_adapters.mt` and `tests/alloc/iterator_adapter_drop_count.mt` | `library/core/iter.mt`; close all lazy, consuming, bidirectional and short-circuit adapters. |
| S012 | P | `tests/library/fmt.mt`; `tests/library/num.mt` | `library/core/fmt.mt`, `num.mt`; F1 specifiers/Debug holes and complete stable formatting/parsing operations remain. |
| S013 | P | `tests/library/cmp_hash.mt`; `tests/alloc/collection_traits.mt` | `library/core/cmp.mt`, `hash.mt`, `num.mt`; complete stable comparison/hash/numeric trait closure remains. |
| S014 | P | `tests/alloc/failing_allocator.mt`; `tests/alloc/btree_alloc_failure.mt`; `tests/alloc/custom_allocator_owners_layouts.mt` | `library/alloc/alloc.mt`; allocator alignment/exhaustion/deallocation and every owner path need closure. |
| S015 | E | `tests/source/run/machine-cell-safe-exchange-and-exclusive-access.mt` | `library/core/borrow.mt`; raw safety, panic and forgetting qualification remains. |
| S016 | E | `tests/source/run/machine-manual-take-and-uninitialized-explicit-destruction.mt` | `library/core/` storage declarations; close partial-init, alignment and unwind cases. |
| S017 | P | `tests/backend/memory.py`; `tests/source/fail/machine-atomic-handles-are-not-implicitly-copy.mt` | `compiler/types/machine.cpp`; target width/order closure and independent memory-model evidence remain. |
| S018 | P | `tests/source/fail/manual-transferable-requires-unsafe.mt`; `tests/source/fail/machine-static-immutable-requires-shareable.mt` | `compiler/semantics/interface_solver.cpp`; generic/region/projection and static-property closure remains. |
| S019 | P | `tests/std/threads_basic.mt`; `tests/std/thread_scope.mt` | `library/std/thread.mt`, `runtime/thread.cpp`; macOS stress/panic and complete operation closure remain. |
| S020 | P | `tests/std/mutex_poison.mt`; `tests/std/sync_primitives.mt` | `library/std/sync/mutex.mt`, `rwlock.mt`; guard affinity, failure and full operation closure remain. |
| S021 | P | `tests/std/sync_primitives.mt` | `library/std/sync/condvar.mt`, `barrier.mt`, `once.mt`; wake/failure/target stress closure remains. |
| S022 | E | `tests/std/channel_rendezvous_select_timeouts_iterator.mt` | `library/std/sync/mpsc.mt`; full target stress/TSan is not part of this lane and other targets are not qualified. |
| S023 | E | `tests/std/tls_static_init_and_exit_order.mt` | `library/std/sync/tls.mt`; reverse destruction-order and target qualification remain. |
| S024 | P | `tests/std/fs_basic.mt`; `tests/std/path_edges.mt` | `library/std/fs.mt`, `path.mt`, `ffi.mt`; macOS non-Unicode filesystem behavior and complete OS-string operation closure remain. |
| S025 | P | `tests/std/net_loopback.mt`; `tests/std/net_ipv6.mt` | `library/std/net.mt`, `sys.mt`; async I/O is implemented but not currently verified; finish network operation closure. |
| S026 | E | `tests/std/process_roundtrip.mt`; `tests/std/env_args.mt` | `library/std/process.mt`, `env.mt`; child cleanup and complete process/environment closure remain. |
| S027 | E | `tests/std/time_basic.mt` | `library/std/time.mt`; complete duration/clock overflow and adjustment closure remains. |
| S028 | E | `tests/std/panic_catch.mt`; `tests/std/panic_hook_abort.mt` | `library/std/panic.mt`; complete payload/hook/recovery failure closure remains. |
| S029 | E | `tests/library/slice_any_text.mt`; `tests/packages.py::type_id_survives_public_reexport` | `library/core/any.mt`; cross-package identity and erased-owner operation fixtures verified on macOS arm64. |
| S030 | E | `tests/std/async_executor.mt`; `tests/std/async_scope_borrowed.mt` | `library/core/future.mt`, `library/std/task.mt`; async-scope fixtures pass in `library.std` and under emitted ASan/TSan; independent soundness/race review found no blocking issues. |
| S031 | P | `tests/source/run/machine-target-direct-guarded-vector.aarch64.mt` | `compiler/types/target.cpp`, `library/std/sys.mt`; finish the macOS-applicable per-item target/cfg audit; Linux/Windows remain not qualified. |
| A001 | P | `tests/backend/machine.py`; `tests/backend/machine_callbacks.c` | `compiler/backend/llvm/abi.cpp`; complete Darwin ARM64 argument/return/callback/variadic ABI probes. |
| A002 | P | `tests/backend/machine.py`; `tests/source/fail/machine-packed-fields-cannot-form-aligned-views.mt` | `compiler/types/layout.cpp`, `compiler/backend/llvm/abi.cpp`; finish layout/calling/validity probes. |
| A003 | P | `tests/source/run/machine-static-union-enum-and-nested-relocations.mt` | `compiler/backend/llvm/object.cpp`, `compiler/driver`; finish symbol/link/lifetime/freestanding closure. |
| A004 | P | `tests/backend/machine_unwind.cpp` | `compiler/backend/llvm/abi.cpp`, `runtime`; complete direct/indirect ABI and cross-language cleanup/escape probes. |
| A005 | P | `tests/source/run/machine-asm-static-symbol-global-and-naked-entry.aarch64.mt` | `compiler/types/assembly.cpp`, `compiler/backend/llvm`; complete ARM64 operand, clobber, unwind and evaluation probes. |
| A006 | P | `tests/backend/machine_vectors.c`; `tests/source/fail/machine-target-rejects-vector-element-shape-mismatch.aarch64.mt` | `compiler/types/target.cpp`, `compiler/backend/llvm`; only initial operation tables exist; enumerate and execute each applicable Darwin ARM64 operation/feature contract. |
| A007 | P | `tests/source/run/machine-pointer-provenance-volatile-and-layout.mt` | `compiler/backend/llvm`; preserve optimized accesses without treating volatile as synchronization; no full operation matrix. |
| A008 | E | `tests/backend/machine.py` (`machine-target-freestanding-no-services`) | `compiler/driver`, `runtime`; freestanding debug/release objects have no undefined service symbols and run linked to a C driver on macOS ARM64 (CTest `backend.machine`). |
| A009 | M | — | Deferred to I17 by owner decision (2026-10-31); not a V1 gate. Optional Rust interoperability package per `library-and-abi.md` section 7 and `tooling-and-packages.md` section 5. |
| T001 | E | `tests/packages.py::path_dependency`; `tests/packages.py::registry_resolution` | `compiler/packages`; complete remaining resolver conflict/offline/target-feature cases. |
| T002 | E | `tests/packages.py::build_script`; `tests/packages.py::build_script_untracked_inputs` | `compiler/driver/build_script.cpp`; finish declared-input/platform closure. |
| T003 | E | `tests/packages.py::incremental_reuse`; `tests/packages.py::object_cache_integrity` | `compiler/packages/store.cpp`, `compiler/driver/cache.cpp`; dependency-object reuse is verified on macOS arm64; front-end query separation and measurements move to I14 (owner decision 2026-10-31). |
| T004 | E | `tests/packages.py::fmt_normalizes_layout_only`; `tests/packages.py::lint_reports_semantic_findings` | `compiler/driver`; format/lint command evidence exists; close accepted source/profile combinations. |
| T005 | E | `tests/packages.py::language_server` | `compiler/lsp`; finish incremental diagnostics/rename closure. |
| T006 | E | `tests/packages.py::debug_info`; `tests/packages.py::debugger_workflow` | `compiler/backend/llvm/debug.cpp`, `tools/debug`; expanded workflow/LLDB checks pass on macOS arm64; Windows CodeView/PDB is excluded and not qualified. |
| T007 | E | `tests/packages.py::test_reports_pass_fail_ignored_and_isolates_panics`; `tests/packages.py::bench_reports_timing` | `compiler/driver/execute.cpp`; package-wide collection and doctest cases are evidenced; finish the remaining runner contract. |

Inventory totals: **67 evidenced, 39 partial, 1 missing (A009, deferred to
I17)**. Remaining partial rows are I13
operation-closure obligations. Full operation closure is a separate, still
open obligation: `docs/baseline/audit-summary.json` reports 106,125 canonical
required contracts, and the baseline explicitly says native declarations are
not typechecked and cfg branches are not compiled. No operation-wide macOS
ARM64 declaration/evidence receipt exists in this worktree.
`docs/baseline/v1-operations.csv`, written by `tools/v1_operations.py` from
`docs/library-surface.md` section 6.1, lists 3,966 families: 2,506 operation
families and 1,460 trait/type pairs. 3,964 are missing and 2 are not-applicable
(Windows `OwnedHandle` conversions). No row is declared or evidenced. Library
declarations for that subset are present and unrun; they were not compiled or
executed on Darwin ARM64. The remainder of the 106,125 canonical contracts is
I17. See `docs/library-surface.md` sections 6–8
for applicability and required supporting-protocol review; do not infer
per-operation closure from the capability-level fixtures above.

The `libs` continuation adds mutable collection predicates, iterator trait
forwarding, empty weak owners and owner protocols, ordering defaults, checked
time operations, OnceLock protocols and sender cloning. Source-review findings
and remaining implementation tasks are recorded in
[i13-library.md](i13-library.md#libs-continuation-ledger-2026-10-31).
These changes are uncompiled on the Windows editing host; the CSV remains at
3,964 missing and 2 not-applicable, with no newly declared or evidenced rows.

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
