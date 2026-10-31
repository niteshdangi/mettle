// expect-error: type
// An Rc held across an await makes the future's state non-Transferable.
import std.task
import alloc.rc

async fn hold(): i32 {
    let counted = rc.new(1)
    await task.yield_now()
    *counted.get()
}

fn main(): i32 {
    let ex = task.executor()
    let handle = ex.spawn(hold())
    0
}
