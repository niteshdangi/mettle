// expect-stdout: borrowed children: 42, 7\n
import std.task

async fn borrowed(value: read i32): i32 {
    await task.yield_now();
    value
}

fn main(): i32 {
    let anchor = 42
    let other = 7
    var scope = task.async_scope(read anchor)
    var first = scope.spawn(borrowed(read anchor))
    var second = scope.spawn(borrowed(read other))

    task.block_on(scope)

    let a = first.take_result().unwrap()
    let b = second.take_result().unwrap()
    if a != 42 || b != 7 { return 1 }
    std.io.print("borrowed children: ok\n")
    0
}
