# Native OS extension contracts

Status: selected platform-operation contracts. This companion to
[native hosted contracts](native-hosted-contracts.md) specifies resource transfer
and platform extension families without implying that their implementations
exist on every selected profile. Deprecated and experimental APIs are excluded.
Frozen identities, signature types and actual target predicates are in the
nondeprecated stable records of `baseline/operations.jsonl.gz`; behavioral rules
are native here. Reexports in `prelude`, `unix.io` and `wasi.io` preserve identity,
not independent resource types.

V1 gate: only Linux (and the portable core of each family) is exercised for V1.
Sections specific to Windows, macOS, Android, WASI or other profiles are
post-V1 obligations ([post-v1-worklist.md](../process/post-v1-worklist.md)); they define
contracts but are not V1 acceptance requirements.

## 1. Platform applicability and common rules

Unix families apply to the selected Linux, macOS and Android profiles only where
the member's target predicate and the platform services permit it. Linux-only
members are not automatically Android members. Darwin families apply to
`macos-arm64`; Windows families to `windows-x64`. WASI byte-string/descriptor
families require `wasi32` imports. Neither `wasm32-core` nor `cortex-m3` acquires
OS services through a reexport. `wasip2` namespace inventory is not selection of
a Preview 2 runtime in the Preview 1 profile.

Read inputs remain borrowed for the call, exclusive byte buffers remain valid
and initialized, and consuming resource operations use `take`. Setters mutate
their builder and return a view of it, not a clone. Raw bitfields have the exact
target-width integer type; they are not narrowed to a portable subset.
An OS failure returns `io.Error` retaining the raw code, unless the operation
has a distinct declared error type. Ordinary heap allocation retains its
separate failure policy. Platform calls can block and have partial external
effects; destructors release resources without reporting close errors.
Queries/handle transfers require O(1) library storage, string copying is linear
in copied units, buffered transfer is linear in bytes transferred, and OS latency
is unbounded unless the operation says otherwise.

OS manuals define OS meanings of mode bits, flags, credentials, timestamps and
syscalls. They do not define Mettle ownership, argument loans, error results or
cleanup. The rules below supply that boundary.

## 2. Descriptors, Windows handles and sockets

| Operation shape | Native ownership contract |
| --- | --- |
| `as_raw_fd`, `as_raw_handle`, `as_raw_socket` | Return a nonowning raw numeric/pointer value. It may be passed only to uses that preserve the owner's invariants. It cannot safely be closed, reconstructed as a second owner or retained beyond the resource lifetime merely because the number is Copy. |
| `as_fd(): BorrowedFd from self`, `as_handle`, `as_socket` | Return a lifetime-bearing resource view; no duplicate OS reference, allocation or transfer. Owner destruction is constrained by this loan. |
| unsafe `Borrowed*.borrow_raw(raw)` | Assert a valid open resource of the correct kind remains usable for the chosen region. No simultaneous close/ownership transfer may invalidate it. Wrapping a reused number does not recover the earlier resource's identity. |
| unsafe `Owned*.from_raw_*(raw)` and resource-specific `from_raw_*` | Transfer the live close obligation into the returned owner, including the correct resource-kind destructor. Caller must have that obligation and relinquish it; an OS failure sentinel cannot masquerade as a successful resource. The explicitly permitted Windows null/pseudo-handle states are distinguished below. |
| `into_raw_*(take owner)` | Suppress that owner's close, transfer the close obligation to the caller, and invalidate the source owner. No duplicate remains implicitly owned by the consumed value. |
| `try_clone`, `Borrowed*.try_clone_to_owned` | Fallibly duplicate the OS reference and return a new owner. Failure preserves the original reference/loan. File offsets, socket options and underlying kernel objects may remain shared. |
| owner-to-owner conversion | Move the resource when valid for the destination type; do not duplicate or close it in transit. A checked conversion failure returns its declared error/retained source, not a leaked resource. |

