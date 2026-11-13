// expect-error: ownership 10:5 access or storage conflicts
import core.iter.ExactSizeIterator
import std.ffi
import std.process.Command

fn main(): i32 {
    var command = Command.new("/bin/true")
    command.env(ffi.os_str_from_text("KEY"), ffi.os_str_from_text("value"))
    let entries = command.get_envs()
    command.env_clear()
    entries.len() as i32
}
