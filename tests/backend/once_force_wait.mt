import std.sync.once
import std.thread
import std.panic.{catch_panic, CatchResult}
import alloc.arc

extern "C" {
    unsafe fn mettle_once_wait_begin(): Unit;
    unsafe fn mettle_once_wait_end(): Unit;
    unsafe fn mettle_once_wait_phase(): i32;
    unsafe fn mettle_once_wait_release(phase: i32): Unit;
}

fn main(): i32 {
    let gate = arc.new(once.new())
    let caught = catch_panic(fn(): Unit {
        gate.get().call_once(fn(): Unit { panic("initialization") })
    })
    match caught { CatchResult.Panicked(_) => {}, _ => { return 2 } }
    let initialized = arc.new(core.sync.atomic.AtomicBool.new(false))
    let worker_gate = gate.retain()
    let worker_initialized = initialized.retain()
    let worker = thread.spawn(take fn(): i32 {
        unsafe { mettle_once_wait_begin() }
        worker_gate.get().wait_force()
        let published = worker_initialized.get().load(core.sync.atomic.Ordering.Acquire)
        unsafe { mettle_once_wait_end() }
        if published { 0 } else { 3 }
    })
    while unsafe { mettle_once_wait_phase() } == 0i32 { thread.yield_now() }
    if unsafe { mettle_once_wait_phase() } != 1i32 || gate.get().is_completed() {
        return 5
    }
    gate.get().call_once_force(fn(state: once.OnceState): Unit {
        if !state.is_poisoned() { panic("poison lost") }
        unsafe { mettle_once_wait_release(1i32) }
        while unsafe { mettle_once_wait_phase() } == 1i32 { thread.yield_now() }
        if unsafe { mettle_once_wait_phase() } != 2i32 {
            panic("waiter did not block during recovery")
        }
        initialized.get().store(true, core.sync.atomic.Ordering.Release)
    })
    unsafe { mettle_once_wait_release(2i32) }
    match take capture worker.join() { success(code) => code, failure(_) => 4 }
}
