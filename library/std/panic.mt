// Hosted panic integration. Panics run their hook before unwinding; an
// uncaught message panic ends the process with status 101.
import core.convert.From
import core.default.Default
import core.any.Any
import core.fmt
import core.fmt.{Debug, Display, Error, Formatter}
import core.future.{Context, Future, Poll}
import core.ops.{Deref, DerefMut}
import core.text.Text
pub import core.panic.{RefUnwindSafe, UnwindSafe}

pub type AssertUnwindSafe<T> { @pinned pub value: T }

unsafe extend<T> AssertUnwindSafe<T> implements core.marker.UnwindSafe {}
unsafe extend<T> AssertUnwindSafe<T> implements core.marker.RefUnwindSafe {}

extend<T> AssertUnwindSafe<T> implements From<T> {
    static fn from(take value: T): AssertUnwindSafe<T> { AssertUnwindSafe(value) }
}

extend<T> AssertUnwindSafe<T> implements Deref {
    type Target = T
    fn deref(): read T from self { read self.value }
}

extend<T> AssertUnwindSafe<T> implements DerefMut {
    mut fn deref_mut(): mut T from self { mut self.value }
}

extend<T: Default> AssertUnwindSafe<T> implements Default {
    static fn default(): AssertUnwindSafe<T> {
        AssertUnwindSafe(T.(Default).default())
    }
}

extend<T: Debug> AssertUnwindSafe<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_tuple("AssertUnwindSafe")
        let _ = try debug.field(self.value)
        try debug.finish()
    }
}

extend<F: Future> AssertUnwindSafe<F> implements Future {
    type Output = F.(Future).Output
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Self.Output> {
        F.(Future).poll(self.project_value(), mut cx)
    }
}

pub interface PanicPayload: Any + Transferable {}

extend<T: Any + Transferable + unsized> T implements PanicPayload {}

pub copy enum BacktraceStatus { Captured, Disabled, Unsupported }

pub copy type Backtrace { status: BacktraceStatus }

extend Backtrace {
    pub static fn `capture`(): Backtrace { Backtrace(BacktraceStatus.Unsupported) }
    pub fn status(): BacktraceStatus { self.status }
}

extend BacktraceStatus implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self {
            BacktraceStatus.Captured => try f.write_str("Captured"),
            BacktraceStatus.Disabled => try f.write_str("Disabled"),
            BacktraceStatus.Unsupported => try f.write_str("Unsupported")
        }
    }
}

extend Backtrace implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("Backtrace")
        let _ = try debug.field("status", self.status)
        try debug.finish()
    }
}

extend Backtrace implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self.status {
            BacktraceStatus.Captured => try f.write_str("backtrace captured"),
            BacktraceStatus.Disabled => try f.write_str("backtrace disabled"),
            BacktraceStatus.Unsupported => try f.write_str("backtrace unsupported")
        }
    }
}

pub copy type PanicMessage<region r> { text: read Text from r }

extend<region r> PanicMessage<region r> not Transferable;
extend<region r> PanicMessage<region r> not Shareable;

extend<region r> PanicMessage<region r> {
    pub fn as_str(): (read Text from static)? { none }
}

extend<region r> PanicMessage<region r> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try Text.(Debug).fmt(self.text, mut f)
    }
}

extend<region r> PanicMessage<region r> implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        try Text.(Display).fmt(self.text, mut f)
    }
}

@layout(C)
pub copy type PanicHookInfo {
    payload: ptr<read u8>
    payload_length: u64
    file: ptr<read u8>
    file_length: u64
    line: u64
    column: u64
}

extern "C" {
    unsafe fn mettle_rt_set_panic_hook(hook: unsafe extern "C" fn(ptr<read PanicHookInfo>): Unit): Unit;
    unsafe fn mettle_rt_take_panic_hook(): ptr<mut u8>;
    unsafe fn mettle_rt_clear_panic_hook(): Unit;
    unsafe fn mettle_rt_panicking(): i32;
    unsafe fn mettle_rt_catch_payload(context: ptr<mut u8>, body: extern "C" fn(ptr<mut u8>): Unit, payload: ptr<mut ptr<mut u8>>): i32;
    unsafe fn mettle_rt_panic_payload_code(payload: ptr<mut u8>): i32;
    unsafe fn mettle_rt_panic_payload_message(payload: ptr<mut u8>, length: ptr<mut u64>): ptr<read u8>;
    unsafe fn mettle_rt_panic_payload_free(payload: ptr<mut u8>): Unit;
}

