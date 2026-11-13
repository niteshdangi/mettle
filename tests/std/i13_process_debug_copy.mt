import alloc.string.{String, ToString}
import core.fmt.Debug
import std.ffi
import std.io.Error
import std.process.{Command, ExitStatus}

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
    let status = ExitStatus.(core.default.Default).default()
    let twin = status
    if status != twin || render(status).as_text() != "ExitStatus { raw: 0 }" { return 1 }

    var command = Command.new(ffi.os_str_from_text("/bin/echo"))
    command.args([ffi.os_string_from_text("hi")])
    if render(command).as_text() != "Command { program: \"/bin/echo\", args: [\"hi\"] }" { return 2 }

    var child = try command.spawn()
    if !render(child).as_text().starts_with("Child { id: ") { return 3 }
    let waited = try child.wait()
    if !waited.succeeded() { return 4 }

    let output = try command.output()
    if render(output).as_text() != "Output { status: ExitStatus { raw: 0 }, stdout: [104, 105, 10], stderr: [] }" {
        return 5
    }
    0
}

fn main(): i32 {
    match capture run() {
        success(code) => code,
        failure(error) => 99
    }
}
