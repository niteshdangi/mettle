// Synchronous byte I/O: `Reader`/`Writer` expose partial transfers (the count a
// single call moved), the `*_all`/`read_exact`/`read_to_end` helpers loop over
// them, and `Error` keeps the raw OS error number so it round-trips unchanged.
import alloc.vec
import alloc.vec.List
import alloc.alloc.{AllocError, Allocator}
import alloc.boxed.Heap
import alloc.arc.Shared
import alloc.collections.Deque
import core.text.Text
import core.cmp.{Eq, PartialEq}
import core.cmp.{Ord, Ordering, PartialOrd}
import core.hash.{Hash, Hasher}
import core.outcome
import core.slice
import core.borrow.{AsMut, AsRef}
import core.default.Default
import core.fmt
import alloc.string.String
import alloc.string.ToString
import core.any.{TypeId, type_id}
import super.sys
import super.path.PathInput
import core.clone.Clone
import core.convert.From
import core.error.{Error as CoreError}
import core.ops.DerefMut
import std.sync.mutex.TryLockError

pub copy enum ErrorKind {
    NotFound, PermissionDenied, ConnectionRefused, ConnectionReset, HostUnreachable,
    NetworkUnreachable, ConnectionAborted, NotConnected, AddrInUse, AddrNotAvailable,
    NetworkDown, BrokenPipe, AlreadyExists, WouldBlock, NotADirectory, IsADirectory,
    DirectoryNotEmpty, ReadOnlyFilesystem, FilesystemLoop, StaleNetworkFileHandle,
    InvalidInput, InvalidData, TimedOut, WriteZero, StorageFull, NotSeekable,
    QuotaExceeded, FileTooLarge, ResourceBusy, ExecutableFileBusy, Deadlock,
    CrossesDevices, TooManyLinks, InvalidFilename, ArgumentListTooLong, Interrupted,
    Unsupported, UnexpectedEof, OutOfMemory, InProgress, TooManyOpenFiles,
    InputOutputError, Other
}

fn kind_from_index(index: i32): ErrorKind {
    match index {
        0 => ErrorKind.NotFound,
        1 => ErrorKind.PermissionDenied,
        2 => ErrorKind.ConnectionRefused,
        3 => ErrorKind.ConnectionReset,
        4 => ErrorKind.ConnectionAborted,
        5 => ErrorKind.NotConnected,
        6 => ErrorKind.AddrInUse,
        7 => ErrorKind.AddrNotAvailable,
        8 => ErrorKind.BrokenPipe,
        9 => ErrorKind.AlreadyExists,
        10 => ErrorKind.WouldBlock,
        11 => ErrorKind.InvalidInput,
        12 => ErrorKind.TimedOut,
        13 => ErrorKind.Interrupted,
        14 => ErrorKind.OutOfMemory,
        15 => ErrorKind.IsADirectory,
        16 => ErrorKind.NotADirectory,
        17 => ErrorKind.DirectoryNotEmpty,
        22 => ErrorKind.Unsupported,
        23 => ErrorKind.ArgumentListTooLong,
        24 => ErrorKind.CrossesDevices,
        25 => ErrorKind.Deadlock,
        26 => ErrorKind.ExecutableFileBusy,
        27 => ErrorKind.FileTooLarge,
        28 => ErrorKind.FilesystemLoop,
        29 => ErrorKind.HostUnreachable,
        30 => ErrorKind.InProgress,
        31 => ErrorKind.InputOutputError,
        32 => ErrorKind.InvalidFilename,
        33 => ErrorKind.NetworkDown,
        34 => ErrorKind.NetworkUnreachable,
        35 => ErrorKind.NotSeekable,
        36 => ErrorKind.QuotaExceeded,
        37 => ErrorKind.ReadOnlyFilesystem,
        38 => ErrorKind.ResourceBusy,
        39 => ErrorKind.StaleNetworkFileHandle,
        40 => ErrorKind.StorageFull,
        41 => ErrorKind.TooManyLinks,
        42 => ErrorKind.TooManyOpenFiles,
        _ => ErrorKind.Other
    }
}

// An I/O failure: a portable `kind` and, for failures reported by the
// operating system, the unmodified `errno` value (`raw_os_error`). A kind-only
// error carries no OS number. The kind of an OS error is derived from the
// number but never replaces it, so `from_raw_os_error(n).raw_os_error() == n`.
pub type Error {
    code: i32
    os: bool
    kind: ErrorKind
    payload: Heap<any CoreError>?
    payload_type: TypeId?
}

pub copy enum SeekFrom { Start(u64), End(i64), Current(i64) }

pub type IoSlice<region r> { data: read [u8] from r }
pub type IoSliceMut<region r> { data: mut [u8] from r }

extend<region r> IoSlice<region r> {
    pub static fn new(read data: [u8] from r): IoSlice<region r> {
        IoSlice(read data)
    }
}

extend<region r> IoSliceMut<region r> {
    pub static fn new(mut data: [u8] from r): IoSliceMut<region r> {
        IoSliceMut(mut data)
    }
}

pub fn from_raw_os_error(code: i32): Error {
    let kind = kind_from_index(unsafe { sys.mettle_rt_errno_kind(code) })
    Error(code, true, kind, none, none)
}

pub fn last_os_error(): Error { from_raw_os_error(sys.errno()) }

pub fn from_kind(kind: ErrorKind): Error { Error(0, false, kind, none, none) }

// An OS error whose portable class is overridden (for example an expired
// socket timeout reported by the OS as "try again"); the raw number is kept.
pub fn with_kind(code: i32, kind: ErrorKind): Error { Error(code, true, kind, none, none) }

// The reference description of each kind (its Display text).
fn kind_text(kind: ErrorKind): read Text from static {
    match kind {
        ErrorKind.NotFound => "entity not found",
        ErrorKind.PermissionDenied => "permission denied",
        ErrorKind.ConnectionRefused => "connection refused",
        ErrorKind.ConnectionReset => "connection reset",
        ErrorKind.ConnectionAborted => "connection aborted",
        ErrorKind.NotConnected => "not connected",
        ErrorKind.AddrInUse => "address in use",
        ErrorKind.AddrNotAvailable => "address not available",
        ErrorKind.BrokenPipe => "broken pipe",
        ErrorKind.AlreadyExists => "entity already exists",
        ErrorKind.WouldBlock => "operation would block",
        ErrorKind.InvalidInput => "invalid input parameter",
        ErrorKind.TimedOut => "timed out",
        ErrorKind.Interrupted => "operation interrupted",
        ErrorKind.OutOfMemory => "out of memory",
        ErrorKind.IsADirectory => "is a directory",
        ErrorKind.NotADirectory => "not a directory",
        ErrorKind.DirectoryNotEmpty => "directory not empty",
        ErrorKind.Other => "other error",
        ErrorKind.InvalidData => "invalid data",
        ErrorKind.WriteZero => "write zero",
        ErrorKind.UnexpectedEof => "unexpected end of file",
        ErrorKind.Unsupported => "unsupported",
        ErrorKind.ArgumentListTooLong => "argument list too long",
        ErrorKind.CrossesDevices => "crosses devices",
        ErrorKind.Deadlock => "deadlock",
        ErrorKind.ExecutableFileBusy => "executable file busy",
        ErrorKind.FileTooLarge => "file too large",
        ErrorKind.FilesystemLoop => "filesystem loop",
        ErrorKind.HostUnreachable => "host unreachable",
        ErrorKind.InProgress => "in progress",
        ErrorKind.InputOutputError => "input/output error",
        ErrorKind.InvalidFilename => "invalid filename",
        ErrorKind.NetworkDown => "network down",
        ErrorKind.NetworkUnreachable => "network unreachable",
        ErrorKind.NotSeekable => "not seekable",
        ErrorKind.QuotaExceeded => "quota exceeded",
        ErrorKind.ReadOnlyFilesystem => "read-only filesystem",
        ErrorKind.ResourceBusy => "resource busy",
        ErrorKind.StaleNetworkFileHandle => "stale network file handle",
        ErrorKind.StorageFull => "storage full",
        ErrorKind.TooManyLinks => "too many links",
        ErrorKind.TooManyOpenFiles => "too many open files"
    }
}