OwnedFd excludes the invalid descriptor sentinel. OwnedHandle uses CloseHandle,
not RegCloseKey or a resource-specific destructor; OwnedSocket uses socket
closing, not generic handle closing. Windows generic handle wrappers permit the
null state produced by absent standard streams and a value of -1 when its
provenance is a valid handle, such as a current-process pseudo-handle, rather
than a failed API's INVALID_HANDLE_VALUE. Numeric equality cannot distinguish
those cases. Do not strengthen their unsafe preconditions into an unconditional
nonzero/nonnegative check. A file-specific reconstruction still needs a resource
usable for its declared I/O. Borrowed Windows standard handles may need a checked
conversion because null/invalid standard-stream state is possible.
`HandleOrNull`/`HandleOrInvalid` preserve the sentinel distinction and their
TryFrom errors; callers cannot turn a failed sentinel check into a valid
OwnedHandle by a cast. Successful conversions transfer ownership once.

These wrappers promise resource liveness, not fixed file contents/position,
exclusive system-wide access or freedom from concurrent foreign calls.
`is_terminal` observes the resource kind and connection at the time of the query.
Debug formatting of a raw identifier is diagnostic, not serialization.

The managed `TcpListener` exception in hosted contracts section 9.2 additionally
requires permanent physical `O_NONBLOCK`. Raw borrowing still lends the real
socket; a foreign accept is physically nonblocking even when managed logical
mode is blocking. Raw duplication/transfer carries no logical-mode state and
never restores blocking. No alias may clear `O_NONBLOCK` or be independently
re-adopted while a managed listener remains. Adoption therefore uses unsafe,
fallible `TcpListener.from_owned_fd`, not safe `From<OwnedFd>`; authority over
all aliases is stronger than owning one close obligation. Known managed clones
share logical mode; arbitrary raw aliases and forked copies do not acquire that
in-process state. This changes neither close-on-exec nor ordinary raw ownership.

### 2.1. Close-on-exec and inheritance

On the selected native Unix profiles, library-created files, pipes and sockets
are noninheritable across exec by default. Descriptor duplication through
OwnedFd/BorrowedFd cloning produces a distinct descriptor with close-on-exec,
even if the original descriptor lacked that flag; the selected native
duplication avoids standard-stream slots 0–2. The open-file description and
its access/status state remain shared, but descriptor flags are per descriptor.
Use atomic creation/duplication flags where the profile supplies them; any
fallback must establish the same final flag before returning success and must
not claim an atomic race guarantee that its OS calls cannot establish.

Borrowing, raw access, `from_raw_fd`, `into_raw_fd` and owner-to-owner moves
neither add nor remove close-on-exec on an existing descriptor. A foreign-owned
descriptor's flags remain the caller's responsibility. Close-on-exec acts at
exec, not at fork: pre_exec runs in a child that can still see inherited open
descriptors. Command's explicit standard-stream setup installs the selected
ends at 0–2 for the executed child; it is not defeated by close-on-exec on the
source descriptor. Parent-side pipe ends stay owned by the parent and must not
be accidentally kept alive by the executed child. Other descriptors deliberately
made inheritable by foreign code are not subject to a promised global
close-everything allowlist.

Windows library file/socket creation and generic owned-handle/socket cloning
produce noninheritable references by default. Handle cloning preserves access
rights, not an inheritable flag copied from the original.
Raw wrapping/moving/borrowing leaves the existing flag unchanged.
Command instead duplicates configured standard handles as inheritable child
references, leaving the original parent's reference and flag intact. Missing
standard streams can remain null. Child-facing pipe ends are inheritable;
parent-facing ends must not keep the child's pipe artificially open.

The selected Windows launch boundary enables OS handle inheritance; it is not
a stable per-command handle-allowlist API. Library launches serialize their
temporary inheritable standard-stream references through process creation and
then release them. A foreign concurrent launcher that does not participate in
that synchronization can inherit such a temporary reference, and unrelated
handles already made inheritable by foreign code can reach the child.
Do not claim isolation from those foreign races or silently expose the
experimental handle-list extension to imply it.

### 2.2. WASI Preview 1 rights

