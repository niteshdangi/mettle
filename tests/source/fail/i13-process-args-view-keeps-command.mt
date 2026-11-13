// expect-error: ownership 9:5 access or storage conflicts
import core.iter.ExactSizeIterator
import std.process.Command

fn main(): i32 {
    var command = Command.new("/bin/true")
    command.arg_text("first")
    let arguments = command.get_args()
    command.arg_text("blocked")
    arguments.len() as i32
}
