// Synchronous byte I/O: `Reader`/`Writer` expose partial transfers (the count a
// single call moved), the `*_all`/`read_exact`/`read_to_end` helpers loop over
// them, and `Error` keeps the raw OS error number so it round-trips unchanged.
import package.alloc.vec
import package.alloc.vec.List
import package.core.text.Text
import package.core.cmp.{PartialEq, Eq}
import package.core.clone.Clone
import package.core.default.Default
import package.core.slice
import package.core.fmt
import package.core.iter.Iterator
import package.alloc.string.String
import super.sys
import super.path.PathInput

pub copy enum ErrorKind {
    NotFound, PermissionDenied, ConnectionRefused, ConnectionReset, ConnectionAborted,
    NotConnected, AddrInUse, AddrNotAvailable, BrokenPipe, AlreadyExists, WouldBlock,
    InvalidInput, TimedOut, Interrupted, OutOfMemory, IsADirectory, NotADirectory,
    DirectoryNotEmpty, Other, InvalidData, WriteZero, UnexpectedEof, Unsupported
}

pub copy enum SeekFrom { Start(u64), End(i64), Current(i64) }

copy type ByteWindow { data: ptr<read u8>; len: usize }
copy type ByteWindowMut { data: ptr<mut u8>; len: usize }

pub copy type IoSlice { pointer: ptr<read u8>; len: usize }
pub copy type IoSliceMut { pointer: ptr<mut u8>; len: usize }

pub fn io_slice(bytes: read [u8]): IoSlice {
    let window = unsafe { core.mem.transmute<ByteWindow>(core.ptr.from_ref(bytes)) }
    IoSlice(window.data, window.len)
}
pub fn io_slice_mut(bytes: mut [u8]): IoSliceMut {
    let window = unsafe { core.mem.transmute<ByteWindowMut>(core.ptr.from_mut(bytes)) }
    IoSliceMut(window.data, window.len)
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
        _ => ErrorKind.Other
    }
}

// An I/O failure: a portable `kind` and, for failures reported by the
// operating system, the unmodified `errno` value (`raw_os_error`). A kind-only
// error carries no OS number. The kind of an OS error is derived from the
// number but never replaces it, so `from_raw_os_error(n).raw_os_error() == n`.
pub copy type Error {
    code: i32
    os: bool
    kind: ErrorKind
}

pub fn from_raw_os_error(code: i32): Error {
    let kind = kind_from_index(unsafe { sys.mettle_rt_errno_kind(code) })
    Error(code, true, kind)
}

pub fn last_os_error(): Error { from_raw_os_error(sys.errno()) }

pub fn from_kind(kind: ErrorKind): Error { Error(0, false, kind) }

// An OS error whose portable class is overridden (for example an expired
// socket timeout reported by the OS as "try again"); the raw number is kept.
pub fn with_kind(code: i32, kind: ErrorKind): Error { Error(code, true, kind) }

fn kind_description(kind: ErrorKind): String {
    var s = package.alloc.string.new()
    match kind {
        ErrorKind.InvalidInput => s.push_str("invalid input"),
        ErrorKind.InvalidData => s.push_str("invalid data"),
        ErrorKind.WriteZero => s.push_str("failed to write whole buffer"),
        ErrorKind.UnexpectedEof => s.push_str("unexpected end of file"),
        ErrorKind.TimedOut => s.push_str("timed out"),
        ErrorKind.Unsupported => s.push_str("unsupported"),
        _ => s.push_str("other error")
    }
    s
}

extend ErrorKind {
    pub fn is(other: ErrorKind): bool { (self as i32) == (other as i32) }
}

extend ErrorKind implements PartialEq {
    fn eq(other: read ErrorKind): bool { self.is(other) }
}

extend Error {
    pub fn kind(): ErrorKind { self.kind }
    pub static fn other(): Error { from_kind(ErrorKind.Other) }
    pub fn raw_os_error(): i32? { if self.os { present(self.code) } else { none } }
    pub fn is_os(): bool { self.os }

    // Human-readable description: the C library message for OS errors.
    pub fn message(): String {
        if self.os {
            let p = unsafe { sys.strerror(self.code) }
            let bytes = unsafe { sys.bytes_from_c(p) }
            let decoded = capture package.alloc.string.from_utf8(bytes)
            match take decoded {
                success(s) => { return s },
                failure(e) => { return package.alloc.string.from_text("unknown error") }
            }
        }
        kind_description(self.kind)
    }
}

