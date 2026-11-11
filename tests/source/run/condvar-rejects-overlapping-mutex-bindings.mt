import std.sync.{mutex, condvar}
import std.thread
import std.time
import std.panic.{catch_panic, CatchResult}
import alloc.arc

fn main(): i32 {
    let lock = arc.new(mutex.new(false))
    let changed = arc.new(condvar.new())
    let entered = arc.new(core.sync.atomic.AtomicBool.new(false))
    let worker_lock = lock.retain()
    let worker_changed = changed.retain()
    let worker_entered = entered.retain()
    let worker = thread.spawn(take fn(): i32 {
        let locked = capture worker_lock.get().lock()
        let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        worker_entered.get().store(true, core.sync.atomic.Ordering.Release)
        let waited = capture worker_changed.get().wait_while(guard, fn(mut ready: bool): bool { !ready })
        let guard = match take waited { success(g) => g, failure(e) => e.into_inner() }
        if *guard.get() { 0 } else { 1 }
    })
    while !entered.get().load(core.sync.atomic.Ordering.Acquire) { thread.yield_now() }
    let locked = capture lock.get().lock()
    var held = match take locked { success(g) => g, failure(e) => e.into_inner() }
    let other = mutex.new(0)
    let rejected = catch_panic(fn(): Unit {
        let locked = capture other.lock()
        let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        let _waited = capture changed.get().wait_timeout(guard, time.from_nanos(0u64))
    })
    *held.get_mut() = true
    changed.get().notify_all()
    core.mem.drop(held)
    match take capture worker.join() { success(0) => {}, _ => { return 2 } }
    match rejected { CatchResult.Panicked(_) => {}, _ => { return 3 } }
    let next = mutex.new(1)
    let locked = capture next.lock()
    let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    let waited = capture changed.get().wait_timeout(guard, time.from_nanos(0u64))
    match take waited {
        success(pair) => { if !pair.1.timed_out() { return 4 } },
        failure(_) => { return 5 }
    }
    0
}