WASI descriptor ownership is ownership of a capability already granted by the
embedder. `as_fd`/raw access, borrowed wrappers and raw-to-owned reconstruction
preserve the descriptor's actual base and inheriting rights; they do not
reconstruct a less-restricted capability from its numeric index.
The unsafe caller still supplies a live descriptor and its unique close
obligation. No requirement to possess every possible file right is added merely
to wrap a restricted descriptor.

Path operations resolve through supplied preopened directory capabilities.
Opening needs the applicable path-open right and can grant a new descriptor
only rights permitted by the directory's inheriting rights. A read-open result
does not imply write, metadata-mutation or namespace-mutation authority.
Reading, writing, seeking/telling, synchronization, metadata access/mutation,
directory enumeration and path creation/removal/link operations each require
their corresponding Preview 1 capability. Missing capability is a returned
operation error retaining its raw code, never fallback to an ambient unrestricted
host path. Path traversal, absolute-path handling and preopen lookup remain
confined to the selected WASI/libc capability resolver.

The frozen stable surface does not expose a WASI rights-mask setter or an
OpenOptions right-selection protocol. Its libc-backed opening does not promise
one exact minimal numeric rights mask. The contract is sufficient rights for
the requested supported operation, bounded by the rights actually granted;
neither wrapping nor opening may amplify those rights. Rights can become more
restricted under the platform attenuation operation, and later calls then
fail according to the rights still available.

Preview 1 supplies no ordinary descriptor duplication import.
OwnedFd/BorrowedFd cloning, and File cloning through that boundary, return
Unsupported on this selected profile rather than copying the number into a
second owner or reopening a path with different identity/rights.
Experimental `std.os.wasi.fs` extension pages do not stabilize rights control
or positioned-I/O APIs through the retained descriptor reexports.

## 3. Native strings

Unix and WASI `OsStrExt.from_bytes(read [u8])` and `as_bytes()` lend exactly the
same bytes without allocation or validation as Unicode. `OsStringExt.from_vec`
consumes byte storage; `into_vec` transfers it back. Embedded NUL is representable
in an OS string but rejected at operations requiring NUL-terminated OS inputs.
No implicit lossy conversion is inserted at that boundary.

`CStr` is an unsized validated byte-string view; its extent includes exactly
one NUL, at the end. Constructors borrow the validated input bytes.
`CString` owns that storage, and its `Borrow<CStr>`, `AsRef<CStr>` and `Deref`
views stay within the owner's borrow without allocating or creating temporary
wrapper storage. Suffix indexing retains the terminator and rejects a start
past it. Unsafe constructors require the same byte invariant and readable
storage for the entire view lifetime.

Windows `OsStringExt.from_wide(read [u16])` copies exactly the supplied UTF-16
code units, including unpaired surrogates. It does not require or remove a
trailing zero; zero is content until a later OS operation rejects it.
`OsStrExt.encode_wide()` borrows the OS string and yields the original u16 units,
without appending a terminator. The iterator allocates nothing and cannot outlive
the source. Thus wide-to-owned-to-wide round-trips ill-formed UTF-16 without ever
fabricating invalid UTF-8 Text.

## 4. Unix filesystem extensions

| Family | Argument/result and OS effect |
| --- | --- |
| `OpenOptionsExt.mode(mode)` | Set requested creation mode; it is filtered by process umask/OS rules and does not chmod an existing object. Default creation permissions remain ordinary read/write mode subject to umask. |
| `custom_flags(flags)` | Replace the previous extension flag set; combine with library-required flags, without allowing raw access-mode bits to override the explicit read/write/append contract. Unsupported flag combinations fail at open. |
| `PermissionsExt.from_mode`, `mode`, `set_mode` | Construct/read/change stored target mode bits without an OS call. Actual permission changes occur when that Permissions value is passed to the filesystem operation. |
| `MetadataExt` common fields | Return snapshot device/inode IDs, permission/type mode, link count, uid/gid, special-device ID, byte size, atime/mtime/ctime seconds and nanosecond components, preferred block size and allocated block count. ctime means status change, not creation. Block counts are OS accounting units, not `len / block_size`. |
| `FileTypeExt.is_block_device/is_char_device/is_fifo/is_socket` | Inspect the stored type bits, without opening the object or following a new path. |
| `DirEntryExt.ino` | Return the enumerated entry's inode identity where provided; it is not globally unique across devices or immune to reuse. |
| `symlink(read original, read link)` | Create a link storing the original native spelling, which may be relative or nonexistent. Do not open or canonicalize its target. |
| `chown(read path, uid?, gid?)`, `lchown`, `fchown(read fd, ...)` | Set only present owner/group IDs; absence leaves that ID unchanged. Path chown follows the final link; lchown does not; fchown names the live open resource. Permissions/security side effects follow the OS and can clear privilege bits. |
| `chroot(read path)` | Change the process root under OS privilege/namespace rules; no claim of sandbox completeness or automatic current-directory change. Existing open descriptors and other process state retain their OS effects. |

