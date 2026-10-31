import super.mutex.MutexGuard
import package.core.panic.panic
import package.core.default.Default
import package.core.fmt
import package.std.time

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
unsafe extend Condvar implements Transferable {}
unsafe extend Condvar implements Shareable {}

pub fn new(): Condvar {
    let raw = unsafe { mettle_rt_cond_new() }
    if raw == core.ptr.null_mut<u8>() { core.intrinsics.abort() }
    Condvar(raw)
}
extend Condvar implements Default {
    static fn default(): Condvar { new() }
}
extend Condvar implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try f.write_str("Condvar { .. }") }
}

// Whether a timed wait ended by its deadline.
pub copy type TimedOut { expired: bool }
extend TimedOut {
    pub fn timed_out(): bool { self.expired }
}

extend Condvar {
    pub fn wait<T, region r>(guard: take MutexGuard<T, region r>): MutexGuard<T, region r> {
        let status = unsafe { mettle_rt_cond_wait(self.raw, guard.lock.raw) }
        if status != 0 { panic("condition wait failed") }
        guard
    }
    pub fn wait_timeout<T, region r>(guard: take MutexGuard<T, region r>, nanoseconds: u64): (MutexGuard<T, region r>, TimedOut) {
        let status = unsafe { mettle_rt_cond_wait_timeout(self.raw, guard.lock.raw, nanoseconds) }
        if status < 0 { panic("timed condition wait failed") }
        (guard, TimedOut(status == 1))
    }
    pub fn wait_while<T, region r, F: mut fn(mut T): bool>(
        guard: take MutexGuard<T, region r>,
        predicate: mut F
    ): MutexGuard<T, region r> {
        var current = guard
        while predicate(current.get_mut()) {
            current = self.wait(current)
        }
        current
    }
    pub fn wait_timeout_while<T, region r, F: mut fn(mut T): bool>(
        guard: take MutexGuard<T, region r>,
        nanoseconds: u64,
        predicate: mut F
    ): (MutexGuard<T, region r>, TimedOut) {
        let start = time.now()
        var current = guard
        while predicate(current.get_mut()) {
            let elapsed = time.now().duration_since(start).as_nanos()
            if elapsed >= nanoseconds as u128 {
                return (current, TimedOut(true))
            }
            let remaining = nanoseconds - elapsed as u64
            let waited = self.wait_timeout(current, remaining)
            current = waited.0
            // The predicate decides success after reacquisition; a native
            // timeout alone does not mean the condition is still pending.
        }
        (current, TimedOut(false))
    }
    pub fn wait_timeout_ms<T, region r>(
        guard: take MutexGuard<T, region r>,
        milliseconds: u64
    ): (MutexGuard<T, region r>, TimedOut) {
        let nanos = milliseconds.saturating_mul(1000000u64)
        self.wait_timeout(guard, nanos)
    }
    pub fn notify_one(): Unit {
        if unsafe { mettle_rt_cond_notify_one(self.raw) } != 0 {
            panic("condition notification failed")
        }
    }
    pub fn notify_all(): Unit {
        if unsafe { mettle_rt_cond_notify_all(self.raw) } != 0 {
            panic("condition notification failed")
        }
    }
}
