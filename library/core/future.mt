// Future poll/wake protocol (S030). No allocation and no executor live here:
// an executor supplies a `RawWaker` (data pointer plus a `RawWakerVTable` of
// code pointers) and polls pinned futures with a `Context` that borrows it.
//
// Contract: `poll` receives exclusive pinned access and a context, and returns
// `Pending` (state stays initialized; the future arranged a wake-up through
// `cx.waker()`) or `Ready(value)`. Spurious wake-ups are allowed; concurrent
// polls are not. Polling after `Ready` is outside the protocol: compiler
// generated futures panic with a defined message.

pub enum Poll<T> { Ready(T); Pending }

impl<T> Poll<T> {
    pub fn is_ready(): bool { match self { Poll::Ready(value) => true, Poll::Pending => false } }
    pub fn is_pending(): bool { match self { Poll::Ready(value) => false, Poll::Pending => true } }
}

pub interface Future {
    type Output;
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<Self::Output>;
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
unsafe impl Waker implements Transferable {}
unsafe impl Waker implements Shareable {}

impl Waker {
    pub take fn wake(): Unit {
        let raw = self.raw
        core::mem::forget(self)
        (raw.vtable.wake)(raw.data)
    }
    pub fn wake_by_ref(): Unit { (self.raw.vtable.wake_by_ref)(self.raw.data) }
    pub fn will_wake(other: read Waker): bool {
        self.raw.data == other.raw.data
    }
    pub fn clone(): Waker {
        Waker((self.raw.vtable.clone)(self.raw.data))
    }
    pub fn data(): ptr<mut u8> { self.raw.data }
}

fn noop_clone(data: ptr<mut u8>): RawWaker { RawWaker(data, noop_table()) }
fn noop_call(data: ptr<mut u8>): Unit {}
fn noop_table(): RawWakerVTable { RawWakerVTable(noop_clone, noop_call, noop_call, noop_call) }

// Safety: the data and all vtable operations must remain valid and thread-safe
// for concurrent clone, wake, wake_by_ref and release calls. Each clone owns
// an independent reference, consumed exactly once by wake or release.
pub unsafe fn waker_from_raw(raw: RawWaker): Waker { Waker(raw) }

// A waker that does nothing, for polling without an executor.
pub fn noop_waker(): Waker {
    Waker(RawWaker(core::ptr::null_mut::<u8>(), noop_table()))
}

// Borrowed polling context: the waker of the task being polled.
pub type Context<region c> {
    waker: read Waker from c
}

impl<region c> Context<region c> {
    pub static fn from_waker(waker: read Waker from c): Context<region c> { Context(read waker) }
    pub fn waker(): read Waker from self { read *self.waker }
}

// Building blocks the compiler lowers `async fn` onto (S030, L052). An async
// body becomes a chain of these typed states: nothing runs before the first
// poll, awaited futures and the continuation closure live inline in the state
// (no allocation), and dropping an unfinished chain drops exactly the state
// that is currently initialized. A completed state panics if polled again.

// Runs `f` once, on the first poll.
pub type Lazy<T, F> { f: F?; result: super::iter::Phantom<T> }
pub fn lazy<T, F: take fn(): T>(f: take F): Lazy<T, F> {
    Lazy(present(f), super::iter::Phantom::<T>())
}
impl<T, F: take fn(): T> Lazy<T, F> implements Future {
    type Output = T
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<T> {
        let me = unsafe { self.get_unchecked_mut() }
        match take me.f.take_value() {
            present(body) => Poll::Ready(body()),
            none => super::panic::panic("async future polled after completion")
        }
    }
}

// Polls `first`; when it is ready its output feeds `cont`, whose future is
// polled in the same place. The two futures never coexist.
pub type Then<A, B, F> { first: A?; cont: F?; second: B?; done: bool }
pub fn then<X, A: Future<Output = X>, B: Future, F: take fn(take X): B>(first: take A, cont: take F): Then<A, B, F> {
    Then(present(first), present(cont), none, false)
}
impl<A: Future, B: Future, F: take fn(take A::Output): B> Then<A, B, F> implements Future {
    type Output = B::Output
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<B::Output> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.done { super::panic::panic("async future polled after completion") }
        if me.second.is_none() {
            let ready = poll_slot(mut me.first, mut cx)
            match take ready {
                present(value) => {
                    let next = me.cont.take_value().unwrap()
                    me.second = present(next(value))
                },
                none => { return Poll::Pending }
            }
        }
        let polled = poll_slot_ready(mut me.second, mut cx)
        match take polled {
            Poll::Ready(value) => { me.second = none; me.done = true; Poll::Ready(value) },
            Poll::Pending => Poll::Pending
        }
    }
}