// Reads bytes. `read_some` moves at most `buf.len()` bytes and returns how many it
// moved; zero means end of input (or an empty buffer). It may move fewer bytes
// than requested without being at the end.
pub interface Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error;
    mut fn `read`(buf: mut [u8]): usize throws Error { try self.read_some(buf) }
    mut fn read_vectored<region r>(bufs: read [IoSliceMut] from r): usize throws Error {
        var index = 0usize
        while index < bufs.len() {
            let part = bufs[index]
            if part.len != 0usize {
                let bytes = unsafe { slice.from_raw_parts_mut<r, u8>(part.pointer, part.len) }
                return try self.read_some(bytes)
            }
            index += 1usize
        }
        0usize
    }

    // Fills `buf` entirely or fails with `UnexpectedEof`.
    mut fn read_exact(buf: mut [u8]): Unit throws Error {
        var done = 0usize
        let total = buf.len()
        while done < total {
            let rest = buf.split_at_mut(done).1
            let n = try self.read_some(rest)
            if n == 0usize { throw from_kind(ErrorKind.UnexpectedEof) }
            done += n
        }
    }

    // Appends everything up to the end of input to `out`; returns the count.
    mut fn read_to_end(out: mut List<u8>): usize throws Error {
        var chunk = [0u8; 4096]
        var total = 0usize
        while true {
            let n = try self.read_some(chunk)
            if n == 0usize { break }
            out.extend_from_slice(chunk.split_at(n).0)
            total += n
        }
        total
    }

    // Appends decoded text. Invalid UTF-8 restores `out` and fails with `InvalidData`
    // after the bytes have already been consumed from this reader.
    mut fn read_to_string(out: mut String): usize throws Error {
        let start = out.len()
        let count = unsafe { try self.read_to_end(out.as_mut_vec()) }
        match package.core.text.from_utf8(out.as_bytes()) {
            present(_) => count,
            none => {
                out.truncate(start)
                throw from_kind(ErrorKind.InvalidData)
            }
        }
    }

    mut fn by_ref<region r>(receiver self: mut Self from r): ReaderRef<region r, Self> {
        ReaderRef(mut self)
    }
    mut fn bytes<region r>(receiver self: mut Self from r): ByteReader<region r, Self> {
        ByteReader(mut self)
    }
    take fn chain<R: Reader>(next: take R): ChainedReader<Self, R> {
        ChainedReader(self, next, false)
    }
    take fn `take`(limit: usize): LimitedReader<Self> { LimitedReader(self, limit) }
}

// Writes bytes. `write_some` accepts a prefix of `buf` and returns its length,
// which can be shorter than `buf`; `write_all` repeats until everything is
// accepted and fails with `WriteZero` if the sink stops accepting bytes.
pub interface Writer {
    mut fn write_some(buf: read [u8]): usize throws Error;
    mut fn write_vectored<region r>(bufs: read [IoSlice] from r): usize throws Error {
        var index = 0usize
        while index < bufs.len() {
            let part = bufs[index]
            if part.len != 0usize {
                let bytes = unsafe { slice.from_raw_parts<r, u8>(part.pointer, part.len) }
                return try self.write_some(bytes)
            }
            index += 1usize
        }
        0usize
    }
    mut fn flush(): Unit throws Error;

    mut fn write_all(buf: read [u8]): Unit throws Error {
        var done = 0usize
        let total = buf.len()
        while done < total {
            let n = try self.write_some(buf.split_at(done).1)
            if n == 0usize { throw from_kind(ErrorKind.WriteZero) }
            done += n
        }
    }

