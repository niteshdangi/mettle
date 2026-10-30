import std.task
import core.future.Future

async fn borrowed(value: read i32): i32 {
    await task.yield_now();
    value
}

fn main(): i32 {
    let value = 42
    let result = task.scope(fn(s: read task.Scope): i32 {
        let child = s.spawn(borrowed(read value))
        match take capture child.join() {
            success(v) => v,
            failure(error) => -1
        }
    })
    if result != 42 { return 1 }
    0
}
