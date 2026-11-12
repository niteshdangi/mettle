import std.sync.once
import std.thread
import std.panic.{catch_panic, CatchResult}
import alloc.arc

fn main(): i32 {
    let gate = arc.new(once.new())
    let caught = catch_panic(fn(): Unit {
        gate.get().call_once(fn(): Unit { panic("initialization") })
    })
    match caught { CatchResult.Panicked(_) => {}, _ => { return 2 } }
    let entered = arc.new(core.sync.atomic.AtomicBool.new(false))
    let initialized = arc.new(core.sync.atomic.AtomicBool.new(false))
    let worker_gate = gate.retain()
    let worker_entered = entered.retain()
    let worker_initialized = initialized.retain()
    let worker = thread.spawn(take fn(): i32 {
        worker_entered.get().store(true, core.sync.atomic.Ordering.Release)
        worker_gate.get().wait_force()
        if worker_initialized.get().load(core.sync.atomic.Ordering.Acquire) { 0 } else { 3 }
    })
    while !entered.get().load(core.sync.atomic.Ordering.Acquire) { thread.yield_now() }
    gate.get().call_once_force(fn(state: once.OnceState): Unit {
        if !state.is_poisoned() { panic("poison lost") }
        initialized.get().store(true, core.sync.atomic.Ordering.Release)
    })
    match take capture worker.join() { success(code) => code, failure(_) => 4 }
}