fn kind_description(kind: ErrorKind): String { alloc.string.from_text(kind_text(kind)) }

extend ErrorKind implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str(kind_text(self)) }
}

// An OS error shows the C library message and its number; a kind-only error
// shows the kind's description.
fn fmt_error<E: CoreError + unsized>(read value: E, mut f: fmt.Formatter): Unit throws fmt.Error {
    try E.(fmt.Display).fmt(value, mut f)
}

extend Error implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        match self.payload.as_view() {
            present(payload) => { return try fmt_error(payload.get(), mut f) },
            none => {}
        }
        if !self.os { return try f.write_str(kind_text(self.kind)) }
        let message = self.message()
        try f.write_str(message.as_text())
        try f.write_str(" (os error ")
        try i32.(fmt.Display).fmt(self.code, mut f)
        try f.write_char(')')
    }
}

extend Error implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("Error")
        try debug.field("kind", self.kind)
        try debug.field("raw_os_error", self.raw_os_error())
        match self.get_ref() {
            present(payload) => { let _ = try debug.field("payload", payload) },
            none => {}
        }
        try debug.finish()
    }
}
extend Error implements CoreError {
    fn source<region r>(receiver read self: Error from r): (read any CoreError from r)? {
        self.get_ref()
    }
}

extend ErrorKind {
    pub fn is(other: ErrorKind): bool { (self as i32) == (other as i32) }
}

extend ErrorKind implements PartialEq {
    fn eq(read other: ErrorKind): bool { self.is(other) }
}

extend ErrorKind implements core.cmp.Eq {}
extend ErrorKind implements core.cmp.PartialOrd {
    fn partial_cmp(read other: ErrorKind): core.cmp.Ordering? {
        present((self as i32).cmp(read (other as i32)))
    }
}
extend ErrorKind implements core.cmp.Ord {
    fn cmp(read other: ErrorKind): core.cmp.Ordering {
        (self as i32).cmp(read (other as i32))
    }
}
extend ErrorKind implements core.hash.Hash {
    fn hash<H: core.hash.Hasher>(mut state: H): Unit {
        state.write_u8(self as u8)
    }
}
extend ErrorKind implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        match self {
            ErrorKind.NotFound => try f.write_str("NotFound"),
            ErrorKind.PermissionDenied => try f.write_str("PermissionDenied"),
            ErrorKind.ConnectionRefused => try f.write_str("ConnectionRefused"),
            ErrorKind.ConnectionReset => try f.write_str("ConnectionReset"),
            ErrorKind.ConnectionAborted => try f.write_str("ConnectionAborted"),
            ErrorKind.NotConnected => try f.write_str("NotConnected"),
            ErrorKind.AddrInUse => try f.write_str("AddrInUse"),
            ErrorKind.AddrNotAvailable => try f.write_str("AddrNotAvailable"),
            ErrorKind.BrokenPipe => try f.write_str("BrokenPipe"),
            ErrorKind.AlreadyExists => try f.write_str("AlreadyExists"),
            ErrorKind.WouldBlock => try f.write_str("WouldBlock"),
            ErrorKind.InvalidInput => try f.write_str("InvalidInput"),
            ErrorKind.TimedOut => try f.write_str("TimedOut"),
            ErrorKind.Interrupted => try f.write_str("Interrupted"),
            ErrorKind.OutOfMemory => try f.write_str("OutOfMemory"),
            ErrorKind.IsADirectory => try f.write_str("IsADirectory"),
            ErrorKind.NotADirectory => try f.write_str("NotADirectory"),
            ErrorKind.DirectoryNotEmpty => try f.write_str("DirectoryNotEmpty"),
            ErrorKind.Other => try f.write_str("Other"),
            ErrorKind.InvalidData => try f.write_str("InvalidData"),
            ErrorKind.WriteZero => try f.write_str("WriteZero"),
            ErrorKind.UnexpectedEof => try f.write_str("UnexpectedEof"),
            ErrorKind.Unsupported => try f.write_str("Unsupported"),
            ErrorKind.ArgumentListTooLong => try f.write_str("ArgumentListTooLong"),
            ErrorKind.CrossesDevices => try f.write_str("CrossesDevices"),
            ErrorKind.Deadlock => try f.write_str("Deadlock"),
            ErrorKind.ExecutableFileBusy => try f.write_str("ExecutableFileBusy"),
            ErrorKind.FileTooLarge => try f.write_str("FileTooLarge"),
            ErrorKind.FilesystemLoop => try f.write_str("FilesystemLoop"),
            ErrorKind.HostUnreachable => try f.write_str("HostUnreachable"),
            ErrorKind.InProgress => try f.write_str("InProgress"),
            ErrorKind.InputOutputError => try f.write_str("InputOutputError"),
            ErrorKind.InvalidFilename => try f.write_str("InvalidFilename"),
            ErrorKind.NetworkDown => try f.write_str("NetworkDown"),
            ErrorKind.NetworkUnreachable => try f.write_str("NetworkUnreachable"),
            ErrorKind.NotSeekable => try f.write_str("NotSeekable"),
            ErrorKind.QuotaExceeded => try f.write_str("QuotaExceeded"),
            ErrorKind.ReadOnlyFilesystem => try f.write_str("ReadOnlyFilesystem"),
            ErrorKind.ResourceBusy => try f.write_str("ResourceBusy"),
            ErrorKind.StaleNetworkFileHandle => try f.write_str("StaleNetworkFileHandle"),
            ErrorKind.StorageFull => try f.write_str("StorageFull"),
            ErrorKind.TooManyLinks => try f.write_str("TooManyLinks"),
            ErrorKind.TooManyOpenFiles => try f.write_str("TooManyOpenFiles")
        }
    }
}

pub interface Seek {
    mut fn seek(pos: SeekFrom): u64 throws Error;
    mut fn stream_position(): u64 throws Error {
        try self.seek(SeekFrom.Current(0i64))
    }
    mut fn rewind(): Unit throws Error {
        let _ = try self.seek(SeekFrom.Start(0u64))
    }
    mut fn seek_relative(offset: i64): Unit throws Error {
        let _ = try self.seek(SeekFrom.Current(offset))
    }
}

extend Error {
    pub static fn last_os_error(): Error { super.io.last_os_error() }
    pub static fn new<E: CoreError + Static + Transferable + Shareable>(kind: ErrorKind, take payload: E): Error {
        let erased: Heap<any CoreError> = heap payload
        Error(0, false, kind, present(erased), present(type_id<E>()))
    }
    pub static fn other<E: CoreError + Static + Transferable + Shareable>(take payload: E): Error {
        Error.new(ErrorKind.Other, payload)
    }
    pub fn kind(): ErrorKind { self.kind }
    pub fn raw_os_error(): i32? { if self.os { present(self.code) } else { none } }
    pub fn is_os(): bool { self.os }
    pub fn get_ref(): (read any CoreError from self)? {
        match self.payload.as_view() {
            present(payload) => present(payload.get()),
            none => none
        }
    }
    pub mut fn get_mut(): (mut any CoreError from self)? {
        match take self.payload.as_mut() {
            present(payload) => present(payload.get_mut()),
            none => none
        }
    }
    pub take fn into_inner(): Heap<any CoreError>? { self.payload }
    pub take fn downcast<T: CoreError + Static>(): Outcome<Heap<T>, Error> {
        var this = self
        if this.payload_type != present(type_id<T>()) { return failure(this) }
        let erased = match take this.payload.`take`() {
            present(payload) => payload,
            none => { return failure(this) }
        }
        let raw = erased.into_raw()
        // Safety: the stored type identity matches T before erasure is removed.
        success(unsafe { alloc.boxed.from_raw<T>(raw.0.cast<T>()) })
    }

    // Payload text takes precedence; OS errors use strerror and kind-only errors use their kind text.
    pub fn message(): String {
        match self.get_ref() {
            present(payload) => {
                var output = alloc.string.new()
                {
                    var formatter = fmt.formatter(mut output, fmt.spec())
                    match capture fmt_error(payload, mut formatter) {
                        success(_) => {},
                        failure(_) => { alloc.alloc.panic_precondition() }
                    }
                }
                return output
            },
            none => {}
        }
        if self.os {
            let p = unsafe { sys.strerror(self.code) }
            let bytes = unsafe { sys.bytes_from_c(p) }
            let decoded = capture alloc.string.from_utf8(bytes)
            match take decoded {
                success(s) => { return s },
                failure(e) => { return alloc.string.from_text("unknown error") }
            }
        }
        kind_description(self.kind)
    }
}

