// expect-error: ownership 10:18 access or storage conflicts
import std.sync.rwlock

fn main(): i32 {
    let lock = rwlock.new(1)
    let locked = capture lock.writer()
    let writer = match take locked { success(g) => g, failure(e) => e.into_inner() }
    let value = writer.get()
    let _before = *value
    let reader = writer.downgrade()
    *value
}
