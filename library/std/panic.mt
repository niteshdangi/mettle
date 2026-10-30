// Hosted panic integration. A panic message reaches the runtime hook
// `mettle_rt_panic_message`, which reports it (stderr by default), unwinds
// with cleanup and ends the process with status 101 (see `runtime/panic.cpp`).
// Recovering from a panic is a separate facility and is not provided here.
extern "C" {
    unsafe fn mettle_rt_set_panic_hook(hook: unsafe extern "C" fn(ptr<read u8>, u64): Unit): Unit;
    unsafe fn mettle_rt_clear_panic_hook(): Unit;
    unsafe fn mettle_rt_panicking(): i32;
}

// Replaces the default report. `hook` receives the message bytes (valid only
// during the call), runs before unwinding, and must not panic itself.
pub fn set_hook(hook: unsafe extern "C" fn(ptr<read u8>, u64): Unit): Unit {
    unsafe { mettle_rt_set_panic_hook(hook) }
}

// Restores the default stderr report.
pub fn reset_hook(): Unit {
    unsafe { mettle_rt_clear_panic_hook() }
}

// True while this thread is unwinding because of a panic.
pub fn panicking(): bool { unsafe { mettle_rt_panicking() } != 0 }