`FileExt.read_at(read self, buf: mut [u8], offset: u64): usize throws Error`
and `write_at(read self, buf: read [u8], offset: u64)` perform partial positioned
I/O without changing the shared file cursor. Offset conversion/range errors
are returned, not wrapped. Short reads/writes and EOF have ordinary I/O meanings.
`read_exact_at`/`write_all_at` advance checked offsets by actual progress,
retry interruption, and respectively report UnexpectedEof/WriteZero on
incomplete progress. Earlier transfers remain externally effective on failure.
Writing past EOF zero-fills the gap under the filesystem contract.
Linux append-open positioned writes can append despite the supplied offset;
this OS caveat is not permission to promise cursor-independent replacement at
that offset on an append-open resource.

`linux.fs.MetadataExt` retains the target stat fields and widths; Android's
predicate must be checked independently. `darwin.fs.MetadataExt` additionally
exposes birth time, flags, generation and spare fields with their target
meanings. Snapshot seconds/nanoseconds must not be silently rounded to a host
compiler's narrower type. `darwin.fs.FileTimesExt.set_created` sets the requested
creation timestamp in the builder; the subsequent file operation reports
support/range/permission failures.

## 5. Windows filesystem extensions

`OpenOptionsExt.access_mode(u32)` overrides desired access, including the
ordinary read/write/append selection. This is explicit target access selection,
not an unnoticed widening by a generic helper. `share_mode(u32)` replaces the
default `FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE`; removing bits
restricts concurrent opens/deletion/rename under Win32 sharing checks.

`custom_flags(u32)` replaces previous custom flags, adding them to required
library flags, not removing those required flags. `attributes(u32)` controls
creation attributes; opening an existing file does not generically reset its
attributes, and truncate/create behavior follows the Win32 replacement rules.
`security_qos_flags(u32)` supplies explicit quality-of-service/impersonation
selection with the required presence bit. These setters do not make a handle
safe for arbitrary foreign overlapped I/O or establish a callback/buffer lifetime.

`FileExt.seek_read(read self, buf: mut [u8], offset: u64)` and
`seek_write(read self, buf: read [u8], offset: u64)` return partial byte counts.
Unlike Unix read_at/write_at, these operations affect the shared cursor, setting
it to the end of the transfer. Read past EOF returns zero; write past EOF extends
with a zero-filled gap. Callers must synchronize shared cursor use, including
cloned handles. These safe APIs cannot leave the OS using the borrowed buffer
after returning, regardless of handle flags.

Metadata extensions expose file attributes, creation/access/write FILETIME
values and size with their declared u32/u64 widths. Times are counts of
100-nanosecond intervals from the Windows epoch, not Unix seconds.
File type extensions distinguish directory versus file symlinks from their
stored reparse attributes. They do not prove a target currently exists.
`FileTimesExt.set_created` requests creation-time modification.
`symlink_file` and `symlink_dir` explicitly select the link kind; the target
need not exist. Privilege/developer-mode/filesystem restrictions remain returned
errors. No silent copy or junction substitution is allowed.

## 6. Unix-domain sockets and Linux extensions

