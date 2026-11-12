import alloc.string.{String, ToString}
import core.cmp.PartialEq
import core.convert.From
import core.fmt.Debug
import std.fs.File
import std.io.Error
import std.process.Stdio

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
    if render(Stdio.Inherit).as_text() != "Inherit" { return 1 }
    if render(Stdio.Piped).as_text() != "Piped" { return 2 }
    if render(Stdio.Null).as_text() != "Null" { return 3 }
    if render(Stdio.StandardOutput).as_text() != "StandardOutput" { return 4 }
    if render(Stdio.StandardError).as_text() != "StandardError" { return 5 }

    let file = try File.open("/dev/null")
    let raw_fd = file.as_raw_fd()
    let descriptor = Stdio.(From<File>).from(file)
    var expected = String("Descriptor(")
    expected.push_str(raw_fd.to_string().as_text())
    expected.push(')')
    if render(read descriptor).as_text() != expected.as_text() { return 6 }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