// Polls the future in `slot`; on completion the finished future is dropped in
// place and the slot becomes `none`. The raw pointer sidesteps the conservative
// loan the interface call ties to the produced value.
fn poll_slot<A: Future>(slot: mut A?, cx: mut Context): A::Output? {
    let raw = core::ptr::from_mut(slot)
    let ready = match mut slot {
        present(inner) => match take unsafe { core::pin::Pin::new_unchecked(mut inner).poll(mut cx) } {
            Poll::Ready(value) => present(value),
            Poll::Pending => none
        },
        none => none
    }
    if ready.is_present() {
        unsafe {
            core::ptr::drop_in_place(raw)
            core::ptr::write(raw, none)
        }
    }
    ready
}
fn poll_slot_ready<A: Future>(slot: mut A?, cx: mut Context): Poll<A::Output> {
    match mut slot {
        present(inner) => unsafe { core::pin::Pin::new_unchecked(mut inner).poll(mut cx) },
        none => Poll::Pending
    }
}

// Calls `f` on the first poll to build the future for the whole body, then
// polls that future in place.
pub type Defer<B, F> { f: F?; inner: B?; done: bool }
pub fn defer<B: Future, F: take fn(): B>(f: take F): Defer<B, F> { Defer(present(f), none, false) }
impl<B: Future, F: take fn(): B> Defer<B, F> implements Future {
    type Output = B::Output
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<B::Output> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.done { super::panic::panic("async future polled after completion") }
        if me.inner.is_none() {
            let body = me.f.take_value().unwrap()
            me.inner = present(body())
        }
        let polled = poll_slot_ready(mut me.inner, mut cx)
        match take polled {
            Poll::Ready(value) => { me.inner = none; me.done = true; Poll::Ready(value) },
            Poll::Pending => Poll::Pending
        }
    }
}

// One step of a loop whose body awaits: either the next iteration's state (the
// loop-carried locals) or the final state together with the `break` value.
pub enum Flow<S, R> { Next(S); Done((S, R)) }
// Names a loop's result type where no `break` value is in sight, so every step
// of the loop agrees on `R` (`Unit` for a loop used as a statement).
pub copy type LoopKind<R> {}
pub fn next_iteration<S, R>(state: take S, kind: LoopKind<R>): Flow<S, R> { Flow::Next(state) }
// The result of a loop that contains a `return`: it either leaves normally
// with its `break` value or leaves the whole function with `F`.
pub enum Exit<R, F> { Leave(R); Return(F) }
pub fn leave<R, F>(value: take R, kind: LoopKind<Exit<R, F>>): Exit<R, F> { Exit::Leave(value) }
pub fn give_up<R, F>(value: take F, kind: LoopKind<Exit<R, F>>): Exit<R, F> { Exit::Return(value) }
pub fn finish_loop<S, R>(state: take S, value: take R): Flow<S, R> { Flow::Done((state, value)) }

// Runs `step` over the state until it reports `Done`. The state or the future
// of the current iteration is inline, never both; dropping an unfinished loop
// drops whichever is initialized.
pub type Repeat<S, R, B, F> { state: S?; step: F; current: B?; done: bool; result: super::iter::Phantom<R> }
pub fn repeat<S, R, B: Future<Output = Flow<S, R>>, F: fn(take S): B>(state: take S, step: take F, kind: LoopKind<R>): Repeat<S, R, B, F> {
    Repeat(present(state), step, none, false, super::iter::Phantom::<R>())
}
impl<S, R, B: Future<Output = Flow<S, R>>, F: fn(take S): B> Repeat<S, R, B, F> implements Future {
    type Output = (S, R)
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<(S, R)> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.done { super::panic::panic("async future polled after completion") }
        loop {
            if me.current.is_none() {
                let state = me.state.take_value().unwrap()
                me.current = present((me.step)(state))
            }
            // Polled through a raw place, so the step's output (the next
            // state) holds no loan of `me` across the loop's back edge.
            let slot = core::ptr::from_mut(mut me.current)
            let polled = unsafe { poll_slot(mut *slot, mut cx) }
            match take polled {
                present(flow) => match take flow {
                    Flow::Next(state) => { me.state = present(state) },
                    Flow::Done(result) => { me.done = true; return Poll::Ready(result) }
                },
                none => { return Poll::Pending }
            }
        }
    }
}

// The two sides of a lowered `if`/`match` whose branches await: each branch is
// its own future and exactly one of them is ever built, so the join costs one
// discriminant and no allocation. `match` nests the pair to the right.
pub enum Either<A, B> { Left(A); Right(B) }
pub fn left<A, B>(value: take A): Either<A, B> { Either::Left(value) }
pub fn right<A, B>(value: take B): Either<A, B> { Either::Right(value) }
impl<A: Future, B: Future<Output = A::Output>> Either<A, B> implements Future {
    type Output = A::Output
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<A::Output> {
        let me = unsafe { self.get_unchecked_mut() }
        match mut me {
            Either::Left(inner) => unsafe { core::pin::Pin::new_unchecked(mut inner).poll(mut cx) },
            Either::Right(inner) => unsafe { core::pin::Pin::new_unchecked(mut inner).poll(mut cx) }
        }
    }
}
