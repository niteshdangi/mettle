import core.panic.panic
import core.outcome
import core.clone.Clone
import core.default.Default
import core.cmp.{Eq, PartialEq}
import core.fmt.{Debug, Display, Error as FmtError, Formatter}

extern "C" {
    unsafe fn mettle_rt_tls_key_new(destructor: extern "C" fn(ptr<mut u8>): Unit): usize;
    unsafe fn mettle_rt_tls_key_free(key: usize): Unit;
    unsafe fn mettle_rt_tls_static_key_new(
        identity: ptr<read u8>,
        destructor: extern "C" fn(ptr<mut u8>): Unit
    ): usize;
    unsafe fn mettle_rt_tls_get(key: usize): ptr<mut u8>;
    unsafe fn mettle_rt_tls_set(key: usize, value: ptr<mut u8>): i32;
    unsafe fn mettle_rt_tls_is_destroying(key: usize): i32;
    unsafe fn mettle_rt_thread_yield(): Unit;
}

pub copy type AccessError {}
extend AccessError implements Clone { fn clone(): AccessError { AccessError() } }
extend AccessError implements PartialEq { fn eq(read other: AccessError): bool { true } }
extend AccessError implements Eq {}
extend AccessError implements Debug {
    fn fmt(mut f: Formatter): Unit throws FmtError { try f.write_str("AccessError") }
}
extend AccessError implements Display {
    fn fmt(mut f: Formatter): Unit throws FmtError {
        try f.write_str("cannot access a thread-local value during or after destruction")
    }
}
extend AccessError implements core.error.Error {}

// A static declaration keeps only its initializer. The runtime keys this
// descriptor by its static address, avoiding generic const-function evaluation.
pub type LocalKey<T> {
    pub initialize: fn(): T
}
// The descriptor contains only immutable code; TLS values stay on their
// owning threads, and its methods require the descriptor's static address.
unsafe extend<T> LocalKey<T> implements Transferable {}
unsafe extend<T> LocalKey<T> implements Shareable {}
extend<T> LocalKey<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws FmtError {
        try f.write_str("LocalKey { .. }")
    }
}

pub type OwnedLocalKey<T> {
    key: core.sync.atomic.AtomicUsize
    initialize: (fn(): T)?
    owned: bool
    drop {
        if self.owned {
            let state = self.key.load(core.sync.atomic.Ordering.Acquire)
            if state > 1usize { unsafe { mettle_rt_tls_key_free(state - 1usize) } }
        }
    }
}
unsafe extend<T> OwnedLocalKey<T> implements Transferable {}
unsafe extend<T> OwnedLocalKey<T> implements Shareable {}

// Only the owning thread accesses this count; a callback loan forbids replacement.
type Value<T> { borrows: usize; mutable: bool; value: T }
type ValueBorrow<T> {
    raw: ptr<mut Value<T>>
    drop { unsafe { (*self.raw).borrows -= 1usize } }
}
type ValueBorrowMut<T> {
    raw: ptr<mut Value<T>>
    drop { unsafe { (*self.raw).mutable = false } }
}

fn borrow_value<T>(raw: ptr<mut u8>): ValueBorrow<T> {
    let value = raw.cast<Value<T>>()
    unsafe {
        if (*value).mutable { panic("cannot immutably borrow a mutably borrowed thread-local value") }
        (*value).borrows = match (*value).borrows.checked_add(1usize) {
            present(next) => next,
            none => core.intrinsics.abort()
        }
    }
    ValueBorrow(value)
}

fn borrow_value_mut<T>(raw: ptr<mut u8>): ValueBorrowMut<T> {
    let value = raw.cast<Value<T>>()
    unsafe {
        if (*value).mutable || (*value).borrows != 0usize {
            panic("cannot mutably borrow an already borrowed thread-local value")
        }
        (*value).mutable = true
    }
    ValueBorrowMut(value)
}