extend Error implements From<ErrorKind> {
    static fn from(take kind: ErrorKind): Error { from_kind(kind) }
}

extend Error implements From<AllocError> {
    static fn from(take error: AllocError): Error { from_kind(ErrorKind.OutOfMemory) }
}

extend Error implements From<alloc.ffi.NulError> {
    static fn from(take error: alloc.ffi.NulError): Error {
        Error.new(ErrorKind.InvalidInput, error)
    }
}

extend Error implements From<super.fs.TryLockError> {
    static fn from(take error: super.fs.TryLockError): Error {
        match take error {
            super.fs.TryLockError.Error(error) => error,
            super.fs.TryLockError.WouldBlock => from_kind(ErrorKind.WouldBlock)
        }
    }
}

extend<G: Static + Transferable + Shareable> Error implements From<TryLockError<G>> {
    static fn from(take error: TryLockError<G>): Error { Error.other(error) }
}

// Reads bytes. `read_some` moves at most `buf.len()` bytes and returns how many it
// moved; zero means end of input (or an empty buffer). It may move fewer bytes
// than requested without being at the end.
pub interface Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error;

    mut fn read_vectored<region r>(mut bufs: [IoSliceMut<region r>]): usize throws Error {
        var index = 0usize
        while index < bufs.len() {
            if bufs[index].data.len() != 0usize {
                return try self.read_some(bufs[index].data)
            }
            index += 1usize
        }
        var empty = [0u8; 0]
        try self.read_some(empty)
    }

    fn by_ref<region r>(receiver mut self: Self from r): mut Self from r {
        mut self
    }

    // Fills `buf` entirely or fails with `UnexpectedEof`.
    mut fn read_exact(mut buf: [u8]): Unit throws Error {
        var done = 0usize
        let total = buf.len()
        while done < total {
            let rest = buf.split_at_mut(done).1
            let n = match take capture self.read_some(rest) {
                success(count) => count,
                failure(error) => {
                    if error.kind().is(ErrorKind.Interrupted) { continue }
                    throw error
                }
            }
            if n == 0usize { throw from_kind(ErrorKind.UnexpectedEof) }
            if n > total - done { throw from_kind(ErrorKind.InvalidData) }
            done += n
        }
    }

    // Appends everything up to the end of input to `out`; returns the count.
    mut fn read_to_end(mut out: List<u8>): usize throws Error {
        var chunk = [0u8; 4096]
        var total = 0usize
        while true {
            let n = match take capture self.read_some(chunk) {
                success(count) => count,
                failure(error) => {
                    if error.kind().is(ErrorKind.Interrupted) { continue }
                    throw error
                }
            }
            if n == 0usize { break }
            let bytes: read [u8] = read chunk
            if n > bytes.len() { throw from_kind(ErrorKind.InvalidData) }
            out.extend_from_slice(bytes.split_at(n).0)
            total += n
        }
        total
    }

    mut fn read_to_string(mut out: String): usize throws Error {
        var bytes = vec.new<u8>()
        let count = try self.read_to_end(mut bytes)
        match core.text.from_utf8(bytes.as_slice()) {
            success(text) => { out.push_str(text); count },
            failure(_) => throw from_kind(ErrorKind.InvalidData)
        }
    }

    take fn chain<R: Reader>(take second: R): Chain<Self, R> where Self: Sized {
        Chain(self, second, false)
    }
    take fn `take`(limit: u64): Take<Self> where Self: Sized {
        Take(self, limit)
    }
    take fn bytes(): Bytes<Self> where Self: Sized { Bytes(self, false) }
}

// Writes bytes. `write_some` accepts a prefix of `buf` and returns its length,
// which can be shorter than `buf`; `write_all` repeats until everything is
// accepted and fails with `WriteZero` if the sink stops accepting bytes.
pub interface Writer {
    mut fn write_some(read buf: [u8]): usize throws Error;
    mut fn flush(): Unit throws Error;

    mut fn write_vectored<region r>(read bufs: [IoSlice<region r>]): usize throws Error {
        var index = 0usize
        while index < bufs.len() {
            if bufs[index].data.len() != 0usize {
                return try self.write_some(bufs[index].data)
            }
            index += 1usize
        }
        var empty = [0u8; 0]
        try self.write_some(empty)
    }

    fn by_ref<region r>(receiver mut self: Self from r): mut Self from r {
        mut self
    }

    mut fn write_all(read buf: [u8]): Unit throws Error {
        var done = 0usize
        let total = buf.len()
        while done < total {
            let n = match take capture self.write_some(buf.split_at(done).1) {
                success(count) => count,
                failure(error) => {
                    if error.kind().is(ErrorKind.Interrupted) { continue }
                    throw error
                }
            }
            if n == 0usize { throw from_kind(ErrorKind.WriteZero) }
            if n > total - done { throw from_kind(ErrorKind.InvalidData) }
            done += n
        }
    }

    // Displays a native path: POSIX output is the path's bytes unchanged.
    mut fn write_path(read input: PathInput): Unit throws Error {
        try self.write_all(input.as_path().as_bytes())
    }
    // Formatted output: renders `message` through a borrowed sink adapter. The
    // first sink error is returned unchanged; a formatter failure without one
    // is `InvalidData`. Partial output is possible.
    mut fn write(message: format fmt.Message): Unit throws Error {
        try format_to(mut self, message, false)
    }
    mut fn write_line(message: format fmt.Message): Unit throws Error {
        try format_to(mut self, message, true)
    }
}

pub type Chain<A: Reader, B: Reader> { first: A; second: B; first_done: bool }
pub type Take<R: Reader> { inner: R; remaining: u64 }
pub type Bytes<R: Reader> { inner: R; finished: bool }

extend<A: Reader, B: Reader> Chain<A, B> implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error {
        if buf.len() == 0usize { return 0usize }
        if self.first_done { return try self.second.read_some(buf) }
        let count = try self.first.read_some(buf)
        if count == 0usize {
            self.first_done = true
            return try self.second.read_some(buf)
        }
        count
    }
}

extend<R: Reader> Take<R> implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error {
        if self.remaining == 0u64 || buf.len() == 0usize { return 0usize }
        var count = buf.len()
        if (count as u64) > self.remaining { count = self.remaining as usize }
        let count_read = try self.inner.read_some(buf.split_at_mut(count).0)
        if count_read > count { throw from_kind(ErrorKind.InvalidData) }
        self.remaining -= count_read as u64
        count_read
    }
}

