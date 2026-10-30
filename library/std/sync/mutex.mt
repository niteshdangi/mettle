import package.core.panic.panic
extern "C" {
    unsafe fn mettle_rt_mutex_new(): ptr<mut u8>;
    unsafe fn mettle_rt_mutex_free(mutex: ptr<mut u8>): Unit;
    unsafe fn mettle_rt_mutex_lock(mutex: ptr<mut u8>): i32;
    unsafe fn mettle_rt_mutex_try_lock(mutex: ptr<mut u8>): i32;
    unsafe fn mettle_rt_mutex_unlock(mutex: ptr<mut u8>): i32;
    unsafe fn mettle_rt_panicking(): i32;
}

// A lock released while its holder was unwinding; the guard is still usable.
pub type PoisonError<G> { pub guard: G }
extend<G> PoisonError<G> {
    pub take fn into_inner(): G { self.guard }
}

pub copy type WouldBlock {}

// Mutual exclusion around `value`. Only one guard exists at a time, so `T`
// needs to be Transferable (the lock moves it between threads) but not
// Shareable.
pub type Mutex<T> {
    pub raw: ptr<mut u8>
    poisoned: core.sync.atomic.AtomicBool
    value: core.cell.UnsafeCell<T>
    drop { unsafe { mettle_rt_mutex_free(self.raw) } }
}

unsafe extend<T: Transferable> Mutex<T> implements Transferable {}
unsafe extend<T: Transferable> Mutex<T> implements Shareable {}

// Holds the lock until dropped. A guard stays on its acquiring thread.
pub type MutexGuard<T, region r> {
    pub lock: read Mutex<T> from r
    drop {
        unsafe {
            if mettle_rt_panicking() != 0 {
                self.lock.poisoned.store(true, core.sync.atomic.Ordering.Release)
            }
            let _status = mettle_rt_mutex_unlock(self.lock.raw)
        }
    }
}
extend<T, region r> MutexGuard<T, region r> not Transferable
unsafe extend<T: Shareable, region r> MutexGuard<T, region r> implements Shareable {}

pub fn new<T>(value: take T): Mutex<T> {
    let raw = unsafe { mettle_rt_mutex_new() }
    if raw == core.ptr.null_mut<u8>() { core.intrinsics.abort() }
    Mutex(raw, core.sync.atomic.AtomicBool.new(false), core.cell.UnsafeCell.new(value))
}

extend<T> Mutex<T> {
    // Blocks until the lock is held. Relocking on the owning thread is
    // reported by the error-checking mutex and panics instead of deadlocking.
    pub fn lock(): MutexGuard<T, region self> throws PoisonError<MutexGuard<T, region self>> {
        let status = unsafe { mettle_rt_mutex_lock(self.raw) }
        if status != 0 { panic("mutex lock failed (relock on the owning thread?)") }
        let guard = MutexGuard(read self)
        if self.poisoned.load(core.sync.atomic.Ordering.Acquire) { throw PoisonError(guard) }
        guard
    }
    pub fn try_lock(): MutexGuard<T, region self> throws WouldBlock {
        let status = unsafe { mettle_rt_mutex_try_lock(self.raw) }
        if status != 0 { throw WouldBlock() }
        MutexGuard(read self)
    }
    pub fn is_poisoned(): bool { self.poisoned.load(core.sync.atomic.Ordering.Acquire) }
}
extend<T, region r> MutexGuard<T, region r> {
    pub fn get(): read T from self { unsafe { read *self.lock.value.get() } }
    pub mut fn get_mut(): mut T from self { unsafe { mut *self.lock.value.get() } }
}