    // Displays a native path: POSIX output is the path's bytes unchanged.
    mut fn write_path(input: read PathInput): Unit throws Error {
        try self.write_all(input.as_path().as_bytes())
    }
    // Formatted output: renders `message` through a borrowed sink adapter. The
    // first sink error is returned unchanged; a formatter failure without one
    // is `InvalidData`. Partial output is possible.
    mut fn write(message: format fmt.Message): Unit throws Error {
        try format_to(mut self, message, false)
    }
    mut fn write_fmt(message: format fmt.Message): Unit throws Error {
        try self.write(message)
    }
    mut fn write_line(message: format fmt.Message): Unit throws Error {
        try format_to(mut self, message, true)
    }
    mut fn by_ref<region r>(receiver self: mut Self from r): WriterRef<region r, Self> {
        WriterRef(mut self)
    }
}

pub interface Seek {
    mut fn seek(pos: SeekFrom): u64 throws Error;
    mut fn rewind(): Unit throws Error {
        let _ignored = try self.seek(SeekFrom.Start(0u64))
    }
    mut fn stream_position(): u64 throws Error { try self.seek(SeekFrom.Current(0i64)) }
    mut fn seek_relative(offset: i64): Unit throws Error {
        let _ignored = try self.seek(SeekFrom.Current(offset))
    }
}

pub interface BufRead: Reader {
    mut fn fill_buf(): read [u8] from self throws Error;
    mut fn consume(amount: usize): Unit;
    mut fn read_until(delimiter: u8, out: mut List<u8>): usize throws Error {
        var total = 0usize
        while true {
            let avail = try self.fill_buf()
            if avail.len() == 0usize { break }
            var index = 0usize
            var found = false
            while index < avail.len() {
                if avail[index] == delimiter { found = true; break }
                index += 1usize
            }
            let used = if found { index + 1usize } else { avail.len() }
            out.extend_from_slice(avail.split_at(used).0)
            self.consume(used)
            total += used
            if found { break }
        }
        total
    }
    mut fn read_line(out: mut List<u8>): usize throws Error { try self.read_until(10u8, out) }
    mut fn skip_until(delimiter: u8): usize throws Error {
        var total = 0usize
        while true {
            let avail = try self.fill_buf()
            if avail.len() == 0usize { break }
            var index = 0usize
            var found = false
            while index < avail.len() {
                if avail[index] == delimiter { found = true; break }
                index += 1usize
            }
            let used = if found { index + 1usize } else { avail.len() }
            self.consume(used)
            total += used
            if found { break }
        }
        total
    }
    mut fn split<region r>(receiver self: mut Self from r, delimiter: u8): Split<region r, Self> {
        Split(mut self, delimiter, false)
    }
    mut fn lines<region r>(receiver self: mut Self from r): Lines<region r, Self> {
        Lines(mut self, false)
    }
}

pub type Split<region r, R: BufRead + unsized> {
    inner: mut R from r
    delimiter: u8
    done: bool
}
extend<region r, R: BufRead + unsized> Split<region r, R> implements Iterator {
    type Item = (List<u8> throws Error);
    mut fn next(): Self.Item? {
        if self.done { return none }
        var out = vec.new<u8>()
        let count = match take capture self.inner.read_until(self.delimiter, out) {
            success(n) => n,
            failure(error) => { return present(failure(error)) }
        }
        if count == 0usize { self.done = true; return none }
        if out.len() > 0usize && out[out.len() - 1usize] == self.delimiter { out.pop() } else { self.done = true }
        present(success(out))
    }
}

pub type Lines<region r, R: BufRead + unsized> { inner: mut R from r; done: bool }
extend<region r, R: BufRead + unsized> Lines<region r, R> implements Iterator {
    type Item = (String throws Error);
    mut fn next(): Self.Item? {
        if self.done { return none }
        var bytes = vec.new<u8>()
        let count = match take capture self.inner.read_line(bytes) {
            success(n) => n,
            failure(error) => { return present(failure(error)) }
        }
        if count == 0usize { self.done = true; return none }
        var ended = false
        if bytes.len() > 0usize && bytes[bytes.len() - 1usize] == 10u8 {
            ended = true
            bytes.pop()
            if bytes.len() > 0usize && bytes[bytes.len() - 1usize] == 13u8 { bytes.pop() }
        }
        if !ended { self.done = true }
        match take capture package.alloc.string.from_utf8(bytes) {
            success(text) => present(success(text)),
            failure(_) => present(failure(from_kind(ErrorKind.InvalidData)))
        }
    }
}

