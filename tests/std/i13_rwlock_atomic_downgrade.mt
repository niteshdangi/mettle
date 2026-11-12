import std.thread
import std.sync.rwlock
import core.sync.atomic.{AtomicBool, Ordering}

fn main(): i32 {
    let sized = rwlock.new([1, 0])
    let lock: read rwlock.RwLock<[i32]> = read sized
    let attempting = AtomicBool.new(false)
    let entered = AtomicBool.new(false)
    let outcome = thread.scope(fn(read scope: thread.Scope): i32 {
        let locked = capture lock.writer()
        var writer = match take locked { success(g) => g, failure(e) => e.into_inner() }
        writer.get_mut()[0usize] = 41
        let child = scope.spawn(fn(): Unit {
            attempting.store(true, Ordering.Release)
            let locked = capture lock.writer()
            var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
            entered.store(true, Ordering.Release)
            guard.get_mut()[0usize] = 42
        })
        while !attempting.load(Ordering.Acquire) { thread.yield_now() }
        let reader = writer.downgrade()
        if reader.get().len() != 2usize || reader.get()[0usize] != 41 ||
           entered.load(Ordering.Acquire) { return 1 }
        core.mem.drop(reader)
        match take capture child.join() {
            success(_) => {},
            failure(_) => { return 2 }
        }
        0
    })
    if outcome != 0 { return outcome }
    let locked = capture lock.reader()
    let reader = match take locked { success(g) => g, failure(e) => e.into_inner() }
    if reader.get()[0usize] != 42 || lock.is_poisoned() { return 3 }
    0
}
