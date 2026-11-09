# Optional and stored-outcome contracts

Status: native operation specification. This document defines the listed
operations without an external language specification. It does not certify
their implementation, constant evaluation or target execution. The
[library layers](library-and-abi.md#1-library-layers-and-naming),
[ownership rules](core-semantics.md) and
[typing rules](semantic-rules.md) apply throughout.

## 1. Values, access and effects

`T?` contains either `present(value: T)` or `none`.
`(Outcome<T, E>)` contains either `success(value: T)` or `failure(error: E)`.
Only the active alternative owns initialized payload storage. Constructing,
matching and moving these values adds no allocation, reference counting,
payload cloning or stack-trace capture. Payload destruction follows the normal
cleanup rules. Nested alternatives remain distinct.

Reading a receiver preserves it. A mutable operation requires exclusive access.
A consuming operation transfers the receiver and cannot be used to move a
non-Copy payload through a borrowed receiver. Returning a view retains the
receiver's region and prevents conflicting mutation or destruction. No operation
extends the lifetime of a payload beyond its backing storage.

Unless stated otherwise, these operations use constant auxiliary storage and
constant work excluding payload operations, user callbacks, formatting and
destruction. They allocate nothing themselves. User-provided Clone, Default,
Deref, callbacks and destructors retain their own effects and costs.

Arguments are evaluated under [the call evaluation rules](core-semantics.md#9-evaluation-order)
before the method runs. An eager fallback value is evaluated and transferred
even when the method will not select it. Unused owned arguments are destroyed.
A lazy callback body runs only on its selected branch, at most once.
Each callback's payload input is transferred or borrowed as specified below;
its returned owned value must satisfy the ordinary result rules.

An operation invoking a callback at most once must accept a compatible
consume-callable callback, including one that consumes captures. Repeatable
callables may satisfy that capability under the
[callable rules](library-and-abi.md#5-iteration-and-callable-apis).
Callback state is not cloned, retained, implicitly erased or heap-allocated.
Unselected callbacks are destroyed without invoking their bodies. A callback
panic propagates after ordinary cleanup; it is not converted to absence or a
stored failure.

## 2. Optional queries and projections

These queries read `T?`:

| Operation | Result |
| --- | --- |
| `is_present(): bool` | True exactly for `present` |
| `is_none(): bool` | True exactly for `none` |
| `as_view()` / `as_ref()` | `present(read payload from self)` or `none` |
| `as_slice()` | A borrowed slice of length one over the payload, or length zero |
| `iter()` | Borrowed iteration over that zero-or-one payload |

`as_mut()` returns an optional exclusive payload view.
`as_mut_slice()` returns an exclusive slice of length one or zero.
`iter_mut()` yields an exclusive view of the present payload, if any.
All exclusive results depend on the receiver's exclusive loan.

Both iterators are exact-size, double-ended and fused: at most one element is
yielded in total, including mixed front/back traversal; exhaustion is permanent.
An empty slice or iterator never accesses an element. No address or optional
representation is exposed as a layout guarantee by these operations.

For `T: Deref`, `as_deref()` maps a present payload to a borrowed view of
`T.(Deref).Target`, or returns `none`. For `T: DerefMut`,
`as_deref_mut()` does the same through exclusive access. Each calls the payload's
selected dereference operation only on presence. Bounds and regions of that
operation remain applicable.

`as_pin_ref()` accepts a pinned read view of the optional and returns an
optional `Pinned<read T>`. `as_pin_mut()` accepts a pinned exclusive view
and returns an optional `Pinned<mut T>`. Both return `none` on absence and
otherwise project the existing payload at its existing address. They neither
move the payload nor allocate, retain or clone it. The resulting pin and
loan retain the source region and
[the parent projection guarantee](advanced-contracts.md#1-pinning-and-address-sensitive-objects).
An exclusive projection cannot coexist with conflicting access to the parent.
Neither method requires `T: Unpin` or grants permission to replace a pinned
address-sensitive payload.

## 3. Optional extraction and mutation

The extraction operations consume `T?`:

| Operation | Present branch | Absent branch |
| --- | --- | --- |
| `unwrap()` | Transfer T | Panic with an absence diagnostic |
| `expect(message: read Text)` | Transfer T | Panic reporting the supplied message |
| `unwrap_or(fallback: take T)` | Transfer T; destroy unused fallback | Transfer fallback |
| `unwrap_or_else(make)` | Transfer T | Invoke `make(): T` |
| `unwrap_or_default()` with `T: Default` | Transfer T | Invoke `T.(Default).default()` |

`unsafe unwrap_unchecked()` consumes the optional and transfers its payload.
The caller must establish presence before the call. Absence violates its
unsafe precondition; no checked failure behavior is promised.

The following require a mutable receiver:

| Operation | State transition and result |
| --- | --- |
| escaped `take()` / `take_value()` | Return the old optional by ownership transfer; leave `none` |
| `replace(value: take T)` | Install `present(value)`; return the old optional without destroying its transferred payload |
| `insert(value: take T)` | Install the new payload, destroy any old payload, return an exclusive view of the new payload |
| `get_or_insert(value: take T)` | Preserve an existing payload and destroy the unused argument; otherwise install it; return an exclusive payload view |
| `get_or_insert_with(make)` | Preserve an existing payload; otherwise invoke `make(): T` once and install its result; return an exclusive payload view |
| `get_or_insert_default()` with `T: Default` | Preserve an existing payload; otherwise construct and install the default; return an exclusive payload view |
| `take_if(test)` | If present, call `test(mut payload): bool`; transfer the possibly mutated payload and leave `none` only when it returns true; otherwise return `none` and retain the possibly mutated payload |

`take_if` does not call its predicate on absence. Predicate mutation is not
rolled back on false or panic. Constructor callbacks run before installation:
if one panics, the absent receiver remains absent. Replacement/destructor panic
behavior follows [replacement cleanup](core-semantics.md#10-destruction-and-failure-edges);
in particular, a recovery boundary must not observe invalidated destination
storage. Returning an exclusive payload view prevents another mutation until
that view's loan ends.

## 4. Optional transformations

These operations consume the receiver. A selected payload is transferred to
a consuming callback; a discarded payload is destroyed.

| Operation | Present branch | Absent branch |
| --- | --- | --- |
| `map(f)` | `present(f(take payload))` | `none` |
| `map_or(fallback: take U, f)` | `f(take payload)` | Transfer fallback |
| `map_or_else(make, f)` | `f(take payload)` | Invoke `make(): U` |
| `map_or_default(f)` with `U: Default` | `f(take payload)` | Construct U's default |
| `and_then(f)` | Return `f(take payload): U?` | `none` |
| `or_else(make)` | Preserve the owned present value | Return `make(): T?` |
| `is_some_and(test)` | Return `test(take payload)` | False |
| `is_none_or(test)` | Return `test(take payload)` | True |
| `ok_or(error: take E)` | `success(payload)` | `failure(error)` |
| `ok_or_else(make_error)` | `success(payload)` | `failure(make_error())` |

`filter(keep)` borrows the payload for `keep(read payload): bool`.
It returns the original owned present value when true, destroys that payload
and returns `none` when false, and never calls `keep` on absence.
`inspect(f)` calls `f(read payload): Unit` on presence and returns the original
owned optional unchanged. Neither grants exclusive payload access; encapsulated
interior mutation retains its separate rules.

`and(other: take U?)` returns `other` when the receiver is present, otherwise
`none`. `or(other: take T?)` returns the receiver when present, otherwise `other`.
`xor(other: take T?)` returns the sole present value when exactly one input is
present, otherwise `none`. Both inputs are consumed and every unreturned payload
is destroyed.

`zip(other: take U?)` returns `present((left, right))` exactly when both inputs
are present, transferring both payloads; otherwise it returns `none`.
`unzip()` on `(A, B)?` returns `(present(left), present(right))` for a present
pair and `(none, none)` otherwise. No payload cloning occurs.
`flatten()` on `(T?)?` returns the inner optional when the outer is present
and `none` otherwise.

`transpose()` on `(Outcome<T, E>)?` maps:

- `none` to `success(none)`;
- `present(success(value))` to `success(present(value))`;
- `present(failure(error))` to `failure(error)`.

On an optional read or exclusive view of `T`, consuming `copied()` produces
an owned optional T under `T: Copy`. Consuming `cloned()` does the same using
`T: Clone`, invoking Clone only on presence. These methods consume the view,
not its backing owner. Clone effects are not hidden by the optional operation.

`bool.then_some(value: take T)` returns `present(value)` for true and `none`
for false. The input is eager in both cases and is destroyed on false.
`bool.then(make)` instead accepts a consume-callable `make(): T`, invokes it
once on true and returns `present` of its result; on false it returns `none`
without invoking the callback. Normal callback cleanup and panic rules apply.

## 5. Stored-outcome queries and projections

These queries read `(Outcome<T, E>)`:

| Operation | Result |
| --- | --- |
| `is_success(): bool` | True exactly for `success` |
| `is_failure(): bool` | True exactly for `failure` |
| `as_view()` / `as_ref()` | Preserve the alternative, replacing its payload with a read view from self |
| `iter()` | Borrowed zero-or-one iteration over the success payload; failure yields no element |

`as_mut()` preserves the alternative and returns its exclusive payload view.
`iter_mut()` yields an exclusive success view, or no element on failure.
Iteration has the same exact-size, double-ended and fused guarantees as in
section 2; it never yields the error payload.

With `T: Deref`, `as_deref()` dereferences a successful payload to a read target
view and returns a read view of E on failure. With `T: DerefMut`,
`as_deref_mut()` produces the analogous exclusive views. Both alternatives
remain tied to the receiver; dereferencing runs only on success.

## 6. Stored-outcome extraction

These operations consume `(Outcome<T, E>)`:

| Operation | Success branch | Failure branch |
| --- | --- | --- |
| `ok()` | `present(payload)` | Destroy E; return `none` |
| `err()` | Destroy T; return `none` | `present(error)` |
| `unwrap()` | Transfer T | Panic with an error diagnostic |
| `expect(message: read Text)` | Transfer T | Panic reporting message and error |
| `unwrap_err()` | Panic with a success diagnostic | Transfer E |
| `expect_err(message: read Text)` | Panic reporting message and success payload | Transfer E |
| `unwrap_or(fallback: take T)` | Transfer T; destroy unused fallback | Destroy E; transfer fallback |
| `unwrap_or_else(make)` | Transfer T | Return `make(take error): T` |
| `unwrap_or_default()` with `T: Default` | Transfer T | Destroy E; construct T's default |

Checked success extraction (`unwrap`, `expect`) requires `E: Debug`;
checked failure extraction (`unwrap_err`, `expect_err`)
requires `T: Debug`. Wrong-alternative diagnostics expose the rejected payload
through that capability. Payload formatting may invoke user code and panic;
ordinary panic/cleanup rules apply. Exact diagnostic punctuation is not an API
guarantee. These bounds are caller contracts, not implementation receipts.

`unsafe unwrap_unchecked()` requires success and transfers T.
`unsafe unwrap_err_unchecked()` requires failure and transfers E.
A wrong alternative violates the unsafe precondition; no checked outcome is
promised.

## 7. Stored-outcome transformations

These operations consume the receiver:

| Operation | Success branch | Failure branch |
| --- | --- | --- |
| `map(f)` | `success(f(take payload))` | Preserve owned E |
| `map_err(f)` | Preserve owned T | `failure(f(take error))` |
| `map_or(fallback: take U, f)` | Return `f(take payload)` | Destroy E; transfer fallback |
| `map_or_else(make, f)` | Return `f(take payload)` | Return `make(take error)` |
| `map_or_default(f)` with `U: Default` | Return `f(take payload)` | Destroy E; construct U's default |
| `and_then(f)` | Return `f(take payload): (U throws E)` | Preserve owned E |
| `or_else(f)` | Preserve owned T | Return `f(take error): (T throws F)` |
| `is_ok_and(test)` | Return `test(take payload)` | Destroy E; false |
| `is_err_and(test)` | Destroy T; false | Return `test(take error)` |

`and(other: take (U throws E))` returns `other` when successful, otherwise the
original failure. `or(other: take (T throws F))` preserves success, otherwise
returns `other`. Both eagerly supplied outcomes are consumed; all unreturned
payloads are destroyed.

`inspect(f)` invokes `f(read payload): Unit` only on success and preserves the
original outcome. `inspect_err(f)` invokes `f(read error): Unit` only on failure
and preserves the original outcome. Borrowed callback inputs do not escape
their declared regions.

For outcomes whose success payload is a read or exclusive view of T,
`copied()` under `T: Copy` duplicates the success payload and `cloned()` under
`T: Clone` clones it. A failure transfers E unchanged; it does not clone or
copy E. The backing owner of a successful view is not consumed.

`flatten()` on `(Outcome<(Outcome<T, E>), E>)` returns the inner outcome on outer
success and the outer error on outer failure.
`transpose()` on `(Outcome<T?, E>)` maps:

- `success(none)` to `none`;
- `success(present(value))` to `present(success(value))`;
- `failure(error)` to `present(failure(error))`.

## 8. Constant evaluation and profile applicability

The following operations must be usable in required constant evaluation when
their input values, payload operations and regions satisfy the
[constant-evaluation rules](specification-annex.md#1-numeric-operations-and-constant-evaluation):

| Receiver | Required constant-callable operations |
| --- | --- |
| Optional | `is_present`, `is_none`, `as_view`, `as_ref`, `as_mut`, `as_pin_ref`, `as_pin_mut`, `as_slice`, `as_mut_slice`, `expect`, `unwrap`, `unwrap_unchecked`, `copied`, `flatten`, `replace`, escaped `take`, `take_value`, `transpose` |
| Stored outcome | `is_success`, `is_failure`, `as_view`, `as_ref`, `as_mut`, `copied`, `flatten`, `transpose` |

This is not a promise that arbitrary destructors, Clone, Default, dereference
implementations or callbacks can execute at compile time. A panic during
required constant evaluation is a compile-time failure, not a runtime panic.
Unsafe constant calls retain their preconditions. Other listed operations have
runtime contracts without a required constant-callability promise here.

These core operations apply on every selected profile, including core-only
profiles, without an allocator, OS or executor dependency. User-provided payload
operations and hosted panic recovery retain their own applicability.

## 9. Acceptance and remaining surfaces

Acceptance must check active alternatives, nested alternatives, consumed versus
borrowed payloads, callback branch/count/access, unused argument cleanup,
partial mutation on failure, returned-view regions and zero-or-one iteration.
Include non-Copy payloads, destructor/callback panics and required-constant
pass/fail cases. An implementation lacking these contracts remains partial.

Existing source fixtures include
[optional operations](../tests/source/run/i13-option-operations.mt) and
[outcome operations](../tests/source/run/i13-outcome-operations.mt).
They are candidate acceptance inputs, not a newly executed receipt.
Current method bodies alone do not establish callable-capability, Debug-bound,
both-view-variant or constant-evaluation closure.

Source review identifies concrete reconciliation work:
[core.option](../library/core/option.mt) declares several callbacks using
read-callable function types and provides optional duplication declarations for
read views, without separate exclusive-view declarations.
[core.outcome](../library/core/outcome.mt) checked extraction bodies currently
report fixed text or the supplied message without the rejected payload's Debug
formatting or explicit Debug bounds. Verify accepted callback/view adaptations
and complete the selected extraction contracts before claiming operation closure.
No compiler/library execution was performed by this specification change.

The contract covers only operations listed here. Named iterator types and the
explicitly described protocol/collection implementations have separate
[core definitions](native-core-library-contracts.md); unlisted methods and
type-specific implementations remain outside this chapter. Native-authority assignments
and the remaining reference-owned surfaces are recorded in
[the mapping register](baseline-mapping.md#7-native-operation-authority).