`SocketAddr.from_pathname(read path)` constructs an owned address with the exact
native bytes after NUL/target length checks. `as_pathname()` lends its pathname,
or none for an unnamed/abstract address. `is_unnamed` distinguishes no address
from an empty spelling under the platform address representation.
Linux `from_abstract_name(read bytes)` stores a length-delimited abstract name,
including permitted embedded zero bytes; `as_abstract_name` lends those bytes.
No pathname conversion, terminator stripping or Unicode normalization may merge
distinct abstract names.

UnixListener bind/connect address methods preserve the distinction between
pathname, unnamed and abstract endpoints. Creating a filesystem socket does not
make the library responsible for unlinking its path on destruction; deleting
the name does not close existing connections. `accept` returns an owned
UnixStream and observed peer address. `incoming` yields stream outcomes without
turning individual failures into permanent EOF.

UnixStream `connect`, `connect_addr`, `pair` and UnixDatagram `bind`, `bind_addr`,
`unbound`, `pair` create unique owned socket references. `pair` creates connected
endpoints without publishing a filesystem name. Failed construction releases
every undelivered endpoint. Datagram connect/address/send_to variants select
one peer/address; recv_from preserves the sender's address kind.
Stream bytes, datagram boundaries/truncation, partial progress, peek, timeouts,
nonblocking mode, try_clone, shutdown and take_error follow hosted-contracts
section 9, with native-domain addressing rather than DNS.

`linux.net.TcpStreamExt.quickack`/`set_quickack(bool)` observe/request
TCP_QUICKACK on applicable sockets. It is a transient stack hint, not a permanent
mode or a latency guarantee; later stack behavior may change it. Invalid socket
kind and unsupported options return actual OS errors.

## 7. Process and thread extensions

### 7.1. Unix process setup and status

`CommandExt.uid`, `gid`, `process_group` and `arg0` store requested child setup.
Setup installs the configured stdin/stdout/stderr endpoints first. If gid was
requested it performs that group-ID change before the requested uid change.
For uid setup without an explicitly configured supplementary-group list, it
attempts to clear supplementary groups before changing uid. Permission denial
EPERM from that clearing attempt alone is tolerated, matching the case where
the caller lacks group-changing authority; other clearing failures stop launch.
The requested setgid/setuid failure is never ignored. Therefore requesting uid
does not prove an empty supplementary-group list when clearing was denied.
Where a separately selected setup supplies an explicit supplementary list, that
list is applied before gid/uid; this does not stabilize a group-list setter.

After credentials, configured root-directory setup precedes current-directory
setup, and current-directory setup precedes process-group setup. Registered
pre_exec callbacks run after this setup, in registration order, before execution
of the new program. Any setup/callback failure stops subsequent steps and is
reported to the parent with its raw OS code. The child may already have changed
its credentials, directories or descriptors; failing `exec` in the current
process leaves those effects in place. A different launch mechanism is permitted
only if it preserves these requested effects, error reporting and callback
preconditions.

`arg0` replaces only argv[0], not the executable
selected for execution. `process_group(0)` requests a new group based on the
child's ID. Configuration is owned by the builder and does not immediately
change the parent.

unsafe `pre_exec(take callback)` stores a Transferable + Shareable + Static
mutating callback returning `Outcome<Unit, io.Error>`. It runs in registration
order in the child after launch setup and before exec; the first failure stops
later callbacks and launch. The parent receives the declared launch error,
including its raw code. Effects already made in the child are not rolled back.
The caller must ensure everything called is valid after fork in a multithreaded
process: no allocator, locked runtime, unsafe environment access, unwind,
non-async-signal-safe foreign service or invalid captured storage. Declaring a
closure Transferable does not establish this post-fork safety.

`exec(mut Command): io.Error` replaces the current process on success and never
returns then; on failure it returns the actual setup/exec error, potentially
after altering process state. Successful replacement runs no Mettle stack
destructors. It does not return a Child or perform an automatic rollback.
`parent_id` observes the current parent identity and can change with reparenting.

