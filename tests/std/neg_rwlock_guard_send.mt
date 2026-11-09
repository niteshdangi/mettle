// expect-error: type
import std.thread
import std.sync.rwlock

fn main(): i32 {
    let lock = rwlock.new(1)
    let acquired = capture lock.reader()
    let guard = match take acquired {
        success(guard) => guard,
        failure(error) => error.into_inner()
    }
    thread.scope(fn(read scope: thread.Scope): i32 {
        let child = scope.spawn(take fn(): i32 { *guard.get() })
        0
    })
}
