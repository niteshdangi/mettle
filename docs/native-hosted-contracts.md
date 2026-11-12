# Native hosted library contracts

Status: selected operation-family contracts, not implementation or profile
qualification evidence. V1 executes on `linux-x64`. The other seven selected
profiles remain obligations after V1; absence of a service on a profile does not
remove that profile or make a valid operation invalid on another profile.

V1 gate: only Linux (and the portable core of each family) is exercised for V1.
Sections specific to Windows, macOS, Android, WASI or other profiles are
post-V1 obligations ([post-v1-worklist.md](post-v1-worklist.md)); they define
contracts but are not V1 acceptance requirements.

## 1. Scope, signatures and effects

This document owns the hosted behavior of `std.io`, OS strings, paths, files,
environment, processes, clocks, threads, TLS, locks, channels and networking.
[Native OS contracts](native-os-contracts.md) own platform extensions and raw
resource transfers. Canonical identities, generic bounds, exact overloads,
stable const-callability and target predicates are identified by the
nondeprecated records in `baseline/operations.jsonl.gz`, translated by
[library-surface sections 2–3](library-surface.md#2-recursive-translation-rules).
The catalog identifies operations; it is not the behavioral authority for the
families specified here. Deprecated records are excluded, including deprecated
members of otherwise retained types. A stable parent does not admit an
experimental child.

Signatures below use `read`, `mut` and `take` for access and ownership;
`Outcome<X, E>` denotes the stored outcome as well as the declared failure of a
throwing entry point, according to its calling form. An omitted method receiver
is read-only. Builder setters have an exclusive receiver and return an exclusive
view of that same builder, never a second owner. `PathInput` parameters are
independently generic read inputs, including unsized inputs; their loans last
through the call. A returned path/string/buffer view names its backing receiver,
not the temporary adapter used to supply an input.

Common rules apply unless a row specifies more:

- Resource constructors return a unique owner; ordinary moves transfer it.
  `try_clone` duplicates an OS resource reference fallibly, not its contents.
  Dropping the last applicable owner releases its OS reference exactly once.
  No resource owner is Copy. Borrowed resource access never closes it.
- Successful OS calls are observations at a point in time, not locks on names,
  permissions, process state or remote peers. External actors can change state
  immediately. A query followed by a mutation is not an atomic transaction.
- Fallible operations return typed errors, not panics for permission denial,
  disconnection, encoding failure, missing files or resource exhaustion at the
  OS boundary. Ordinary allocation still uses the selected abort-on-exhaustion
  policy; a returned `io.Error` does not make all allocation fallible.
- Internal buffers, owned snapshots, adapters that own their source, callback
  storage and OS resources remain alive until transferred or destroyed.
  Views prevent invalidating mutation. No operation silently clones a payload,
  retains a shared owner or extends a region to satisfy an OS call.
- OS work may block indefinitely unless the operation has a timeout or is
  explicitly nonblocking. Timeout bounds waiting, subject to scheduling and
  clock resolution; it does not bound cleanup or undo completed effects.
  Synchronous methods have no task-cancellation guarantee.
- Error, panic and destruction do not roll back external effects. Destructors
  cannot report ordinary close/flush errors. Use explicit fallible completion
  operations when those errors matter. Cleanup during panic follows the panic
  mode; a second panic during unwinding aborts.
- Metadata queries and resource-handle operations require O(1) library storage;
  the OS cost is not bounded. Byte processing is linear in bytes processed,
  allocation is proportional to retained bytes, and copying snapshots is linear
  in snapshot size. No constant-time, lock-free, fairness, durability or
  bounded-latency guarantee follows from an OS API name.

Existing native authorities remain in force: allocation and error propagation
in [library-and-abi](library-and-abi.md), validity/loans/thread properties in
[memory-and-concurrency](memory-and-concurrency.md), formatting and broken-pipe
output in [library-surface section 10](library-surface.md#10-formatting-and-output),
lending lines in section 11, and hosted task scopes in section 13. Core error
protocols, C strings, scalar arithmetic, ordinary iterators, smart owners
and atomic operations retain their separate native authorities. Their std
reexports do not define new types. Section 7 also owns allocation-free
`core.time.Duration` and its std reexport; this placement adds no core dependency
on hosted clocks. Section 9's address-value rules apply to the matching
`core.net` identities, with the eligibility boundary in section 10.
An archive page alone does not establish a stable `core.io` exposure.

Debug implementations borrow their value and produce diagnostics through the
selected formatting sink. They obey its failure and callback/loan contracts;
they do not transfer the formatted owner. Debug text, field order, punctuation,
escaping choices and pretty-print layout are not a stable serialization or
cross-version byte-string compatibility promise. Payload formatters retain
their own effects and costs. This does not weaken separately specified Display
forms, such as numeric socket-address text, or the reversible native OS-string
conversions. No additional Debug-text migration gate is required for these
hosted types merely because their diagnostic rendering is not a compatibility surface.

## 2. Hosted prerequisites

| Profiles | Prerequisites and applicability |
| --- | --- |
| `linux-x64`, `linux-arm64` | Recorded installed kernel/libc, C startup, allocator, errno, descriptors, filesystem, clocks, pthread/TLS, process and socket services. A specific distribution or libc version is not inferred. |
| `android-arm64` | API 28/Bionic and NDK r27c; filesystem namespace, permissions, process execution and networking remain subject to the application sandbox. A denied operation is not an absent language capability. |
| `macos-arm64` | macOS 15/Xcode 16.2 baseline; Darwin filesystem, pthread/TLS, Mach clocks and sockets. Optional runtime readiness requires the selected reactor separately. |
| `windows-x64` | Windows 11 24H2/SDK 10.0.26100.0, compatible CRT/startup, wide filesystem/environment/process calls, Win32 threads/TLS, synchronization and Winsock initialization. Console and redirected output need distinct sink adapters. These are delivery prerequisites, not existing Windows std evidence. |
| `wasi32` | Preview 1 imports under wasi-sdk-25/Wasmtime 29.0.1; preopened directory capabilities, supplied arguments/environment, descriptor I/O, clock and random-access file imports. No baseline process spawning, host-environment mutation, general DNS/TCP/UDP, hosted threads or pthread TLS. Unsupported services must be diagnosed or return their declared `Unsupported` result, not be silently simulated. |
| `wasm32-core`, `cortex-m3` | No hosted std by default. Core and optional alloc remain usable. Embedder imports or board services require a separately selected hosted adapter; they do not manufacture a standard filesystem/process/thread environment. |

Target applicability follows the actual operation predicate and these service
prerequisites, not a blanket "Unix" label. For example, Android is not evidence
for every Linux extension, and WASI descriptor access is not POSIX process
support. Profile locks and ABI/panic prerequisites remain in
[reference-profiles](reference-profiles.md) and
[platform-contracts](platform-contracts.md).

## 3. I/O errors, buffers and streams

### 3.1. Error values

`Error.from_raw_os_error(code)` stores the target's complete error-code value.
`raw_os_error(): RawOsError?` returns that value for OS errors, including errors
whose portable kind is unknown; constructing an OS error and reading it back
must not truncate or reinterpret it as a different platform's code.
`last_os_error()` captures the calling thread's current OS error immediately.
Do not perform an intervening operation that overwrites that state.

`Error.new(kind, take cause)` owns an explicitly erased error cause under its
declared transfer/sharing/static bounds and may allocate. Kind-only construction
need not allocate. `kind()` returns the portable classification.
`other(take cause)` explicitly chooses kind Other. `get_ref`/`get_mut` return
cause views tied to the error, and `into_inner(take
self)` transfers its owned cause, or returns none for an error without one.
`downcast<E>(take self)` moves out the stored concrete E on an exact type match;
otherwise its failure owns the original Error. Its E must satisfy the declared
error/Transferable/Shareable/Static bounds. A raw OS error is not an E merely
because its display text matches E.
Formatting may inspect but cannot consume a borrowed error; display text is
diagnostic, not a stable serialization or a way to recover the raw code.

Kinds classify conditions: missing object, permission denial, already-existing
object, invalid input/data, interrupted operation, nonblocking unavailability,
unexpected EOF, zero-progress write, broken pipe, timeout, unsupported operation,
connection refusal/reset/abort, unconnected socket, address conflict/unavailability,
network/host unreachability, storage exhaustion, quota/file-size limits, read-only
filesystem, directory/type mismatches, busy/deadlocked resources, excessive links
and invalid executable input. Preserve distinctions for applicable frozen
`ErrorKind` variants; an unrecognized OS condition keeps an unclassified
nonexhaustive category, not a fabricated known condition or a success.
Implementation-reserved/experimental category names do not become stable public
variants through that rule. Explicit application `Other` errors remain distinct.
The enum is open to additional kinds: exhaustive handling must include the
native nonexhaustive alternative.

`Interrupted` permits retry but does not itself retry. `WouldBlock` means the
requested nonblocking progress is unavailable now; it is not EOF.
`UnexpectedEof` and `WriteZero` are synthesized by exact/all helpers as below.
Portable mapping retains the original raw code alongside the kind. The selected
native socket-timeout normalization is in section 9; resolver failure keeps its
resolver-domain numeric information rather than pretending it is an unrelated
filesystem errno.

### 3.2. Reader, Writer and seeking

| Native operation/signature shape | Required behavior |
| --- | --- |
| `Reader.read(mut self, buf: mut [u8]): usize throws Error` | Return `n` in `0..=buf.len`, initializing the reported prefix with bytes in stream order. The supplied slice is already valid initialized storage; a safe implementation cannot make it uninitialized. Short reads are successful. Zero for a nonempty buffer means no bytes available at this source's end, not a universal promise that a growable source never produces more. An empty buffer may return zero without examining the source. |
| `Writer.write(mut self, buf: read [u8]): usize throws Error` | Accept an ordered prefix of at most `buf.len` bytes, reporting its count. A short write is success. Zero on nonempty input indicates no progress, not successful delivery of the remaining bytes. The view is not retained after return. |
| `read_vectored(mut buffers)`, `write_vectored(read buffers)` | Behave as one read/write over the concatenation in slice order, allowing progress to stop inside a slice. Empty slices contribute no bytes. A default implementation may operate on only the first nonempty slice; no scatter/gather syscall or throughput guarantee is implied. |
| `read_exact(mut buf): Unit throws Error` | Retry interruptions and continue after short reads until the buffer is filled. Early EOF yields `UnexpectedEof`; other errors stop immediately. On failure, contents are still initialized but the filled extent is unspecified to the caller. Earlier input consumption is not restored. |
| `write_all(read bytes): Unit throws Error` | Retry interruptions and short writes, advancing only by confirmed counts. Nonempty zero-progress gives `WriteZero`. Failure may follow an externally visible prefix; retrying the whole original input can duplicate output. |
| `flush(mut self): Unit throws Error` | Submit this writer's buffered bytes through its underlying sink. It does not imply filesystem durability, remote receipt or flushing unrelated writers. An unbuffered sink may have no additional work. |
| `Seek.seek(mut self, from: take SeekFrom): u64 throws Error` | Position relative to start, current position or end with checked signed displacement. Negative or unrepresentable positions fail; positions beyond EOF may succeed without extending a file. Return the resulting absolute position. |
| `rewind`, `stream_position`, `seek_relative` | Rewind selects start zero; position queries do not consume bytes; relative seek changes position by the specified displacement. Buffered implementations account for unread buffered bytes and may satisfy relative seeks within their buffer. |
| `stream_len` | Determine length without intentionally changing final position on success. Intermediate seeks may occur; a failing seek can leave the position changed. Not every stream supports length/seek. |

An error from a primitive call reports no successful count for that call. Output
buffer contents need not be unchanged on error. Earlier successful calls in a
compound operation retain their effects. Implementations and callers must check
reported counts before indexing or exposing initialized prefixes; a buggy safe
Reader/Writer implementation is not authority for unchecked memory access.
Reader counts larger than the supplied extent produce `InvalidData` before
appending, decrementing a Take allowance, yielding a byte or publishing a
refilled buffer. Earlier successful progress is retained; an invalid count
does not itself mark a Bytes iterator exhausted.

`read_to_end(mut List<u8>)` appends until EOF, preserving existing contents and
returning the appended count. It retries interruptions, may reserve repeatedly,
and retains successfully read bytes on I/O failure. A source that never reaches
EOF may never return and may grow storage without bound.
`read_to_string(mut String)` similarly appends validated UTF-8. Invalid UTF-8
returns `InvalidData` without changing the original String. An I/O error can
leave already-read valid text appended; it never exposes invalid String storage.
`io.read_to_string(take reader)` creates and returns a new owned String.
`io.copy(mut reader, mut writer): u64 throws Error` transfers until EOF using
bounded scratch storage, retries interruptions and exacts complete writes for
each read chunk. Failure may leave the input advanced farther than the output.
The count is bytes successfully transferred, not a commit/durability token;
successful counts and internal offsets use checked representable arithmetic.

### 3.3. Buffer access and adapters

`IoSlice` and `IoSliceMut` borrow byte slices; construction does not allocate.
On Windows, construction panics if length exceeds the native vector descriptor's
u32 length range; it must not truncate to fit. Other adapter size conversions
likewise cannot silently narrow a borrowed extent.
Read-only versus exclusive access and source regions survive conversion into
platform vector descriptors. `advance(n)`/`advance_slices(n)` remove a prefix
from the descriptor views and panic if `n` exceeds their total available length;
they do not advance a file, move backing bytes or release the backing owners.
Exclusive vectored buffers cannot overlap through independent live loans.

`BufRead.fill_buf(mut self): read [u8] from self throws Error` lends currently
available bytes, refilling only if needed. Empty means current EOF.
`consume(mut self, amount)` discards a prefix already obtained from that buffer;
consuming beyond the available prefix violates the protocol and may panic but
cannot justify memory unsafety in safe code. Refilling/consuming requires the
prior loan to end.

`read_until(delimiter, mut List<u8>)` and `read_line(mut String)` append through
the delimiter, including it, and return the appended byte count. Zero means no
new bytes at EOF. They retry interruptions. The line delimiter is LF; CR before
LF is ordinary retained data. The text operation validates UTF-8 and preserves
the original String unchanged on invalid UTF-8. On I/O failure, the byte form
retains bytes already appended and the text form may retain already collected
valid UTF-8; neither exposes invalid String storage. `skip_until` discards through and
including the delimiter without constructing an owned line.
`split` yields owned byte segments excluding the delimiter; `lines` yields
owned UTF-8 lines without LF and a preceding CR. A final unterminated item is
yielded, but a delimiter at EOF does not add a trailing empty item. Each iterator
item can fail independently and a read error is not silently treated as EOF.

The distinct native lending methods `read_line_into` and
`read_bytes_line_into` clear caller storage first, retain line endings, and lend
from that storage, as specified by library-surface section 11. To make error
contents explicit: on I/O or UTF-8 failure the text buffer is empty and valid;
the byte buffer retains the prefix collected before an I/O failure. Neither
returns a view on failure. Consumed source bytes are not restored.

| Adapter | Ownership, state and completion |
| --- | --- |
| `BufferedReader.new(take reader)`, `with_capacity(capacity, take reader)` | Own source and bounded read-ahead storage; construction allocates but does not read. Capacity is at least the requested size; the default size is not a contract. `buffer()` lends unread bytes. `get_ref`/`get_mut` lend the inner source; direct inner I/O can bypass buffered bytes and must not be presented as coherent stream sequencing. `into_inner(take self)` discards unread buffered bytes and transfers the source. |
| `BufferedWriter.new(take writer)`, `with_capacity` | Own source and pending-output storage. Large writes may bypass buffering after earlier buffered bytes are drained. `buffer()` lends unwritten bytes; `get_mut` bypasses sequencing and does not secretly flush. `flush` drains buffer and invokes the inner writer's flush. |
| `BufferedWriter.into_inner(take self)` | Drain pending bytes before transferring writer. On failure return an `IntoInnerError` owning the still-live buffered writer plus the error; callers can recover/retry rather than lose ownership. Draining does not itself promise inner durability. |
| `into_parts(take self)` | Transfer writer and buffered byte storage without writing. If an inner write panicked, mark the buffer as `WriterPanicked`: external progress is unknown, although bytes can be recovered. Do not retry unknown-progress output automatically during unwind. |
| `BufferedWriter` destruction | Attempt ordinary buffered completion where allowed, ignore returned errors, and release owned state. It is not a substitute for explicit flush. A panicking writer must not cause blind replay of bytes whose written prefix is unknown. |
| `LineWriter` | Own writer; submit complete LF-terminated lines while allowing a trailing incomplete line to remain buffered. Flushing also submits that suffix. CR alone is not a trigger. The same ownership, recovery and partial-write rules apply. |
| `Cursor<T>` | Own storage/accessor `T` and a u64 position, initially zero regardless of existing length. Reads and seeks operate on that storage; fixed writable slices do not grow, growable byte owners may allocate and zero-fill a gap before a write. Position beyond EOF reads zero. Overflow/out-of-range seek fails; no invalid buffer view is created. |
| `Chain<A,B>` | Own/reborrow both readers; read A until its first nonempty-buffer EOF, then B, without merging resource identities. Empty-buffer calls alone must not switch permanently to B. |
| `Take<R>` | Own/reborrow reader and remaining u64 limit; read no more than that limit, decrement by actual progress and expose EOF when it reaches zero. `set_limit` changes allowance, not source position. |
| `Bytes<R>` | Own/reborrow source and yield per-byte outcomes; no mandatory buffer allocation. Errors are values, not termination disguised as EOF. |
| `empty`, `repeat(byte)`, `sink` | Empty always reads EOF, repeat fills requested bytes without EOF, sink accepts all offered bytes. No OS resource or heap allocation is required. |

`by_ref` adapters borrow rather than consume the backing stream. Owning an
adapter does not upgrade a borrow into ownership. Accessor views and iterator
items retain their actual source regions.

`IntoInnerError.error()` lends its error, `into_error(take self)` moves the
error and destroys the retained writer, `into_inner(take self)` moves the writer
and destroys the error, and `into_parts(take self)` transfers both.
`WriterPanicked.into_inner(take self)` transfers its recoverable buffered bytes;
the returned bytes do not establish which prefix reached the external sink.
BufferedWriter seeking first drains pending output and fails without seeking
if that drain fails. Ordinary BufferedReader seek discards read-ahead and
positions relative to the logical stream position, not blindly relative to the
inner cursor. `Cursor.position`/`set_position` observe/set its logical offset
without moving storage or performing I/O; `get_ref`/`get_mut` lend storage and
`into_inner` transfers it, preserving its contents and ordinary validity rules.

### 3.4. Standard streams and pipes

`stdin`, `stdout`, `stderr` produce handles to process-wide streams, not newly
opened independent files. Locks serialize access to the corresponding Mettle
stream state; a lock guard keeps that access until release. They do not serialize
arbitrary foreign writes to the same descriptor or promise whole-message
atomicity across processes. Buffered input may read ahead, so mixing direct
descriptor reads and stdin is not coherent sequencing.

Stdin is line-oriented at terminals only to the extent provided by the terminal;
redirected stdin is a byte stream. Stdout's terminal line buffering and stderr's
unbuffered behavior do not guarantee durability or freedom from errors.
`is_terminal` queries terminal association, not Unicode encoding, color support
or interactive authorization. Windows console byte input/output requires the
console adapter; invalid Unicode byte input is an I/O error, not invalid Text.

Writer `write`/`write_line` formatting, `write_path`, `print`/`eprint`, message
lifetimes and stdout-only EPIPE-to-exit-141 convenience behavior are owned by
library-surface sections 10 and 12. Fallible Writer operations preserve their
first full error and partial output when an error is returned. The explicit
convenience exit does not apply to stderr, arbitrary sockets or ordinary fallible
writers. Independently, ordinary descriptor writes remain subject to the inherited
SIGPIPE disposition.

`std.macros.dbg!` evaluates each supplied operand once, in source order,
formats it through Debug to stderr and returns that operand, or a tuple for
multiple operands. `matches!` evaluates its input once and returns a bool;
an optional guard runs only after its pattern matches. Both accept a trailing
comma. These contracts do not establish profile-gated debug assertions.

`pipe(): (PipeReader, PipeWriter) throws Error` returns two independent unique
owners for a one-way byte stream. Reads block while empty with writers alive;
closing every writer allows EOF after buffered bytes drain. Writes may block
while full and fail with broken pipe when no readers remain, subject to the
selected signal policy. Clones count as live ends. Capacity and atomic-write
limits are OS properties, not unbounded library storage promises. Dropping an
unused inherited pipe end is necessary to observe EOF; neither parent nor child
waiting implicitly closes every clone.

## 4. OS strings and lexical paths

### 4.1. Representation and ownership

`OsStr` is an unsized borrowed native-string view; `OsString` owns its storage.
On Unix and WASI every byte sequence is representable. On Windows every sequence
of UTF-16 code units, including unpaired surrogates, must round-trip through the
wide conversion APIs. Internal encoded bytes are platform-specific, preserve
valid UTF-8 as a subset, and are not an interchange format across targets,
compiler/library versions or independently supplied foreign byte strings.

`as_os_str`/`as_encoded_bytes` borrow without allocation.
`from_encoded_bytes_unchecked` is unsafe: bytes must originate in the same
target/version encoding, and any split must be at a boundary justified by that
encoding, including the permitted boundary around a nonempty valid UTF-8
substring. Arbitrary integer slicing or unvalidated file/network bytes do not
establish that precondition. The resulting view borrows the byte source.
Unix/WASI byte and Windows wide conversions are specified in native-os-contracts.

`to_str(): read Text from self?` validates Unicode and returns none when the
native representation is not Unicode; it does not replace bytes.
`into_string(take self)` either transfers an owned valid String or returns the
original OsString in the failure alternative. `to_string_lossy` replaces invalid
sequences with U+FFFD, borrowing if already valid and otherwise allocating;
it is display, not reversible path serialization.
`display` borrows the original and formats human-readable replacement text.
`Writer.write_path` instead follows the separately selected byte/escape policy.

`new`, `with_capacity`, `reserve`/`try_reserve`, `reserve_exact`/
`try_reserve_exact`, `shrink_to`/`shrink_to_fit`, `capacity`, `len`, `clear`,
`push`, clone and boxed conversions have ordinary owned-buffer contracts:
capacity counts encoded storage units exposed by the API, not Unicode scalars;
growth can invalidate views only after their loans end; fallible reservation
preserves the original contents; clear preserves capacity; shrinking never
changes contents and need not reach an exact allocator size. `push(read input)`
copies native content without inserting separators. Owned conversions move
where representationally possible; borrowed-to-owned conversion copies.
ASCII case/query operations change or compare only ASCII letters and leave
non-ASCII representation intact. Equality/order/hash operate on the native
string representation, not locale case-folding or filesystem equivalence.
`into_encoded_bytes(take self)` transfers the encoding bytes with the same
noninterchange-format restriction as the borrowed exposure.
`OsString.leak(take self)` intentionally relinquishes deallocation and returns
an exclusive OsStr view for the selected region under its region restrictions;
unused capacity can remain leaked. It does not leak a second owner that can
concurrently free the storage.

### 4.2. Path components and mutation

`Path` borrows native path storage; `PathBuf` owns it. Conversion between Path
and OsStr or their owning forms preserves contents, not a parsed filesystem
object. `Path.new(read input)` and `as_path` lend; `to_path_buf` copies;
`into_os_string` and boxed ownership conversions transfer ownership.

`components` yields borrowed prefix/root/current/parent/normal components.
Unix separators are `/`; Windows ordinarily recognizes both slash forms and
drive, UNC, device and verbatim prefixes. Repeated separators and noninitial
`.` components are normalized for ordinary lexical component iteration; an
initial relative `.` is retained. `..` is not resolved against preceding names.
Windows verbatim paths preserve their special separator/normalization rules.
`iter` yields the component OS-string views; `ancestors` yields self and repeated
parents through the empty relative ancestor or root. These iterators allocate
nothing and keep the source loan.

| Operations | Lexical result |
| --- | --- |
| `is_absolute`, `is_relative`, `has_root` | Unix rooted paths are absolute. Windows absolute paths require the appropriate prefix and root; `\name` can have a root without a drive, and `C:name` is drive-relative, not absolute. |
| `parent`, `file_name` | Parent removes the final component; roots/prefix-only paths have no parent. Normal final components are names; paths ending in unresolved `..` do not invent a filename. |
| `file_stem`, `extension` | Split a filename at its last dot; a leading dot alone does not create an extension. No dot means no extension; a final dot gives an empty extension. |
| `file_prefix` | Split before the first nonleading dot, retaining the leading-dot component of a dotfile. This differs from stem for multi-extension names. |
| `starts_with`, `ends_with`, `strip_prefix` | Compare complete normalized components, not arbitrary encoded-byte prefixes or filesystem identities. A failed strip returns its typed mismatch error. Returned suffix borrows the original path. |
| `join(read input)`, `push(read input)` | Join returns an allocated PathBuf; push mutates the owner. Insert a separator where needed. An absolute input replaces the base. Windows rooted-without-prefix input retains the base prefix, and a prefixed input replaces the base; verbatim-base joining applies the platform lexical normalization. |
| `pop` | Remove the last component if a parent exists; return whether removal occurred. It does not remove anything on disk. |
| `set_file_name`, `with_file_name` | Replace final name, or append where no final name exists. Input containing separators is path input, not a validated single component. |
| `set_extension`, `with_extension` | Replace the last extension, remove it for empty input, and fail to change when there is no filename. A separator in an extension is a programmer error and panics. |
| `add_extension`, `with_added_extension` | Append a dot and extension to an existing filename instead of replacing its old extension; empty extension leaves the name unchanged. Apply the same separator check. |

PathBuf capacity/clear/reservation/shrink methods follow the OsString rules.
`as_mut_os_string` and `as_mut_os_str` lend the appropriate exclusive backing
view, with no stronger path-validity invariant than native string storage;
`PathBuf.leak` has the same intentional allocation-leak contract as OsString.
Path comparisons and hashing use normalized lexical components, so harmless
separator/`.` spelling differences can compare equal; this does not change
OsStr's representation comparison or imply filesystem identity.
Mutations are linear in affected path bytes and may allocate; component
inspection is allocation-free and scans at most the path. `absolute(read path)`
uses current-directory information to produce an absolute lexical path and can
fail to obtain that information; it does not require the object to exist or
resolve symlinks. `canonicalize` does require OS resolution as in section 5.
No path parser performs Unicode normalization, sandbox confinement, `..`
elimination across symlinks or case-insensitive filesystem lookup.

### 4.3. Windows prefix and verbatim components

These are lexical rules over the native OS string, not an instruction to open
a device or validate a filesystem name. A PrefixComponent lends its original
spelling through `as_os_str`; `kind` returns the parsed Prefix with its embedded
OS-string views still borrowing the same input. Parsed drive letters are ASCII
uppercase, while the original prefix spelling remains unchanged.

| Prefix kind | Recognition and payload |
| --- | --- |
| `Disk(letter)` | An ASCII letter followed by `:` at the beginning. It consumes those two units, even if a relative name immediately follows. |
| `UNC(server, share)` | Two leading separators, a nonempty server component, a separator and a nonempty share component. Either slash spelling is a separator. Incomplete ordinary UNC spelling does not manufacture a prefix. |
| `DeviceNS(device)` | Two leading separators, `.`, another separator, then one component as the device name. Either slash spelling is accepted in the introducer and component splitting. |
| `VerbatimDisk(letter)` | Literal `\\?\`, followed by an ASCII drive letter and `:`, with end-of-input or a slash/backslash immediately after the colon. The prefix ends at the colon. |
| `VerbatimUNC(server, share)` | Literal `\\?\UNC\`, with uppercase `UNC`, then server and share components split only at backslashes. This is lexical recognition; empty verbatim server/share components are not rejected here as they are for ordinary UNC. |
| `Verbatim(name)` | Literal `\\?\` followed by its first backslash-delimited component when the preceding two verbatim forms do not match. Thus `\\?\C:relative` has a generic verbatim prefix, not a VerbatimDisk prefix. |

Recognition tries the special introducers before ordinary UNC and drive forms.
Outside the verbatim introducer, slash/backslash substitutions are accepted;
the four units `\\?\` themselves must be literal backslashes. A slash-modified
lookalike is not verbatim. Prefix names/server/share/device content is not
case-folded; only a parsed drive letter is normalized.
`Prefix.is_verbatim` is true exactly for Verbatim, VerbatimDisk and VerbatimUNC,
not DeviceNS.
`Component.as_os_str` lends the stored spelling for Prefix/Normal and the
canonical separator, `.` or `..` for RootDir/CurDir/ParentDir. Components supports
forward/reverse traversal of that same component sequence; `as_path` lends the
remaining unconsumed path without allocation. No component view outlives its
actual input or static canonical backing.

After prefix removal, component iteration recognizes an immediate physical
root using the ordinary Windows slash/backslash test. Within the subsequent
verbatim body, only backslash separates components: `/` is content, `.` is
returned as CurDir, and `..` as ParentDir. Empty components from repeated or
trailing backslashes are skipped. The ordinary nonverbatim body instead skips
noninitial `.` as in section 4.2.

`has_root` is true for a physical root or any parsed prefix other than Disk.
Consequently a verbatim prefix can imply rootedness even with no physical
separator. Component iteration emits an implicit RootDir only for nonverbatim
root-implying prefixes; it does not invent a missing separator for a verbatim
prefix. `is_absolute` requires both a prefix and rootedness. These distinctions
are why rootedness cannot be inferred merely by counting emitted RootDir items.

For `PathBuf.push`/`Path.join`, any prefixed or absolute input replaces the base.
An unprefixed rooted input otherwise retains only the base prefix.
There is a specific verbatim-base rule for a nonempty unprefixed input:
start from the base's components; an incoming root discards everything after
the prefix, an incoming `.` is omitted, and an incoming `..` removes the last
component only if it is Normal, otherwise contributing nothing. Other incoming
components append. Reconstruct using backslash separators. This does not
retroactively resolve the base's existing ParentDir components or inspect
symlinks. Empty input does not run that normalization.

Windows `absolute` preserves a recognized verbatim input's spelling, rejecting
embedded NUL; other inputs use the platform full-path expansion, including its
drive-relative/current-directory rules, and return errors rather than truncated
paths. Neither prefix parsing nor `absolute` proves that a device/path exists.

## 5. Files and directories

OS path-taking calls reject embedded NUL with `InvalidInput` before invoking
the path operation. Separate path inputs borrow independently. No call receives
permission to retain a caller's string after return.

### 5.1. Opening, file state and metadata

`File.open(read path)` opens for reading; `File.create(read path)` opens for
writing, creating or truncating; `create_new` atomically requires nonexistence
at the opened name, including refusing an existing symlink.
`OpenOptions.new` initially enables no access. Its read/write/append/truncate/
create/create_new setters overwrite their flags. `open` needs a coherent access
combination: truncation needs write access, creation needs write or append, and
`create_new` takes precedence over create/truncate. Invalid combinations fail
with `InvalidInput`, not silent access escalation.

Append writes target the current end atomically with respect to the OS append
operation; a complete multi-call write or formatted message need not be atomic.
Concurrent appenders can interleave between partial writes. Reading through an
append-open handle still has a cursor, whose position can be affected by writes.
Opening/truncation can take effect even if later work fails. Creation permissions
and platform sharing flags are owned by native-os-contracts.

File implements Reader, Writer and Seek with section 3 semantics.
`File.options()` is an OpenOptions constructor, not a query of an open file.
`try_clone` creates another owned reference to the same open-file state: cursor,
status and relevant locks can be shared. It does not promise an independent
seek position. `set_len(size: u64)` truncates or zero-extends contents without
changing the cursor; cursor past new EOF remains there. `sync_all` requests
content plus metadata synchronization, `sync_data` only the data and metadata
needed for it. Platform/device guarantees still determine persistence; neither
implicitly synchronizes the parent directory's namespace change.

`metadata` queries the open object. `set_permissions(take Permissions)` and
`set_times(take FileTimes)` modify it; FileTimes' optional accessed/modified
fields leave unspecified timestamps unchanged. Repeated setters replace the
selected field. Timestamp precision/range and creation-time support depend on
the platform and can fail; unsupported fields are not silently reported as set.

`Metadata` owns a snapshot. Length, permissions, file type and available
accessed/modified/created times describe that observation; querying an unsupported
timestamp returns an error. FileType distinguishes regular file, directory and
symlink plus platform extensions. `Permissions.readonly` expresses the platform
read-only projection, not an access-control decision; `set_readonly(false)` can
broaden Unix write permission bits and does not bypass ACLs, credentials or
read-only mounts. Clone copies snapshot values, not live OS objects.

`lock`/`lock_shared` block for exclusive/shared file locks; `try_lock`/
`try_lock_shared` return `WouldBlock` separately from an OS error.
`unlock` releases locks associated with that open resource. Reacquiring through
the same or a cloned handle is platform-dependent and can deadlock; unlocking
an unlocked resource may succeed or fail. Advisory versus mandatory enforcement
is an OS/filesystem property. These operations are not Mettle payload mutexes
and do not bypass the borrow or memory model.

### 5.2. Name operations

| Operation | Results, failure and externally visible effects |
| --- | --- |
| `metadata`, `symlink_metadata` | Follow the final symlink versus inspect it. Return owned snapshots. Intermediate components are resolved by the OS. |
| `exists`, `Path.try_exists` | Follow the path; return false for a missing object/dangling symlink, propagate other errors. `Path.exists`, `is_file`, `is_dir`, `is_symlink` are convenience booleans that return false on failed inspection; they are not permission/existence proofs. |
| `canonicalize` | Resolve an existing path and symlinks to an absolute native PathBuf, failing if resolution fails. Windows can return an extended-length spelling; do not strip its prefix or feed it to a different parser as ordinary text. |
| `read_link` | Return owned stored link target, possibly relative and possibly nonexistent. It does not canonicalize against the link's parent. |
| `read`, `read_to_string`, `write` | Read a whole file into new owned bytes/validated UTF-8, or create/truncate and completely write supplied bytes. Retry interrupted byte transfer. Read allocation scales with actual bytes, not a trusted metadata size. Failed write can leave a created/truncated/partial file. |
| `copy(from,to): u64 throws Error` | Copy file contents and permission bits, replacing destination contents; return copied byte count. No atomic replacement, sparse-layout preservation, metadata completeness or source snapshot is implied. Aliased source/destination can truncate the source; check identity separately if required. Failure can leave a partial destination. |
| `rename(from,to)` | Rename/move according to the filesystem's namespace rules; an existing destination may be replaced where the OS permits. Cross-filesystem moves can fail; there is no hidden copy/delete fallback. Atomic namespace replacement on success does not make it durable or preserve handles by pathname. |
| `hard_link(from,to)` | Create another name for an existing object where allowed. It does not clone bytes or permit cross-filesystem linking automatically. Existing destination and unsupported object/filesystem cases fail. |
| `create_dir`, `create_dir_all` | Create one directory, or missing ancestor directories. The recursive form is not transactional, tolerates concurrently created needed directories, and can leave ancestors behind on failure. Empty recursive input is a no-op. |
| `remove_file`, `remove_dir` | Remove a name or an empty directory; reject incompatible cases according to the platform. Removing a name need not destroy an object still held open. |
| `remove_dir_all` | Recursively remove children without traversing symlink targets; removing a symlink removes the link, not its target. Partial deletion remains on failure. Concurrent mutation can cause failure, including a nonempty directory. The adapter must prevent symlink-replacement races from escaping the tree where the profile supplies the needed relative-handle operations; WASI Preview 1 does not establish that protection automatically. |
| `set_permissions`, `set_times`, `set_times_nofollow` | Change the named object, following the final symlink except for the explicit nofollow timestamp form. They are subject to permission/range/support errors and do not provide a multi-field transaction across separate calls. |

`read_dir(read path)` owns directory iteration state. Construction and each
`next()` can fail separately. Entries exclude `.` and `..`; order is unspecified
and concurrent mutation need not yield a snapshot. `DirEntry.file_name` returns
owned native spelling, `path` builds an owned joined path, and metadata/type
queries can fail after enumeration. DirEntry may retain directory resources
beyond iterator destruction; collecting entries therefore can retain handles.
Recursive operations use storage proportional to traversal state, not a promise
of constant space or bounded directory depth.

`DirBuilder.new` starts nonrecursive. `recursive(bool)` changes that choice;
`create(read path)` performs the corresponding create_dir/create_dir_all
operation without consuming the builder. Its Unix mode extension selects
requested permissions for newly created directories, filtered by umask, and
does not chmod directories already present.

## 6. Environment and processes

### 6.1. Process-global input

The native `env.args()` returns owned OS strings, as selected by library-surface
section 12; `args_os` is the canonical native-preserving exposure of the same
argument source. Iteration owns its snapshot, including the executable spelling
at position zero when supplied by the host. It is not proof of `current_exe`,
and OS parsing/startup determines how the command line became arguments.
Unicode-only argument exposures, if separately retained by the canonical
mapping, panic on invalid Unicode rather than losing native data.

`var_os(read key): OsString?` returns an owned native value or absence.
`var(read key): String throws VarError` distinguishes absent from present but
non-Unicode; the latter error owns the original OsString. `vars_os` snapshots
native key/value pairs; Unicode `vars` panics on non-Unicode data. Iterators do
not keep a live pointer into mutable process environment storage.
Invalid lookup keys containing NUL or `=` are absent, while mutation validates
them as below.

`set_var(read key, read value)` and `remove_var(read key)` mutate the current
process environment, not existing children. Empty keys, `=`/NUL in a key, or NUL
in a value panic before mutation. Preserve their unsafe-call requirement:
outside Windows, callers must exclude concurrent environment reads or mutations,
including foreign code and indirectly environment-reading services. A library
mutex that foreign code does not share is insufficient. Windows supplies its
platform-safe environment mutation boundary. Prefer a Command's private
environment when starting children.

`split_paths(read OsStr)` lends an iterator that returns owned PathBuf entries,
splitting the platform PATH format, including empty entries.
`join_paths(take iterable)` consumes the iterator, reads each path and creates
an owned native list string; separators within Unix entries or quotes within
Windows entries yield `JoinPathsError`. Windows separator-containing entries
are quoted rather than split. Neither API performs filesystem lookup.

`current_dir` and `current_exe` allocate native PathBuf results and can fail.
The executable path can reflect symlink, rename, namespace and OS limitations;
it is not a trusted executable identity. `set_current_dir` changes process-wide
resolution state, racing with other relative-path users.
`temp_dir` returns the configured/default path without creating or securing a
directory; `home_dir` returns an optional platform-discovered home path, with
no existence/access/security guarantee. Unix discovery uses the process home
setting or user database; Windows uses the user-profile setting/service.
WASI need not have either directory convention.

### 6.2. Commands, children and termination

`Command.new(read program)` owns a copy of the native executable specification.
`arg`/`args` append owned native arguments without invoking a shell or splitting
on spaces; Windows constructs a command line for the selected child parser.
An executable that uses different parsing requires the explicit raw OS
extension. `env`/`envs`, `env_remove`, `env_clear` build a private child
environment, inheriting parent entries not overridden unless cleared.
Windows environment keys compare case-insensitively; Unix keys do not.
`current_dir`, stdin/stdout/stderr configuration and setters persist in the
builder across uses. Getter iterators lend the builder's configured entries,
not a computed snapshot of all inherited OS state.

Paths and arguments reject NUL before launch with `InvalidInput`. Executable
search and relative executable/current-directory interactions follow the
target's launch rules; use an absolute program path when that ambiguity matters.
Builder mutation may allocate proportional to accumulated strings. Spawning
does not consume the builder, but each returned Child owns distinct process/
stream resources.

The current Unix builder retains only the latest edit for each environment key,
including removal markers. An unmodified environment is inherited at launch
without building a library-owned snapshot.

`spawn` returns a Child after launch setup, not after successful program exit.
`status` waits and returns ExitStatus, inheriting standard streams by default.
`output` captures stdout/stderr and supplies closed/null stdin by default.
Explicit overrides take precedence. `Stdio.inherit`, `null`, `piped` select
inheritance, a null device or a new pipe; conversion from an owned file/pipe
consumes that resource, while a borrowed conversion must duplicate it explicitly.
Launch failure closes partially created library resources, but a child can
already have produced effects before a later reporting error.

| Child operation | Ownership and progress |
| --- | --- |
| `id`, `try_wait` | Observe identifier or optional completion. A completed status can be returned repeatedly. IDs can be reused after OS lifetime ends and are not a permanent capability. |
| `wait(mut self)` | Close the Child's still-owned stdin endpoint before waiting, reap/obtain completion, and cache status. It does not close pipe ends moved out by the caller or prevent output-pipe deadlock if nobody drains them. |
| `kill(mut self)` | Request forced termination using the target mechanism; return an OS error if that request fails. It is not join/reap, does not kill a whole process tree and does not ensure graceful cleanup. |
| `wait_with_output(take self)` | Close owned stdin, drain owned stdout and stderr concurrently enough to avoid mutual pipe-capacity deadlock, wait and return owned bytes plus status. Capture can grow without bound. Failure need not return already captured output. |
| Child/stream destruction | Close owned handles, not implicitly kill and wait for the process. A child may outlive its handle; Unix reaping remains the caller's responsibility. Moving a pipe endpoint out transfers its close obligation. |

ExitStatus distinguishes success from failure and optional numeric exit code;
signal termination on Unix is not an invented ordinary exit code.
ExitStatusError owns an unsuccessful status and can expose it again.
`ExitCode` represents the portable process-exit-code value under its target
conversion, not an entire wait status. `Termination.report` translates the main
result according to its declared implementation; stored errors are not silently
discarded.

`process.id(): u32` observes the current process ID without allocation or a new
process reference; OS reuse rules apply after that process ends.
`process.exit(code): Never` immediately terminates without unwinding live Mettle
stacks or running their destructors; foreign/runtime exit handling follows the
platform. Unix shell-observable numeric status uses the OS low-byte convention.
`abort(): Never` requests abnormal termination without language cleanup.
Normal return from main performs ordinary destruction and the selected main
thread TLS teardown. Hosted panic recovery and uncaught status 101 remain owned
by library-surface section 1 and library-and-abi section 6.

### 6.3. Windows command-line construction

The command builder owns the logical native strings supplied by `arg`/`args`.
Ordinary Windows launch serializes them into a temporary UTF-16 command line
for the standard C-runtime argument parser. This is separate from the resolved
executable path passed to process creation; executable lookup does not rewrite
the configured program spelling exposed to the child as its program argument.
The program spelling is surrounded by double quotes. Arguments are separated
by a single space, and each regular argument is encoded as follows:

- Surround an empty argument, or one containing space or tab, with double
  quotes. Ordinary nonempty arguments without those characters need no outer
  quotes.
- Preserve ordinary UTF-16 units, including unpaired surrogates. For a run of
  n backslashes followed by a literal double quote, output 2n+1 backslashes
  followed by that quote. A literal double quote without preceding backslashes
  is therefore escaped by one backslash.
- Immediately before a closing outer quote, double a trailing run of
  backslashes. Otherwise leave a backslash run unchanged.

The resulting standard-parser arguments retain the input boundaries, literal
quotes and backslashes. This encoding performs no globbing, environment
expansion or shell evaluation. NUL is rejected with InvalidInput at launch;
invalid executable names/process-creation limits produce ordinary launch
errors. Construction takes linear storage/time in the encoded command line.

`CommandExt.raw_arg` appends its copied wide content after the argument separator
without these transformations. It does not assert that the content corresponds
to one argument. Mixing regular and raw entries preserves insertion order;
the chosen child parser determines how the combined string is interpreted.
Neither regular CRT encoding nor raw_arg is a general escaping contract for
an explicit `cmd.exe /c`, PowerShell or another custom parser.

The pinned launch selection also recognizes a resolved `.bat` or `.cmd` suffix,
ASCII-case-insensitively, and invokes the system command processor rather than
treating the script as a CRT executable. It uses command extensions enabled,
delayed expansion disabled and AutoRun disabled (`/e:ON /v:OFF /d /c`), with an
outer quote pair around the script invocation and a separate pair around the
script path. A script path containing a quote or ending in backslash is
InvalidInput; ordinary batch arguments containing CR or LF are InvalidInput.
The batch-specific regular-argument encoding:

- Quotes empty values and values ending in backslash. It also quotes ASCII
  punctuation other than `#$*+-./:?@\_`, and control characters; ASCII letters
  and digits do not themselves require quotes.
- Doubles each literal quote and doubles the backslash run immediately before
  it; doubles trailing backslashes before an outer closing quote.
- Shields each `%` from environment-variable expansion by placing an empty
  `%cd:~,%` expansion after an extra `%`, yielding `%%cd:~,%` for the original
  percent unit.

Raw entries bypass batch regular-argument encoding, including its CR/LF check,
but still reject NUL. These rules describe transport to the command processor,
not the safety of a batch file's own substitutions, re-parsing or use of
untrusted arguments as commands. The batch compatibility behavior is not a
promise that every possible input can be escaped; rejected inputs return a
launch error, and scripts with custom parsing still require caller-specific
validation. No experimental force-quotes API is selected by these rules.

## 7. Clocks

### 7.1. Allocation-free Duration values

`Duration` is a nonnegative amount of time with a u64 whole-second part and
nanoseconds in `0..1_000_000_000`. `ZERO` is zero; `MAX` is u64::MAX seconds
plus 999,999,999 nanoseconds. Named unit constants denote their exact durations.
It is a Copy value; a consuming operation still uses the native take rule.
All integer construction, queries, comparisons and arithmetic require O(1)
storage/time and no OS, allocator or executor.

`new(secs: u64, nanos: u32)` carries excess nanoseconds into seconds and panics
if that carry overflows. `from_secs`, `from_millis`, `from_micros`,
`from_nanos(u64)` construct exactly, quotient/remainder-normalizing subsecond
units. `from_nanos_u128` panics if the total does not fit Duration.
`from_mins`/`from_hours` use checked scale conversion and panic on overflow.
These panics do not become wrapping behavior in Release or const evaluation.

`as_secs(): u64` returns whole seconds. `as_millis`/`as_micros`/`as_nanos`
return total whole units as u128 without truncating to u64.
`subsec_millis`/`subsec_micros`/`subsec_nanos` return the fractional-second
component in the indicated units, not total elapsed units; sub-nanosecond
information does not exist. `is_zero` tests both stored parts.

`checked_add`, `checked_sub`, `checked_mul(u32)` and `checked_div(u32)` return
none on range failure, negative difference or division by zero.
Ordinary add/subtract/multiply/divide and their assignment forms panic for the
corresponding failure. Integer division truncates toward zero at nanosecond
resolution. `saturating_add`/`saturating_mul` clamp to MAX; saturating subtraction
clamps to ZERO. `abs_diff` returns the exact nonnegative difference.
Summation starts at ZERO and uses checked-range ordinary addition; it panics on
overflow and does not secretly saturate. Summing n inputs takes O(n) iterator
steps and O(1) accumulator storage, excluding the iterator's own work.

`as_secs_f32/f64` convert to approximate floating seconds with the named width's
rounding. `from_secs_f32/f64` reject negative, nonfinite and out-of-range values
by panic; `try_from_secs_f32/f64` instead return TryFromFloatSecsError without
allocation. Finite accepted values round to the nearest representable nanosecond
with halfway ties to even; signed negative zero represents ZERO.
`mul_f32/f64` and `div_f32/f64` perform the named-width floating-second
calculation and convert back under those same range/rounding checks, not exact
rational arithmetic. `div_duration_f32/f64` instead return a floating ratio;
zero divisors follow floating division (infinity or NaN), not integer-divide
panic. No floating conversion promises invertibility at large durations.
Exact stable const eligibility is per operation, independent of runtime
availability.

### 7.2. Monotonic and wall clocks

`Instant.now` produces an opaque monotonic-clock reading; it has no portable
epoch and cannot be serialized as wall time. Suspend accounting and resolution
are profile properties. `SystemTime.now` reads wall time and may move backward;
`UNIX_EPOCH` is its selected reference point, not a monotonic origin.
Neither type implies nanosecond measurement precision merely because Duration
can represent nanoseconds.

`Instant.duration_since`/`elapsed` saturate to zero for a reversed ordering;
`checked_duration_since` returns none instead, and
`saturating_duration_since` names saturation explicitly.
`SystemTime.duration_since`/`elapsed` return a duration or SystemTimeError owning
the magnitude of the reversed difference. `SystemTimeError.duration` reads that
magnitude. Clock reads and arithmetic require no heap allocation.

`checked_add`/`checked_sub` return none when an instant/time is outside the
representable range. Operators and assignment operators panic on such overflow,
in every optimization profile; they do not wrap platform timestamps. Duration's
independent native arithmetic rules still apply. Time comparison/clone/hash do
not query a fresh clock or refresh a stored reading.

The native `system_time_from_parts(secs: i64, nanos: u32)` constructor carries
whole seconds from nanos and retains a fractional part below 1_000_000_000.
That carry is checked: overflow of the signed seconds range panics in every
optimization profile rather than wrapping the timestamp.

## 8. Threads, TLS and synchronization

### 8.1. Thread lifecycle

`spawn(take closure): JoinHandle<T>` requires the consuming closure and result
to be Transferable and Static. `Builder.spawn` is fallible with `io.Error` for
OS thread creation; the convenience spawn panics on that failure.
Builder name and minimum stack-size requests are owned configuration; actual
stack size can be rounded up and invalid names containing NUL panic. Launch
transfers closure ownership to the new thread; a failed launch destroys it
without calling it.
The spawned thread and its handles report the full configured name, including
an empty name; without a configured name they report none.

Thread start publishes the captured state to the child. `join(take handle)`
waits, then returns owned output or the owned panic payload; completed child
effects happen-before successful join return. Child panic does not itself panic
the joiner. `is_finished` is only a completion observation, not join's
publication edge or proof TLS cleanup has completed.
Dropping a join handle detaches; it does not cancel the thread. Cloning a Thread
notification handle does not clone the execution or its result.

`thread.scope(take callback)` allows scoped children borrowing the scope's
region under Transferable/Shareable bounds. All running children must be joined
before the scope returns or resumes a panic, including children with forgotten
handles. Manually joined panic results can be handled; an unhandled child panic
causes the scope to panic after other children are joined. Scoped handles never
authorize a borrowed child to outlive its storage.
`Builder.spawn_unchecked` is unsafe: the caller must keep captured borrows and
result dependencies alive until actual termination/join; forgetting or dropping
the handle does not establish this.

`current`, `Thread.id`, `Thread.name` expose identity and borrowed optional name
without transferring execution ownership. ThreadId is opaque and not a raw OS
thread ID; its equality/hash preserve identity and do not grant signaling rights.
`available_parallelism` returns a fallible nonzero scheduling-capacity estimate,
not a reservation, affinity mask or immutable core count.
`panicking()` reports whether the calling thread is currently unwinding a
Mettle panic; it does not inspect another thread or predict a later panic.

`sleep(duration)` blocks for at least the requested duration, subject to clock
resolution and scheduling, retrying interruption as needed; zero need not yield.
`yield_now` offers execution to the scheduler without fairness promises.
Each thread has one park token: `unpark` makes it available and `park` consumes
it, or waits. Multiple notifications coalesce. Spurious wakeups are permitted;
use a predicate loop. Release by unpark and acquire by a matching park publish
prior memory effects. `park_timeout` may return spuriously or after the duration
and does not distinguish those outcomes by a return value.

### 8.2. TLS

The selected `std.sync.tls.LocalKey` declaration, dynamic `new`, reverse
installation destruction, bounded destructor passes and main-thread cleanup
are specified in library-and-abi section 6. The canonical `std.thread.LocalKey`
exposure must preserve the same applicable access semantics, not create a
second independently initialized key through a reexport.

`with` consumes a callback borrowing this thread's value only for the callback;
its result cannot smuggle out that loan. First access initializes only this
thread's instance. Initialization panic propagates without exposing partial T.
Access while the same value is being destroyed fails: `try_with` returns
AccessError, while `with` panics. Initialization reentrancy is not a supported
way to obtain partially initialized storage and can panic or fail to terminate.
Process exit/abort/foreign thread teardown do not promise full destructor runs.

Replacing the entire stored T while a `with` callback borrows it must panic
before mutation or destruction of that T. Callback cleanup releases this access
on both return and panic. This does not prohibit mutation through a borrowed
Cell or RefCell under that wrapper's own access rules.

Cell-like key `set` directly installs/replaces without running the default
initializer; replacement destroys the old initialized value. `get`, `replace`,
`take`, `update` retain their Copy/default/callback bounds and transfer the
specified values, not hidden clones. RefCell-like `with_borrow`/
`with_borrow_mut` keep checked shared/exclusive access through the callback and
panic on conflicting dynamic access. Callback panic releases the active loan
before ordinary unwinding continues.

### 8.3. Locks, conditions and barriers

| Facility and signature family | Required contract |
| --- | --- |
| `Mutex.new(take T)`, `lock(read self)` | Own T; lock returns an exclusive guard tied to self. Contended lock blocks. Unlock on guard drop publishes writes to a later successful acquisition. Guard is not Transferable where OS unlock affinity forbids it; Shareable access to a guard never grants mutation. |
| `try_lock` | Return guard, `WouldBlock`, or poison containing an acquired guard. It does not wait for availability. Poison is not loss of the payload. |
| `RwLock.read`/`write`, `try_read`/`try_write` | Multiple shared guards or one exclusive guard; same publication rules as lock acquisition/release. Scheduling priority between readers/writers is unspecified. Reentrant acquisition can deadlock. |
| `RwLockWriteGuard.downgrade(take guard)` | Atomically replace exclusive ownership by a read guard, without an intervening writer acquiring the lock. The old guard is consumed and must not unlock again. |
| `is_poisoned`, `clear_poison`, `PoisonError.get_ref/get_mut/into_inner` | Query advisory state, explicitly clear it, or inspect/recover the stored acquired guard/value. Clearing does not repair T. A false query is not a guarantee against later poison. |
| `get_mut(mut lock)`, `into_inner(take lock)` | Obtain exclusive T access or transfer T without locking, using the existing exclusive/owned authority. Poison remains an explicit result carrying the obtainable access/value. |
| `Condvar.wait(take MutexGuard)` | Atomically release the associated mutex and wait; reacquire it before returning a guard or poison containing that guard. Spurious wakeups are allowed. Concurrent waits must use the same mutex; reject a conflicting live association before entering the OS wait. Sequential reuse with another mutex is allowed after all waits finish. |
| `wait_while`, timeout variants | Recheck predicate while holding the reacquired guard. Timeout status is a clock/wait observation, not proof the predicate is false. Repeated wakeups do not reset the total wait budget of a timeout-while call. |
| `notify_one`, `notify_all` | Wake eligible current waiters, without accumulating a future notification token and without transferring the mutex. Publish shared data through the mutex, not the notification alone. |
| `Barrier.new(n)`, `wait` | Reusable generations release participating threads once the generation's count is met; prior participant effects are visible after successful passage. One result per completed generation is designated leader. No cancellation removes a missing participant. |

Zero and one are valid participant counts. For either, each `wait` completes
without waiting for another participant and its `is_leader()` result is true.
This does not rendezvous with an unrelated caller or publish that caller's
otherwise unsynchronized effects. Larger counts require that many arrivals per
generation; forgetting a participant is not cancellation.

Panic while holding a Mutex guard poisons it; RwLock poison is associated with
panic under exclusive writing, not ordinary shared reading. Poison detection
is advisory and cannot be relied on as the unsafe boundary establishing T's
validity. Recovery/clear and exception contexts can defeat simplistic "poison
means invalid; unpoisoned means valid" reasoning. Locks remain safe when their
guards are forgotten: leakage may permanently lock or retain resources but
cannot expose a conflicting safe loan. Blocking, locking storage allocation and
OS errors remain profile-dependent; uncontended lock/unlock do not clone T.

`Once.call_once(take callback)` runs one successful initializer and blocks
competing calls until it finishes. Its successful effects are published before
other successful callers return. Initializer panic poisons; ordinary call_once
and wait then panic. `call_once_force` supplies OnceState describing poison
and can clear it by succeeding; a new panic keeps poison.
`wait_force` ignores poison and waits for successful completion, not merely
for the failing attempt to end. `is_completed` is false before successful
initialization, including poisoned state. Recursive initialization can deadlock
or panic; no partial success is published.

`OnceLock<T>` owns an initially empty slot. `set(take T)` waits for competing
initialization and returns the uninstalled T if already initialized.
`get` is nonblocking and returns none while empty/initializing; `wait` blocks
for an initialized read view. `get_or_init(take callback)` runs at most one
successful initializer, propagates panic and leaves the slot available for
retry rather than poisoning it. Exclusive `get_mut`/`take` require a mutable
receiver; take empties the slot and moves T out.
`LazyLock<T,F>` owns a single initializer and initializes on force/dereference.
A panic poisons it permanently; later force attempts panic rather than reuse
the consumed F. `force_mut` requires exclusive access and returns an exclusive
view; nonforcing getters return none until initialized. These primitives retain
the exact stable member set; experimental fallible-initialization variants do
not become available through this family description.

### 8.4. Channels

`channel<T>()` returns an unbounded FIFO Sender and single Receiver;
`sync_channel<T>(capacity)` returns bounded SyncSender and Receiver. Senders can
be explicitly cloned; receiver ownership is not clonable. Messages cross threads
only when T is Transferable. A channel owns each accepted queued T exactly once.

`send(take T)` transfers on success; disconnection returns the unaccepted T in
SendError. Unbounded send does not wait for a receive but may allocate.
Bounded send waits for capacity, and capacity zero is a rendezvous that completes
only when a receive takes the message. Successful enqueue is not proof the
receiver's application code has processed the value.
`try_send(take T)` returns Full(T) or Disconnected(T) without losing the value.
The native `send_timeout` additionally returns T on expiration; it must not
report a returned value that has also been accepted by a receiver.

Receipt and reclamation bookkeeping belongs to each individual send attempt:
a sender cannot reclaim another attempt's T or use its receipt as acknowledgment.

`recv()` moves the oldest queued T or reports disconnection once all senders
are gone and the queue is drained. `try_recv` distinguishes connected-empty from
drained-disconnected. `recv_timeout` distinguishes timeout from disconnection.
Timeout races choose one result without delivering or destroying a message twice.
Queue publication synchronizes a successful send with receipt of that message.
FIFO preserves each sender's order; simultaneous sends do not promise a
cross-thread wall-clock ordering.

Blocking receiver iteration ends on drained disconnection; try-iteration ends
when no message is immediately available and does not promise permanent EOF
while senders remain. Dropping Receiver disconnects senders and drops queued
values; dropping the final sender wakes blocked receivers. Dropping a failed
send error drops its still-owned T. Buffered channels retain storage proportional
to queued messages/capacity; a rendezvous needs synchronization storage but no
message queue.

Destroy accepted values discarded on receiver close without holding the internal
queue lock across their user destructors; cleanup may reenter the channel.

The native `Select` behavior remains the one in library-and-abi section 6:
borrow same-item receivers, wait without polling, report a ready index without
consuming, treat disconnection as ready, rotate ready-index consideration.
Readiness is advisory when another permitted actor can receive; the next receive
still determines ownership transfer. No general cancellation/fairness guarantee
is inferred for blocking channel calls.

## 9. Networking and optional async hosting

### 9.1. Addresses and resolution

IP addresses are values, not resource owners. IPv4 stores four octets, IPv6
sixteen network-order octets; octet/segment constructors, integer conversions
and mapped-address conversions preserve the specified numeric bits. Classification
queries examine the selected address ranges, not reachability, DNS or routing.
IPv6 classification can depend on exact mapped/embedded forms; it must not
classify every IPv6 address by simply discarding its upper 96 bits.
`SocketAddrV4.new` stores address/port; V6 construction additionally stores
flowinfo/scope ID. Address/port/flow/scope getters return values or receiver
views as declared; setters replace only the selected field. Generic
SocketAddr.set_ip changes the family when necessary and initializes new
IPv6-only fields to zero, rather than retaining stale fields from another
variant. Octet/segment extraction and integer/network-bit conversions require
no allocator or OS.

Parsing accepts numeric address grammar, checks component ranges and rejects
trailing junk. IPv4 requires exactly four decimal octets with no ambiguous
leading-zero forms; IPv6 permits at most one `::` compression and its valid
embedded IPv4 form. Socket addresses preserve port, address family, IPv6 flowinfo and
scope ID. Port is a 16-bit numeric value; text IPv6-with-port uses brackets.
The native constructors, malformed-input error and RFC 5952 display selection
are specified by library-surface section 13. Formatting never performs DNS.

`ToSocketAddrs.to_socket_addrs(read self)` returns the declared owned/borrowed
address iterator without extending input regions. Numeric inputs do not require
DNS. Host-name resolution may block, allocate and return zero, one or several
IPv4/IPv6 candidates; preserve resolver order without deduplicating by a lossy
address representation. Native `resolve(read Text host, port)` retains the
resolver's numeric failure alongside a portable I/O kind. DNS order, caching,
search suffixes, interface configuration and addresses are OS/environment
observations, not stable deterministic library results.

The native protocol uses `type Iter<region r>: Iterator<Item = SocketAddr>`
and `to_socket_addrs<region r>(receiver read self: Self from r)`.
Numeric address values and address/port tuples produce one address without
allocation. Address slices lend a copied-value iterator; keeping it alive
keeps the source borrowed. Text/String socket forms and host/port tuples
produce owned candidates. Synchronous TCP connect/listen and UDP bind/connect/
send_to accept independently generic read inputs through this protocol;
connect_timeout and the optional async endpoints retain their numeric inputs.
TCP connect and TCP/UDP bind try candidates in order, as does UDP connect.
An empty sequence is InvalidInput. UDP send_to uses only the first candidate,
including when sending to it fails.

#### Stable classification tables

The following are exact tests, not queries of the current routing table or an
automatically updated Internet registry. CIDR ranges include every address
whose high-order bits match the stated prefix.

| Receiver and member | True exactly for |
| --- | --- |
| `Ipv4Addr.is_unspecified` | `0.0.0.0` |
| `Ipv4Addr.is_loopback` | `127.0.0.0/8` |
| `Ipv4Addr.is_private` | `10.0.0.0/8`, `172.16.0.0/12`, or `192.168.0.0/16` |
| `Ipv4Addr.is_link_local` | `169.254.0.0/16` |
| `Ipv4Addr.is_broadcast` | `255.255.255.255`; this is not a subnet-directed-broadcast calculation |
| `Ipv4Addr.is_multicast` | `224.0.0.0/4` |
| `Ipv4Addr.is_documentation` | `192.0.2.0/24`, `198.51.100.0/24`, or `203.0.113.0/24` |
| `Ipv6Addr.is_unspecified` | `::` |
| `Ipv6Addr.is_loopback` | `::1` |
| `Ipv6Addr.is_multicast` | `ff00::/8` |
| `Ipv6Addr.is_unique_local` | `fc00::/7` |
| `Ipv6Addr.is_unicast_link_local` | `fe80::/10`, including all values of the remaining 118 bits |
| `IpAddr.is_ipv4`, `IpAddr.is_ipv6` | The corresponding stored variant |

`IpAddr.is_unspecified`, `is_loopback` and `is_multicast` dispatch to the stored
variant's test without canonicalization. In particular an IPv4-mapped IPv6
loopback address is not the IPv6 loopback value `::1`.
All these queries borrow their receiver, allocate nothing, cannot fail or
panic on a valid address, and use O(1) work/storage.

The pinned catalog marks `is_global`, `is_benchmarking`, IPv4 `is_shared`/
`is_reserved`, IpAddr/IPv6 `is_documentation`, IPv6 `is_unicast`/
`is_unicast_global`/`is_ipv4_mapped` and multicast-scope facilities experimental.
They are not stable migration gaps and are not admitted by a stable address
type or by the presence of their implementation in the source archive.

#### Canonicalization, conversions and bitwise operations

`Ipv4Addr.to_ipv6_compatible` places its four octets after twelve zero octets.
`to_ipv6_mapped` instead places them after ten zero octets followed by `ff ff`.
Both return independent IPv6 values without allocation.
`Ipv6Addr.to_ipv4` returns the last four octets when the first twelve are all
zero, or when they have that mapped prefix; otherwise it returns none.
Thus the compatible extraction includes `::` and `::1`, yielding `0.0.0.0`
and `0.0.0.1`. `to_ipv4_mapped` accepts only the mapped prefix.

`Ipv6Addr.to_canonical(): IpAddr` produces V4 only for an IPv4-mapped input;
every other input, including compatible IPv6, remains V6.
`IpAddr.to_canonical` leaves V4 unchanged and applies that rule to V6.
These operations read their receivers and return values, preserving no loan
to the input. They do not resolve DNS or rewrite socket scope/flow metadata.
Address equality, ordering and hashing do not implicitly canonicalize:
distinct family variants remain distinct even if explicit canonicalization
would yield the same address.

`Ipv4Addr.to_bits`/`from_bits` and the matching u32 conversions interpret the
first network octet as the most significant eight bits. IPv6 uses the analogous
u128 rule. For example `1.2.3.4` has bits `0x01020304` on every target, not a
host-endian integer reinterpreted from memory. Octet-array conversions preserve
the four/sixteen bytes; IPv6 segment-array conversion splits/joins each u16
in network order. These are exact inverse representation conversions under
their declared widths, not checked routing or Unicode conversions.

For each of Ipv4Addr and Ipv6Addr, `BitAnd.bitand` and `BitOr.bitor` combine the
corresponding 32 or 128 address bits; `Not.not` complements exactly those bits.
Return a new same-family value. The owned/borrowed operand overloads have the
same bit result, preserving their declared take/read modes without a hidden
payload clone. `BitAndAssign.bitand_assign` and `BitOrAssign.bitor_assign`
replace the exclusively borrowed left value, with owned or borrowed right input
as declared. All bitwise operations allocate nothing, use O(1) work/storage,
and cannot overflow or panic for valid values. They provide no implicit
cross-family conversion. The frozen stable implementations do not select XOR,
shift or arithmetic operators merely by selecting these interfaces.

### 9.2. TCP and UDP

| Operation family | Required effects |
| --- | --- |
| `TcpStream.connect(read addresses)` | Resolve and try candidates in order until one connects; return the first success or the final connection error. An empty candidate sequence is `InvalidInput`. Close unsuccessful attempt resources. No overall timeout is implicit. |
| `connect_timeout(read SocketAddr, timeout)` | Operate on one numeric endpoint; zero duration is `InvalidInput`. Bound the connection wait using a nonblocking connection and completion check or equivalent. Report actual connection failure, not success based on writability alone. |
| `TcpListener.bind(read addresses)` | Try candidate local endpoints until one binds; return first success or final error. Port zero requests OS port assignment; use `local_addr` to discover it. |
| `accept`, `incoming` | Accept into a new owned stream plus peer address; the listener remains usable. Incoming iteration yields owned stream outcomes and does not become permanently exhausted merely because one accept failed. |
| stream Reader/Writer, `peek(mut bytes)` | Ordered byte-stream semantics, partial transfer and EOF as section 3. Peek copies available bytes without consuming them; repeated peeks can observe the same bytes. Flush does not acknowledge remote receipt. |
| `UdpSocket.bind`, `connect` | Bind a local datagram endpoint; connect selects a default peer and receive filtering, not a TCP handshake or delivery guarantee. Reconnecting need not discard all OS queued state. |
| `send_to`, `send`, `recv_from`, `recv` | Send one datagram or receive at most one. A receive buffer shorter than a datagram may discard its tail; zero length can be a valid empty datagram, not EOF. send_to resolves input and uses the selected endpoint rather than broadcasting to every resolved candidate. Failure may occur after a peer has observed data. |
| `peek_from`, `peek` | Observe one queued datagram and its source where applicable without removing it; truncation rules still apply to the supplied buffer. |
| `local_addr`, `peer_addr`, `take_error` | Observe endpoint state; unconnected peer queries fail. take_error retrieves and clears the pending socket error state, not an error history. |
| `try_clone` | Duplicate an owned reference to the same socket; options and traffic queues are shared. It does not create a new TCP connection or UDP port. |
| `shutdown(Read/Write/Both)` | Disable the requested connection half; write shutdown follows already accepted bytes with end-of-stream where supported. Repeated shutdown can succeed or report a platform error. Dropping one cloned handle need not close the connection while others own it. |

UDP receive operations still consult the socket when given an empty buffer.
`recv` and `recv_from` consume one queued datagram and discard any uncopied
bytes; `peek` and `peek_from` leave it queued. With no datagram available,
an empty buffer does not bypass blocking, nonblocking or timeout behavior.
An empty datagram is observable and consumable independently of buffer size.

Socket option getters/setters borrow the owner. Except for managed TCP listeners
below, `set_nonblocking` changes shared kernel socket mode; subsequent progress
that would wait returns `WouldBlock`.
`set_nodelay` controls TCP's small-write coalescing; TTL/hop-limit setters preserve
range validation and target errors. UDP broadcast, multicast loopback, TTL and
join/leave membership operations act on the specified group/interface and can
fail if family, interface, permissions or support are wrong. Membership lifetime
and route selection are OS state; no library copy of a socket creates an
independent membership.

Read/write timeout `none` removes the configured timeout; zero duration is
`InvalidInput`, not an immediate poll. The selected native hosted contract maps
actual timeout expiration to `TimedOut` while retaining the platform raw code
(even where the raw errno is also used for nonblocking unavailability).
An explicit nonblocking lack of progress remains `WouldBlock`. Distinguish the
cause using socket mode and the operation, not a raw-code-only conversion table.
Set/get can round to OS clock granularity. Options do not create an aggregate
deadline across an application loop.

Native socket writes suppress socket-generated SIGPIPE at the socket/call
boundary and return broken-pipe errors. They do not install a process-wide
signal disposition or change stdout's selected policy.

#### Managed TCP listeners

Synchronous `TcpListener` keeps its listening socket physically nonblocking.
`set_nonblocking` changes a logical mode shared by its managed `try_clone`
family, not `O_NONBLOCK`. Each `accept` snapshots that mode at entry; a mode
change affects later calls, not an already-running accept. Logical nonblocking
never waits, even with an accept timeout configured. Logical blocking retries
readiness loss using one monotonic deadline, or waits without a deadline when
no timeout is set. Readiness stolen by a clone or raw accepter and interrupted
syscalls do not restart the budget. Expiration is `TimedOut`; immediate
nonblocking unavailability is `WouldBlock`, retaining the raw OS error.

`set_accept_timeout` remains a per-handle budget, copied by `try_clone` and
subsequently independently configurable; it is not a shared kernel option.
Synchronous accepted `TcpStream` sockets are physically blocking, regardless
of listener logical mode. Async listeners/streams retain their nonblocking
readiness-driven behavior; no executor is required for synchronous waiting.

Raw listener access exposes the actual permanently-nonblocking socket, even
after `set_nonblocking(false)`. Foreign accept may consume connections but does
not perform logical blocking. The logical mode is in-process clone-family
state, not kernel state shared with arbitrary duplicates or across fork.
Raw transfer never restores blocking, including for the last managed handle.

The infallible `From<OwnedFd>` listener conversion is replaced by unsafe,
fallible `TcpListener.from_owned_fd(take fd): TcpListener throws io.Error`.
Adoption captures the existing physical mode as initial logical mode, establishes
physical `O_NONBLOCK`, preserves other flags, and consumes/closes the transferred
descriptor on failure. The caller must supply a suitable socket, have authority
over every alias, and ensure no alias clears `O_NONBLOCK` or is independently
re-adopted into another managed family while any managed listener remains.
Owning one descriptor alone does not establish those facts. The constructor
allocates shared mode state before its final flag change; normal allocation
failure follows the selected allocation policy. Dropping closes each handle
once and releases its shared state without restoring socket mode. This exception
does not redesign `TcpStream`, `UdpSocket` or native-domain listeners.

### 9.3. Async wrappers and cancellation

Hosted std does not select an executor. Future polling, pinning and borrowed
scope epochs remain governed by memory-and-concurrency and library-surface
section 13. `std.task` owned/local handle behavior and reentrant-drive panic are
specified by library-and-abi section 1.

`readable`, `writable`, `sleep` and AsyncTcpListener/AsyncTcpStream require the
explicit std.task reactor/waker integration. Readiness is advisory: poll the
nonblocking operation, register interest without losing a concurrent readiness
change, and retry after notification. A notification alone is not completed I/O.
Timer completion means the selected deadline was observed, not a scheduling
guarantee. No per-await heap allocation is required by concrete futures, but
task creation, reactor registration and erased storage can allocate explicitly.

`async_tcp_listen` owns a nonblocking listener. `async_tcp_connect`/
`AsyncTcpStream.connect` return futures that produce an owned stream or error.
`accept` produces a new owner; `read_some(mut buffer)` and
`write_some(read buffer)` retain their buffer loans through polling and completion;
`write_all` accumulates partial progress using the synchronous byte-order rules.
Future construction alone does not execute its deferred async body, although
an explicitly synchronous constructor can allocate/create its resource.

Dropping a pending I/O/timer future synchronously unregisters its reactor token
and releases its loans. Notification metadata may outlive it but cannot
dereference freed future/buffer storage. Cancellation cannot leave an OS operation
using a borrowed buffer after the loan ends: a completion-based adapter must
quiesce it or own separate storage until completion. Cancelling an accepted/
connected result before delivery must close the undelivered owned resource.
Bytes already consumed/sent, a connection already initiated, or a deadline
already passed are not rolled back; cancelling write_all may expose a prefix.
There is no asynchronous destructor or promise of protocol shutdown on drop.

The POSIX socket wrapper selection does not itself qualify Windows IOCP,
WASI networking, remote-worker borrowed scopes or any particular Linux reactor.
An adapter must meet these ownership/wakeup contracts and the profile imports
before its service can be claimed.

## 10. Coverage boundary and remaining receipts

This document supplies family behavior for the signatures explicitly grouped
in sections 3–9, including native aliases and reexports of those same identities.
Inherited slice/iterator/format/error/owner operations remain with their native
owners; appearing on a hosted type's documentation page is not a second hosted
implementation obligation. OS-specific members are assigned separately by
native-os-contracts.

These are concrete limits, not permissions to discard frozen capabilities:

1. A per-canonical-operation reconciliation must still identify every eligible
   overload, implementation relation, target predicate and stable const member
   against these sections and the other native owners. This prose alone is not
   evidence that every record was assigned or verified.
2. The exact stable IP classification tables, conversions and selected bitwise
   operations are specified in section 9.1. Experimental registry queries are
   excluded rather than left as stable migration gaps. This does not select
   every operator/conversion merely because it appears on an address page.
3. Windows component rules and ordinary/batch argument encoding are specified
   in sections 4.3 and 6.3. Uncommon platform error-code classification tables
   still need per-operation reconciliation; raw code retention alone does not
   specify every portable classification.
4. WASI recursive-deletion race resistance, Windows console/overlapped I/O,
   Linux/Android/macOS reactor adapters, all-profile thread/TLS teardown and
   process inheritance require profile-specific implementation/evidence.
   Missing OS imports are explicit capability limits, not optional removal of
   the eight-profile plan.
5. Debug is governed by section 1's diagnostic-format contract, not an invented
   stable output-byte obligation. Specialized members outside the explicit
   selectors still require their own contracts.

### 10.1. Operation selectors for integration

Selectors use catalog reference paths solely to identify the native operations.
Apply `runtime_stability == stable`, `deprecated == false` and the actual
availability predicate before selecting. A `Type.*` below denotes the explicitly
described inherent/interface members of that type, not every inherited method,
implementation relation, associated constant or undocumented future member.

| Catalog selector | Native contract location |
| --- | --- |
| `std::io::{Read,Write,BufRead,Seek}::{read,read_vectored,read_exact,read_to_end,read_to_string,write,write_vectored,write_all,flush,write_fmt,fill_buf,consume,read_until,read_line,skip_until,lines,split,seek,rewind,stream_position,seek_relative,by_ref,bytes,chain,take}` where actually declared | Sections 3.2–3.3; formatted output delegates to library-surface section 10 |
| `std::io::{Error,IoSlice,IoSliceMut,BufReader,BufWriter,LineWriter,Cursor,Chain,Take,Bytes,Empty,Repeat,Sink,IntoInnerError,WriterPanicked}` described members | Sections 3.1–3.3 |
| `std::io::{copy,empty,repeat,sink,read_to_string,stdin,stdout,stderr,pipe}` and described standard-stream/pipe members | Sections 3.2–3.4 |
| `std::ffi::{OsStr,OsString}` and `std::path::{Path,PathBuf,Components,Ancestors,Iter}` described members; `std::path::{absolute,is_separator}` | Sections 4.1–4.3 |
| `std::fs::{File,OpenOptions,Metadata,Permissions,FileType,FileTimes,DirBuilder,ReadDir,DirEntry}` described members and all free filesystem functions explicitly listed in section 5 | Section 5 |
| `std::env::{args,args_os,var,var_os,vars,vars_os,set_var,remove_var,split_paths,join_paths,current_dir,current_exe,set_current_dir,temp_dir,home_dir}` | Section 6.1 |
| `std::process::{Command,Child,ChildStdin,ChildStdout,ChildStderr,Stdio,Output,ExitStatus,ExitStatusError,ExitCode,Termination}` described members; `std::process::{id,exit,abort}` | Sections 6.2–6.3 |
| `core::time::Duration` and `std::time::Duration` named constructors/queries/arithmetic in section 7.1, including `TryFromFloatSecsError`; `std::time::{Instant,SystemTime,SystemTimeError}` described members | Section 7; Debug follows section 1 |
| `std::thread::{spawn,scope,current,available_parallelism,sleep,yield_now,park,park_timeout,panicking}` and described Builder/Thread/ThreadId/JoinHandle/Scope/ScopedJoinHandle/LocalKey members | Sections 8.1–8.2 |
| `std::sync::{Mutex,RwLock,Condvar,Barrier,Once,OnceLock,LazyLock}` and their described guards/poison/wait-result members; `std::sync::mpsc` send/receive/iterator families | Sections 8.3–8.4 |
| `std::net::{TcpStream,TcpListener,UdpSocket,ToSocketAddrs}` described members; `core::net`/std address constructors, parsing, field access/mutation, octet/segment/integer conversion | Section 9; explicit additional selectors below |
| Native `std.task` readiness/timers, AsyncTcpListener/AsyncTcpStream and scope operations | Section 9.3 plus existing library-surface section 13 and library-and-abi section 1; not new catalog identities |

This table is a review selector, not permission to assign whole module/type
prefixes mechanically. In particular no `std::*`, `core::net::*` or
`std::os::*` blanket migration is established.

Additional precise selectors closed by sections 4.3, 6.3 and 9.1 follow.
Address selectors apply to the canonical `core::net` definitions and matching
`std::net` reexports, not independently defined address types.

| Member selector | Contract |
| --- | --- |
| `IpAddr::{is_ipv4,is_ipv6,is_unspecified,is_loopback,is_multicast,to_canonical}` | Exact stored-variant tests and mapped-only canonicalization |
| `Ipv4Addr::{is_unspecified,is_loopback,is_private,is_link_local,is_broadcast,is_multicast,is_documentation,to_ipv6_compatible,to_ipv6_mapped,to_bits,from_bits}` | Exact tables and conversions in section 9.1 |
| `Ipv6Addr::{is_unspecified,is_loopback,is_multicast,is_unique_local,is_unicast_link_local,to_ipv4,to_ipv4_mapped,to_canonical,to_bits,from_bits}` | Exact tables and conversions in section 9.1 |
| Ipv4Addr/Ipv6Addr implementations of `BitAnd.bitand`, `BitOr.bitor`, `Not.not`, `BitAndAssign.bitand_assign`, `BitOrAssign.bitor_assign` | All frozen stable owned/borrowed overloads with those interface identities; no other operator family |
| Ipv4Addr conversions with u32/[u8;4]; Ipv6Addr conversions with u128/[u8;16]/[u16;8] | Network-significance and array-unit rules in section 9.1 |
| `std::path::Prefix::is_verbatim`; `PrefixComponent::{kind,as_os_str}`; `Component::as_os_str`; `Components::{next,next_back,as_path}`; Windows `Path::{components,iter,has_root,is_absolute,is_relative,join}`, `PathBuf::push`, `path.absolute` | Prefix/body/root rules in section 4.3, combined with existing section 4.2 operations |
| Windows `std::process::Command::{arg,args,spawn,status,output}`; `std::os::windows::process::CommandExt::raw_arg` | Ordinary/batch encoding and rejection rules in section 6.3 |
| Hosted-type implementations of `core.fmt.Debug.fmt`, including address/time types | Section 1 diagnostic-format rules; no output-byte compatibility obligation |

The parent authority register must link these sections before retiring any
reference-owned fallback.