extend<R: Reader> Bytes<R> implements core.iter.Iterator {
    type Item = (Outcome<u8, Error>);
    mut fn next(): (Outcome<u8, Error>)? {
        if self.finished { return none }
        var byte = [0u8; 1]
        let result = capture self.inner.read_some(byte)
        match take result {
            success(0usize) => {
                self.finished = true
                none
            },
            success(1usize) => present(success(byte[0usize])),
            success(_) => present(failure(from_kind(ErrorKind.InvalidData))),
            failure(error) => present(failure(error))
        }
    }
}

pub interface BufRead: Reader {
    mut fn fill_buf(): read [u8] from self throws Error;
    mut fn consume(n: usize): Unit;

    mut fn read_until(delimiter: u8, mut out: List<u8>): usize throws Error {
        var total = 0usize
        while true {
            let available = match take capture self.fill_buf() {
                success(bytes) => bytes,
                failure(error) => {
                    if error.kind().is(ErrorKind.Interrupted) { continue }
                    throw error
                }
            }
            if available.len() == 0usize { break }
            var count = 0usize
            while count < available.len() && available[count] != delimiter {
                count += 1usize
            }
            let used = if count < available.len() { count + 1usize } else { count }
            out.extend_from_slice(available.split_at(used).0)
            self.consume(used)
            total += used
            if used > count { break }
        }
        total
    }

    mut fn skip_until(delimiter: u8): usize throws Error {
        var total = 0usize
        while true {
            let available = match take capture self.fill_buf() {
                success(bytes) => bytes,
                failure(error) => {
                    if error.kind().is(ErrorKind.Interrupted) { continue }
                    throw error
                }
            }
            if available.len() == 0usize { break }
            var count = 0usize
            while count < available.len() && available[count] != delimiter {
                count += 1usize
            }
            let used = if count < available.len() { count + 1usize } else { count }
            self.consume(used)
            total += used
            if used > count { break }
        }
        total
    }

    mut fn read_line(mut out: String): usize throws Error {
        var bytes = vec.new<u8>()
        let count = try self.read_until(10u8, mut bytes)
        match core.text.from_utf8(bytes.as_slice()) {
            success(text) => out.push_str(text),
            failure(_) => throw from_kind(ErrorKind.InvalidData)
        }
        count
    }

    take fn lines(): Lines<Self> where Self: Sized { Lines(self, false) }
    take fn split(delimiter: u8): Split<Self> where Self: Sized {
        Split(self, delimiter, false)
    }
}

pub type Lines<B: BufRead> { reader: B; finished: bool }
pub type Split<B: BufRead> { reader: B; delimiter: u8; finished: bool }

extend<B: BufRead> Lines<B> implements core.iter.Iterator {
    type Item = (Outcome<String, Error>);
    mut fn next(): (Outcome<String, Error>)? {
        if self.finished { return none }
        var line = alloc.string.new()
        let result = capture self.reader.read_line(mut line)
        match take result {
            success(0usize) => {
                self.finished = true
                none
            },
            success(_) => {
                let len = line.len()
                if len > 0usize && line.as_bytes()[len - 1usize] == 10u8 {
                    line.truncate(len - 1usize)
                    let len = line.len()
                    if len > 0usize && line.as_bytes()[len - 1usize] == 13u8 {
                        line.truncate(len - 1usize)
                    }
                }
                present(success(line))
            },
            failure(error) => {
                present(failure(error))
            }
        }
    }
}

extend<B: BufRead + fmt.Debug> Lines<B> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("Lines")
        try debug.field("reader", self.reader)
        try debug.field("finished", self.finished)
        try debug.finish()
    }
}

// Safety: Lines owns only its reader and a boolean; its marker properties follow the reader.
// Payloads enter only through `new`, which requires Transferable + Shareable.
unsafe extend Error implements Transferable {}
unsafe extend Error implements Shareable {}
unsafe extend<B: BufRead + Transferable> Lines<B> implements Transferable {}
unsafe extend<B: BufRead + Shareable> Lines<B> implements Shareable {}

extend<B: BufRead> Split<B> implements core.iter.Iterator {
    type Item = (Outcome<List<u8>, Error>);
    mut fn next(): (Outcome<List<u8>, Error>)? {
        if self.finished { return none }
        var bytes = vec.new<u8>()
        let result = capture self.reader.read_until(self.delimiter, mut bytes)
        match take result {
            success(0usize) => {
                self.finished = true
                none
            },
            success(count) => {
                if bytes.len() > 0usize &&
                    bytes[bytes.len() - 1usize] == self.delimiter {
                    let _ = bytes.pop()
                }
                present(success(bytes))
            },
            failure(error) => {
                present(failure(error))
            }
        }
    }
}

// Adapts a byte writer to the formatting sink, keeping the first writer error.
type FormatSink<region r, W: Writer + unsized> { inner: mut W from r; first_error: Error? }
extend<region r, W: Writer + unsized> FormatSink<region r, W> implements fmt.Write {
    mut fn write_str(read text: Text): Unit throws fmt.Error {
        if self.first_error.is_present() { throw fmt.Error() }
        let done = capture self.inner.write_all(text.as_bytes())
        match take done {
            success(_) => {},
            failure(e) => { self.first_error = present(e); throw fmt.Error() }
        }
    }
}

fn format_to<W: Writer + unsized>(mut writer: W, message: format fmt.Message, newline: bool): Unit throws Error {
    var sink = FormatSink(mut writer, none)
    let outcome = capture message.write_to(mut sink)
    match take sink.first_error {
        present(error) => throw error,
        none => {}
    }
    match take outcome {
        success(_) => {},
        failure(_) => throw from_kind(ErrorKind.InvalidData)
    }
    if newline { try sink.inner.write_all("\n".as_bytes()) }
}

