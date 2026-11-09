import alloc.string.String
import alloc.vec
import core.error.{Error as CoreError}
import core.fmt
import core.text.Text
import std.io.{Error, ErrorKind, Reader, Writer}

fn render<T: fmt.Debug>(read value: T): String throws Error {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(fmt.Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { throw std.io.from_kind(ErrorKind.Other) }
        }
    }
    output
}

fn require_error<E: CoreError>(read error: E): Unit {}
fn require_reader<T: Reader>(mut value: T): Unit {}
fn require_writer<T: Writer>(mut value: T): Unit {}

fn run(): i32 throws Error {
    let error = std.io.from_kind(ErrorKind.InvalidInput)
    require_error(read error)
    if !(try render(read error)).as_text().starts_with("Error") { return 1 }
    if !(try render(read Error.last_os_error())).as_text().starts_with("Error") {
        return 8
    }
    if !(try render(ErrorKind.InvalidInput)).as_text().starts_with("InvalidInput") {
        return 2
    }
    if !(try render(std.io.stdin())).as_text().starts_with("Stdin") { return 3 }
    if !(try render(std.io.stdout())).as_text().starts_with("Stdout") { return 4 }
    if !(try render(std.io.stderr())).as_text().starts_with("Stderr") { return 5 }
    var input = std.io.stdin()
    var output = std.io.stdout()
    var error_output = std.io.stderr()
    require_reader(mut input)
    require_writer(mut output)
    require_writer(mut error_output)

    var reader = std.io.buf_reader_with_capacity(
        4usize,
        std.io.slice_reader("buffered".as_bytes())
    )
    if !(try render(read reader)).as_text().starts_with("BufferedReader") { return 6 }
    var writer = std.io.buf_writer_with_capacity(4usize, vec.new<u8>())
    if !(try render(read writer)).as_text().starts_with("BufferedWriter") { return 7 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(_) => 100
    }
}
