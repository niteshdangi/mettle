# Memory and concurrency design contract

Status: selected semantic contract, not a mechanically proved model.

## 1. Allocations, bytes and values

An allocation has identity, byte extent, alignment, lifetime and permitted
accesses. Reusing an address after deallocation creates a new identity.
Pointer equality of addresses does not establish identical provenance.

Safe typed reads require initialized storage containing a valid value. Reference
values are non-null, aligned, and backed by live valid storage for their promised
access. Integer/scalar validity follows the declared type; bool and enum tags
cannot contain arbitrary invalid bit patterns. Uninitialized padding is not a
typed value and must not be observed as initialized scalar data.

Raw byte-copy operations may copy uninitialized storage under their specified
contract without pretending the result is an initialized T. Converting that
storage to a safe T or reference requires validity. `MaybeUninit`-like storage
does not relax these obligations merely by being wrapped in a safe type.

Every memory operation specifies its accessed extent. Ordinary typed access
requires proper alignment even for zero-sized types; dedicated unaligned
operations relax only alignment, not lifetime, validity or ownership.

## 2. Provenance and address arithmetic

A raw pointer carries an address and allocation provenance. Offset operations
that promise in-bounds arithmetic require the resulting range to remain in the
same live allocation, allowing a one-past pointer that cannot be dereferenced.
Wrapping address arithmetic may create a non-dereferenceable pointer; it does not
grant access to another allocation merely because its address happens to match.

Provide strict-provenance address extraction and address replacement relative
to an existing pointer. An address-only integer does not itself preserve a
dereferenceable reference. Explicit exposed-provenance conversions preserve the
separate capability to recover an eligible exposed allocation, with the caller
responsible for liveness, extent and access authority. No conversion recovers
deallocated storage.

Foreign pointers enter through declared allocation/provenance contracts. MMIO
volatile operations may access designated device addresses under target-specific
rules without pretending they are ordinary heap allocations.

## 3. Aliasing and access authority

Safe loans define an authority tree over projected allocation regions.
Reborrowing derives authority from a parent, cannot enlarge its region or access
rights, and temporarily suspends conflicting parent access. Read authority
permits reads; exclusive authority permits reads/writes through itself and valid
derived accesses. Independently obtained overlapping authority cannot bypass a
live conflicting loan.

Unsafe raw pointers may alias each other without creating safe reference loans.
Access through them is permitted only while satisfying allocation, initialization,
race and active-reference constraints. Deriving a raw pointer from an exclusive
view does not authorize simultaneously using an independent conflicting alias.
After a raw-access phase, any new safe reference must re-establish its complete
validity and aliasing contract.

Interior-mutable storage is a marked region exempt from a read view's ordinary
freeze promise, not from initialization, race or exclusive-access obligations.
Safe wrappers establish synchronization or dynamic borrowing before exposing
payload access. The mark does not make data races legal.

Loan liveness is defined by uses and declared region contracts, including derived
views and destructors. Code generation may exploit only the authority justified
at the relevant program point. Do not emit function-wide noalias solely because
the source signature contains mut.

The authority tree is semantic bookkeeping, not a required runtime data
structure. An interpreter/sanitizer may implement it to test the model. Its exact
translation into optimization metadata needs a separately checked lowering.

## 4. Atomics and happens-before

Adopt the pinned std::sync::atomic contract: C++20-style ordering without consume,
applied to memory accesses rather than permanent atomic objects.

Define sequenced-before within a thread; synchronization edges from matching
release/acquire operations, valid fences, thread start/join and synchronization
APIs; happens-before is their transitive closure. Relaxed atomic accesses do not
by themselves publish unrelated data.

Each atomic location has modification-order coherence. Sequentially consistent
operations obey the additional global order prescribed by the incorporated
contract. Compare-exchange failure is a load: failure ordering cannot be Release
or AcqRel. Weak compare-exchange may fail spuriously.

Conflicting unsynchronized accesses with at least one non-atomic access are
data races and undefined behavior. Non-synchronized conflicting atomic accesses
may not partially overlap at different sizes. Read-only overlapping accesses do
not become writes merely because one uses an atomic operation.

