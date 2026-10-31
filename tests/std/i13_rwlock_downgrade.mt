import std.sync.rwlock
import std.sync.mutex

fn discard<T>(value: take T): Unit {}

fn main(): i32 {
    let lock = rwlock.new(1)
    let acquired = capture lock.writer()
    let writer = match take acquired { success(g) => g, failure(e) => e.into_inner() }
    var exclusive = writer
    *exclusive.get_mut() = 5
    let reader = exclusive.downgrade()
    if *reader.get() != 5 { return 1 }

    // The downgraded hold is shared: other readers enter, writers do not.
    let second = capture lock.try_reader()
    match take second { success(g) => { if *g.get() != 5 { return 2 } }, failure(_) => { return 3 } }
    let blocked = capture lock.try_writer()
    match take blocked {
        success(_) => { return 4 },
        failure(error) => match error {
            mutex.TryLockError.WouldBlock => {},
            mutex.TryLockError.Poisoned(_) => { return 5 }
        }
    }
    if lock.is_poisoned() { return 6 }

    // Dropping the last downgraded reader releases the lock for writers.
    discard(take reader)
    let again = capture lock.try_writer()
    match take again { success(g) => { if *g.get() != 5 { return 7 } }, failure(_) => { return 8 } }
    0
}