pub type ReaderRef<region r, R: Reader + unsized> { inner: mut R from r }
extend<region r, R: Reader + unsized> ReaderRef<region r, R> implements Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error { try self.inner.read_some(buf) }
}

pub type WriterRef<region r, W: Writer + unsized> { inner: mut W from r }
extend<region r, W: Writer + unsized> WriterRef<region r, W> implements Writer {
    mut fn write_some(buf: read [u8]): usize throws Error { try self.inner.write_some(buf) }
    mut fn flush(): Unit throws Error { try self.inner.flush() }
}

pub type ByteReader<region r, R: Reader + unsized> { inner: mut R from r }
extend<region r, R: Reader + unsized> ByteReader<region r, R> implements Iterator {
    type Item = (u8 throws Error)
    mut fn next(): Self.Item? {
        var buf = [0u8; 1]
        let outcome = capture self.inner.read_some(buf)
        match take outcome {
            failure(error) => present(failure(error)),
            success(0usize) => none,
            success(_) => present(success(buf[0]))
        }
    }
}

pub type ChainedReader<A: Reader, B: Reader> {
    first: A
    second: B
    done_first: bool
}
extend<A: Reader, B: Reader> ChainedReader<A, B> implements Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error {
        if !self.done_first {
            let n = try self.first.read_some(buf)
            if n > 0usize { return n }
            self.done_first = true
        }
        try self.second.read_some(buf)
    }
}

pub type LimitedReader<R: Reader> { inner: R; left: usize }
extend<R: Reader> LimitedReader<R> implements Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error {
        if self.left == 0usize || buf.len() == 0usize { return 0usize }
        let cap = if buf.len() < self.left { buf.len() } else { self.left }
        let n = try self.inner.read_some(buf.split_at_mut(cap).0)
        self.left -= n
        n
    }
}

// Adapts a byte writer to the formatting sink, keeping the first writer error.
type FormatSink<region r, W: Writer + unsized> { inner: mut W from r; first_error: Error? }
extend<region r, W: Writer + unsized> FormatSink<region r, W> implements fmt.Write {
    mut fn write_str(text: read Text): Unit throws fmt.Error {
        let done = capture self.inner.write_all(text.as_bytes())
        match take done {
            success(_) => {},
            failure(e) => { self.first_error = present(e); throw fmt.Error() }
        }
    }
}

fn format_to<W: Writer + unsized>(writer: mut W, message: format fmt.Message, newline: bool): Unit throws Error {
    var sink = FormatSink(mut writer, none)
    let outcome = capture message.write_to(mut sink)
    match take outcome {
        success(_) => {},
        failure(_) => {
            match sink.first_error {
                present(e) => { throw e },
                none => { throw from_kind(ErrorKind.InvalidData) }
            }
        }
    }
    if newline { try sink.inner.write_all("\n".as_bytes()) }
}

fn fd_read(fd: i32, buf: mut [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    while true {
        let n = unsafe { sys.`read`(fd, sys.data_mut(buf), buf.len()) }
        if n >= 0isize { return n as usize }
        let e = last_os_error()
        if !e.kind().is(ErrorKind.Interrupted) { throw e }
    }
    0usize
}

fn fd_write(fd: i32, buf: read [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    while true {
        let n = unsafe { sys.write(fd, slice.data(buf), buf.len()) }
        if n >= 0isize { return n as usize }
        let e = last_os_error()
        if !e.kind().is(ErrorKind.Interrupted) { throw e }
    }
    0usize
}

pub fn read_fd(fd: i32, buf: mut [u8]): usize throws Error { try fd_read(fd, buf) }
pub fn `copy`<R: Reader, W: Writer>(reader: mut R, writer: mut W): usize throws Error {
    var buf = [0u8; 8192]
    var total = 0usize
    while true {
        let count = try reader.read_some(buf)
        if count == 0usize { return total }
        try writer.write_all(buf.split_at(count).0)
        total += count
    }
    total
}
pub fn write_fd(fd: i32, buf: read [u8]): usize throws Error { try fd_write(fd, buf) }

pub copy type Stdin {}
pub copy type Stdout {}
pub copy type Stderr {}
pub fn stdin(): Stdin { Stdin() }
pub fn stdout(): Stdout { Stdout() }
pub fn stderr(): Stderr { Stderr() }

extend Stdin implements Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error { try fd_read(0, buf) }
}
extend Stdout implements Writer {
    mut fn write_some(buf: read [u8]): usize throws Error { try fd_write(1, buf) }
    mut fn flush(): Unit throws Error {}
}
extend Stderr implements Writer {
    mut fn write_some(buf: read [u8]): usize throws Error { try fd_write(2, buf) }
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
            package.core.panic.panic("failed to write to standard output")
        }
    }
}
// Like `print` for standard error; every failure panics.
pub fn println(message: format fmt.Message): Unit {
    var out = stdout()
    let outcome = capture out.write_line(message)
    match take outcome {
        success(_) => {},
        failure(e) => {
            if e.kind().is(ErrorKind.BrokenPipe) { unsafe { sys.exit(141) } }
            package.core.panic.panic("failed to write to standard output")
        }
    }
}

