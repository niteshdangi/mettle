// Future poll/wake protocol (S030). No allocation and no executor live here:
// an executor supplies a `RawWaker` (data pointer plus a `RawWakerVTable` of
// code pointers) and polls pinned futures with a `Context` that borrows it.
//
// Contract: `poll` receives exclusive pinned access and a context, and returns
// `Pending` (state stays initialized; the future arranged a wake-up through
// `cx.waker()`) or `Ready(value)`. Spurious wake-ups are allowed; concurrent
// polls are not. Polling after `Ready` is outside the protocol: compiler
// generated futures panic with a defined message.
import package.core.clone.Clone
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.convert.From
import package.core.fmt.{Debug, Formatter}
import package.core.hash.{Hash, Hasher}

pub enum Poll<T> { Ready(T); Pending }

extend<T> Poll<T> {
    pub const fn is_ready(): bool { match self { Poll.Ready(value) => true, Poll.Pending => false } }
    pub const fn is_pending(): bool { match self { Poll.Ready(value) => false, Poll.Pending => true } }
    pub take fn map<U, F: take fn(take T): U>(take f: F): Poll<U> {
        match take self {
            Poll.Ready(value) => Poll.Ready(f(value)),
            Poll.Pending => Poll.Pending
        }
    }
}

extend<T: Clone> Poll<T> implements Clone {
    fn clone(): Poll<T> {
        match self {
            Poll.Ready(value) => Poll.Ready(value.clone()),
            Poll.Pending => Poll.Pending
        }
    }
}
extend<T: PartialEq> Poll<T> implements PartialEq {
    fn eq(read other: Poll<T>): bool {
        match self {
            Poll.Ready(value) => match other {
                Poll.Ready(other_value) => value == other_value,
                Poll.Pending => false
            },
            Poll.Pending => other.is_pending()
        }
    }
}
extend<T: Eq> Poll<T> implements Eq {}
extend<T: PartialOrd> Poll<T> implements PartialOrd {
    fn partial_cmp(read other: Poll<T>): Ordering? {
        match self {
            Poll.Ready(value) => match other {
                Poll.Ready(other_value) => value.partial_cmp(other_value),
                Poll.Pending => present(Ordering.Less)
            },
            Poll.Pending => present(if other.is_pending() { Ordering.Equal } else { Ordering.Greater })
        }
    }
}
extend<T: Ord> Poll<T> implements Ord {
    fn cmp(read other: Poll<T>): Ordering {
        match self {
            Poll.Ready(value) => match other {
                Poll.Ready(other_value) => value.cmp(other_value),
                Poll.Pending => Ordering.Less
            },
            Poll.Pending => if other.is_pending() { Ordering.Equal } else { Ordering.Greater }
        }
    }
}
extend<T: Hash> Poll<T> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        match self {
            Poll.Ready(value) => { state.write_u8(0u8); value.hash(mut state) },
            Poll.Pending => state.write_u8(1u8)
        }
    }
}
extend<T: Debug> Poll<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws package.core.fmt.Error {
        match self {
            Poll.Ready(value) => {
                try f.write_str("Ready(")
                try value.fmt(mut f)
                try f.write_str(")")
            },
            Poll.Pending => try f.write_str("Pending")
        }
    }
}
extend<T> Poll<T> implements From<T> {
    static fn from(take value: T): Poll<T> { Poll.Ready(value) }
}

extend<T, E> Poll<(Outcome<T, E>)> {
    pub take fn map_ok<U, F: take fn(take T): U>(take f: F): Poll<(Outcome<U, E>)> {
        match take self {
            Poll.Ready(result) => Poll.Ready(match take result {
                success(value) => success(f(value)),
                failure(error) => failure(error)
            }),
            Poll.Pending => Poll.Pending
        }
    }
    pub take fn map_err<F, G: take fn(take E): F>(take f: G): Poll<(Outcome<T, F>)> {
        match take self {
            Poll.Ready(result) => Poll.Ready(match take result {
                success(value) => success(value),
                failure(error) => failure(f(error))
            }),
            Poll.Pending => Poll.Pending
        }
    }
}

extend<T, E> Poll<(Outcome<T, E>)?> {
    pub take fn map_ok<U, F: take fn(take T): U>(take f: F): Poll<(Outcome<U, E>)?> {
        match take self {
            Poll.Ready(result) => Poll.Ready(match take result {
                present(outcome) => present(match take outcome {
                    success(value) => success(f(value)),
                    failure(error) => failure(error)
                }),
                none => none
            }),
            Poll.Pending => Poll.Pending
        }
    }
    pub take fn map_err<F, G: take fn(take E): F>(take f: G): Poll<(Outcome<T, F>)?> {
        match take self {
            Poll.Ready(result) => Poll.Ready(match take result {
                present(outcome) => present(match take outcome {
                    success(value) => success(value),
                    failure(error) => failure(f(error))
                }),
                none => none
            }),
            Poll.Pending => Poll.Pending
        }
    }
}

pub interface Future {
    type Output;
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Self.Output>;
}

// Table of the four waker operations over an executor-owned data pointer.
// `clone` returns an independent waker for the same task; `wake` consumes one
// waker; `wake_by_ref` does not; `release` releases one waker.
pub copy type RawWakerVTable {
    pub clone: fn(ptr<mut u8>): RawWaker
    pub wake: fn(ptr<mut u8>): Unit
    pub wake_by_ref: fn(ptr<mut u8>): Unit
    pub release: fn(ptr<mut u8>): Unit
}

pub copy type RawWaker {
    pub data: ptr<mut u8>
    pub vtable: RawWakerVTable
}

// An owned handle that wakes one task. Ownership of one reference-count-like
// unit of the executor's data is held until `wake` or drop.
pub type Waker {
    raw: RawWaker
    drop { (self.raw.vtable.release)(self.raw.data) }
}

