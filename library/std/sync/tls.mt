import package.core.panic.panic;

extern "C" {
    unsafe fn mettle_rt_tls_key_new(destructor: extern "C" fn(ptr<mut u8>): Unit): usize;
    unsafe fn mettle_rt_tls_key_free(key: usize): Unit;
    unsafe fn mettle_rt_tls_static_key_new(
        identity: ptr<read u8>,
        destructor: extern "C" fn(ptr<mut u8>): Unit
    ): usize;
    unsafe fn mettle_rt_tls_get(key: usize): ptr<mut u8>;
    unsafe fn mettle_rt_tls_set(key: usize, value: ptr<mut u8>): i32;
    unsafe fn mettle_rt_thread_yield(): Unit;
}

// A static declaration keeps only its initializer. The runtime keys this
// descriptor by its static address, avoiding generic const-function evaluation.
pub type LocalKey<T> {
    pub initialize: fn(): T
}
// The descriptor contains only immutable code; TLS values stay on their
// owning threads, and its methods require the descriptor's static address.
unsafe extend<T> LocalKey<T> implements Transferable {}
unsafe extend<T> LocalKey<T> implements Shareable {}

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

fn drop_value<T>(raw: ptr<mut u8>): Unit {
    let _owned = unsafe { package.alloc.boxed.from_raw_in(raw.cast<T>(), package.alloc.alloc.Global()) }
}

pub fn new<T>(): OwnedLocalKey<T> {
    let destructor = unsafe { core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(drop_value<T>) }
    let key = unsafe { mettle_rt_tls_key_new(destructor) }
    if key == 0usize { panic("out of thread-local keys") }
    OwnedLocalKey(core.sync.atomic.AtomicUsize.new(key + 1usize), none, true)
}

extend<T> LocalKey<T> {
    fn key(receiver self: read LocalKey<T> from static): usize {
        let identity = core.ptr.from_ref(self).cast<u8>()
        let destructor = unsafe { core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(drop_value<T>) }
        let key = unsafe { mettle_rt_tls_static_key_new(identity, destructor) }
        if key == 0usize { panic("out of thread-local keys") }
        key
    }

    fn value(receiver self: read LocalKey<T> from static): ptr<mut u8> {
        let key = self.key()
        var raw = unsafe { mettle_rt_tls_get(key) }
        if raw == core.ptr.null_mut<u8>() {
            let initialize = self.initialize
            let value = package.alloc.boxed.new(initialize()).into_raw().0
            raw = value.cast<u8>()
            if unsafe { mettle_rt_tls_set(key, raw) } != 0 {
                let _owned = unsafe { package.alloc.boxed.from_raw_in(value, package.alloc.alloc.Global()) }
                panic("failed to set thread-local value")
            }
        }
        raw
    }

    pub fn set(receiver self: read LocalKey<T> from static, value: take T): Unit {
        let key = self.key()
        let raw = package.alloc.boxed.new(value).into_raw().0.cast<u8>()
        unsafe {
            let old = mettle_rt_tls_get(key)
            if mettle_rt_tls_set(key, raw) != 0 {
                let _owned = package.alloc.boxed.from_raw_in(raw.cast<T>(), package.alloc.alloc.Global())
                panic("failed to set thread-local value")
            }
            if old != core.ptr.null_mut<u8>() { drop_value<T>(old) }
        }
    }

    pub fn is_set(receiver self: read LocalKey<T> from static): bool {
        unsafe { mettle_rt_tls_get(self.key()) != core.ptr.null_mut<u8>() }
    }

    pub fn with<R>(
        receiver self: read LocalKey<T> from static,
        f: take fn(read T): R
    ): R? {
        let raw = self.value()
        present(unsafe { f(read *raw.cast<T>()) })
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
        var raw = unsafe { mettle_rt_tls_get(key) }
        if raw == core.ptr.null_mut<u8>() && initialize {
            match self.initialize {
                present(make) => {
                    let value = package.alloc.boxed.new(make()).into_raw().0
                    raw = value.cast<u8>()
                    if unsafe { mettle_rt_tls_set(key, raw) } != 0 {
                        let _owned = unsafe { package.alloc.boxed.from_raw_in(value, package.alloc.alloc.Global()) }
                        panic("failed to set thread-local value")
                    }
                },
                none => {}
            }
        }
        raw
    }

    pub fn set(value: take T): Unit {
        let key = self.key()
        let raw = package.alloc.boxed.new(value).into_raw().0.cast<u8>()
        unsafe {
            let old = mettle_rt_tls_get(key)
            if mettle_rt_tls_set(key, raw) != 0 {
                let _owned = package.alloc.boxed.from_raw_in(raw.cast<T>(), package.alloc.alloc.Global())
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

    pub fn with<R>(f: take fn(read T): R): R? {
        let raw = self.value(true)
        if raw == core.ptr.null_mut<u8>() { return none }
        present(unsafe { f(read *raw.cast<T>()) })
    }
}
