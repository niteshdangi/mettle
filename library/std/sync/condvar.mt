import super.mutex
import super.mutex.{MutexGuard, PoisonError}
import package.core.panic.panic
import package.core.default.Default
import package.core.fmt.{Debug, Error, Formatter}
import package.std.time

extern "C" {
    unsafe fn mettle_rt_cond_new(): ptr<mut u8>;
    unsafe fn mettle_rt_cond_free(cond: ptr<mut u8>): Unit;
    unsafe fn mettle_rt_cond_wait(cond: ptr<mut u8>, mutex: ptr<mut u8>): i32;
    unsafe fn mettle_rt_cond_wait_timeout(cond: ptr<mut u8>, mutex: ptr<mut u8>, nanoseconds: u64): i32;
    unsafe fn mettle_rt_cond_notify_one(cond: ptr<mut u8>): i32;
    unsafe fn mettle_rt_cond_notify_all(cond: ptr<mut u8>): i32;
}

type Binding { mutex: ptr<mut u8>; waiters: usize }
type WaitBinding<region r> {
    binding: read mutex.Mutex<Binding> from r
    drop {
        let locked = capture self.binding.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        guard.get_mut().waiters -= 1usize
    }
}

// Waits release and reacquire their mutex; callbacks must recheck after spurious wakeups.
pub type Condvar {
    raw: ptr<mut u8>
    binding: mutex.Mutex<Binding>
    drop { unsafe { mettle_rt_cond_free(self.raw) } }
}
unsafe extend Condvar implements Transferable {}
unsafe extend Condvar implements Shareable {}

pub fn new(): Condvar {
    let raw = unsafe { mettle_rt_cond_new() }
    if raw == core.ptr.null_mut<u8>() { core.intrinsics.abort() }
    Condvar(raw, mutex.new(Binding(core.ptr.null_mut<u8>(), 0usize)))
}
extend Condvar implements Default {
    static fn default(): Condvar { new() }
}
extend Condvar implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("Condvar { .. }")
    }
}

// Whether a timed wait ended by its deadline.
pub copy type TimedOut { expired: bool }
extend TimedOut {
    pub fn timed_out(): bool { self.expired }
}

extend Condvar {
    fn bind(raw: ptr<mut u8>): WaitBinding<region self> {
        // A live waiter owns a mutex guard, so this native mutex cannot be recycled.
        let locked = capture self.binding.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if guard.get().waiters != 0usize && guard.get().mutex != raw {
            panic("condition variable used with unrelated mutexes")
        }
        let next = match guard.get().waiters.checked_add(1usize) {
            present(next) => next,
            none => core.intrinsics.abort()
        }
        guard.get_mut().mutex = raw
        guard.get_mut().waiters = next
        WaitBinding(read self.binding)
    }

    pub fn wait<T, region r>(
        take guard: MutexGuard<T, region r>
    ): MutexGuard<T, region r> throws PoisonError<MutexGuard<T, region r>> {
        let _binding = self.bind(guard.lock.raw)
        let status = unsafe { mettle_rt_cond_wait(self.raw, guard.lock.raw) }
        if status != 0 { panic("condition wait failed") }
        if guard.is_poisoned() { throw PoisonError(guard) }
        guard
    }
    pub fn wait_timeout<T, region r>(
        take guard: MutexGuard<T, region r>,
        duration: time.Duration
    ): (MutexGuard<T, region r>, TimedOut) throws PoisonError<(MutexGuard<T, region r>, TimedOut)> {
        let _binding = self.bind(guard.lock.raw)
        let started = time.now()
        let timeout = duration.as_nanos()
        while true {
            let elapsed = time.now().duration_since(started).as_nanos()
            let remaining = if elapsed >= timeout { 0u128 } else { timeout - elapsed }
            let chunk = if remaining > 18446744073709551615u128 {
                18446744073709551615u64
            } else {
                remaining as u64
            }
            let status = unsafe {
                mettle_rt_cond_wait_timeout(self.raw, guard.lock.raw, chunk)
            }
            if status < 0 { panic("timed condition wait failed") }
            if status == 0 {
                if guard.is_poisoned() { throw PoisonError((guard, TimedOut(false))) }
                return (guard, TimedOut(false))
            }
            let elapsed = time.now().duration_since(started).as_nanos()
            if guard.is_poisoned() { throw PoisonError((guard, TimedOut(elapsed >= timeout))) }
            if elapsed >= timeout { return (guard, TimedOut(true)) }
        }
    }
    pub fn wait_while<T, region r, F: mut fn(mut T): bool>(
        take guard: MutexGuard<T, region r>,
        take predicate: F
    ): MutexGuard<T, region r> throws PoisonError<MutexGuard<T, region r>> {
        var current = guard
        var test = predicate
        while test(current.get_mut()) {
            current = try self.wait(current)
        }
        current
    }
    pub fn wait_timeout_while<T, region r, F: mut fn(mut T): bool>(
        take guard: MutexGuard<T, region r>,
        duration: time.Duration,
        take predicate: F
    ): (MutexGuard<T, region r>, TimedOut) throws PoisonError<(MutexGuard<T, region r>, TimedOut)> {
        let start = time.now()
        var current = guard
        var test = predicate
        var first_wait = true
        while test(current.get_mut()) {
            let elapsed = time.now().duration_since(start)
            if !first_wait && elapsed >= duration {
                return (current, TimedOut(true))
            }
            let remaining = match duration.checked_sub(elapsed) {
                present(value) => value,
                none => time.from_nanos(0u64)
            }
            let waited = try self.wait_timeout(current, remaining)
            current = waited.0
            first_wait = false
        }
        (current, TimedOut(false))
    }
    pub fn wait_timeout_ms<T, region r>(
        take guard: MutexGuard<T, region r>,
        milliseconds: u64
    ): (MutexGuard<T, region r>, TimedOut) throws PoisonError<(MutexGuard<T, region r>, TimedOut)> {
        try self.wait_timeout(guard, time.from_millis(milliseconds))
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