// All raw-waker constructors must provide thread-safe data and operations.
unsafe extend Waker implements Transferable {}
unsafe extend Waker implements Shareable {}

extend Waker {
    pub take fn wake(): Unit {
        let raw = self.raw
        core.mem.forget(self)
        (raw.vtable.wake)(raw.data)
    }
    pub fn wake_by_ref(): Unit { (self.raw.vtable.wake_by_ref)(self.raw.data) }
    pub fn will_wake(read other: Waker): bool {
        self.raw.data == other.raw.data && self.uses_vtable(other.raw.vtable)
    }
    // Identifies wakers built from one vtable by its callback addresses.
    pub fn uses_vtable(other: RawWakerVTable): bool {
        unsafe {
            core.mem.transmute<usize>(self.raw.vtable.clone) == core.mem.transmute<usize>(other.clone) &&
                core.mem.transmute<usize>(self.raw.vtable.wake) == core.mem.transmute<usize>(other.wake) &&
                core.mem.transmute<usize>(self.raw.vtable.wake_by_ref) == core.mem.transmute<usize>(other.wake_by_ref) &&
                core.mem.transmute<usize>(self.raw.vtable.release) == core.mem.transmute<usize>(other.release)
        }
    }
    pub fn data(): ptr<mut u8> { self.raw.data }
    // Transfers this reference to a caller that will invoke exactly one
    // `wake` or `release` callback.
    pub take fn into_raw(): RawWaker {
        let raw = self.raw
        core.mem.forget(self)
        raw
    }
}

extend Waker implements Clone {
    fn clone(): Waker { Waker((self.raw.vtable.clone)(self.raw.data)) }
}

extend Waker implements Debug {
    fn fmt(mut f: Formatter): Unit throws package.core.fmt.Error {
        try f.write_str("Waker")
    }
}

extend Waker {
    pub unsafe static const fn from_raw(raw: RawWaker): Waker { waker_from_raw(raw) }
    pub unsafe static const fn new(data: ptr<mut u8>, vtable: RawWakerVTable): Waker {
        waker_from_raw(RawWaker(data, vtable))
    }
    pub static const fn noop(): read Waker from static { read NOOP_WAKER }
    pub fn vtable(): RawWakerVTable { self.raw.vtable }
}

fn noop_clone(data: ptr<mut u8>): RawWaker { RawWaker(data, noop_table()) }
fn noop_call(data: ptr<mut u8>): Unit {}
const fn noop_table(): RawWakerVTable { RawWakerVTable(noop_clone, noop_call, noop_call, noop_call) }
static NOOP_WAKER: Waker = Waker(RawWaker(
    core.ptr.null_mut<u8>(),
    RawWakerVTable(noop_clone, noop_call, noop_call, noop_call)
))

// Safety: the data and all vtable operations must remain valid and thread-safe
// for concurrent clone, wake, wake_by_ref and release calls. Each clone owns
// an independent reference, consumed exactly once by wake or release.
pub unsafe const fn waker_from_raw(raw: RawWaker): Waker { Waker(raw) }

// A waker that does nothing, for polling without an executor.
pub const fn noop_waker(): Waker {
    Waker(RawWaker(core.ptr.null_mut<u8>(), noop_table()))
}

// Borrowed polling context: the waker of the task being polled.
pub type Context<region c> {
    waker: read Waker from c
}

extend<region c> Context<region c> {
    pub static const fn from_waker(read waker: Waker from c): Context<region c> { Context(read waker) }
    pub const fn waker(): read Waker from c { read *self.waker }
}

extend<region c> Context<region c> implements Debug {
    fn fmt(mut f: Formatter): Unit throws package.core.fmt.Error {
        try f.write_str("Context { waker: ")
        try self.waker().fmt(mut f)
        try f.write_str(" }")
    }
}

// The future of an `async` body (S030, L052). The compiler turns the body into
// a coroutine closure: its locals, awaited futures and resume point live in the
// inline `CoroutineState`, so nothing allocates and nothing runs before the
// first poll. Dropping an unfinished future drops exactly the locals that are
// initialized at its suspension point; polling a finished or panicked future
// panics with a defined message.
pub type Coroutine<T, C> {
    state: core.future.CoroutineState<T, C>
    marker: core.marker.PhantomPinned
}

pub fn coroutine<T, C: take fn(): T>(take body: C): Coroutine<T, C> {
    Coroutine(unsafe { core.intrinsics.coroutine_start<core.future.CoroutineState<T, C>>(body) }, core.marker.PhantomPinned)
}

pub fn throwing_coroutine<T, E, C: take fn(): T throws E>(take body: C): Coroutine<(Outcome<T, E>), C> {
    Coroutine(unsafe { core.intrinsics.coroutine_start<core.future.CoroutineState<(Outcome<T, E>), C>>(body) }, core.marker.PhantomPinned)
}

extend<T, C> Coroutine<T, C> implements Future {
    type Output = T
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<T> {
        let me = unsafe { self.get_unchecked_mut() }
        let context = core.ptr.from_mut(mut cx).cast<u8>()
        match take unsafe { core.intrinsics.coroutine_resume(mut me.state, context) } {
            present(value) => Poll.Ready(value),
            none => Poll.Pending
        }
    }
}

// Safety: future stays pinned through destruction; cx is a live, initialized,
// exclusively borrowed Context for this poll.
pub unsafe fn poll_await<F: Future>(mut future: F, cx: ptr<mut u8>): F.Output? {
    let context = unsafe { mut *cx.cast<Context>() }
    match take unsafe { core.pin.Pin.new_unchecked(mut future).poll(context) } {
        Poll.Ready(value) => present(value),
        Poll.Pending => none
    }
}
