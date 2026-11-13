import alloc.string.String
import core.cmp.{Ordering, PartialOrd}
import core.fmt.Debug
import std.fs
import std.io.{BufRead, Cursor, Error, ErrorKind}

fn render<T: Debug>(read value: T): String {
    var output = alloc.string.new()
    {
        var formatter = core.fmt.formatter(mut output, core.fmt.spec())
        match capture T.(Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { panic("Debug formatting failed") }
        }
    }
    output
}

fn run(): i32 throws Error {
    if ErrorKind.NotFound.partial_cmp(read ErrorKind.PermissionDenied) != present(Ordering.Less) { return 1 }
    if !(ErrorKind.TimedOut > ErrorKind.NotFound) { return 2 }

    let kind = try fs.metadata("/").file_type()
    let twin = kind
    if !kind.is_dir() || kind != twin { return 3 }

    let lines = Cursor.new([97u8, 10u8]).lines()
    if !render(lines).as_text().starts_with("Lines") { return 4 }
    0
}

fn main(): i32 {
    match capture run() {
        success(code) => code,
        failure(error) => 99
    }
}
