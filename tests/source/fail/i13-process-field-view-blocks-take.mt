// expect-error: ownership 8:5 access or storage lifetime conflicts
import core.option
import std.process.Child

fn conflict(mut child: Child): bool {
    let input = child.stdin.as_view()
    if input.is_none() { return false }
    child.take_stdin()
    input.is_present()
}

fn main(): i32 { 0 }
