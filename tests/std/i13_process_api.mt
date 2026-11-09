import core.default.Default
import core.fmt.Debug
import core.iter.Iterator
import core.cmp.PartialEq
import core.text.Text
import std.ffi
import std.io.Error
import std.process.{Command, ExitStatus, Output, Stdio}

fn debug<T: Debug>(read value: T): Unit {}

fn run(): i32 throws Error {
    let status = ExitStatus.(Default).default()
    if !status.succeeded() || status != ExitStatus.(Default).default() { return 1 }
    debug(read status)
    debug(Stdio.inherit())

    var command = Command.new(ffi.os_str_from_text("/bin/cat"))
    let arguments = [
        ffi.os_string_from_text("first"),
        ffi.os_string_from_text("second")
    ]
    command.args(read arguments)
    command.env(ffi.os_str_from_text("MT_I13"), ffi.os_str_from_text("value"))
    let environment = [(
        ffi.os_string_from_text("MT_I13_SECOND"),
        ffi.os_string_from_text("other")
    )]
    command.envs(read environment)
    let program = match command.get_program().to_str() {
        present(value) => value,
        none => { return 2 }
    }
    if program != "/bin/cat" { return 3 }

    var args = command.get_args()
    match args.next() {
        present(value) => match value.to_str() {
            present(text) => { if text != "first" { return 4 } },
            none => { return 5 }
        },
        none => { return 6 }
    }
    var envs = command.get_envs()
    match envs.next() {
        present((name, value)) => {
            if !text_is(name.to_str(), "MT_I13") || !text_is(value.to_str(), "value") {
                return 7
            }
        },
        none => { return 8 }
    }
    if command.get_current_dir().is_present() { return 9 }
    command.current_dir(std.path.path_from_text("."))
    if command.get_current_dir().is_none() { return 10 }
    debug(read command)

    command.stdin(Stdio.Piped)
    command.stdout(Stdio.Piped)
    command.stderr(Stdio.Piped)
    var child = try command.spawn()
    debug(read child)
    if child.stdin().is_none() { return 11 }
    if child.stdout().is_none() || child.stderr().is_none() { return 12 }
    let output = try child.wait_with_output()
    debug(read output)
    let empty = Output(status, alloc.vec.new<u8>(), alloc.vec.new<u8>())
    if empty != Output(status, alloc.vec.new<u8>(), alloc.vec.new<u8>()) { return 13 }
    var empty_environment = Command.new(ffi.os_str_from_text("/usr/bin/env"))
    empty_environment.env(ffi.os_str_from_text("MT_I13"), ffi.os_str_from_text("value"))
    empty_environment.env_clear()
    let cleared_output = try empty_environment.output()
    if !cleared_output.status.succeeded() ||
       cleared_output.stdout.len() != 0usize ||
       cleared_output.stderr.len() != 0usize {
        return 14
    }
    var waiting = Command.new(ffi.os_str_from_text("/bin/cat"))
    waiting.stdin(Stdio.Piped)
    var blocked_child = try waiting.spawn()
    let _held_input = match take blocked_child.stdin() {
        present(input) => input,
        none => { return 15 }
    }
    if (try blocked_child.try_wait()).is_present() { return 16 }
    try blocked_child.kill()
    let killed = try blocked_child.wait()
    if killed.signal() != present(9i32) { return 17 }
    0
}

fn text_is<region r>(value: (read Text from r)?, read expected: Text): bool {
    match value { present(text) => text == expected, none => false }
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(error) => 100
    }
}