fn check_replace<T>(raw: ptr<mut u8>): Unit {
    if raw != core.ptr.null_mut<u8>() && unsafe {
        let value = raw.cast<Value<T>>()
        (*value).borrows != 0usize || (*value).mutable
    } {
        panic("cannot replace a borrowed thread-local value")
    }
}

fn is_destroying(key: usize): bool {
    unsafe { mettle_rt_tls_is_destroying(key) != 0 }
}

fn panic_if_destroying(key: usize): Unit {
    if is_destroying(key) {
        panic("cannot access a thread-local value during or after destruction")
    }
}

fn drop_value<T>(raw: ptr<mut u8>): Unit {
    let _owned = unsafe { alloc.boxed.from_raw_in(raw.cast<Value<T>>(), alloc.alloc.Global()) }
}

pub fn new<T>(): OwnedLocalKey<T> {
    let destructor = unsafe { core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(drop_value<T>) }
    let key = unsafe { mettle_rt_tls_key_new(destructor) }
    if key == 0usize { panic("out of thread-local keys") }
    OwnedLocalKey(core.sync.atomic.AtomicUsize.new(key + 1usize), none, true)
}

extend<T> LocalKey<T> {
    fn key(receiver read self: LocalKey<T> from static): usize {
        let identity = core.ptr.from_ref(self).cast<u8>()
        let destructor = unsafe { core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(drop_value<T>) }
        let key = unsafe { mettle_rt_tls_static_key_new(identity, destructor) }
        if key == 0usize { panic("out of thread-local keys") }
        key
    }

    fn value(receiver read self: LocalKey<T> from static): ptr<mut u8> {
        let key = self.key()
        panic_if_destroying(key)
        var raw = unsafe { mettle_rt_tls_get(key) }
        if raw == core.ptr.null_mut<u8>() {
            let initialize = self.initialize
            let value = alloc.boxed.new(Value(0usize, false, initialize())).into_raw().0
            raw = value.cast<u8>()
            if unsafe { mettle_rt_tls_set(key, raw) } != 0 {
                let _owned = unsafe { alloc.boxed.from_raw_in(value, alloc.alloc.Global()) }
                panic("failed to set thread-local value")
            }
        }
        raw
    }

    pub fn set(receiver read self: LocalKey<T> from static, take value: T): Unit {
        let key = self.key()
        panic_if_destroying(key)
        let old = unsafe { mettle_rt_tls_get(key) }
        check_replace<T>(old)
        let raw = alloc.boxed.new(Value(0usize, false, value)).into_raw().0.cast<u8>()
        unsafe {
            if mettle_rt_tls_set(key, raw) != 0 {
                let _owned = alloc.boxed.from_raw_in(raw.cast<Value<T>>(), alloc.alloc.Global())
                panic("failed to set thread-local value")
            }
            if old != core.ptr.null_mut<u8>() { drop_value<T>(old) }
        }
    }

    pub fn is_set(receiver read self: LocalKey<T> from static): bool {
        unsafe { mettle_rt_tls_get(self.key()) != core.ptr.null_mut<u8>() }
    }

    pub fn with<R, F: take fn(read T): R>(
        receiver read self: LocalKey<T> from static,
        take f: F
    ): R {
        self.with_borrow(take f)
    }

    pub fn try_with<R, F: take fn(read T): R>(
        receiver read self: LocalKey<T> from static,
        take f: F
    ): Outcome<R, AccessError> {
        let key = self.key()
        if is_destroying(key) { return failure(AccessError()) }
        let borrowed = borrow_value<T>(self.value())
        success(unsafe { f(read (*borrowed.raw).value) })
    }

    pub fn with_borrow<R, F: take fn(read T): R>(
        receiver read self: LocalKey<T> from static,
        take f: F
    ): R {
        match take self.try_with(take f) {
            success(value) => value,
            failure(_) => panic("cannot access a thread-local value during or after destruction")
        }
    }

    pub fn with_borrow_mut<R, F: take fn(mut T): R>(
        receiver read self: LocalKey<T> from static,
        take f: F
    ): R {
        let borrowed = borrow_value_mut<T>(self.value())
        unsafe { f(mut (*borrowed.raw).value) }
    }
}

