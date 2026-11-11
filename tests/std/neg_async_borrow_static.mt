// expect-error: region 9:18 borrowed source does not outlive the required region
// A future capturing a borrow of a local is not Static.
import std.task

fn main(): i32 {
    let value = 5
    let view = read value
    let ex = task.executor()
    let handle = ex.spawn(async { let r = view; *r })
    0
}
