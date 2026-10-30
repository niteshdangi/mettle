// Synchronous byte I/O: `Read`/`Write` expose partial transfers (the count a
// single call moved), the `*_all`/`read_exact`/`read_to_end` helpers loop over
// them, and `Error` keeps the raw OS error number so it round-trips unchanged.
import package::alloc::vec;
import package::alloc::vec::Vec;
import package::core::text::Text;
import package::core::cmp::PartialEq;
import package::core::slice;
import package::core::fmt;
import package::alloc::string::String;
import super::sys;

pub copy enum ErrorKind {
    NotFound, PermissionDenied, ConnectionRefused, ConnectionReset, ConnectionAborted,
    NotConnected, AddrInUse, AddrNotAvailable, BrokenPipe, AlreadyExists, WouldBlock,
    InvalidInput, TimedOut, Interrupted, OutOfMemory, IsADirectory, NotADirectory,
    DirectoryNotEmpty, Other, InvalidData, WriteZero, UnexpectedEof, Unsupported
}

fn kind_from_index(index: i32): ErrorKind {
    match index {
        0 => ErrorKind::NotFound,
        1 => ErrorKind::PermissionDenied,
        2 => ErrorKind::ConnectionRefused,
        3 => ErrorKind::ConnectionReset,
        4 => ErrorKind::ConnectionAborted,
        5 => ErrorKind::NotConnected,
        6 => ErrorKind::AddrInUse,
        7 => ErrorKind::AddrNotAvailable,
        8 => ErrorKind::BrokenPipe,
        9 => ErrorKind::AlreadyExists,
        10 => ErrorKind::WouldBlock,
        11 => ErrorKind::InvalidInput,
        12 => ErrorKind::TimedOut,
        13 => ErrorKind::Interrupted,
        14 => ErrorKind::OutOfMemory,
        15 => ErrorKind::IsADirectory,
        16 => ErrorKind::NotADirectory,
        17 => ErrorKind::DirectoryNotEmpty,
        _ => ErrorKind::Other
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
    let kind = kind_from_index(unsafe { sys::mettle_rt_errno_kind(code) })
    Error(code, true, kind)
}

pub fn last_os_error(): Error { from_raw_os_error(sys::errno()) }

pub fn from_kind(kind: ErrorKind): Error { Error(0, false, kind) }

// An OS error whose portable class is overridden (for example an expired
// socket timeout reported by the OS as "try again"); the raw number is kept.
pub fn with_kind(code: i32, kind: ErrorKind): Error { Error(code, true, kind) }

fn kind_description(kind: ErrorKind): String {
    var s = package::alloc::string::new()
    match kind {
        ErrorKind::InvalidInput => s.push_str("invalid input"),
        ErrorKind::InvalidData => s.push_str("invalid data"),
        ErrorKind::WriteZero => s.push_str("failed to write whole buffer"),
        ErrorKind::UnexpectedEof => s.push_str("unexpected end of file"),
        ErrorKind::TimedOut => s.push_str("timed out"),
        ErrorKind::Unsupported => s.push_str("unsupported"),
        _ => s.push_str("other error")
    }
    s
}

impl ErrorKind {
    pub fn is(other: ErrorKind): bool { (self as i32) == (other as i32) }
}

impl ErrorKind implements PartialEq {
    fn eq(other: read ErrorKind): bool { self.is(other) }
}

impl Error {
    pub fn kind(): ErrorKind { self.kind }
    pub fn raw_os_error(): i32? { if self.os { present(self.code) } else { none } }
    pub fn is_os(): bool { self.os }

    // Human-readable description: the C library message for OS errors.
    pub fn message(): String {
        if self.os {
            let p = unsafe { sys::strerror(self.code) }
            let bytes = unsafe { sys::bytes_from_c(p) }
            let decoded = capture package::alloc::string::from_utf8(bytes)
            match take decoded {
                success(s) => { return s },
                failure(e) => { return package::alloc::string::from_text("unknown error") }
            }
        }
        kind_description(self.kind)
    }
}

// Reads bytes. `read_some` moves at most `buf.len()` bytes and returns how many it
// moved; zero means end of input (or an empty buffer). It may move fewer bytes
// than requested without being at the end.
pub interface Read {
    mut fn read_some(buf: mut [u8]): usize throws Error;

    // Fills `buf` entirely or fails with `UnexpectedEof`.
    mut fn read_exact(buf: mut [u8]): Unit throws Error {
        var done = 0usize
        let total = buf.len()
        while done < total {
            let rest = buf.split_at_mut(done).1
            let n = try self.read_some(rest)
            if n == 0usize { throw from_kind(ErrorKind::UnexpectedEof) }
            done += n
        }
    }

    // Appends everything up to the end of input to `out`; returns the count.
    mut fn read_to_end(out: mut Vec<u8>): usize throws Error {
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
}

// Writes bytes. `write_some` accepts a prefix of `buf` and returns its length,
// which can be shorter than `buf`; `write_all` repeats until everything is
// accepted and fails with `WriteZero` if the sink stops accepting bytes.
pub interface Write {
    mut fn write_some(buf: read [u8]): usize throws Error;
    mut fn flush(): Unit throws Error;

    mut fn write_all(buf: read [u8]): Unit throws Error {
        var done = 0usize
        let total = buf.len()
        while done < total {
            let n = try self.write_some(buf.split_at(done).1)
            if n == 0usize { throw from_kind(ErrorKind::WriteZero) }
            done += n
        }
    }

    // Formatted output: renders `message` through a borrowed sink adapter. The
    // first sink error is returned unchanged; a formatter failure without one
    // is `InvalidData`. Partial output is possible.
    mut fn write(message: format fmt::Message): Unit throws Error {
        try format_to(mut self, message, false)
    }
    mut fn write_line(message: format fmt::Message): Unit throws Error {
        try format_to(mut self, message, true)
    }
}

// Adapts a byte writer to the formatting sink, keeping the first writer error.
type FormatSink<region r, W: Write> { inner: mut W from r; failure: Error? }
impl<region r, W: Write> FormatSink<region r, W> implements fmt::Write {
    mut fn write_str(text: read Text): Unit throws fmt::Error {
        let done = capture self.inner.write_all(text.as_bytes())
        match take done {
            success(_) => {},
            failure(e) => { self.failure = present(e); throw fmt::Error() }
        }
    }
}

fn format_to<W: Write>(writer: mut W, message: format fmt::Message, newline: bool): Unit throws Error {
    var sink = FormatSink(mut writer, none)
    let outcome = capture message.write_to(mut sink)
    match take outcome {
        success(_) => {},
        failure(_) => {
            match sink.failure {
                present(e) => { throw e },
                none => { throw from_kind(ErrorKind::InvalidData) }
            }
        }
    }
    if newline { try sink.inner.write_all("\n".as_bytes()) }
}

fn fd_read(fd: i32, buf: mut [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    while true {
        let n = unsafe { sys::`read`(fd, sys::data_mut(buf), buf.len()) }
        if n >= 0isize { return n as usize }
        let e = last_os_error()
        if !e.kind().is(ErrorKind::Interrupted) { throw e }
    }
    0usize
}

fn fd_write(fd: i32, buf: read [u8]): usize throws Error {
    if buf.len() == 0usize { return 0usize }
    while true {
        let n = unsafe { sys::write(fd, slice::data(buf), buf.len()) }
        if n >= 0isize { return n as usize }
        let e = last_os_error()
        if !e.kind().is(ErrorKind::Interrupted) { throw e }
    }
    0usize
}

pub fn read_fd(fd: i32, buf: mut [u8]): usize throws Error { try fd_read(fd, buf) }
pub fn write_fd(fd: i32, buf: read [u8]): usize throws Error { try fd_write(fd, buf) }

pub copy type Stdin {}
pub copy type Stdout {}
pub copy type Stderr {}
pub fn stdin(): Stdin { Stdin() }
pub fn stdout(): Stdout { Stdout() }
pub fn stderr(): Stderr { Stderr() }

impl Stdin implements Read {
    mut fn read_some(buf: mut [u8]): usize throws Error { try fd_read(0, buf) }
}
impl Stdout implements Write {
    mut fn write_some(buf: read [u8]): usize throws Error { try fd_write(1, buf) }
    mut fn flush(): Unit throws Error {}
}
impl Stderr implements Write {
    mut fn write_some(buf: read [u8]): usize throws Error { try fd_write(2, buf) }
    mut fn flush(): Unit throws Error {}
}

// Writes the formatted message to standard output without a newline. An
// ordinary failure panics. A closed pipe (EPIPE) ends the process quietly with
// status 141 and runs no destructors, like `process::exit`; callers needing
// cleanup use `stdout().write(...)` and handle the error.
pub fn print(message: format fmt::Message): Unit {
    var out = stdout()
    let outcome = capture out.write(message)
    match take outcome {
        success(_) => {},
        failure(e) => {
            if e.kind().is(ErrorKind::BrokenPipe) { unsafe { sys::exit(141) } }
            package::core::panic::panic("failed to write to standard output")
        }
    }
}
// Like `print` for standard error; every failure panics.
pub fn eprint(message: format fmt::Message): Unit {
    var err = stderr()
    let outcome = capture err.write(message)
    match take outcome {
        success(_) => {},
        failure(e) => { package::core::panic::panic("failed to write to standard error") }
    }
}

// Appends the bytes of `src` to a growable buffer: `Vec<u8>` is a sink.
impl Vec<u8> implements Write {
    mut fn write_some(buf: read [u8]): usize throws Error {
        self.extend_from_slice(buf)
        buf.len()
    }
    mut fn flush(): Unit throws Error {}
}

// Reads from an in-memory slice, advancing past what was consumed.
pub type SliceReader<region r> { data: read [u8] from r; pos: usize }
pub fn slice_reader<region r>(data: read [u8] from r): SliceReader<region r> { SliceReader(read data, 0usize) }
impl<region r> SliceReader<region r> implements Read {
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
pub type BufReader<R: Read> {
    inner: R
    buf: Vec<u8>
    pos: usize
    filled: usize
}

pub fn buf_reader<R: Read>(inner: take R): BufReader<R> { buf_reader_with_capacity(8192usize, inner) }

pub fn buf_reader_with_capacity<R: Read>(capacity: usize, inner: take R): BufReader<R> {
    var buf = vec::with_capacity::<u8>(capacity)
    buf.resize(capacity, 0u8)
    BufReader(inner, buf, 0usize, 0usize)
}

impl<R: Read> BufReader<R> {
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

    // Appends bytes up to and including `delimiter` (or the end of input) to
    // `out`; returns how many were appended.
    pub mut fn read_until(delimiter: u8, out: mut Vec<u8>): usize throws Error {
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
    pub mut fn read_line(out: mut Vec<u8>): usize throws Error { try self.read_until(10u8, out) }
}

impl<R: Read> BufReader<R> implements Read {
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
pub type BufWriter<W: Write> {
    inner: W
    buf: Vec<u8>
    capacity: usize
    drop {
        let ignored = capture self.flush_buf()
    }
}

pub fn buf_writer<W: Write>(inner: take W): BufWriter<W> { buf_writer_with_capacity(8192usize, inner) }

pub fn buf_writer_with_capacity<W: Write>(capacity: usize, inner: take W): BufWriter<W> {
    BufWriter(inner, vec::with_capacity::<u8>(capacity), capacity)
}

impl<W: Write> BufWriter<W> {
    mut fn flush_buf(): Unit throws Error {
        if self.buf.len() > 0usize {
            try self.inner.write_all(self.buf.as_slice())
            self.buf.clear()
        }
    }
    pub fn get_ref(): read W from self { read self.inner }
    pub fn buffered(): usize { self.buf.len() }
}

impl<W: Write> BufWriter<W> implements Write {
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