Unix ExitStatusExt `from_raw(i32)` preserves the raw wait-status bits;
`into_raw(take status)` returns them, not an ordinary exit code.
`signal`, `stopped_signal`, `continued`, `core_dumped` decode status categories
without confusing a signal with code `128 + signal`. Core-dump indication does
not prove a readable core file was produced. Windows ExitStatusExt.from_raw(u32)
preserves the complete process exit code and does not apply Unix wait decoding.

### 7.2. Windows process setup

`CommandExt.creation_flags(u32)` replaces stored extension flags, which are
combined with required `CREATE_UNICODE_ENVIRONMENT` for launch. Unsupported
combinations fail through process creation; no silent bit truncation occurs.
`raw_arg(read OsStr)` copies literal native content into the command line
without automatic quoting or escaping. This is explicit parser-specific control,
not a shell-safe argument operation; untrusted input must not be treated as
escaped by its use. Ordinary `arg` remains a logical argument for the selected
standard parser. Inputs still reject embedded NUL.

Experimental process-attribute, handle-list and asynchronous-pipe builder
methods are not admitted by the stable CommandExt family. Their absence cannot
be bypassed by claiming that a stable builder owns every child member.

### 7.3. Thread resource extraction

Unix `JoinHandleExt.as_pthread_t` returns a nonowning platform thread identifier;
the execution/handle must remain valid for its foreign use. `into_pthread_t`
consumes the Mettle handle and transfers its native joinable-thread obligation:
the caller must eventually join or detach exactly once. It must not also run
Mettle join/drop cleanup for that transferred native handle.

The Mettle result/panic packet is separate from the pthread return pointer.
Consuming the join handle releases its packet reference; the running thread
keeps the packet alive until completion. An output or panic payload no longer
observable through a Mettle joiner is destroyed exactly once when the last
packet reference is released, possibly during conversion if already complete,
otherwise on completion. No `T*`, owning allocation or panic payload is
transferred by `into_pthread_t`. The selected normal pthread entry returns a
null pointer; foreign pthread_join must not reconstruct/free that as a boxed T.
Joining/detaching releases native thread resources, not a second result packet.
An unobserved result/panic payload whose destructor panics at final packet
cleanup aborts, rather than unwinding across the foreign thread entry boundary.

`as_pthread_t` alone transfers none of these obligations: foreign join/detach
through its borrowed ID would conflict with the still-owned Mettle handle.
Cancellation/termination through foreign pthread APIs is outside ordinary safe
thread execution and must not bypass closure/result/TLS cleanup invariants.

Windows thread handle borrowing/consuming conversions use section 2. An OS
handle can keep the kernel thread object alive without keeping it running or
granting access to a Mettle result. Raw extraction does not make a non-Static
thread safe to outlive its borrowed data.

## 8. C aliases, evidence and explicit limits

`std.os.raw` C scalar aliases and Windows raw aliases retain the target C ABI
width, signedness and identity. They are not selected from the build host's C++
types. Opaque `c_void` is not dereferenceable initialized language payload.
Calling conventions/layout/foreign unwinding and allocator ownership remain
governed by library-and-abi sections 7–8 and platform-contracts.

Covered extension families are fd/handle/socket ownership; Unix/WASI byte and
Windows wide OS strings; Unix/Linux/Darwin/Windows file extensions; Unix-domain
and Linux abstract/quickack sockets; Unix/Windows process setup/status; Unix and
Windows thread-resource transfer; and target C aliases. Generic inherited
operations are not independently redefined here.

Unclosed details requiring explicit assignment rather than inference:

- Exhaustive source-record reconciliation, including platform-specific auto/
  implementation relations, constants and less common aliases, is not supplied
  by a list of family names.
- Windows verbatim/device-path grammar and ordinary/batch Command encoding are
  specified by native-hosted-contracts sections 4.3 and 6.3.
- Sections 2.1–2.2 and 7 specify inheritance, rights, credential order and
  pthread result cleanup. Profile probes must still establish stat layout/field
  widths, flag availability and that each adapter enforces those contracts;
  missing execution is not an unspecified ownership or rights rule.
- `wasi32` selects Preview 1 only. A `wasip2` namespace or an archive page for
  another OS does not select new runtime imports or additional profiles.

### 8.1. Integration selectors