pub fn eprintln(message: format fmt.Message): Unit {
    var err = stderr()
    let outcome = capture err.write_line(message)
    match take outcome {
        success(_) => {},
        failure(_) => { package.core.panic.panic("failed to write to standard error") }
    }
}

pub fn eprint(message: format fmt.Message): Unit {
    var err = stderr()
    let outcome = capture err.write(message)
    match take outcome {
        success(_) => {},
        failure(e) => { package.core.panic.panic("failed to write to standard error") }
    }
}

// Appends the bytes of `src` to a growable buffer: `List<u8>` is a sink.
extend List<u8> implements Writer {
    mut fn write_some(buf: read [u8]): usize throws Error {
        self.extend_from_slice(buf)
        buf.len()
    }
    mut fn flush(): Unit throws Error {}
}

// Reads from an in-memory slice, advancing past what was consumed.
pub type SliceReader<region r> { data: read [u8] from r; pos: usize }
pub fn slice_reader<region r>(data: read [u8] from r): SliceReader<region r> { SliceReader(read data, 0usize) }
extend<region r> SliceReader<region r> implements Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error {
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

// Buffered reader: serves small reads from an internal buffer and refills it
// with one large read.
pub type BufferedReader<R: Reader> {
    inner: R
    buf: List<u8>
    pos: usize
    filled: usize
}

pub fn buf_reader<R: Reader>(inner: take R): BufferedReader<R> { buf_reader_with_capacity(8192usize, inner) }
extend<R: Reader> BufferedReader<R> {
    pub static fn with_capacity(capacity: usize, inner: take R): BufferedReader<R> {
        buf_reader_with_capacity(capacity, inner)
    }
}

pub fn buf_reader_with_capacity<R: Reader>(capacity: usize, inner: take R): BufferedReader<R> {
    var buf = vec.with_capacity<u8>(capacity)
    buf.resize(capacity, 0u8)
    BufferedReader(inner, buf, 0usize, 0usize)
}

extend<R: Reader> BufferedReader<R> {
    // The unread bytes, refilling from the source when the buffer is drained.
    pub mut fn fill_buf(): read [u8] from self throws Error {
        if self.pos >= self.filled {
            let n = try self.inner.read_some(self.buf.as_mut_slice())
            self.pos = 0usize
            self.filled = n
        }
        self.buf.as_slice().split_at(self.filled).0.split_at(self.pos).1
    }
    pub mut fn consume(n: usize): Unit {
        self.pos += n
        if self.pos > self.filled { self.pos = self.filled }
    }
    pub fn get_ref(): read R from self { read self.inner }
    pub take fn into_inner(): R { self.inner }
    pub fn buffer(): read [u8] from self {
        self.buf.as_slice().split_at(self.filled).0.split_at(self.pos).1
    }
    pub fn capacity(): usize { self.buf.capacity() }

    // Appends bytes up to and including `delimiter` (or the end of input) to
    // `out`; returns how many were appended.
    pub mut fn read_until(delimiter: u8, out: mut List<u8>): usize throws Error {
        var total = 0usize
        while true {
            let avail = try self.fill_buf()
            if avail.len() == 0usize { break }
            var i = 0usize
            var found = false
            while i < avail.len() {
                if avail[i] == delimiter { found = true; break }
                i += 1usize
            }
            let used = if found { i + 1usize } else { avail.len() }
            out.extend_from_slice(avail.split_at(used).0)
            self.consume(used)
            total += used
            if found { break }
        }
        total
    }

    // Appends one line, including its newline, to `out`; zero means end of input.
    pub mut fn read_line(out: mut List<u8>): usize throws Error { try self.read_until(10u8, out) }

    // Replaces `buf` with the next line, LF or CRLF included, and views it;
    // none only at end of input with no bytes left. The last line may lack a
    // terminator. The view depends on `buf`, so `buf` cannot be changed while
    // it lives. Memory is the longest line plus this reader's buffer. Bytes that
    // are not UTF-8 fail with `InvalidData` after consuming the line, leaving
    // `buf` empty. An I/O failure also leaves `buf` empty (consumed input is lost).
    pub mut fn read_line_into(buf: mut String): (read Text from buf)? throws Error {
        buf.clear()
        let read_result = capture self.read_until(10u8, unsafe { buf.as_mut_vec() })
        let n = match take read_result {
            success(count) => count,
            failure(e) => { buf.clear(); throw e }
        }
        if n == 0usize { return none }
        let valid = match package.core.text.from_utf8(buf.as_bytes()) {
            present(_) => true,
            none => false
        }
        if !valid { buf.clear(); throw from_kind(ErrorKind.InvalidData) }
        present(buf.as_text())
    }

    // As `read_line_into` for arbitrary bytes: no validation, so only an I/O
    // failure (which leaves the bytes read so far in `buf`) can fail.
    pub mut fn read_bytes_line_into(buf: mut List<u8>): (read [u8] from buf)? throws Error {
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
            self.pos = 0usize
            self.filled = n
        }
        self.buf.as_slice().split_at(self.filled).0.split_at(self.pos).1
    }
    mut fn consume(amount: usize): Unit {
        self.pos += amount
        if self.pos > self.filled { self.pos = self.filled }
    }
}

