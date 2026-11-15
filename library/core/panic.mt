// Source-level panic: an unwind failure with a message, routed through the
// compiler-owned hook `core.intrinsics.panic_message`. Hosted code may recover
// it with `std.panic.catch_panic`; an uncaught panic exits with status 101.
// Freestanding execution has no unwind runtime and aborts (trap).
import super.text.Text
import super.fmt
import super.fmt.{Message, Write, Error}
import super.cmp.{ Ordering, PartialEq, Eq, PartialOrd, Ord }
import super.hash.{ Hash, Hasher }

pub import core.marker.{RefUnwindSafe, UnwindSafe}

type PanicSink {
    context: ptr<mut u8>
    write: unsafe extern "C" fn(ptr<mut u8>, ptr<read u8>, u64): Unit
}

extend PanicSink implements Write {
    mut fn write_str(read text: Text): Unit throws Error {
        let bytes = text.as_bytes()
        unsafe {
            (self.write)(self.context, core.slice.data(bytes),
                         bytes.len() as u64)
        }
    }
}

unsafe extern "C" fn render_panic<region r>(
    context: ptr<mut u8>,
    write: unsafe extern "C" fn(ptr<mut u8>, ptr<read u8>, u64): Unit,
    sink_context: ptr<mut u8>
): Unit {
    let message = unsafe { read *context.cast<Message<region r>>() }
    var sink = PanicSink(sink_context, write)
    match capture message.write_to(mut sink) {
        success(_) => {},
        failure(_) => core.intrinsics.abort()
    }
}

@track_caller
pub fn panic_fmt<region r>(message: format Message<region r>): Never {
    unsafe {
        core.intrinsics.panic_fmt(message, render_panic<region r>)
    }
}

pub copy type Location<region r> {
    file: read [u8] from r
    line: u64
    column: u64
}

extend<region r> Location<region r> {
    pub static fn from_parts<region s>(
        read file: [u8] from s,
        line: u64,
        column: u64
    ): Location<region s> {
        Location<region s>(read file, line, column)
    }

    pub fn file_bytes(): read [u8] from self { self.file }

    pub fn file(): Outcome<
        read Text from self, super.text.Utf8Error
    > {
        super.text.from_utf8(self.file_bytes())
    }

    pub fn line(): u64 { self.line }
    pub fn column(): u64 { self.column }
}

extend Location<region static> {
    @track_caller
    pub static fn caller(): Location<region static> {
        core.intrinsics.caller_location<Location<region static>>()
    }
}

extend<region r> Location<region r> implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        match self.file() {
            success(file) => try f.write_str(file),
            failure(_) => try f.write_str("<non-UTF-8 path>")
        }
        try f.write_str(":")
        try u64.(fmt.Display).fmt(self.line, mut f)
        try f.write_str(":")
        try u64.(fmt.Display).fmt(self.column, mut f)
    }
}

extend<region r> Location<region r> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var structure = try f.debug_struct("Location")
        let _ = try structure.field("file_bytes", self.file_bytes())
        let _ = try structure.field("line", self.line)
        let _ = try structure.field("column", self.column)
        try take structure.finish()
    }
}

extend<region r> Location<region r> implements super.clone.Clone {
    fn clone(): Location<region r> { self }
}

extend<region r, region s> Location<region r> implements PartialEq<Location<region s>> {
    fn eq(read other: Location<region s>): bool {
        self.file_bytes() == other.file_bytes() &&
            self.line == other.line && self.column == other.column
    }
}
extend<region r> Location<region r> implements Eq {}

extend<region r, region s> Location<region r> implements PartialOrd<Location<region s>> {
    fn partial_cmp(read other: Location<region s>): Ordering? {
        let by_file = self.file_bytes().cmp(other.file_bytes())
        let by_line = by_file.then(self.line.cmp(other.line))
        present(by_line.then(self.column.cmp(other.column)))
    }
}
extend<region r> Location<region r> implements Ord {
    fn cmp(read other: Location<region r>): Ordering {
        let by_file = self.file_bytes().cmp(other.file_bytes())
        let by_line = by_file.then(self.line.cmp(other.line))
        by_line.then(self.column.cmp(other.column))
    }
}

extend<region r> Location<region r> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.file_bytes().hash(mut state)
        self.line.hash(mut state)
        self.column.hash(mut state)
    }
}

@track_caller
pub fn panic(read message: Text): Never {
    core.intrinsics.panic_message(message.as_bytes())
}

@track_caller
pub fn assert(condition: bool, read message: Text) {
    if !condition { panic(message) }
}

@track_caller
pub fn unreachable(): Never { panic("entered unreachable code") }
