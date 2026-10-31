// expect-error: type
// A future capturing a borrow of a local is not Static.
import std.task

fn main(): i32 {
    let value = 5
    let view = read value
    let ex = task.executor()
    let handle = ex.spawn(async { let r = view; *r })
    0
}