pub fn read_fd(fd: i32, mut buf: [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    while true {
        let n = unsafe { sys.`read`(fd, sys.data_mut(buf), buf.len()) }
        if n >= 0isize { return n as usize }
        let e = last_os_error()
        if !e.kind().is(ErrorKind.Interrupted) { throw e }
    }
    0usize
}

pub fn write_fd(fd: i32, read buf: [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    while true {
        let n = unsafe { sys.write(fd, slice.data(buf), buf.len()) }
        if n >= 0isize { return n as usize }
        let e = last_os_error()
        if !e.kind().is(ErrorKind.Interrupted) { throw e }
    }
    0usize
}

pub type PipeReader { descriptor: sys.OwnedFd }
pub type PipeWriter { descriptor: sys.OwnedFd }

extend PipeReader implements Reader {
    mut fn read_some(mut bytes: [u8]): usize throws Error {
        try read_fd(self.descriptor.as_raw_fd(), bytes)
    }
}

extend PipeWriter implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error {
        try write_fd(self.descriptor.as_raw_fd(), bytes)
    }
    mut fn flush(): Unit throws Error {}
}

extend PipeReader implements From<sys.OwnedFd> {
    static fn from(take descriptor: sys.OwnedFd): PipeReader { PipeReader(descriptor) }
}

extend PipeWriter implements From<sys.OwnedFd> {
    static fn from(take descriptor: sys.OwnedFd): PipeWriter { PipeWriter(descriptor) }
}

extend sys.OwnedFd implements From<PipeReader> {
    static fn from(take value: PipeReader): sys.OwnedFd { value.descriptor }
}

extend sys.OwnedFd implements From<PipeWriter> {
    static fn from(take value: PipeWriter): sys.OwnedFd { value.descriptor }
}

pub fn `copy`<R: Reader + unsized, W: Writer + unsized>(mut reader: R, mut writer: W): u64 throws Error {
    var buffer = [0u8; 8192]
    var total = 0u64
    while true {
        let count = match take capture reader.read_some(buffer) {
            success(count) => count,
            failure(error) => {
                if error.kind().is(ErrorKind.Interrupted) { continue }
                throw error
            }
        }
        if count == 0usize { break }
        let bytes: read [u8] = read buffer
        if count > bytes.len() { throw from_kind(ErrorKind.InvalidData) }
        try writer.write_all(bytes.split_at(count).0)
        total += count as u64
    }
    total
}

pub copy type Stdin {}
pub copy type Stdout {}
pub copy type Stderr {}

extern "C" {
    unsafe fn atexit(callback: extern "C" fn(): Unit): i32;
}

// Published mutexes and stream state live until process termination.
static STDIN_MUTEX: core.sync.atomic.AtomicPtr<u8> = core.sync.atomic.AtomicPtr<u8>.new(core.ptr.null_mut<u8>())
static STDOUT_MUTEX: core.sync.atomic.AtomicPtr<u8> = core.sync.atomic.AtomicPtr<u8>.new(core.ptr.null_mut<u8>())
static STDERR_MUTEX: core.sync.atomic.AtomicPtr<u8> = core.sync.atomic.AtomicPtr<u8>.new(core.ptr.null_mut<u8>())
static STDIN_STATE: core.cell.UnsafeCell<core.cell.RefCell<BufferedReader<RawStdin>>?> = core.cell.UnsafeCell.new(none)
static STDOUT_STATE: core.cell.UnsafeCell<core.cell.RefCell<BufferedWriter<RawOutput>>?> = core.cell.UnsafeCell.new(none)

type StdioLock {
    raw: ptr<mut u8>
    drop {
        if unsafe { sys.mettle_rt_mutex_unlock(self.raw) } != 0i32 {
            core.intrinsics.abort()
        }
    }
}
extend StdioLock not Transferable
// Sharing the opaque token exposes no operation on its owning-thread lock.
unsafe extend StdioLock implements Shareable {}

fn stream_lock(read slot: core.sync.atomic.AtomicPtr<u8>): StdioLock {
    let order = core.sync.atomic.Ordering.Acquire
    var raw = slot.load(order)
    if raw == core.ptr.null_mut<u8>() {
        let candidate = unsafe { sys.mettle_rt_reentrant_mutex_new() }
        if candidate == core.ptr.null_mut<u8>() { core.intrinsics.abort() }
        match slot.compare_exchange(core.ptr.null_mut<u8>(), candidate,
            core.sync.atomic.Ordering.AcqRel, order) {
            success(_) => { raw = candidate },
            failure(published) => {
                unsafe { sys.mettle_rt_mutex_free(candidate) }
                raw = published
            }
        }
    }
    if unsafe { sys.mettle_rt_mutex_lock(raw) } != 0i32 { core.intrinsics.abort() }
    StdioLock(raw)
}

// Caller holds the stream lock; initialization publishes once without user callbacks.
fn stream_state<T, F: fn(): T>(
    read cell: core.cell.UnsafeCell<core.cell.RefCell<T>?>, take initialize: F
): read core.cell.RefCell<T> from cell {
    match unsafe { read *cell.get() } {
        present(state) => { return read state },
        none => {}
    }
    let initialized = core.cell.RefCell.new(initialize())
    unsafe { *cell.get() = present(initialized) }
    match unsafe { read *cell.get() } {
        present(state) => read state,
        none => { core.intrinsics.abort() }
    }
}

type RawStdin {}
extend RawStdin implements Reader {
    mut fn read_some(mut bytes: [u8]): usize throws Error { try read_fd(0i32, bytes) }
}
type RawOutput { fd: i32 }
extend RawOutput implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error { try write_fd(self.fd, bytes) }
    mut fn flush(): Unit throws Error {}
}

fn input_state(): read core.cell.RefCell<BufferedReader<RawStdin>> from static {
    stream_state(STDIN_STATE, fn(): BufferedReader<RawStdin> { buf_reader(RawStdin()) })
}

fn output_state(): read core.cell.RefCell<BufferedWriter<RawOutput>> from static {
    stream_state(STDOUT_STATE, fn(): BufferedWriter<RawOutput> {
        let writer = buf_writer(RawOutput(1i32))
        if unsafe { atexit(stdout_cleanup) } != 0i32 { core.intrinsics.abort() }
        writer
    })
}

extern "C" fn stdout_cleanup(): Unit {
    let lock = stream_lock(STDOUT_MUTEX)
    match unsafe { read *STDOUT_STATE.get() } {
        present(state) => {
            match take state.try_borrow_mut() {
                success(guard) => {
                    var guard = guard
                    let _ = capture guard.get_mut().flush()
                },
                failure(_) => {}
            }
        },
        none => {}
    }
}

pub type StdinLock {
    token: StdioLock
    loan: (core.cell.Ref<BufferedReader<RawStdin>> from static)?
    drop { core.mem.drop(self.loan.`take`()) }
}
pub type StdoutLock { token: StdioLock }
pub type StderrLock { token: StdioLock }
extend StdinLock not Transferable
extend StdoutLock not Transferable
extend StderrLock not Transferable
// Shared guard views expose neither mutable state nor the retained borrow counter.
unsafe extend StdinLock implements Shareable {}
unsafe extend StdoutLock implements Shareable {}
unsafe extend StderrLock implements Shareable {}

extend Stdin {
    pub fn lock(): StdinLock { StdinLock(stream_lock(STDIN_MUTEX), none) }
    pub fn read_line(mut out: String): usize throws Error {
        var locked = self.lock()
        try locked.read_line(mut out)
    }
    pub take fn lines(): Lines<StdinLock> { self.lock().lines() }
}
extend Stdout {
    pub fn lock(): StdoutLock { StdoutLock(stream_lock(STDOUT_MUTEX)) }
}
extend Stderr {
    pub fn lock(): StderrLock { StderrLock(stream_lock(STDERR_MUTEX)) }
}

extend StdinLock implements Reader {
    mut fn read_some(mut bytes: [u8]): usize throws Error {
        core.mem.drop(self.loan.`take`())
        if bytes.len() == 0usize { return 0usize }
        var borrowed = input_state().borrow_mut()
        try borrowed.get_mut().read_some(bytes)
    }
    mut fn read_exact(mut bytes: [u8]): Unit throws Error {
        core.mem.drop(self.loan.`take`())
        if bytes.len() == 0usize { return }
        var borrowed = input_state().borrow_mut()
        try borrowed.get_mut().read_exact(bytes)
    }
}
extend StdinLock implements BufRead {
    mut fn fill_buf(): read [u8] from self throws Error {
        core.mem.drop(self.loan.`take`())
        let available = {
            var borrowed = input_state().borrow_mut()
            try borrowed.get_mut().fill_buf().len()
        }
        if available == 0usize { return "".as_bytes() }
        self.loan = present(input_state().borrow())
        match self.loan.as_view() {
            present(borrowed) => borrowed.get_ref().buffer(),
            none => { core.intrinsics.abort() }
        }
    }
    mut fn consume(count: usize): Unit {
        core.mem.drop(self.loan.`take`())
        var borrowed = input_state().borrow_mut()
        borrowed.get_mut().consume(count)
    }
}

extend StdoutLock implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error {
        var borrowed = output_state().borrow_mut()
        let writer = borrowed.get_mut()
        var line_end = 0usize
        var index = 0usize
        while index < bytes.len() {
            if bytes[index] == 10u8 { line_end = index + 1usize }
            index += 1usize
        }
        if line_end == 0usize { return try writer.write_some(bytes) }
        try writer.flush()
        let prefix = try writer.get_mut().write_some(bytes.split_at(line_end).0)
        if prefix > line_end { throw from_kind(ErrorKind.InvalidData) }
        if prefix < line_end || line_end == bytes.len() { return prefix }
        match take capture writer.write_some(bytes.split_at(line_end).1) {
            success(suffix) => line_end + suffix,
            failure(_) => line_end
        }
    }
    mut fn flush(): Unit throws Error {
        var borrowed = output_state().borrow_mut()
        try borrowed.get_mut().flush()
    }
}
extend StderrLock implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error { try write_fd(2i32, bytes) }
    mut fn flush(): Unit throws Error {}
}