extend<R: Reader + Seek> BufferedReader<R> {
    pub mut fn seek_relative(offset: i64): Unit throws Error {
        let unread = (self.filled - self.pos) as i64
        self.pos = 0usize
        self.filled = 0usize
        match offset.checked_sub(unread) {
            present(delta) => { try self.inner.seek_relative(delta) },
            none => { throw from_kind(ErrorKind.InvalidInput) }
        }
    }
}

extend<R: Reader> BufferedReader<R> implements Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error {
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

// Buffered writer: coalesces small writes; `flush` (or drop) pushes them out.
pub type BufferedWriter<W: Writer> {
    inner: W
    buf: List<u8>
    capacity: usize
    drop {
        let ignored = capture self.flush_buf()
    }
}

pub fn buf_writer<W: Writer>(inner: take W): BufferedWriter<W> { buf_writer_with_capacity(8192usize, inner) }
extend<W: Writer> BufferedWriter<W> {
    pub static fn with_capacity(capacity: usize, inner: take W): BufferedWriter<W> {
        buf_writer_with_capacity(capacity, inner)
    }
}

pub fn buf_writer_with_capacity<W: Writer>(capacity: usize, inner: take W): BufferedWriter<W> {
    BufferedWriter(inner, vec.with_capacity<u8>(capacity), capacity)
}

extend<W: Writer> BufferedWriter<W> {
    mut fn flush_buf(): Unit throws Error {
        if self.buf.len() > 0usize {
            try self.inner.write_all(self.buf.as_slice())
            self.buf.clear()
        }
    }
    pub fn get_ref(): read W from self { read self.inner }
    pub fn buffered(): usize { self.buf.len() }
    pub fn buffer(): read [u8] from self { self.buf.as_slice() }
    pub fn capacity(): usize { self.capacity }
    // The unflushed bytes stay in the list. Drop does not run, so they are not written.
    pub take fn into_parts(): (W, List<u8>) {
        unsafe {
            let inner = core.ptr.`read`(core.ptr.from_ref(self.inner))
            let pending = core.ptr.`read`(core.ptr.from_ref(self.buf))
            core.mem.forget(take self)
            (inner, pending)
        }
    }
}

extend<W: Writer> BufferedWriter<W> implements Writer {
    mut fn write_some(buf: read [u8]): usize throws Error {
        if self.buf.len() + buf.len() > self.capacity { try self.flush_buf() }
        if buf.len() >= self.capacity {
            return try self.inner.write_some(buf)
        }
        self.buf.extend_from_slice(buf)
        buf.len()
    }
    mut fn flush(): Unit throws Error {
        try self.flush_buf()
        try self.inner.flush()
    }
}

pub type Cursor<T> { inner: T; pos: u64 }

extend<T> Cursor<T> {
    pub static fn new(inner: take T): Cursor<T> { Cursor(inner, 0u64) }
    pub fn position(): u64 { self.pos }
    pub mut fn set_position(position: u64): Unit { self.pos = position }
    pub fn get_ref(): read T from self { read self.inner }
    pub mut fn get_mut(): mut T from self { mut self.inner }
    pub take fn into_inner(): T { self.inner }
}

extend<T: Clone> Cursor<T> implements Clone {
    fn clone(): Cursor<T> { Cursor(self.inner.clone(), self.pos) }
}
extend<T: Default> Cursor<T> implements Default {
    static fn default(): Cursor<T> { Cursor(T.(Default).default(), 0u64) }
}
extend<T: PartialEq> Cursor<T> implements PartialEq {
    fn eq(other: read Cursor<T>): bool { self.pos == other.pos && self.inner == other.inner }
}
extend<T: Eq> Cursor<T> implements Eq {}

extend Cursor<List<u8>> implements Reader {
    mut fn read_some(buf: mut [u8]): usize throws Error {
        if buf.len() == 0usize || self.pos > self.inner.len() as u64 { return 0usize }
        let avail = self.inner.as_slice().split_at(self.pos as usize).1
        var count = buf.len()
        if count > avail.len() { count = avail.len() }
        var index = 0usize
        while index < count {
            buf[index] = avail[index]
            index += 1usize
        }
        self.pos += count as u64
        count
    }
}

extend Cursor<List<u8>> implements Writer {
    mut fn write_some(buf: read [u8]): usize throws Error {
        if buf.len() == 0usize { return 0usize }
        let start = self.pos as usize
        if self.pos > self.inner.len() as u64 { self.inner.resize(start, 0u8) }
        var index = 0usize
        while index < buf.len() {
            let at = start + index
            if at < self.inner.len() { self.inner[at] = buf[index] } else { self.inner.push(buf[index]) }
            index += 1usize
        }
        self.pos += buf.len() as u64
        buf.len()
    }
    mut fn flush(): Unit throws Error {}
}

extend Cursor<List<u8>> implements BufRead {
    mut fn fill_buf(): read [u8] from self throws Error {
        if self.pos >= self.inner.len() as u64 {
            return self.inner.as_slice().split_at(self.inner.len()).1
        }
        self.inner.as_slice().split_at(self.pos as usize).1
    }
    mut fn consume(amount: usize): Unit {
        let start = self.pos as usize
        let rest = if start >= self.inner.len() { 0usize } else { self.inner.len() - start }
        let used = if amount > rest { rest } else { amount }
        self.pos += used as u64
    }
}

extend Cursor<List<u8>> implements Seek {
    mut fn seek(pos: SeekFrom): u64 throws Error {
        let len = self.inner.len() as u64
        var next = self.pos
        match pos {
            SeekFrom.Start(n) => { next = n },
            SeekFrom.End(n) => {
                if n >= 0i64 {
                    match len.checked_add(n as u64) {
                        present(value) => { next = value },
                        none => { throw from_kind(ErrorKind.InvalidInput) }
                    }
                } else {
                    let back = (-n) as u64
                    if back > len { throw from_kind(ErrorKind.InvalidInput) }
                    next = len - back
                }
            },
            SeekFrom.Current(n) => {
                if n >= 0i64 {
                    match self.pos.checked_add(n as u64) {
                        present(value) => { next = value },
                        none => { throw from_kind(ErrorKind.InvalidInput) }
                    }
                } else {
                    let back = (-n) as u64
                    if back > self.pos { throw from_kind(ErrorKind.InvalidInput) }
                    next = self.pos - back
                }
            }
        }
        self.pos = next
        next
    }
}
