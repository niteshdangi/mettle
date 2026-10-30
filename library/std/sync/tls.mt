import package::core::panic::panic;

extern "C" {
    unsafe fn mettle_rt_tls_key_new(destructor: extern "C" fn(ptr<mut u8>): Unit): usize;
    unsafe fn mettle_rt_tls_key_free(key: usize): Unit;
    unsafe fn mettle_rt_tls_get(key: usize): ptr<mut u8>;
    unsafe fn mettle_rt_tls_set(key: usize, value: ptr<mut u8>): i32;
}

// A per-thread slot of `T`, empty on every thread until it sets a value. The
// value never leaves its thread, so the key is shareable for any `T`; a
// thread's value is dropped when that thread exits.
pub type LocalKey<T> {
    key: usize
    drop { unsafe { mettle_rt_tls_key_free(self.key) } }
}
unsafe impl<T> LocalKey<T> implements Transferable {}
unsafe impl<T> LocalKey<T> implements Shareable {}

fn drop_value<T>(raw: ptr<mut u8>): Unit {
    let _owned = unsafe { package::alloc::boxed::from_raw_in(raw.cast::<T>(), package::alloc::alloc::Global()) }
}

pub fn new<T>(): LocalKey<T> {
    let run = unsafe { core::mem::transmute::<extern "C" fn(ptr<mut u8>): Unit>(drop_value::<T>) }
    let key = unsafe { mettle_rt_tls_key_new(run) }
    if key == 0usize { panic("out of thread-local keys") }
    LocalKey(key)
}

impl<T> LocalKey<T> {
    // Replaces the calling thread's value, dropping the old one.
    pub fn set(value: take T): Unit {
        let raw = package::alloc::boxed::new(value).into_raw().0.cast::<u8>()
        unsafe {
            let old = mettle_rt_tls_get(self.key)
            if mettle_rt_tls_set(self.key, raw) != 0 { panic("failed to set thread-local value") }
            if old != core::ptr::null_mut::<u8>() { drop_value::<T>(old) }
        }
    }
    pub fn is_set(): bool { unsafe { mettle_rt_tls_get(self.key) != core::ptr::null_mut::<u8>() } }
    // Runs `f` on the calling thread's value, if it has one.
    pub fn with<R>(f: take fn(read T): R): R? {
        let raw = unsafe { mettle_rt_tls_get(self.key) }
        if raw == core::ptr::null_mut::<u8>() { return none }
        present(unsafe { f(read *raw.cast::<T>()) })
    }
}
