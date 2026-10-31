import package.core.panic.panic
import package.core.default.Default
import package.core.convert.From
import package.core.ops.{Deref, DerefMut}
import package.core.fmt
import super.mutex.{PoisonError, TryLockError}

extern "C" {
    unsafe fn mettle_rt_panicking(): i32;
    unsafe fn mettle_rt_rwlock_new(): ptr<mut u8>;
    unsafe fn mettle_rt_rwlock_free(lock: ptr<mut u8>): Unit;
    unsafe fn mettle_rt_rwlock_read(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_try_read(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_write(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_try_write(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_unlock(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_downgrade(lock: ptr<mut u8>): i32;
}

// Many readers or one writer. Readers share `T`, so sharing the lock needs
// `T` to be Shareable as well as Transferable.
pub type RwLock<T> {
    raw: ptr<mut u8>
    poisoned: core.sync.atomic.AtomicBool
    value: core.cell.UnsafeCell<T>
    drop { unsafe { mettle_rt_rwlock_free(self.raw) } }
}
unsafe extend<T: Transferable> RwLock<T> implements Transferable {}
unsafe extend<T: Transferable + Shareable> RwLock<T> implements Shareable {}

pub type ReadGuard<T, region r> {
    lock: read RwLock<T> from r
    drop { let _status = unsafe { mettle_rt_rwlock_unlock(self.lock.raw) } }
}
pub type WriteGuard<T, region r> {
    lock: read RwLock<T> from r
    drop {
        unsafe {
            if mettle_rt_panicking() != 0 {
                self.lock.poisoned.store(true, core.sync.atomic.Ordering.Release)
            }
            let _status = mettle_rt_rwlock_unlock(self.lock.raw)
        }
    }
}
extend<T, region r> ReadGuard<T, region r> not Transferable
extend<T, region r> WriteGuard<T, region r> not Transferable
unsafe extend<T: Shareable, region r> ReadGuard<T, region r> implements Shareable {}
unsafe extend<T: Shareable, region r> WriteGuard<T, region r> implements Shareable {}

pub fn new<T>(value: take T): RwLock<T> {
    let raw = unsafe { mettle_rt_rwlock_new() }
    if raw == core.ptr.null_mut<u8>() { core.intrinsics.abort() }
    RwLock(raw, core.sync.atomic.AtomicBool.new(false), core.cell.UnsafeCell.new(value))
}
extend<T: Default> RwLock<T> implements Default {
    static fn default(): RwLock<T> { new(T.(Default).default()) }
}
extend<T> RwLock<T> implements From<T> {
    static fn `from`(value: take T): RwLock<T> { new(value) }
}
extend<T: fmt.Debug> RwLock<T> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        let acquired = capture self.try_reader()
        var fields = try f.debug_struct("RwLock")
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

extend<T> RwLock<T> {
    pub fn `read`(): ReadGuard<T, region self> throws PoisonError<ReadGuard<T, region self>> {
        try self.reader()
    }

    pub fn write(): WriteGuard<T, region self> throws PoisonError<WriteGuard<T, region self>> {
        try self.writer()
    }

    pub fn try_read(): ReadGuard<T, region self> throws TryLockError<ReadGuard<T, region self>> {
        try self.try_reader()
    }

    pub fn try_write(): WriteGuard<T, region self> throws TryLockError<WriteGuard<T, region self>> {
        try self.try_writer()
    }

    pub fn reader(): ReadGuard<T, region self> throws PoisonError<ReadGuard<T, region self>> {
        if unsafe { mettle_rt_rwlock_read(self.raw) } != 0 { panic("rwlock read lock failed") }
        let guard = ReadGuard(read self)
        if self.poisoned.load(core.sync.atomic.Ordering.Acquire) { throw PoisonError(guard) }
        guard
    }
    pub fn writer(): WriteGuard<T, region self> throws PoisonError<WriteGuard<T, region self>> {
        if unsafe { mettle_rt_rwlock_write(self.raw) } != 0 { panic("rwlock write lock failed") }
        let guard = WriteGuard(read self)
        if self.poisoned.load(core.sync.atomic.Ordering.Acquire) { throw PoisonError(guard) }
        guard
    }
    pub fn try_reader(): ReadGuard<T, region self> throws TryLockError<ReadGuard<T, region self>> {
        let status = unsafe { mettle_rt_rwlock_try_read(self.raw) }
        if status == 1 { throw TryLockError.WouldBlock }
        if status != 0 { panic("rwlock try_read failed") }
        let guard = ReadGuard(read self)
        if self.poisoned.load(core.sync.atomic.Ordering.Acquire) {
            throw TryLockError.Poisoned(guard)
        }
        guard
    }
    pub fn try_writer(): WriteGuard<T, region self> throws TryLockError<WriteGuard<T, region self>> {
        let status = unsafe { mettle_rt_rwlock_try_write(self.raw) }
        if status == 1 { throw TryLockError.WouldBlock }
        if status != 0 { panic("rwlock try_write failed") }
        let guard = WriteGuard(read self)
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
        unsafe { mettle_rt_rwlock_free(raw) }
        if poisoned { throw PoisonError(value) }
        value
    }
}
extend<T, region r> ReadGuard<T, region r> {
    pub fn get(): read T from self { unsafe { read *self.lock.value.get() } }
}
extend<T, region r> WriteGuard<T, region r> {
    pub fn get(): read T from self { unsafe { read *self.lock.value.get() } }
    pub mut fn get_mut(): mut T from self { unsafe { mut *self.lock.value.get() } }

    // Converts exclusive access into shared access in one runtime step, so no
    // other writer can be admitted in between. The write guard's drop (and its
    // panic poisoning) is skipped: the hold now belongs to the returned guard.
    pub take fn downgrade(): ReadGuard<T, region r> {
        let lock = self.lock
        if unsafe { mettle_rt_rwlock_downgrade(lock.raw) } != 0 {
            panic("rwlock downgrade without exclusive hold")
        }
        core.mem.forget(take self)
        ReadGuard(lock)
    }
}
extend<T, region r> ReadGuard<T, region r> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T, region r> WriteGuard<T, region r> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T, region r> WriteGuard<T, region r> implements DerefMut {
    type Target = T
    mut fn deref_mut(): mut T from self { self.get_mut() }
}
extend<T: fmt.Debug, region r> ReadGuard<T, region r> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.get(), mut f)
    }
}
extend<T: fmt.Display, region r> ReadGuard<T, region r> implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Display).fmt(self.get(), mut f)
    }
}
extend<T: fmt.Debug, region r> WriteGuard<T, region r> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.get(), mut f)
    }
}
extend<T: fmt.Display, region r> WriteGuard<T, region r> implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Display).fmt(self.get(), mut f)
    }
}