extend StdinLock implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("StdinLock") }
}
extend StdoutLock implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("StdoutLock") }
}
extend StderrLock implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("StderrLock") }
}

extend Stdin implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("Stdin") }
}
extend Stdout implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("Stdout") }
}
extend Stderr implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("Stderr") }
}
pub fn stdin(): Stdin { Stdin() }
pub fn stdout(): Stdout { Stdout() }
pub fn stderr(): Stderr { Stderr() }

extend Stdin implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error {
        var locked = self.lock()
        try locked.read_some(buf)
    }
}
extend<region r> read Stdin from r implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error {
        var locked = self.lock()
        try locked.read_some(buf)
    }
}
extend Stdout implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        var locked = self.lock()
        try locked.write_some(buf)
    }
    mut fn flush(): Unit throws Error {
        var locked = self.lock()
        try locked.flush()
    }
}
extend<region r> read Stdout from r implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        var locked = self.lock()
        try locked.write_some(buf)
    }
    mut fn flush(): Unit throws Error {
        var locked = self.lock()
        try locked.flush()
    }
}
extend Stderr implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        var locked = self.lock()
        try locked.write_some(buf)
    }
    mut fn flush(): Unit throws Error {
        var locked = self.lock()
        try locked.flush()
    }
}
extend<region r> read Stderr from r implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        var locked = self.lock()
        try locked.write_some(buf)
    }
    mut fn flush(): Unit throws Error {
        var locked = self.lock()
        try locked.flush()
    }
}

extend<T: Reader + unsized, A: Allocator> Heap<T, A> implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error {
        try self.get_mut().read_some(buf)
    }
}

extend<T: Writer + unsized, A: Allocator> Heap<T, A> implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        try self.get_mut().write_some(buf)
    }
    mut fn flush(): Unit throws Error { try self.get_mut().flush() }
}

extend<T: Seek + unsized, A: Allocator> Heap<T, A> implements Seek {
    mut fn seek(pos: SeekFrom): u64 throws Error {
        try self.get_mut().seek(pos)
    }
}

extend<T: unsized, A: Allocator> Shared<T, A> implements Reader where read T: Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error {
        var view = self.get()
        try view.read_some(buf)
    }
    mut fn read_vectored<region r>(mut bufs: [IoSliceMut<region r>]): usize throws Error {
        var view = self.get()
        try view.read_vectored(bufs)
    }
    mut fn read_exact(mut buf: [u8]): Unit throws Error {
        var view = self.get()
        try view.read_exact(buf)
    }
    mut fn read_to_end(mut out: List<u8>): usize throws Error {
        var view = self.get()
        try view.read_to_end(out)
    }
    mut fn read_to_string(mut out: String): usize throws Error {
        var view = self.get()
        try view.read_to_string(out)
    }
}

extend<T: unsized, A: Allocator> Shared<T, A> implements Writer where read T: Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        var view = self.get()
        try view.write_some(buf)
    }
    mut fn write_vectored<region r>(read bufs: [IoSlice<region r>]): usize throws Error {
        var view = self.get()
        try view.write_vectored(bufs)
    }
    mut fn write_all(read buf: [u8]): Unit throws Error {
        var view = self.get()
        try view.write_all(buf)
    }
    mut fn flush(): Unit throws Error {
        var view = self.get()
        try view.flush()
    }
    mut fn write_path(read input: PathInput): Unit throws Error {
        var view = self.get()
        try view.write_path(input)
    }
    mut fn write(message: format fmt.Message): Unit throws Error {
        var view = self.get()
        try view.write(message)
    }
    mut fn write_line(message: format fmt.Message): Unit throws Error {
        var view = self.get()
        try view.write_line(message)
    }
}

extend<T: unsized, A: Allocator> Shared<T, A> implements Seek where read T: Seek {
    mut fn seek(pos: SeekFrom): u64 throws Error {
        var view = self.get()
        try view.seek(pos)
    }
    mut fn stream_position(): u64 throws Error {
        var view = self.get()
        try view.stream_position()
    }
    mut fn rewind(): Unit throws Error {
        var view = self.get()
        try view.rewind()
    }
    mut fn seek_relative(offset: i64): Unit throws Error {
        var view = self.get()
        try view.seek_relative(offset)
    }
}

extend<T: BufRead + unsized, A: Allocator> Heap<T, A> implements BufRead {
    mut fn fill_buf(): read [u8] from self throws Error {
        try self.get_mut().fill_buf()
    }
    mut fn consume(n: usize): Unit { self.get_mut().consume(n) }
}

extend<A: Allocator> Deque<u8, A> implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error {
        var count = 0usize
        while count < buf.len() {
            match self.pop_front() {
                present(byte) => {
                    buf[count] = byte
                    count += 1usize
                },
                none => { break }
            }
        }
        count
    }
}

extend<A: Allocator> Deque<u8, A> implements BufRead {
    mut fn fill_buf(): read [u8] from self throws Error {
        let slices = self.as_slices()
        if slices.0.len() > 0usize { slices.0 } else { slices.1 }
    }
    mut fn consume(n: usize): Unit {
        var remaining = n
        while remaining > 0usize {
            match self.pop_front() {
                present(_) => { remaining -= 1usize },
                none => { break }
            }
        }
    }
}

extend<A: Allocator> Deque<u8, A> implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        var count = 0usize
        while count < buf.len() {
            let byte = buf[count]
            let pushed = capture self.try_push_back(byte)
            match take pushed {
                success(_) => { count += 1usize },
                failure(_) => {
                    if count == 0usize { throw from_kind(ErrorKind.OutOfMemory) }
                    return count
                }
            }
        }
        count
    }
    mut fn flush(): Unit throws Error {}
}

// Writes the formatted message to standard output without a newline. An
// ordinary failure panics. A closed pipe (EPIPE) ends the process quietly with
// status 141 and runs no destructors, like `process.exit`; callers needing
// cleanup use `stdout().write(...)` and handle the error.
pub fn print(message: format fmt.Message): Unit {
    var out = stdout()
    let outcome = capture out.write(message)
    match take outcome {
        success(_) => {},
        failure(e) => {
            if e.kind().is(ErrorKind.BrokenPipe) { unsafe { sys.exit(141) } }
            core.panic.panic("failed to write to standard output")
        }
    }
}
// Like `print` for standard error; every failure panics.
pub fn eprint(message: format fmt.Message): Unit {
    var err = stderr()
    let outcome = capture err.write(message)
    match take outcome {
        success(_) => {},
        failure(e) => { core.panic.panic("failed to write to standard error") }
    }
}

// Appends the bytes of `src` to a growable buffer: `List<u8>` is a sink.
extend List<u8> implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        self.extend_from_slice(buf)
        buf.len()
    }
    mut fn flush(): Unit throws Error {}
}

// Reads from an in-memory slice, advancing past what was consumed.
pub type SliceReader<region r> { data: read [u8] from r; pos: usize }
pub fn slice_reader<region r>(read data: [u8] from r): SliceReader<region r> { SliceReader(read data, 0usize) }
extend<region r> SliceReader<region r> implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error {
        let left = self.data.len() - self.pos
        var n = buf.len()
        if left < n { n = left }
        var i = 0usize
        while i < n {
            buf[i] = self.data[self.pos + i]
            i += 1usize
        }
        self.pos += n
        n
    }
}

extend<region r> SliceReader<region r> implements BufRead {
    mut fn fill_buf(): read [u8] from self throws Error { self.data.split_at(self.pos).1 }
    mut fn consume(n: usize): Unit {
        let left = self.data.len() - self.pos
        self.pos += if n < left { n } else { left }
    }
}

extend<region r> SliceReader<region r> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("SliceReader")
        try debug.field("data", self.data)
        try debug.field("position", self.pos)
        try debug.finish()
    }
}

