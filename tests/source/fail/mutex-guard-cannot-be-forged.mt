// expect-error: name 5:18 private or restricted field 'lock' is inaccessible
import std.sync.mutex
fn main(): i32 {
    let lock = mutex.new(0)
    let forged = mutex.MutexGuard(read lock)
    *forged.get()
}
