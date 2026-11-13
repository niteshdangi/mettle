# Standard library, package and ABI contracts

Status: selected library/ABI contracts. Per-operation rules and names are owned
by [library-surface.md](library-surface.md). Native operation definitions are in
[value contracts](native-value-contracts.md),
[core contracts](native-core-library-contracts.md),
[collection contracts](native-collection-contracts.md),
[hosted contracts](native-hosted-contracts.md),
[OS extensions](native-os-contracts.md) and
[machine contracts](native-machine-contracts.md).
The [authority register](../process/baseline-mapping.md#7-native-operation-authority)
identifies their exact assignments;
unmigrated operations retain the explicit fallback in
[baseline-mapping.md](../process/baseline-mapping.md). Profile-scoped implementation
evidence is recorded in [implementation-plan.md](../process/implementation-plan.md);
the API contract is not a qualification receipt.

## 1. Library layers and naming

`core` contains primitives, views, optional/outcome operations, traits/interfaces,
iteration, formatting to an explicit sink, atomics supported by the target, and
low-level memory facilities. It requires neither allocator nor OS.

`alloc` adds unique/shared owners, owned text, growable/ordered/hash collections,
allocation-backed formatting and explicitly erased values. It depends on a
provided allocator but does not require processes, files or an executor.

`alloc.future.erase` consumes a `Static` future and allocates a fixed-address
payload using the global allocator. Its
`Erased<T>` handle can move without moving the payload; polling dispatches
through pinned exclusive access and dropping the handle destroys and frees the
payload. Construction does not poll. This interface does not erase
non-`Static` borrows or grant cross-thread transfer; it does not select an
executor. Polling, allocation failure and destructor panics retain their
underlying contracts.

`std` adds hosted files/paths, OS strings, clocks, threads, synchronization,
networking and processes. The official async runtime is separately selectable,
not linked merely because a program imports core.

The local `std.task` executor's `spawn` allocates a task, requires a
`Transferable + Static` future and output, and returns a non-transferable handle.
Joining drives the executor;
dropping or aborting the handle cancels, and poll/destructor panics become
`JoinError.Panicked`. The executor retains registrations even if handles are
forgotten and closes them on drop. A local scope permits `Within` borrows,
drives ready children and cancels suspended ones before returning; it does not
keep children running across an enclosing async future's polls. No fairness or
bounded completion is promised. Completed task metadata is retained until the
executor is destroyed. Calling `run` or `run_until_stalled` reentrantly from a
task poll on that same executor panics rather than nesting a poll or blocking.

The exact versioned `experience-1` prelude, collection/interface/I/O names and
canonical aliases are in library-surface §9; compiler-predeclared names remain
separate. The prelude neither reexports platform APIs nor selects an executor.
Package/module paths use dotted qualification (language-grammar §13).

## 2. Ownership and allocation operations

| Facility | Required contract |
| --- | --- |
| heap T construction | One owned allocation; consume payload; fallible alternative |
| heap extraction | Return owned T; dispose allocation without dropping T twice |
| shared/local shared construction | One initial strong owner; explicit allocation and mode |
| retain | Read owner handle; produce another owner of identical payload |
| weak creation | Produce bookkeeping handle without retaining payload |
| weak upgrade | Optional strong owner; atomic success coordinates with destruction |
| unique extraction | Succeeds only when payload ownership can be transferred soundly |
| raw ownership conversion | Explicit unsafe reconstruction contract with allocator identity |

No smart-owner handle is Copy. Retention does not clone T. Moving a handle
transfers it. Strong cycles can leak. Weak handles may retain allocation metadata
after payload destruction. Counter overflow must fail safely, not wrap into
premature deallocation; specify abort as the default nonrecoverable response.

Shared handles cross threads only when payload transfer and sharing contracts
permit it. Atomic counting does not imply arbitrary thread-safe payload mutation.
Local handles cannot silently upgrade at thread boundaries.

Allocator operations identify size, alignment and allocation ownership. A
deallocation must use a compatible allocator and layout. Reallocation failure
preserves the original allocation unless an API explicitly documents otherwise.
Zero-size allocation and zero-capacity containers need explicit representations,
not forged non-null references to invalid storage.

Ordinary allocation aborts on exhaustion by default. Fallible operations return
typed failure without pretending all allocation inside arbitrary user callbacks
is recoverable. Custom policies require documented entry points.

## 3. Text and collection contracts

Text is an unsized validated UTF-8 view. String owns UTF-8 storage. String literals
have static validated backing and do not allocate merely to exist.
Byte containers are not automatically text. Conversion from arbitrary bytes is
fallible unless an unsafe caller establishes validity.

Text exposes byte length and byte/scalar iteration. Arbitrary integer character
indexing is not defined. Checked slicing validates range and UTF-8 boundaries
(`read text[i..j]` panics on an out-of-range or non-char-boundary range, through
`core.ops.IndexRange`); an existing view prevents operations that can
invalidate its backing storage. Byte literals `b"..."` are static `[u8; N]`
views; `core.slice.from_raw_parts[_mut]` and `core.text.from_utf8_unchecked`
build views from raw parts in unsafe code, the caller asserting the region.
Normalization is not automatic. Grapheme operations use a versioned Unicode
library and are not confused with constant-time byte access.

Initial collection API obligations:

| Operation | Ownership / failure / invalidation |
| --- | --- |
| length, capacity, empty | Read access; no allocation |
| get(index) | Optional borrowed view; no ownership production |
| index operator | Borrowed access with bounds panic unless proved in range |
| get_mut(index) | Optional exclusive view tied to receiver loan |
| push(take value: T) | Consume value; may allocate; exclusive receiver |
| try_push(take value: T) | On allocation failure, return error retaining ownership of uninserted value |
| pop() | Optional owned T; no clone |
| insert/remove | Explicit element movement and iterator invalidation |
| reserve/try_reserve | Capacity guarantee or typed failure; existing live views constrain use |
| clear | Destroy initialized elements exactly once |
| consuming iteration | Own collection state and yield owned elements |
| borrowed iteration | Hold receiver region; yield views without cloning |

`List` implements consuming (`OwnedIterable`), borrowed (`Iterable`) and
mutable (`MutableIterable`) iteration through the core interfaces, so
`for x in take v`, `for x in read v` and `for x in mut v` work; `VecDeque`,
`LinkedList` and (values only) the maps add `MutableIterable`; every collection
provides borrowed iteration and `FromItems`/`ExtendItems` (over any
`OwnedIterable` with a matching `Item`; `Iterator.collect` builds any
`FromItems`), and borrowed `keys()`/`values()` on maps. Alloc types implement
the matching `core.cmp`, `core.hash`, `core.ops` (`Deref`, `IndexRange`) and
`core.fmt` interfaces; `String` is a `core.fmt.Write` sink.

`Box<[T; N], A>` supports consuming, borrowed and mutable iteration. Consuming
iteration yields each initialized `T` by move and keeps the original allocation,
layout and allocator with the iterator; dropping a partially consumed iterator
drops only the remaining elements, exactly once, before deallocation. Borrowed
iteration yields views tied to the corresponding shared or exclusive borrow of
the box. For `N == 0`, all three iterators yield no elements and never
dereference an element pointer.

Because take consumes Copy values too, callers that need another independent
copy must produce it explicitly before a consuming collection call. Do not
silently weaken take for library conveniences.

Floating `to_int_unchecked<Int>` is unsafe and accepts native integer targets.
The input must be finite and its integer part, truncated toward zero, must fit
the target. NaN, infinity and out-of-range inputs violate the precondition; this
operation does not promise the saturating behavior of ordinary floating casts.
The target can be explicit, an integer alias or inferred from a result context.
An abstract target without a concrete native integer identity remains explicitly
unsupported; no unstable public conversion trait is introduced.

Floating `FromStr` parses decimal text without an allocator or OS dependency,
rounding directly to the requested binary32/binary64 width, ties to even.
Invalid grammar returns `ParseFloatError`; valid overflow/underflow produces
infinity/signed zero. Long discarded mantissa digits retain sticky information.
Fixed-precision Display/Debug rounds fractional digits ties to even, propagates
carry and preserves the sign of zero; width, alignment and writer errors remain
part of the formatter contract. Native float MIN/MAX preserve their type and
finite bit pattern in static and runtime use. Runtime algebraic wrappers use
strict operators. Bit and endian-byte conversions preserve exact NaN payloads
and signed zero through const-function frames and static storage.
Contextual literals round directly to the requested width; numeric casts and
classification retain their declared result types. Non-const calls and invalid
clamp bounds are rejected during required initialization.

The selected lossless numeric `From` implementations admit bool and the
selected narrow integer domains for f32/f64, plus f32-to-f64 widening. Boolean
conversion produces positive zero or one; finite widening and signed zero are
exact, while cross-width NaN payloads are not promised. The `Into` blanket uses
these implementations; no general `From`-to-`TryFrom` blanket is introduced.
Both float widths implement the selected arithmetic and assignment interfaces
for owned and readonly-view operands using the existing intrinsic IEEE operators.

`alloc.string.ToString` supplies the `Display + unsized` blanket without adding
allocation to core. It renders default Display options into an independently
owned Global-allocated String. Allocation and formatting failures panic rather
than returning partial output; rendering cost includes Display and appending
the emitted bytes.

Float constant metadata has its declared integer type: DIGITS, MANTISSA_DIGITS
and RADIX are u32, while exponent bounds are i32. EPSILON and MIN_POSITIVE use
the owner's binary width; INFINITY, NEG_INFINITY and NAN are associated values,
not new numeric-token spellings. NAN's payload is unspecified. The compiler's
checked numeric carrier accepts canonical nonfinite values without permitting
implicit narrowing or changing source identifier/lexer rules.

Vector growth factor is not a semantic guarantee. Ordered maps guarantee key
ordering; hash-map iteration order is unspecified and hash policy is visible.
Capacity/allocator choices must not change semantic ownership. Drain, entry,
split, splice and cursor APIs retain their individual contracts under
library-surface.

Decision D30: the alloc Map default is deterministic and requires no hidden OS
entropy. It does not promise collision-attack resistance; applications with
untrusted keys explicitly select a randomized builder. Hash algorithm/output
and iteration order are not stabilized by that default.
Decision D31: general borrowed-or-owned values use
`BorrowedOrOwned<region r,B>`; slices spell `BorrowedOrOwned<region r,[T]>`; no
alias or parallel implementation exists.

## 4. Optional, outcomes and errors

The [native value contracts](native-value-contracts.md) specify queries,
mapping, flat-mapping, fallback, borrowed/mutable projections, extraction,
transposition and zero-or-one borrowed iteration.
Collection/short-circuit implementations and other surfaces outside that
document remain separate obligations; value syntax does not discharge them.

Error propagation does not allocate or capture a stack trace by default.
Cause/context facilities are explicit and may own storage. A dynamic error
container advertises erasure, allocation and thread/lifetime requirements.

The standard error contract distinguishes absent data, recoverable failure,
cancelled work and programmer panic. Cancellation of an operation is not proof
that its external effects did not occur.

## 5. Iteration and callable APIs

Read, exclusive and consuming iteration have separate signatures. A generic
loop must not clone elements to satisfy a consuming API. Iterator adapters are
lazy unless explicitly documented otherwise and carry their captured regions.

Read-callable, mutate-callable and consume-callable capabilities express repeated
invocation permissions. A consuming closure can be invoked only once unless
ownership is deliberately reconstructed. Callback allocation and erasure remain
separate from its invocation mode.

Formatting writes into a caller-selected sink. Streaming formatting must be
available without building an intermediate String; the `format` parameter kind
and borrowed `Message` of library-surface.md section 10 are its target contract. Parsing distinguishes
invalid input, incomplete input, overflow and target-specific I/O failures where
the operation supports them.

## 6. Synchronization and hosted services

Locks yield lifetime-bearing guards; thread affinity, poisoning/recovery and
blocking/async behavior are per-type contracts. Atomic orderings must have a
specified memory model. A channel owns queued messages and defines disconnection,
bounded capacity, cancellation, and destruction behavior.

`std.sync.mpsc.channel` is an unbounded FIFO. `sync_channel(n)` has capacity
`n`; capacity zero is a rendezvous, so a blocking send completes only after a
receiver takes its message. `try_send` returns the unaccepted value when full or
disconnected. `try_recv` distinguishes an empty connected channel from a drained
disconnected one. `recv_timeout` distinguishes timeout from disconnection, and
`SyncSender.send_timeout` returns its value on either failure. Receiver
iteration blocks until a message arrives and ends only after all senders are
gone and queued messages are drained. `Select` borrows receivers carrying the
same item type, blocks without polling, and returns a ready receiver index
without consuming its message; a disconnected receiver is ready. Ready indices
are considered in rotating order.

Declare a static `std.sync.tls.LocalKey<T>` with its initializer function as
the field value, for example `static KEY: LocalKey<T> = LocalKey(make_value)`.
This aggregate initializer avoids a generic const-function call; methods on a
`LocalKey` require a static-storage receiver. The runtime creates its native
key on first use, and the initializer runs independently on each thread's first
`with` access. `set` installs a value directly. `std.sync.tls.new<T>()`
instead returns an owned, dynamically created key. Each thread destroys live
values in reverse order of first installation. Values reinstalled by a
destructor are considered in a later destructor pass, up to the host pthread
destructor-iteration limit. The hosted Mettle entry point runs the main
thread's remaining TLS destructors after `main` returns or panics and before it
returns the process status. Other process-termination paths do not promise this
cleanup.

Files and sockets expose partial reads/writes. A successful write is not a
durability guarantee. OS path strings preserve non-Unicode data when the platform
permits it. Process exit status, environment encoding, handle inheritance and
thread-local destructors remain profile-specific obligations outside the hosted
pthread profiles.

The POSIX `std.net` address, socket, resolution and timeout contracts are in
library-surface §13. DNS errors retain the runtime's errno-style value alongside
a portable I/O kind. No Windows networking profile is selected here.

The native `std` modules are `io`, `ffi`, `path`, `fs`, `process`, `env`,
`time`, `net` and `panic`. Raw OS errors are kept in `io.Error` unchanged next
to a portable kind; operations that time out report kind `TimedOut` and keep the
OS number. `OsStr`/`Path` preserve POSIX bytes without a Unicode requirement; Windows native
storage and `write_path` display follow library-surface §12. A
byte string containing NUL is rejected with `InvalidInput` before reaching the OS.
The hosted panic hook (`std.panic.set_hook`) receives the message before
unwinding. An uncaught message panic exits with status 101; hosted
`std.panic.catch_panic` instead returns its code and owned message payload after
cleanup completes. A panic raised by a hook aborts. Freestanding execution
uses aborting traps and does not provide in-process panic recovery.

Wall time and monotonic elapsed time are distinct types. No monotonicity promise
is made for wall time. Timeouts distinguish expiration from completed cleanup.

## 7. Native layout and C ABI

Default native layout is compiler-owned and not a stable cross-version ABI.
Expose size/alignment/offset introspection where guaranteed, not a promise that
all field offsets remain unchanged forever.

`@layout(C)` selects the target C-compatible aggregate layout. `@align(N)` and
`@packed(N)` require valid powers of two and defined combinations. Packed storage
does not permit forming an ordinarily aligned reference to an unaligned field.
Use explicit unaligned access operations instead.

Native bool has valid values false/true; arbitrary foreign bytes require
validation or a documented ABI conversion. Native `char` crosses the C ABI as
`uint32_t` (`char32_t`); a foreign value must be a Unicode scalar, so unchecked
foreign integers need validation. Function ABI passing is distinct from
memory layout. A matching struct size does not establish call compatibility.

Extern calls require named ABI, symbol resolution, linkage and target features.
Foreign varargs use target C promotions and an explicit unsafe contract. Closure
callbacks need an explicit context pointer, destruction ownership and lifetime.
No native closure or outcome representation is assumed C-compatible.

Typed failures cross foreign boundaries only through explicit compatible tagged
representations/statuses. Ordinary C boundaries cannot carry arbitrary unwind.
Compatible unwind entry points require matching runtime and cleanup validation.

All cross-language ownership transfers specify who destroys the value and with
which allocator. Exported names and C adapters are the initial stable integration
boundary; native ABI stability remains a separate future commitment.

## 8. Profile artifacts and toolchain lock

For each target publish a machine-readable profile containing:

```text
triple, object_format, endian, pointer_width
primitive_sizes_and_alignments, c_abi, stack_alignment
atomic_widths, tls_model, panic_modes
os_sdk_sysroot_identity, linker_identity, startup
core_alloc_std_runtime_availability, debug_format
compiler_and_backend_revision, validation_artifact_ids
```

Every claimed profile field needs a source, a probe, or an explicitly marked
design choice. No populated value is treated as tested merely because LLVM
knows the target triple.

Freeze exact source revisions and hashes for C++ compiler, LLVM, CMake, Ninja,
linker and sysroot before reproducible builds. The lock also records optional
build flags, enabled targets and host tools. Keep platform SDK licensing and
distribution constraints separate from the Mettle project license decision.

Source identities are in toolchain-pins.json; target designs are in
platform-contracts.md. Record actual installed hashes and probe results.

## 9. Package and compatibility policy

Use package name plus source identity and version as resolver identity.
Lock exact dependency versions and content hashes, including host-generated
inputs. Reject a checksum mismatch. Offline operation either uses available
verified artifacts or explains the missing input; it does not silently fetch.

Target and feature selection enter cache keys. Host macro/build execution is
identified to the user and follows project policy; undeclared external inputs
disable unsound cache reuse. Sandboxing remains optional.

Published signatures include access modes, region constraints, associated
identities and error types. Changing Copy eligibility can change default parameter
semantics; treat it as an API compatibility change. Rebuild dependent native
packages unless a separately promised ABI says otherwise.

Registry namespace governance, publishing credentials and moderation are product
decisions before a public registry, not implicit authorization to create one.
The exact project license remains an owner decision.

## 10. Comparison and performance

Borrowed views, concrete iterators, ordinary error results and C-compatible
calls require no mandatory allocation. Compare equivalent layout, allocator,
dispatch and failure behavior under [performance.md](../process/performance.md).

Operation authority is assigned by [the native mapping register](../process/baseline-mapping.md#7-native-operation-authority).
Unmigrated contracts retain their recorded reference; native layout and C ABI
requirements are specified in sections 7-8 and the
[platform contracts](../spec/platform-contracts.md).
