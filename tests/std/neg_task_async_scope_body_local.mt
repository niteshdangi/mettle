// expect-error: region
import std.task

async fn borrowed(value: read i32): i32 { value }

fn main(): i32 {
    let anchor = 0
    var scope = task.async_scope(read anchor)
    {
        let inner = 3
        let _child = scope.spawn(borrowed(read inner))
    }
    task.block_on(scope)
    0
}
