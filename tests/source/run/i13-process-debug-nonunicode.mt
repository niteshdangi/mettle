// profiles: debug release
import alloc.string.String
import core.fmt
import core.fmt.Debug
import std.ffi
import std.process.Command

fn debug_command(read command: Command): String throws fmt.Error {
    var output = String("")
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        try command.fmt(mut formatter)
    }
    output
}

fn check(): i32 throws fmt.Error {
    let direct = Command.new("direct")
    if !direct.get_program().same(ffi.os_str_from_text("direct")) { return 3 }
    var owned = String("owned")
    let copied = Command.new(read owned)
    owned.clear()
    if !copied.get_program().same(ffi.os_str_from_text("owned")) { return 4 }
    let program = [b'p', 255u8]
    let argument = [b'a', 254u8]
    var command = Command.new(ffi.os_str(read program))
    command.arg(ffi.os_str(read argument))
    command.arg_text("visible")
    let formatted = try debug_command(read command)
    let changed = [b'p', 253u8]
    var other = Command.new(ffi.os_str(read changed))
    other.arg(ffi.os_str(read argument))
    other.arg_text("visible")
    if (try debug_command(read other)).as_text() == formatted.as_text() { return 1 }
    let changed_argument = [b'a', 252u8]
    var other_argument = Command.new(ffi.os_str(read program))
    other_argument.arg(ffi.os_str(read changed_argument))
    other_argument.arg_text("visible")
    if (try debug_command(read other_argument)).as_text() == formatted.as_text() { return 2 }
    0
}

fn main(): i32 {
    match take capture check() {
        success(code) => code,
        failure(_) => 100
    }
}
