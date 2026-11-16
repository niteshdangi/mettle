import std.task
import core.future.Future

async fn borrowed(read value: i32): i32 {
    await task.yield_now();
    value
}

fn main(): i32 {
    let value = 42
    let source = read value
    let token = heap 7
    let result = task.scope(take fn(read s: task.Scope): i32 {
        if token.into_inner() != 7 { return -2 }
        let child = s.spawn(borrowed(source))
        match take capture child.join() {
            success(v) => v,
            failure(error) => -1
        }
    })
    if result != 42 { return 1 }
    0
}
