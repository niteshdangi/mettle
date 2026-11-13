// expect-error: ownership 8:5 access or storage conflicts
import core.option
import std.process.Child

fn conflict(mut child: Child): bool {
    let input = child.stdin.as_ref()
    if input.is_none() { return false }
    child.take_stdin()
    input.is_present()
}

fn main(): i32 { 0 }
