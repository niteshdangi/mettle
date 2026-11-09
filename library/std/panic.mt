// Hosted panic integration. Panics run their hook before unwinding; an
// uncaught message panic ends the process with status 101.
import package.core.text.Text

extern "C" {
    unsafe fn mettle_rt_set_panic_hook(hook: unsafe extern "C" fn(ptr<read u8>, u64): Unit): Unit;
    unsafe fn mettle_rt_take_panic_hook(): ptr<mut u8>;
    unsafe fn mettle_rt_clear_panic_hook(): Unit;
    unsafe fn mettle_rt_panicking(): i32;
    unsafe fn mettle_rt_catch_payload(context: ptr<mut u8>, body: extern "C" fn(ptr<mut u8>): Unit, payload: ptr<mut ptr<mut u8>>): i32;
    unsafe fn mettle_rt_panic_payload_code(payload: ptr<mut u8>): i32;
    unsafe fn mettle_rt_panic_payload_message(payload: ptr<mut u8>, length: ptr<mut u64>): ptr<read u8>;
    unsafe fn mettle_rt_panic_payload_free(payload: ptr<mut u8>): Unit;
}

pub enum CatchResult<T> { Returned(T); Panicked(PanicInfo) }

// The payload lives in the runtime until this value is dropped.
pub type PanicInfo {
    payload: ptr<mut u8>
    drop { unsafe { mettle_rt_panic_payload_free(self.payload) } }
}

extend PanicInfo {
    pub fn code(): i32 { unsafe { mettle_rt_panic_payload_code(self.payload) } }
    pub fn message(): read Text from self {
        var length = 0u64
        let data = unsafe { mettle_rt_panic_payload_message(self.payload, core.ptr.from_mut(length)) }
        let bytes = unsafe { package.core.slice.from_raw_parts(data, length as usize) }
        unsafe { package.core.text.from_utf8_unchecked(bytes) }
    }
}

// Replaces the default report. The borrowed message is valid only during the
// call. Hooks must not panic; a panic raised by a hook aborts the process.
pub fn set_hook(hook: unsafe extern "C" fn(ptr<read u8>, u64): Unit): Unit {
    unsafe { mettle_rt_set_panic_hook(hook) }
}

// Takes the custom hook and restores the default stderr report. `none` means
// the default hook was active.
pub fn take_hook(): (unsafe extern "C" fn(ptr<read u8>, u64): Unit)? {
    let hook = unsafe { mettle_rt_take_panic_hook() }
    if hook == core.ptr.null_mut<u8>() { return none }
    present(unsafe {
        core.mem.transmute<unsafe extern "C" fn(ptr<read u8>, u64): Unit>(hook)
    })
}

// Restores the default stderr report without returning the previous hook.
pub fn reset_hook(): Unit {
    unsafe { mettle_rt_clear_panic_hook() }
}

// True while this thread is unwinding because of a panic.
pub fn panicking(): bool { unsafe { mettle_rt_panicking() } != 0 }

type CatchContext<T, F> {
    operation: core.mem.MaybeUninit<F>
    result: core.mem.MaybeUninit<T>
}

fn run_catch<T, F: take fn(): T>(raw: ptr<mut u8>): Unit {
    unsafe {
        let context = raw.cast<CatchContext<T, F>>()
        let operation = core.ptr.`read`((*context).operation.as_ptr())
        (*context).operation = core.mem.MaybeUninit<F>.uninit()
        let value = operation()
        core.ptr.write((*context).result.as_mut_ptr(), value)
    }
}

// Runs one closure on the current thread. Its ordinary local cleanup completes
// before the panic payload is returned; the payload message borrows its owner.
pub fn catch_panic<T, F: take fn(): T>(take operation: F): CatchResult<T> {
    var context = CatchContext<T, F>(
        core.mem.MaybeUninit.new(operation),
        core.mem.MaybeUninit<T>.uninit()
    )
    var payload = core.ptr.null_mut<u8>()
    let action: fn(ptr<mut u8>): Unit = run_catch<T, F>
    let body = unsafe { core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(action) }
    let code = unsafe {
        mettle_rt_catch_payload(
            core.ptr.from_mut(context).cast<u8>(),
            body,
            core.ptr.from_mut(payload)
        )
    }
    if code == 0 {
        CatchResult.Returned(unsafe { core.ptr.`read`(context.result.as_ptr()) })
    } else {
        CatchResult.Panicked(PanicInfo(payload))
    }
}
