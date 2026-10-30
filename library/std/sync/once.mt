// Runs an initialiser exactly once. If it panics the cell is re-armed, so a
// later caller retries; callers that lose the race wait for completion.
type Arm<region r> {
    state: read core::sync::atomic::AtomicU32 from r
    drop {
        let finished = if unsafe { mettle_rt_panicking() } != 0 { 0u32 } else { 2u32 }
        self.state.store(finished, core::sync::atomic::Ordering::Release)
    }
}

extern "C" {
    unsafe fn mettle_rt_panicking(): i32;
    unsafe fn mettle_rt_thread_yield(): Unit;
}

pub type Once {
    state: core::sync::atomic::AtomicU32
}
unsafe impl Once implements Transferable {}
unsafe impl Once implements Shareable {}

pub fn new(): Once { Once(core::sync::atomic::AtomicU32::new(0u32)) }

impl Once {
    pub fn is_completed(): bool { self.state.load(core::sync::atomic::Ordering::Acquire) == 2u32 }
    pub fn call_once<F: fn(): Unit>(f: take F): Unit {
        var done = false
        while !done {
            let seen = self.state.compare_exchange(0u32, 1u32, core::sync::atomic::Ordering::AcqRel, core::sync::atomic::Ordering::Acquire)
            if seen.is_failure() {
                if self.is_completed() { done = true } else { unsafe { mettle_rt_thread_yield() } }
            } else {
                let arm = Arm(read self.state)
                f()
                done = true
            }
        }
    }
}
