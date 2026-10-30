import super::mutex::MutexGuard;

extern "C" {
    unsafe fn mettle_rt_cond_new(): ptr<mut u8>;
    unsafe fn mettle_rt_cond_free(cond: ptr<mut u8>): Unit;
    unsafe fn mettle_rt_cond_wait(cond: ptr<mut u8>, mutex: ptr<mut u8>): i32;
    unsafe fn mettle_rt_cond_wait_timeout(cond: ptr<mut u8>, mutex: ptr<mut u8>, nanoseconds: u64): i32;
    unsafe fn mettle_rt_cond_notify_one(cond: ptr<mut u8>): i32;
    unsafe fn mettle_rt_cond_notify_all(cond: ptr<mut u8>): i32;
}

// Waits release the guard's mutex while blocked and reacquire it before
// returning, so wakeups may be spurious: callers re-check their predicate.
pub type Condvar {
    raw: ptr<mut u8>
    drop { unsafe { mettle_rt_cond_free(self.raw) } }
}
unsafe impl Condvar implements Transferable {}
unsafe impl Condvar implements Shareable {}

pub fn new(): Condvar {
    let raw = unsafe { mettle_rt_cond_new() }
    if raw == core::ptr::null_mut::<u8>() { core::intrinsics::abort() }
    Condvar(raw)
}

// Whether a timed wait ended by its deadline.
pub copy type TimedOut { pub timed_out: bool }

impl Condvar {
    pub fn wait<T, region r>(guard: take MutexGuard<T, region r>): MutexGuard<T, region r> {
        let _status = unsafe { mettle_rt_cond_wait(self.raw, guard.lock.raw) }
        guard
    }
    pub fn wait_timeout<T, region r>(guard: take MutexGuard<T, region r>, nanoseconds: u64): (MutexGuard<T, region r>, TimedOut) {
        let status = unsafe { mettle_rt_cond_wait_timeout(self.raw, guard.lock.raw, nanoseconds) }
        (guard, TimedOut(status == 1))
    }
    pub fn notify_one(): Unit { let _status = unsafe { mettle_rt_cond_notify_one(self.raw) } }
    pub fn notify_all(): Unit { let _status = unsafe { mettle_rt_cond_notify_all(self.raw) } }
}
