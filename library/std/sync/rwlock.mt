import package.core.panic.panic

extern "C" {
    unsafe fn mettle_rt_rwlock_new(): ptr<mut u8>;
    unsafe fn mettle_rt_rwlock_free(lock: ptr<mut u8>): Unit;
    unsafe fn mettle_rt_rwlock_read(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_try_read(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_write(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_try_write(lock: ptr<mut u8>): i32;
    unsafe fn mettle_rt_rwlock_unlock(lock: ptr<mut u8>): i32;
}

pub copy type WouldBlock {}

// Many readers or one writer. Readers share `T`, so sharing the lock needs
// `T` to be Shareable as well as Transferable.
pub type RwLock<T> {
    raw: ptr<mut u8>
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
    drop { let _status = unsafe { mettle_rt_rwlock_unlock(self.lock.raw) } }
}
extend<T, region r> ReadGuard<T, region r> not Transferable
extend<T, region r> WriteGuard<T, region r> not Transferable

pub fn new<T>(value: take T): RwLock<T> {
    let raw = unsafe { mettle_rt_rwlock_new() }
    if raw == core.ptr.null_mut<u8>() { core.intrinsics.abort() }
    RwLock(raw, core.cell.UnsafeCell.new(value))
}

extend<T> RwLock<T> {
    pub fn reader(): ReadGuard<T, region self> {
        if unsafe { mettle_rt_rwlock_read(self.raw) } != 0 { panic("rwlock read lock failed") }
        ReadGuard(read self)
    }
    pub fn writer(): WriteGuard<T, region self> {
        if unsafe { mettle_rt_rwlock_write(self.raw) } != 0 { panic("rwlock write lock failed") }
        WriteGuard(read self)
    }
    pub fn try_reader(): ReadGuard<T, region self> throws WouldBlock {
        if unsafe { mettle_rt_rwlock_try_read(self.raw) } != 0 { throw WouldBlock() }
        ReadGuard(read self)
    }
    pub fn try_writer(): WriteGuard<T, region self> throws WouldBlock {
        if unsafe { mettle_rt_rwlock_try_write(self.raw) } != 0 { throw WouldBlock() }
        WriteGuard(read self)
    }
}
extend<T, region r> ReadGuard<T, region r> {
    pub fn get(): read T from self { unsafe { read *self.lock.value.get() } }
}
extend<T, region r> WriteGuard<T, region r> {
    pub fn get(): read T from self { unsafe { read *self.lock.value.get() } }
    pub mut fn get_mut(): mut T from self { unsafe { mut *self.lock.value.get() } }
}
