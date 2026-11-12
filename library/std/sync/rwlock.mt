import package.core.panic.panic
import package.core.convert.From
import package.core.default.Default
import package.core.borrow.Borrow
import package.core.fmt.{Debug, Display, Error, Formatter}
import package.core.ops.{Deref, DerefMut}
import super.mutex.{PoisonError, TryLockError}

extern "C" {
    unsafe fn mettle_rt_panicking(): i32;
    unsafe fn mettle_rt_rwlock_new(): ptr<mut u8>;
    unsafe fn mettle_rt_rwlock_free(lock: ptr<mut u8>): Unit;
    unsafe fn mettle_rt_rwlock_read(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_try_read(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_write(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_try_write(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_downgrade(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_unlock(lock: ptr<mut u8>): i32;
}

// Many readers or one writer. Readers share `T`, so sharing the lock needs
// `T` to be Shareable as well as Transferable.
pub type RwLock<T: unsized> {
    raw: ptr<mut u8>
    poisoned: core.sync.atomic.AtomicBool
    value: core.cell.Cell<T>
    drop { unsafe { mettle_rt_rwlock_free(self.raw) } }
}
unsafe extend<T: Transferable + unsized> RwLock<T> implements Transferable {}
unsafe extend<T: Transferable + Shareable + unsized> RwLock<T> implements Shareable {}

pub type ReadGuard<T: unsized, region r> {
    lock: read RwLock<T> from r
    drop { let _status = unsafe { mettle_rt_rwlock_unlock(self.lock.raw) } }
}
pub type WriteGuard<T: unsized, region r> {
    lock: read RwLock<T> from r
    panicking: bool
    drop {
        unsafe {
            if !self.panicking && mettle_rt_panicking() != 0 {
                self.lock.poisoned.store(true, core.sync.atomic.Ordering.Release)
            }
            let _status = mettle_rt_rwlock_unlock(self.lock.raw)
        }
    }
}
extend<T: unsized, region r> ReadGuard<T, region r> not Transferable
extend<T: unsized, region r> WriteGuard<T, region r> not Transferable

pub fn new<T>(take value: T): RwLock<T> {
    let raw = unsafe { mettle_rt_rwlock_new() }
    if raw == core.ptr.null_mut<u8>() { core.intrinsics.abort() }
    RwLock(raw, core.sync.atomic.AtomicBool.new(false), core.cell.Cell.new(value))
}
extend<T> RwLock<T> implements From<T> {
    static fn from(take value: T): RwLock<T> { new(value) }
}
extend<T: Default> RwLock<T> implements Default {
    static fn default(): RwLock<T> { new(T.(Default).default()) }
}

extend<T: unsized> RwLock<T> {
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
        let guard = WriteGuard(read self, unsafe { mettle_rt_panicking() != 0 })
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
        let guard = WriteGuard(read self, unsafe { mettle_rt_panicking() != 0 })
        if self.poisoned.load(core.sync.atomic.Ordering.Acquire) {
            throw TryLockError.Poisoned(guard)
        }
        guard
    }
    pub fn is_poisoned(): bool { self.poisoned.load(core.sync.atomic.Ordering.Acquire) }
    pub fn get_mut<region r>(
        receiver mut self: RwLock<T> from r
    ): mut T from r throws PoisonError<mut T from r> {
        let value = unsafe { mut *self.value.as_ptr() }
        if self.poisoned.load(core.sync.atomic.Ordering.Acquire) {
            throw PoisonError(value)
        }
        value
    }
    pub fn clear_poison(): Unit {
        self.poisoned.store(false, core.sync.atomic.Ordering.Release)
    }
}

extend<T> RwLock<T> {
    pub take fn into_inner(): T throws PoisonError<T> {
        let raw = self.raw
        let poisoned = self.poisoned.load(core.sync.atomic.Ordering.Acquire)
        let value = unsafe { core.ptr.`read`(self.value.as_ptr()) }
        core.mem.forget(take self)
        unsafe { mettle_rt_rwlock_free(raw) }
        if poisoned { throw PoisonError(value) }
        value
    }
}
extend<T: unsized, region r> ReadGuard<T, region r> {
    pub fn get(): read T from self { unsafe { read *self.lock.value.as_ptr() } }
}
extend<T: unsized, region r> ReadGuard<T, region r> implements Borrow<T> {
    fn borrow(): read T from self { self.get() }
}
extend<T: unsized, region r> ReadGuard<T, region r> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T: unsized, region r> WriteGuard<T, region r> {
    pub take fn downgrade(): ReadGuard<T, region r> {
        if unsafe { mettle_rt_rwlock_downgrade(self.lock.raw) } != 0 {
            panic("rwlock downgrade failed")
        }
        let lock = self.lock
        core.mem.forget(take self)
        ReadGuard(lock)
    }

    pub fn get(): read T from self { unsafe { read *self.lock.value.as_ptr() } }
    pub mut fn get_mut(): mut T from self { unsafe { mut *self.lock.value.as_ptr() } }
}
extend<T: unsized, region r> WriteGuard<T, region r> implements Borrow<T> {
    fn borrow(): read T from self { self.get() }
}
extend<T: unsized, region r> WriteGuard<T, region r> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T: unsized, region r> WriteGuard<T, region r> implements DerefMut {
    mut fn deref_mut(): mut T from self { self.get_mut() }
}

extend<T: Debug + unsized> RwLock<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        // A successful try-read acquires the normal read edge; guard drop
        // releases it even when formatting propagates a writer error.
        var poisoned = self.is_poisoned()
        var debug = try f.debug_struct("RwLock")
        match take capture self.try_reader() {
            success(guard) => {
                poisoned = self.is_poisoned()
                try debug.field("data", guard.get());
            },
            failure(error) => match take error {
                TryLockError.WouldBlock => { try debug.field("data", "<locked>"); },
                TryLockError.Poisoned(guard) => {
                    poisoned = true
                    try debug.field("data", guard.get());
                }
            }
        }
        try debug.field("poisoned", read poisoned)
        try debug.finish()
    }
}
extend<T: Debug + unsized, region r> ReadGuard<T, region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try T.(Debug).fmt(self.get(), mut f)
    }
}
extend<T: Display + unsized, region r> ReadGuard<T, region r> implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        try T.(Display).fmt(self.get(), mut f)
    }
}
extend<T: Debug + unsized, region r> WriteGuard<T, region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try T.(Debug).fmt(self.get(), mut f)
    }
}
extend<T: Display + unsized, region r> WriteGuard<T, region r> implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        try T.(Display).fmt(self.get(), mut f)
    }
}