pub type Cursor<T> { inner: T; position: u64 }

extend<T> Cursor<T> {
    pub static const fn new(take inner: T): Cursor<T> { Cursor(inner, 0u64) }
    pub const fn get_ref(): read T from self { read self.inner }
    pub mut const fn get_mut(): mut T from self { mut self.inner }
    pub take fn into_inner(): T { self.inner }
    pub const fn position(): u64 { self.position }
    pub mut const fn set_position(position: u64): Unit { self.position = position }
}

fn cursor_start(read bytes: [u8], position: u64): usize {
    if position >= bytes.len() as u64 { bytes.len() } else { position as usize }
}

fn cursor_seek_offset(base: u64, offset: i64): u64 throws Error {
    if offset >= 0i64 {
        match base.checked_add(offset as u64) {
            present(position) => position,
            none => throw from_kind(ErrorKind.InvalidInput)
        }
    } else {
        let magnitude = if offset == -9223372036854775807i64 - 1i64 {
            9223372036854775808u64
        } else {
            (-offset) as u64
        }
        match base.checked_sub(magnitude) {
            present(position) => position,
            none => throw from_kind(ErrorKind.InvalidInput)
        }
    }
}

fn cursor_write_some(mut target: [u8], position: u64, read source: [u8]): usize {
    let start = cursor_start(read target, position)
    var count = source.len()
    let remaining = target.len() - start
    if count > remaining { count = remaining }
    var index = 0usize
    while index < count {
        target[start + index] = source[index]
        index += 1usize
    }
    count
}

extend<T: AsRef<[u8]>> Cursor<T> implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error {
        let bytes = T.(AsRef<[u8]>).as_ref(self.inner)
        let start = cursor_start(bytes, self.position)
        var count = buf.len()
        let remaining = bytes.len() - start
        if count > remaining { count = remaining }
        var index = 0usize
        while index < count {
            buf[index] = bytes[start + index]
            index += 1usize
        }
        self.position += count as u64
        count
    }
}

extend<T: AsRef<[u8]>> Cursor<T> implements BufRead {
    mut fn fill_buf(): read [u8] from self throws Error {
        let bytes = T.(AsRef<[u8]>).as_ref(self.inner)
        bytes.split_at(cursor_start(bytes, self.position)).1
    }
    mut fn consume(n: usize): Unit {
        self.position = self.position.saturating_add(n as u64)
    }
}

extend<T: AsRef<[u8]>> Cursor<T> implements Seek {
    mut fn seek(pos: SeekFrom): u64 throws Error {
        let next = match pos {
            SeekFrom.Start(position) => position,
            SeekFrom.Current(offset) => try cursor_seek_offset(self.position, offset),
            SeekFrom.End(offset) => {
                try cursor_seek_offset(T.(AsRef<[u8]>).as_ref(self.inner).len() as u64, offset)
            }
        }
        self.position = next
        next
    }
}

extend<const N: usize> Cursor<[u8; N]> implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        let target = [u8; N].(AsMut<[u8]>).as_mut(mut self.inner)
        let count = cursor_write_some(target, self.position, buf)
        self.position += count as u64
        count
    }
    mut fn flush(): Unit throws Error {}
}

extend<region r> Cursor<mut [u8] from r> implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        let count = cursor_write_some(mut self.inner, self.position, buf)
        self.position += count as u64
        count
    }
    mut fn flush(): Unit throws Error {}
}

extend<T: Clone> Cursor<T> implements Clone {
    fn clone(): Cursor<T> { Cursor(self.inner.clone(), self.position) }
}

extend<T: PartialEq> Cursor<T> implements PartialEq {
    fn eq(read other: Cursor<T>): bool {
        self.position == other.position && self.inner.eq(other.inner)
    }
}
extend<T: Eq> Cursor<T> implements Eq {}

extend<T: fmt.Debug> Cursor<T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("Cursor")
        try debug.field("inner", self.inner)
        try debug.field("position", self.position)
        try debug.finish()
    }
}

extend<T: Default> Cursor<T> implements Default {
    static fn default(): Cursor<T> { Cursor(T.(Default).default(), 0u64) }
}

// Safety: Cursor contains only T and a position; its marker properties follow T.
unsafe extend<T: Transferable> Cursor<T> implements Transferable {}
unsafe extend<T: Shareable> Cursor<T> implements Shareable {}

// Buffered reader: serves small reads from an internal buffer and refills it
// with one large read.
pub type BufferedReader<R: Reader> {
    inner: R
    buf: List<u8>
    pos: usize
    filled: usize
}

extend<R: Reader> BufferedReader<R> {
    pub static fn new(take inner: R): BufferedReader<R> { buf_reader(inner) }
    pub static fn with_capacity(capacity: usize, take inner: R): BufferedReader<R> {
        buf_reader_with_capacity(capacity, inner)
    }
}

pub fn buf_reader<R: Reader>(take inner: R): BufferedReader<R> { buf_reader_with_capacity(8192usize, inner) }

pub fn buf_reader_with_capacity<R: Reader>(capacity: usize, take inner: R): BufferedReader<R> {
    let usable = if capacity == 0usize { 1usize } else { capacity }
    var buf = vec.with_capacity<u8>(usable)
    buf.resize(usable, 0u8)
    BufferedReader(inner, buf, 0usize, 0usize)
}

extend<R: Reader> BufferedReader<R> {
    pub fn buffer(): read [u8] from self {
        self.buf.as_slice().split_at(self.filled).0.split_at(self.pos).1
    }
    pub fn capacity(): usize { self.buf.len() }
    pub fn get_ref(): read R from self { read self.inner }
    pub mut fn get_mut(): mut R from self { mut self.inner }
    pub take fn into_inner(): R { self.inner }

    // Replaces `buf` with the next line, LF or CRLF included, and views it;
    // none only at end of input with no bytes left. The last line may lack a
    // terminator. The view depends on `buf`, so `buf` cannot be changed while
    // it lives. Memory is the longest line plus this reader's buffer. Bytes that
    // are not UTF-8 fail with `InvalidData` after consuming the line, leaving
    // `buf` empty. An I/O failure also leaves `buf` empty (consumed input is lost).
    pub mut fn read_line_into(mut buf: String): (read Text from buf)? throws Error {
        buf.clear()
        let n = try self.read_line(mut buf)
        if n == 0usize { return none }
        present(buf.as_text())
    }

    // As `read_line_into` for arbitrary bytes: no validation, so only an I/O
    // failure (which leaves the bytes read so far in `buf`) can fail.
    pub mut fn read_bytes_line_into(mut buf: List<u8>): (read [u8] from buf)? throws Error {
        buf.clear()
        let n = try self.read_until(10u8, buf)
        if n == 0usize { return none }
        present(buf.as_slice())
    }
}

extend<R: Reader> BufferedReader<R> implements BufRead {
    mut fn fill_buf(): read [u8] from self throws Error {
        if self.pos >= self.filled {
            let n = try self.inner.read_some(self.buf.as_mut_slice())
            if n > self.buf.len() { throw from_kind(ErrorKind.InvalidData) }
            self.pos = 0usize
            self.filled = n
        }
        self.buf.as_slice().split_at(self.filled).0.split_at(self.pos).1
    }
    mut fn consume(n: usize): Unit {
        let remaining = self.filled - self.pos
        self.pos += if n < remaining { n } else { remaining }
    }
}

