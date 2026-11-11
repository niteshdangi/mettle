// stdin: input\n
import std.io.Error
import std.process.Stdio

fn run(): i32 throws Error {
    var command = std.process.command_text("/bin/echo")
    command.arg_text("x")
    command.stdout(Stdio.Null)
    let output = try command.output()
    if output.stdout.len() != 0usize || !output.status.succeeded() { return 1 }
    let output = try command.output()
    if output.stdout.len() != 0usize { return 2 }
    var defaults = std.process.command_text("/bin/echo")
    defaults.arg_text("y")
    let captured = try defaults.output()
    if captured.stdout.as_slice() != "y\n".as_bytes() { return 3 }
    var input = std.process.command_text("/bin/cat")
    input.stdin(Stdio.Inherit)
    if (try input.output()).stdout.as_slice() != "input\n".as_bytes() { return 4 }
    var errors = std.process.command_text("/bin/sh")
    errors.arg_text("-c")
    errors.arg_text("printf error >&2")
    errors.stderr(Stdio.Null)
    if (try errors.output()).stderr.len() != 0usize { return 5 }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
