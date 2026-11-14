import std.thread
import alloc.boxed

fn main(): i32 {
    var index = 0
    while index < 32 {
        let captured = index
        let owned = boxed.new(captured)
        var builder = thread.Builder.new()
        builder.name("owned-output")
        let handle = match take capture builder.spawn(take fn(): boxed.Heap<i32> { owned }) {
            success(handle) => handle,
            failure(_) => { return 2 }
        }
        match take capture handle.join() {
            success(value) => { if *value.get() != index { return 3 } },
            failure(_) => { return 4 }
        }
        index += 1
    }
    0
}