Load does not accept Release/AcqRel; store does not accept Acquire/AcqRel.
RMW orderings apply their load/store portions as specified. Native baseline
atomic types must preserve the baseline's lock-free guarantee wherever they are
available. A blocking emulation cannot replace one under the same API. Any
separately named emulated facility discloses blocking and is not parity evidence
for an unavailable lock-free type.

Volatile preserves required observable device accesses. It is not synchronization
and does not create a happens-before edge by itself.

## 5. Transfer and sharing properties

Transferable means ownership may cross threads. Shareable means read views may
be shared across threads under their full contracts. Derive structurally from
fields/parameters with explicit negative declarations for affinity.

An exclusive view may transfer when its backing access and lifetime permit it;
a read view's cross-thread use needs Shareable backing. Atomic shared ownership
also requires the payload's applicable transfer/sharing guarantees.
An unsafe manual implementation must establish these conditions, not merely
assert that a type is convenient to send.

Deadlock freedom, fairness, lock ordering, bounded latency and transaction
atomicity are not implied by race freedom.

## 6. Borrowed async scopes: poll-scoped execution epochs

Select an enforcement mechanism rather than a destructor-only guard:
borrowed child futures may persist in parent-owned storage, but their independent
execution authority exists only during a parent poll execution epoch.

Entry requires valid exclusive pinned access to the parent future. The compiler/
scope runtime opens an epoch and may schedule registered child polls on eligible
workers. Before that parent poll returns Pending/Ready or unwinds, all executing
child polls must have returned or unwound and their execution leases must be
joined. No borrowing child remains runnable outside the epoch.

Children that return Pending retain their state inside the parent's scope
storage. Wake notifications mark readiness and wake the parent; they do not
directly schedule another child poll without a new parent epoch. Notification
objects must not hold independently dereferenceable pointers to parent storage;
use owned readiness metadata and the caller-provided waker contract.

This closes the forgotten-outer-future case: after a returned poll there is no
active child access. Forgetting the parent may leak its stored state and readiness
metadata but cannot leave a worker executing against subsequently invalid
external borrows. Leaked children are not independently polled or destroyed by a
notification callback. If the parent is itself owned by a running executor task,
that executor retains its normal ownership/lifetime obligations.

Destruction after poll quiescence synchronously drops initialized children.
Normal async scope completion may poll cooperative cancellation/cleanup to
completion across further epochs. Forced parent destruction cannot promise
asynchronous cleanup; external effects are not rolled back.

If a child poll never returns, the current epoch may never quiesce. The parent
must wait rather than return and invalidate storage. This preserves memory
safety but makes no bounded-latency guarantee. Local child polls run cooperatively
on the parent thread; the runtime must not block that thread waiting for an
unscheduled local poll.

For remote workers, panic is captured at the poll boundary, all other active
polls are joined, and only then is the parent panic resumed. A teardown panic
during an existing unwind aborts. Reentrant/concurrent parent polling is forbidden
by exclusive access; custom runtime integrations must enforce that rule even
when wakers are invoked recursively.

Custom executors can opt into this unsafe epoch/lease interface. Ordinary owned
tasks retain independent scheduling and are not restricted to parent epochs.
Direct borrowed await remains available without spawned-task registration.

Comparison must include scheduling/bookkeeping under equivalent scoped execution.

## 7. Required review cases and trusted boundary

Review allocation reuse, integer round trips, packed references, initialized
padding, raw-pointer phases, reborrows, overlapping atomics, release/acquire
publication, repeated wake after parent drop, forgotten parent state, child panic,
recursive polling and an uncooperative child.

Require operational tests/model checks before claiming enforcement. Unsafe
runtime, allocator, executor and foreign implementations remain trusted to
honor their explicit contracts.

Primary normative comparisons:
- https://doc.rust-lang.org/1.99.1/std/ptr/index.html
- https://doc.rust-lang.org/1.99.1/std/sync/atomic/index.html
- https://doc.rust-lang.org/1.99.1/reference/behavior-considered-undefined.html