extend BacktraceStatus implements core.cmp.PartialEq {
    fn eq(read other: BacktraceStatus): bool {
        match self {
            BacktraceStatus.Captured => match other {
                BacktraceStatus.Captured => true,
                _ => false
            },
            BacktraceStatus.Disabled => match other {
                BacktraceStatus.Disabled => true,
                _ => false
            },
            BacktraceStatus.Unsupported => match other {
                BacktraceStatus.Unsupported => true,
                _ => false
            }
        }
    }
}
extend BacktraceStatus implements core.cmp.Eq {}

extend PanicHookInfo {
    pub fn payload<region r>(
        receiver read self: PanicHookInfo from r
    ): read any PanicPayload from r {
        // Panic messages are UTF-8 and address-space-sized for the callback.
        let bytes = unsafe {
            core.slice.from_raw_parts(self.payload, self.payload_length as usize)
        }
        let text = unsafe { core.text.from_utf8_unchecked(bytes) }
        text
    }

    pub fn payload_as_str<region r>(
        receiver read self: PanicHookInfo from r
    ): (read Text from r)? {
        let bytes = unsafe {
            core.slice.from_raw_parts(self.payload, self.payload_length as usize)
        }
        let text = unsafe { core.text.from_utf8_unchecked(bytes) }
        present(text)
    }

    pub fn message<region r>(
        receiver read self: PanicHookInfo from r
    ): PanicMessage<region r>? {
        match self.payload_as_str() {
            present(text) => present(PanicMessage(read text)),
            none => none
        }
    }

    // Safety: the source bytes must remain valid for the returned view's lifetime.
    pub unsafe fn location<region r>(
        receiver read self: PanicHookInfo from r
    ): (core.panic.Location<region r>)? {
        if self.file == core.ptr.null<u8>() || self.line == 0u64 ||
            self.column == 0u64 {
            return none
        }
        // Source bytes remain valid and address-space-sized through the callback.
        let bytes = unsafe {
            core.slice.from_raw_parts(self.file, self.file_length as usize)
        }
        present(core.panic.Location<region r>.from_parts(bytes, self.line, self.column))
    }
}

extend PanicHookInfo implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("PanicHookInfo")
        let _ = try debug.field("payload_length", self.payload_length)
        let _ = try debug.field("file_length", self.file_length)
        let _ = try debug.field("line", self.line)
        let _ = try debug.field("column", self.column)
        try debug.finish()
    }
}

extend PanicHookInfo implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        // The byte views are callback-scoped and must not be dereferenced here.
        try f.write_str("panic at line ")
        try u64.(Display).fmt(self.line, mut f)
        try f.write_str(", column ")
        try u64.(Display).fmt(self.column, mut f)
    }
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
        let bytes = unsafe { core.slice.from_raw_parts(data, length as usize) }
        unsafe { core.text.from_utf8_unchecked(bytes) }
    }
}
extend PanicInfo implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("PanicInfo")
        try debug.field("code", self.code())
        try debug.field("message", self.message())
        try debug.finish()
    }
}
extend PanicInfo implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str(self.message()) }
}

extend PanicHookInfo not Transferable;
extend PanicHookInfo not Shareable;
extend PanicHookInfo not core.marker.UnwindSafe;
extend PanicHookInfo not core.marker.RefUnwindSafe;

// Hooks must not panic; a panic raised by a hook aborts the process.
pub fn set_hook(hook: unsafe extern "C" fn(ptr<read PanicHookInfo>): Unit): Unit {
    unsafe { mettle_rt_set_panic_hook(hook) }
}

pub fn take_hook(): (unsafe extern "C" fn(ptr<read PanicHookInfo>): Unit)? {
    let hook = unsafe { mettle_rt_take_panic_hook() }
    if hook == core.ptr.null_mut<u8>() { return none }
    present(unsafe {
        core.mem.transmute<unsafe extern "C" fn(ptr<read PanicHookInfo>): Unit>(hook)
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
