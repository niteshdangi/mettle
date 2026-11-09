import std.task

async fn borrowed(read value: i32): i32 {
    await task.yield_now();
    value
}

fn main(): i32 {
    let value = 42
    var scope = task.async_scope(read value)
    var child = scope.spawn(borrowed(read value))
    task.block_on(take scope)
    match take child.take_result() {
        present(result) => if result == 42 { 0 } else { 1 },
        none => 2
    }
}
