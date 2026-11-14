import std.thread
import std.panic.{catch_panic, CatchResult}
import alloc.arc

type FailingResult {
    release: arc.Shared<core.sync.atomic.AtomicBool>
    drop {
        self.release.get().store(true, core.sync.atomic.Ordering.Release)
        panic("unclaimed scoped result")
    }
}

fn main(): i32 {
    let finished = core.sync.atomic.AtomicBool.new(false)
    let gate = arc.new(core.sync.atomic.AtomicBool.new(false))
    let first_gate = gate.retain()
    let last_gate = gate.retain()
    let caught = catch_panic(fn(): Unit {
        thread.scope(fn(read scope: thread.Scope): Unit {
            let first = scope.spawn(fn(): Unit {
                while !first_gate.get().load(core.sync.atomic.Ordering.Acquire) {
                    thread.yield_now()
                }
                thread.sleep_ms(20u64)
                finished.store(true, core.sync.atomic.Ordering.Release)
            })
            let last = scope.spawn(fn(): FailingResult {
                FailingResult(last_gate.retain())
            })
        })
    })
    let joined = finished.load(core.sync.atomic.Ordering.Acquire)
    // Keep the borrowed storage alive even when the baseline misses the join.
    while !finished.load(core.sync.atomic.Ordering.Acquire) { thread.yield_now() }
    match caught {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    if joined { 0 } else { 2 }
}