extend<R: Reader + Seek> BufferedReader<R> implements Seek {
    mut fn seek(pos: SeekFrom): u64 throws Error {
        let unread = self.filled - self.pos
        let adjusted = match pos {
            SeekFrom.Current(offset) => {
                if (unread as u64) > 9223372036854775807u64 {
                    throw from_kind(ErrorKind.InvalidInput)
                }
                let skipped = unread as i64
                let minimum = -9223372036854775807i64 - 1i64
                if offset < minimum + skipped {
                    throw from_kind(ErrorKind.InvalidInput)
                }
                SeekFrom.Current(offset - skipped)
            },
            _ => pos
        }
        let position = try self.inner.seek(adjusted)
        self.pos = 0usize
        self.filled = 0usize
        position
    }

    mut fn stream_position(): u64 throws Error {
        let position = try self.inner.stream_position()
        match position.checked_sub((self.filled - self.pos) as u64) {
            present(logical) => logical,
            none => { core.panic.panic("buffered reader position precedes its buffer") }
        }
    }

    mut fn seek_relative(offset: i64): Unit throws Error {
        if offset >= 0i64 {
            let advance = offset as u64
            if advance <= (self.filled - self.pos) as u64 {
                self.pos += advance as usize
                return
            }
        } else {
            let rewind = (-(offset + 1i64)) as u64 + 1u64
            if rewind <= self.pos as u64 {
                self.pos -= rewind as usize
                return
            }
        }
        let _ = try self.seek(SeekFrom.Current(offset))
    }
}

extend<R: Reader> BufferedReader<R> implements Reader {
    mut fn read_some(mut buf: [u8]): usize throws Error {
        if buf.len() == 0usize { return 0usize }
        let avail = try self.fill_buf()
        var n = buf.len()
        if avail.len() < n { n = avail.len() }
        var i = 0usize
        while i < n {
            buf[i] = avail[i]
            i += 1usize
        }
        self.consume(n)
        n
    }
}

extend<R: Reader + fmt.Debug> BufferedReader<R> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("BufferedReader")
        try debug.field("inner", self.inner)
        try debug.field("buffer", self.buf.as_slice())
        try debug.field("position", self.pos)
        try debug.field("filled", self.filled)
        try debug.finish()
    }
}

// Buffered writer: coalesces small writes; `flush` (or drop) pushes them out.
pub type BufferedWriter<W: Writer> {
    inner: W
    buf: List<u8>
    capacity: usize
    panicked: bool
    drop {
        if !self.panicked { let ignored = capture self.flush_buf() }
    }
}

extend<W: Writer> BufferedWriter<W> {
    pub static fn new(take inner: W): BufferedWriter<W> { buf_writer(inner) }
    pub static fn with_capacity(capacity: usize, take inner: W): BufferedWriter<W> {
        buf_writer_with_capacity(capacity, inner)
    }
}

pub fn buf_writer<W: Writer>(take inner: W): BufferedWriter<W> { buf_writer_with_capacity(8192usize, inner) }

pub fn buf_writer_with_capacity<W: Writer>(capacity: usize, take inner: W): BufferedWriter<W> {
    BufferedWriter(inner, vec.with_capacity<u8>(capacity), capacity, false)
}

type BufferedDrain<region r> {
    bytes: mut List<u8> from r
    written: usize
    drop {
        let remaining = self.bytes.len() - self.written
        var index = 0usize
        while index < remaining {
            self.bytes[index] = self.bytes[self.written + index]
            index += 1usize
        }
        self.bytes.truncate(remaining)
    }
}

fn tracked_write<W: Writer>(mut inner: W, mut panicked: bool, read bytes: [u8]): usize throws Error {
    let previous = panicked
    panicked = true
    let result = capture inner.write_some(bytes)
    panicked = previous
    match take result {
        success(count) => count,
        failure(error) => throw error
    }
}

extend<W: Writer> BufferedWriter<W> {
    mut fn flush_buf(): Unit throws Error {
        var drain = BufferedDrain(mut self.buf, 0usize)
        while drain.written < drain.bytes.len() {
            let result = capture tracked_write(
                mut self.inner, mut self.panicked,
                drain.bytes.as_slice().split_at(drain.written).1
            )
            let count = match take result {
                success(count) => count,
                failure(error) => {
                    if error.kind().is(ErrorKind.Interrupted) { continue }
                    throw error
                }
            }
            if count == 0usize { throw from_kind(ErrorKind.WriteZero) }
            if count > drain.bytes.len() - drain.written {
                throw from_kind(ErrorKind.InvalidData)
            }
            drain.written += count
        }
    }
    pub fn buffer(): read [u8] from self { self.buf.as_slice() }
    pub fn capacity(): usize { self.capacity }
    pub fn get_ref(): read W from self { read self.inner }
    pub mut fn get_mut(): mut W from self { mut self.inner }
    pub fn buffered(): usize { self.buf.len() }
}

extend<W: Writer> BufferedWriter<W> implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        if buf.len() > self.capacity - self.buf.len() { try self.flush_buf() }
        if buf.len() >= self.capacity {
            return try tracked_write(mut self.inner, mut self.panicked, buf)
        }
        self.buf.extend_from_slice(buf)
        buf.len()
    }
    mut fn flush(): Unit throws Error {
        try self.flush_buf()
        try self.inner.flush()
    }
}

pub type IntoInnerError<W: Writer> { writer: BufferedWriter<W>; error: Error }

extend<W: Writer> IntoInnerError<W> {
    pub fn error(): read Error from self { read self.error }
    pub take fn into_inner(): BufferedWriter<W> { self.writer }
}

extend<W: Writer> IntoInnerError<W> implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try Error.(fmt.Display).fmt(self.error, mut f)
    }
}
extend<W: Writer> IntoInnerError<W> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try Error.(fmt.Debug).fmt(self.error, mut f)
    }
}
extend<W: Writer> IntoInnerError<W> implements core.error.Error {}

extend<W: Writer> Error implements From<IntoInnerError<W>> {
    static fn from(take value: IntoInnerError<W>): Error { value.error }
}

pub type WriterPanicked { bytes: List<u8> }
extend WriterPanicked {
    pub take fn into_inner(): List<u8> { self.bytes }
}
extend WriterPanicked implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("writer panicked with unknown output progress")
    }
}
extend WriterPanicked implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("WriterPanicked")
    }
}
extend WriterPanicked implements CoreError {}

fn buffered_writer_parts<W: Writer>(take writer: BufferedWriter<W>): (W, Outcome<List<u8>, WriterPanicked>) {
    var owner = core.mem.ManuallyDrop.new(writer)
    let panicked = owner.deref_mut().panicked
    // Safety: the suppressed writer drop is replaced by one move of each owned field.
    let inner = unsafe {
        core.ptr.`read`(core.ptr.from_mut(mut owner.deref_mut().inner))
    }
    let buffer = unsafe {
        core.ptr.`read`(core.ptr.from_mut(mut owner.deref_mut().buf))
    }
    if panicked { (inner, failure(WriterPanicked(buffer))) } else { (inner, success(buffer)) }
}

extend<W: Writer> BufferedWriter<W> {
    pub take fn into_parts(): (W, Outcome<List<u8>, WriterPanicked>) {
        buffered_writer_parts(self)
    }

    pub take fn into_inner(): W throws IntoInnerError<W> {
        var this = self
        let flushed = capture this.flush_buf()
        match take flushed {
            success(_) => {
                let parts = this.into_parts()
                let _ = parts.1
                parts.0
            },
            failure(error) => { throw IntoInnerError(this, error) }
        }
    }
}

extend<W: Writer + Seek> BufferedWriter<W> implements Seek {
    mut fn seek(pos: SeekFrom): u64 throws Error {
        try self.flush_buf()
        try self.inner.seek(pos)
    }
}

extend<W: Writer + fmt.Debug> BufferedWriter<W> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("BufferedWriter")
        try debug.field("inner", self.inner)
        try debug.field("buffer", self.buf.as_slice())
        try debug.field("capacity", self.capacity)
        try debug.finish()
    }
}

// Value types duplicate by copy; owners clone their buffers.
extend ErrorKind implements Clone {
    fn clone(): ErrorKind { self }
}
