import core.error.{Error as CoreError}
import core.convert.From
import core.fmt
import std.io.{Error, ErrorKind}
import alloc.string.String
import std.io.Writer
import std.sync.mutex.TryLockError

type TestError { value: i32 }
extend TestError implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("payload ")
        try i32.(fmt.Display).fmt(self.value, mut f)
    }
}
extend TestError implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("TestError")
        try debug.field("value", self.value)
        try debug.finish()
    }
}
extend TestError implements CoreError {}

type FailingWriter {}
extend FailingWriter implements Writer {
    mut fn write_some(read buf: [u8]): usize throws Error {
        throw std.io.from_kind(ErrorKind.BrokenPipe)
    }
    mut fn flush(): Unit throws Error {
        throw std.io.from_kind(ErrorKind.BrokenPipe)
    }
}

fn render<T: unsized + fmt.Display>(read value: T): String throws Error {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(fmt.Display).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { throw std.io.from_kind(ErrorKind.Other) }
        }
    }
    output
}

fn run(): i32 throws Error {
    var error = Error.new(ErrorKind.Other, TestError(42i32))
    if !error.get_ref().is_present() || !error.get_mut().is_present() { return 1 }
    if !error.message().as_text().starts_with("payload 42") { return 2 }
    if !(try render(read error)).as_text().starts_with("payload 42") { return 3 }

    match take error.downcast<TestError>() {
        success(payload) => {
            if payload.get().value != 42i32 { return 4 }
        },
        failure(_) => { return 5 }
    }

    let other = Error.other(TestError(17i32))
    if other.kind() != ErrorKind.Other { return 6 }
    match take other.downcast<TryLockError<i32>>() {
        success(_) => { return 7 },
        failure(error) => {
            if !error.get_ref().is_present() { return 8 }
        }
    }

    let kind_error = Error.(From<ErrorKind>).from(ErrorKind.InvalidInput)
    if kind_error.kind() != ErrorKind.InvalidInput ||
        kind_error.get_ref().is_present() {
        return 9
    }

    let lock_error = TryLockError.WouldBlock
    let converted_lock_error =
        Error.(From<TryLockError<i32>>).from(lock_error)
    if converted_lock_error.kind() != ErrorKind.Other { return 23 }
    match take converted_lock_error.downcast<TryLockError<i32>>() {
        success(payload) => {
            match payload.get() {
                TryLockError.WouldBlock => {},
                _ => { return 24 }
            }
        },
        _ => { return 24 }
    }

    let owned_error = Error.new(ErrorKind.Other, TestError(9i32))
    match take owned_error.into_inner() {
        present(payload) => {
            if !(try render(payload.get())).as_text().starts_with("payload 9") {
                return 10
            }
        },
        none => { return 11 }
    }

    var writer = std.io.buf_writer_with_capacity(4usize, FailingWriter())
    try writer.write_all("x".as_bytes())
    let into_inner = capture writer.into_inner()
    let converted = match take into_inner {
        success(_) => { return 12 },
        failure(error) => Error.(From<std.io.IntoInnerError<FailingWriter>>).from(error)
    }
    if converted.kind() != ErrorKind.BrokenPipe { return 13 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(_) => 100
    }
}