extend<T: Copy> LocalKey<T> {
    pub fn get(receiver read self: LocalKey<T> from static): T {
        self.with_borrow(fn(read value: T): T { value })
    }

    pub fn update<F: take fn(T): T>(
        receiver read self: LocalKey<T> from static,
        take f: F
    ): Unit {
        self.with_borrow_mut(take fn(mut value: T): Unit { value = f(value) })
    }
}

extend<T> LocalKey<T> {
    pub fn replace(receiver read self: LocalKey<T> from static, take value: T): T {
        self.with_borrow_mut(take fn(mut current: T): T {
            core.mem.replace(mut current, value)
        })
    }
}

extend<T: Default> LocalKey<T> {
    pub fn `take`(receiver read self: LocalKey<T> from static): T {
        self.replace(T.(Default).default())
    }
}

extend<T> OwnedLocalKey<T> {
    fn key(): usize {
        while true {
            let state = self.key.load(core.sync.atomic.Ordering.Acquire)
            if state > 1usize { return state - 1usize }
            if state == 0usize {
                let claimed = self.key.compare_exchange(0usize, 1usize, core.sync.atomic.Ordering.AcqRel, core.sync.atomic.Ordering.Acquire)
                if claimed.is_success() {
                    let destructor = unsafe { core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(drop_value<T>) }
                    let key = unsafe { mettle_rt_tls_key_new(destructor) }
                    if key == 0usize {
                        self.key.store(0usize, core.sync.atomic.Ordering.Release)
                        panic("out of thread-local keys")
                    }
                    self.key.store(key + 1usize, core.sync.atomic.Ordering.Release)
                    return key
                }
            } else {
                unsafe { mettle_rt_thread_yield() }
            }
        }
        core.intrinsics.abort()
    }

    fn value(initialize: bool): ptr<mut u8> {
        let key = self.key()
        panic_if_destroying(key)
        var raw = unsafe { mettle_rt_tls_get(key) }
        if raw == core.ptr.null_mut<u8>() && initialize {
            match self.initialize {
                present(make) => {
                    let value = alloc.boxed.new(Value(0usize, false, make())).into_raw().0
                    raw = value.cast<u8>()
                    if unsafe { mettle_rt_tls_set(key, raw) } != 0 {
                        let _owned = unsafe { alloc.boxed.from_raw_in(value, alloc.alloc.Global()) }
                        panic("failed to set thread-local value")
                    }
                },
                none => {}
            }
        }
        raw
    }

    pub fn set(take value: T): Unit {
        let key = self.key()
        panic_if_destroying(key)
        let old = unsafe { mettle_rt_tls_get(key) }
        check_replace<T>(old)
        let raw = alloc.boxed.new(Value(0usize, false, value)).into_raw().0.cast<u8>()
        unsafe {
            if mettle_rt_tls_set(key, raw) != 0 {
                let _owned = alloc.boxed.from_raw_in(raw.cast<Value<T>>(), alloc.alloc.Global())
                panic("failed to set thread-local value")
            }
            if old != core.ptr.null_mut<u8>() { drop_value<T>(old) }
        }
    }

    pub fn is_set(): bool {
        var state = self.key.load(core.sync.atomic.Ordering.Acquire)
        while state == 1usize {
            unsafe { mettle_rt_thread_yield() }
            state = self.key.load(core.sync.atomic.Ordering.Acquire)
        }
        if state == 0usize { return false }
        unsafe { mettle_rt_tls_get(state - 1usize) != core.ptr.null_mut<u8>() }
    }

    pub fn with<R, F: take fn(read T): R>(take f: F): R? {
        let raw = self.value(true)
        if raw == core.ptr.null_mut<u8>() { return none }
        let borrowed = borrow_value<T>(raw)
        present(unsafe { f(read (*borrowed.raw).value) })
    }
}
