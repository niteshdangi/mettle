import std.sync.{mutex, condition}
import std.thread
import std.panic.{catch_panic, CatchResult}
import alloc.arc

fn main(): i32 {
    let lock = arc.new(mutex.new(false))
    let changed = arc.new(condition.new())
    let entered = arc.new(core.sync.atomic.AtomicBool.new(false))
    let worker_lock = lock.retain()
    let worker_changed = changed.retain()
    let worker_entered = entered.retain()
    let worker = thread.spawn(take fn(): i32 {
        let guard = match take capture worker_lock.get().lock() {
            success(guard) => guard,
            failure(error) => error.into_inner()
        }
        worker_entered.get().store(true, core.sync.atomic.Ordering.Release)
        match take capture worker_changed.get().wait_while(guard, fn(mut ready: bool): bool { !ready }) {
            success(_) => 1,
            failure(error) => {
                let guard = error.into_inner()
                if !*guard.get() { return 2 }
                match take capture worker_changed.get().wait_timeout(guard, std.time.from_nanos(0u64)) {
                    success(_) => 5,
                    failure(error) => {
                        let pair = error.into_inner()
                        if *pair.0.get() { 0 } else { 6 }
                    }
                }
            }
        }
    })
    while !entered.get().load(core.sync.atomic.Ordering.Acquire) { thread.yield_now() }
    let caught = catch_panic(fn(): Unit {
        var guard = match take capture lock.get().lock() {
            success(guard) => guard,
            failure(error) => error.into_inner()
        }
        *guard.get_mut() = true
        changed.get().notify_one()
        panic("poison after waking")
    })
    match caught { CatchResult.Panicked(_) => {}, _ => { return 3 } }
    match take capture worker.join() { success(code) => code, failure(_) => 4 }
}
