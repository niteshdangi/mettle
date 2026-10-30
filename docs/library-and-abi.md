# Standard library, package and ABI contracts

Status: architecture and native API contracts. The
[baseline mapping policy](baseline-mapping.md) incorporates unchanged per-item
contracts and specifies their translation. The source-backed inventory and its
checks are documented in [baseline/README.md](baseline/README.md). Native
declaration checking and executable parity remain implementation work.

## 1. Library layers and naming

`core` contains primitives, views, optional/outcome operations, traits/interfaces,
iteration, formatting to an explicit sink, atomics supported by the target, and
low-level memory facilities. It requires neither allocator nor OS.

`alloc` adds unique/shared owners, owned text, growable/ordered/hash collections,
allocation-backed formatting and explicitly erased values. It depends on a
provided allocator but does not require processes, files or an executor.

`alloc.future.erase` (implemented, verified on macOS arm64) consumes a `Static` future
and allocates a fixed-address payload using the global allocator. Its
`Erased<T>` handle can move without moving the payload; polling dispatches
through pinned exclusive access and dropping the handle destroys and frees the
payload. Construction does not poll. This interface does not erase
non-`Static` borrows or grant cross-thread transfer; it does not select an
executor. Polling, allocation failure and destructor panics retain their
underlying contracts.

`std` adds hosted files/paths, OS strings, clocks, threads, synchronization,
networking and processes. The official async runtime is separately selectable,
not linked merely because a program imports core.

The local `std.task` executor and its synchronous `scope` are implemented,
verified on macOS arm64. `spawn` allocates a task, requires `Transferable + Static` future
and output, and returns a non-transferable handle. Joining drives the executor;
dropping or aborting the handle cancels, and poll/destructor panics become
`JoinError.Panicked`. The executor retains registrations even if handles are
forgotten and closes them on drop. A local scope permits `Within` borrows,
drives ready children and cancels suspended ones before returning; it does not
keep children running across an enclosing async future's polls. No fairness or
bounded completion is promised. Completed task metadata is retained until the
executor is destroyed.

Working prelude: scalar names, Copy, Sized, iterator/call capabilities, Text,
String when allocation is enabled, and native optional/outcome constructors.
The loader implements the core subset (`Text`, iterator interfaces, comparison
interfaces, `panic`, `assert`, `String`); it has lowest name priority and no
opt-out. Do not silently reexport every platform API or choose a runtime from the prelude.
The versioned `experience-1` prelude of library-surface.md section 9 specifies
the current prelude, including `List`, `Map` and `Set` when allocation is enabled.

Package and module paths use dotted qualification
(language-grammar.md section 13). Names in this document are selected API
contracts, not a promise of source compatibility with Rust; collection,
interface and I/O names follow library-surface.md section 9.

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
| push(value: take T) | Consume value; may allocate; exclusive receiver |
| try_push(value: take T) | On allocation failure, return error retaining ownership of uninserted value |
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

Because take consumes Copy values too, callers that need another independent
copy must produce it explicitly before a consuming collection call. Do not
silently weaken take for library conveniences.

Vector growth factor is not a semantic guarantee. Ordered maps guarantee key
ordering; hash-map iteration order is unspecified and hash policy is visible.
Capacity/allocator choices must not change semantic ownership. Drain, entry,
split, splice and cursor APIs need individual contracts before being counted as
implemented equivalents.

## 4. Optional, outcomes and errors

Native syntax replaces wrapper spellings, not operations. Preserve mapping,
flat-mapping, fallback, borrowed/mutable projections, extraction, transposition,
collection/short-circuiting, and iterating zero-or-one values.

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

The POSIX hosted `std.net` surface includes IPv4/IPv6 TCP and UDP, RFC 5952
IPv6 text formatting, `getaddrinfo`-based `resolve`, and a poll-backed
`TcpStream.connect_timeout`; these additions are implemented, unverified (not
yet built). IPv6 `SocketAddr` preserves port, flowinfo and scope id in socket
operations; its bracketed text form includes the optional scope id but not
flowinfo. DNS errors map to the portable I/O error kind while preserving the
runtime's errno-style error value. Windows networking is not included.

The native `std` modules are `io`, `ffi`, `path`, `fs`, `process`, `env`,
`time`, `net` and `panic`. Raw OS errors are kept in `io.Error` unchanged next
to a portable kind; operations that time out report kind `TimedOut` and keep the
OS number. `OsStr`/`Path` are byte sequences without a Unicode requirement on the POSIX profiles; the
native Windows path encoding and its display (`write_path`) are specified in
library-surface.md section 12 and reconciled with this statement before the
Windows profile is delivered. A
byte string containing NUL is rejected with `InvalidInput` before reaching the OS.
The hosted panic hook (`std.panic.set_hook`) receives the message; the process
still exits with status 101.

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
validation or a documented ABI conversion. Function ABI passing is distinct from
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

Source identities are pinned in toolchain-pins.json and target designs in
reference-profiles.md. Installed artifact hashes and target probe results remain
absent. Do not fill them with invented hashes.

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

Rust already provides layered core/alloc/std, ownership-bearing containers,
zero-allocation-capable iteration/formatting and explicit unsafe ABI facilities.
Mettle must preserve equivalent operations rather than claim them as inventions.

For equivalent layout, allocator, dispatch and failure behavior, syntax changes
establish no speed advantage. Avoid mandatory allocation in borrowed views,
concrete iterators, ordinary error results or C-compatible calls. Measure the
actual implementation against equivalent Rust paths.

Primary baseline:
- https://doc.rust-lang.org/1.99.1/core/
- https://doc.rust-lang.org/1.99.1/alloc/
- https://doc.rust-lang.org/1.99.1/std/
- https://doc.rust-lang.org/1.99.1/reference/type-layout.html
- https://doc.rust-lang.org/1.99.1/reference/items/external-blocks.html