Within the nondeprecated stable catalog, sections 2–7 target these operation
owners and their explicitly described members:

| Catalog selector | Section |
| --- | --- |
| `std::os::fd::{AsFd,AsRawFd,FromRawFd,IntoRawFd,BorrowedFd,OwnedFd}` and canonical Unix/WASI reexports | 2 |
| `std::os::windows::io::{AsHandle,AsRawHandle,FromRawHandle,IntoRawHandle,BorrowedHandle,OwnedHandle,AsSocket,AsRawSocket,FromRawSocket,IntoRawSocket,BorrowedSocket,OwnedSocket,HandleOrNull,HandleOrInvalid}` | 2 |
| `std::os::{unix,wasi}::ffi::{OsStrExt,OsStringExt}`; `std::os::windows::ffi::{OsStrExt,OsStringExt,EncodeWide}` | 3 |
| `std::os::unix::fs::{OpenOptionsExt,PermissionsExt,MetadataExt,FileTypeExt,DirEntryExt,FileExt,DirBuilderExt}` and `{symlink,chown,lchown,fchown,chroot}` | 4 |
| `std::os::{linux,darwin}::fs::MetadataExt`; `std::os::darwin::fs::FileTimesExt` | 4 |
| `std::os::windows::fs::{OpenOptionsExt,FileExt,MetadataExt,FileTypeExt,FileTimesExt,symlink_file,symlink_dir}` | 5 |
| `std::os::unix::net::{SocketAddr,UnixStream,UnixListener,UnixDatagram,Incoming}`; `std::os::linux::net::{SocketAddrExt,TcpStreamExt}` | 6 |
| `std::os::unix::process::{CommandExt,ExitStatusExt,ExitStatusErrorExt,parent_id}`; `std::os::windows::process::{CommandExt,ExitStatusExt}` | 7.1–7.2 |
| `std::os::unix::thread::JoinHandleExt`; Windows thread handle relations | 7.3 |
| `std::os::raw` and `std::os::windows::raw` target C aliases | 8 |

Each member must still be matched to its actual declaration, target condition
and native receiver/ownership mode. The table does not assign arbitrary
inherited iterator/conversion methods or every operation under those prefixes.

The bounded adapter follow-up additionally fixes the contract of:

- `OwnedFd::try_clone`, `BorrowedFd::try_clone_to_owned`, and descriptor-backed
  `File::try_clone`, socket/pipe clones: section 2.1 defaults, section 2.2 WASI
  unsupported duplication, preserving each operation's actual availability.
- Windows `OwnedHandle::try_clone`, `BorrowedHandle::try_clone_to_owned`,
  `OwnedSocket::try_clone`, `BorrowedSocket::try_clone_to_owned` and resource
  clones through those boundaries: section 2.1 noninheritance; section 2's
  provenance-sensitive null/pseudo-handle rules.
- Native file/pipe/socket construction, raw borrow/wrap/transfer members, and
  `Command::{spawn,status,output}` standard-stream setup: sections 2–2.2,
  distinguishing default flags from foreign-configured inheritable state.
- `std::os::unix::process::CommandExt::{uid,gid,pre_exec,exec,process_group}`:
  section 7.1 ordering, EPERM-only supplementary-group exception and partial
  effects; no newly stabilized credential APIs.
- `std::os::unix::thread::JoinHandleExt::{as_pthread_t,into_pthread_t}`:
  section 7.3 native join/detach obligation versus separately cleaned Mettle
  result/panic packet.

Primary OS authorities for platform effects are the
[POSIX system interfaces](https://pubs.opengroup.org/onlinepubs/9799919799/functions/contents.html),
the [Linux man-pages](https://www.kernel.org/doc/man-pages/),
[Win32 file handling](https://learn.microsoft.com/en-us/windows/win32/fileio/file-management-functions),
[CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)
and the
[WASI Preview 1 interface](https://github.com/WebAssembly/WASI/blob/main/legacy/preview1/docs.md).
They supply OS effects under the selected SDK/runtime, not Mettle signatures,
ownership rules or safety rules.
