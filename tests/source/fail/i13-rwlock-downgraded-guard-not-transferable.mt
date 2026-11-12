// expect-error: type 10:5 unsatisfied interface bound 'Transferable'
import std.sync.rwlock

fn send<T: Transferable>(take value: T): Unit {}
fn main(): i32 {
    let lock = rwlock.new(1)
    let locked = capture lock.writer()
    let writer = match take locked { success(g) => g, failure(e) => e.into_inner() }
    let reader = writer.downgrade()
    send(reader)
    0
}
