import std.thread
import std.panic.{catch_panic, CatchResult}

fn main(): i32 {
    let rejected = catch_panic(fn(): Unit {
        var builder = thread.Builder.new()
        builder.name("left\u{0}right")
        match take capture builder.spawn(fn(): Unit {}) {
            success(handle) => { let _result = capture handle.join() },
            failure(_) => { core.intrinsics.abort() }
        }
    })
    match rejected { CatchResult.Panicked(_) => 0, CatchResult.Returned(_) => 1 }
}
