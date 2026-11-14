// Spawning infers `T` from the callee's `Future<Output = T>` bound, which must
// resolve in std.task even though this module never imports `Future`.
import std.task
import alloc.rc

async fn one(): i32 { 1 }

// An LocalShared whose scope ends before the await is not part of the future's state.
async fn two(): i32 {
    var first = 0
    {
        let counted = rc.new(1)
        first = *counted.get()
    }
    await task.yield_now()
    first + (await one())
}

fn main(): i32 {
    let ex = task.executor()
    let handle = ex.spawn(two())
    ex.run()
    let result = capture handle.join()
    match take result {
        success(value) => if value == 2 { 0 } else { 1 },
        failure(e) => 2,
    }
}
