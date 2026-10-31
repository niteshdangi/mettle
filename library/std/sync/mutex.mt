import package.core.panic.panic
import package.core.default.Default
import package.core.convert.From
import package.core.ops.{Deref, DerefMut}
import package.core.fmt
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
    pub static fn new(guard: take G): PoisonError<G> { PoisonError(guard) }
    pub fn get_ref(): read G from self { read self.guard }
    pub mut fn get_mut(): mut G from self { mut self.guard }
    pub take fn into_inner(): G { self.guard }
}

extend<G> PoisonError<G> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try f.write_str("PoisonError { .. }") }
}
extend<G> PoisonError<G> implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("poisoned lock: another task failed inside")
    }
}
extend<G> PoisonError<G> implements core.error.Error {}

pub enum TryLockError<G> { WouldBlock; Poisoned(G) }
extend<G> TryLockError<G> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        match self {
            TryLockError.WouldBlock => { try f.write_str("WouldBlock") },
            TryLockError.Poisoned(_) => { try f.write_str("Poisoned(..)") }
        }
    }
}
extend<G> TryLockError<G> implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        match self {
            TryLockError.WouldBlock => {
                try f.write_str("try_lock failed because the operation would block")
            },
            TryLockError.Poisoned(_) => {
                try f.write_str("poisoned lock: another task failed inside")
            }
        }
    }
}
extend<G> TryLockError<G> implements core.error.Error {}

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
extend<T: Default> Mutex<T> implements Default {
    static fn default(): Mutex<T> { new(T.(Default).default()) }
}
extend<T> Mutex<T> implements From<T> {
    static fn `from`(value: take T): Mutex<T> { new(value) }
}
extend<T: fmt.Debug> Mutex<T> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        // Formatting must not wait for a lock held by the current thread.
        let acquired = capture self.try_lock()
        var fields = try f.debug_struct("Mutex")
        match take acquired {
            success(guard) => { try fields.field("data", guard.get()) },
            failure(error) => match take error {
                TryLockError.Poisoned(guard) => { try fields.field("data", guard.get()) },
                TryLockError.WouldBlock => { try fields.field("data", "<locked>") }
            }
        }
        try fields.field("poisoned", self.is_poisoned())
        try fields.finish()
    }
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
    pub fn try_lock(): MutexGuard<T, region self> throws TryLockError<MutexGuard<T, region self>> {
        let status = unsafe { mettle_rt_mutex_try_lock(self.raw) }
        if status == 1 { throw TryLockError.WouldBlock }
        if status != 0 { panic("mutex try_lock failed") }
        let guard = MutexGuard(read self)
        if self.poisoned.load(core.sync.atomic.Ordering.Acquire) {
            throw TryLockError.Poisoned(guard)
        }
        guard
    }
    pub fn is_poisoned(): bool { self.poisoned.load(core.sync.atomic.Ordering.Acquire) }
    pub mut fn get_mut(): mut T from self throws PoisonError<mut T from self> {
        let poisoned = self.poisoned.load(core.sync.atomic.Ordering.Acquire)
        let value = unsafe { mut *self.value.get() }
        if poisoned { throw PoisonError(value) }
        value
    }
    pub fn clear_poison(): Unit {
        self.poisoned.store(false, core.sync.atomic.Ordering.Release)
    }

    pub take fn into_inner(): T throws PoisonError<T> {
        let raw = self.raw
        let poisoned = self.poisoned.load(core.sync.atomic.Ordering.Acquire)
        let value = unsafe { core.ptr.`read`(self.value.get()) }
        core.mem.forget(take self)
        unsafe { mettle_rt_mutex_free(raw) }
        if poisoned { throw PoisonError(value) }
        value
    }
}
extend<T, region r> MutexGuard<T, region r> {
    pub fn get(): read T from self { unsafe { read *self.lock.value.get() } }
    pub mut fn get_mut(): mut T from self { unsafe { mut *self.lock.value.get() } }
}
extend<T, region r> MutexGuard<T, region r> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T, region r> MutexGuard<T, region r> implements DerefMut {
    type Target = T
    mut fn deref_mut(): mut T from self { self.get_mut() }
}
extend<T: fmt.Debug, region r> MutexGuard<T, region r> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.get(), mut f)
    }
}
extend<T: fmt.Display, region r> MutexGuard<T, region r> implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Display).fmt(self.get(), mut f)
    }
}
