// Optional hosted executor for the `core::future` protocol: `block_on` and a
// single-threaded `Executor`. Nothing in `core` or `alloc` depends on it; a
// program may use any other executor that supplies a `Waker`.
//
// Wake protocol (S030): every poll gets a fresh `Waker` for its task. A wake
// that arrives while the task is being polled (wake-before-pending) or any
// number of repeated wakes coalesce into one queued re-poll, because the
// task's `queued` flag is cleared before the poll and set by the first wake.
// A task whose future returned `Ready` is removed from its slot, so a later
// wake finds nothing to poll: the executor never polls a completed future.
import super::sync::mutex;
import super::sync::condvar;
import package::alloc::arc;
import package::alloc::arc::Arc;
import package::alloc::boxed;
import package::alloc::alloc::Global;
import package::alloc::vec_deque::VecDeque;
import package::core::future::{Future, Poll, Context, Waker, RawWaker, RawWakerVTable};
import package::core::panic::panic;

// A task handle that can be woken from any thread. `me` is the Arc the waker
// owns, so the implementation can re-queue itself.
pub interface Wake: Sized {
    fn wake(me: read Arc<Self>): Unit;
}

fn waker_table<W: Wake + Transferable + Shareable>(): RawWakerVTable {
    RawWakerVTable(waker_clone::<W>, waker_wake::<W>, waker_wake_by_ref::<W>, waker_release::<W>)
}

fn waker_clone<W: Wake + Transferable + Shareable>(data: ptr<mut u8>): RawWaker {
    unsafe {
        let handle = data.cast::<Arc<W>>()
        let dup = boxed::new((*handle).retain())
        let parts = dup.into_raw()
        RawWaker(parts.0.cast::<u8>(), waker_table::<W>())
    }
}
fn waker_wake<W: Wake + Transferable + Shareable>(data: ptr<mut u8>): Unit {
    unsafe {
        let owned = boxed::from_raw_in(data.cast::<Arc<W>>(), Global())
        owned.get().get().wake(owned.get())
    }
}
fn waker_wake_by_ref<W: Wake + Transferable + Shareable>(data: ptr<mut u8>): Unit {
    unsafe {
        let handle = data.cast::<Arc<W>>()
        (*handle).get().wake(read *handle)
    }
}
fn waker_release<W: Wake + Transferable + Shareable>(data: ptr<mut u8>): Unit {
    unsafe { let _owned = boxed::from_raw_in(data.cast::<Arc<W>>(), Global()) }
}

// A waker owning one reference to `handle`'s payload.
pub fn waker_from_arc<W: Wake + Transferable + Shareable>(handle: read Arc<W>): Waker {
    let dup = boxed::new(handle.retain())
    let parts = dup.into_raw()
    unsafe { package::core::future::waker_from_raw(RawWaker(parts.0.cast::<u8>(), waker_table::<W>())) }
}

// A latch that a waker sets and a blocked thread consumes.
type Signal {
    set: mutex::Mutex<bool>
    changed: condvar::Condvar
}
fn new_signal(): Signal { Signal(mutex::new(false), condvar::new()) }

impl Signal implements Wake {
    fn wake(me: read Arc<Signal>): Unit {
        let locked = capture self.set.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        *guard.get_mut() = true
        self.changed.notify_one()
    }
}
impl Signal {
    fn wait(): Unit {
        let locked = capture self.set.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        while !*guard.get() { guard = self.changed.wait(guard) }
        *guard.get_mut() = false
    }
}
unsafe impl Signal implements Transferable {}
unsafe impl Signal implements Shareable {}

// Polls `future` on the calling thread, parking between wake-ups, until it is
// ready. The future is pinned in this frame and dropped before returning.
pub fn block_on<F: Future>(future: take F): F::Output {
    let signal = arc::new(new_signal())
    let waker = waker_from_arc(read signal)
    var pin_ = core::pin::pin(future)
    var result: F::Output? = none
    while result.is_none() {
        // A fresh Context per poll: the interface call conservatively ties the
        // pinned receiver's loan to the Context it was given.
        var cx = Context::from_waker(read waker)
        match take pin_.as_mut().poll(mut cx) {
            Poll::Ready(value) => { result = present(value) },
            Poll::Pending => { signal.get().wait() }
        }
    }
    result.unwrap()
}

// Pending exactly once, waking itself first so a poll loop reschedules it.
pub type YieldNow { yielded: bool }
pub fn yield_now(): YieldNow { YieldNow(false) }
impl YieldNow implements Future {
    type Output = Unit
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<Unit> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.yielded { Poll::Ready(()) } else {
            me.yielded = true
            cx.waker().wake_by_ref()
            Poll::Pending
        }
    }
}

// Type-erased heap future: `poll` returns whether it completed; `release`
// drops and frees the allocation exactly once.
type ErasedFuture {
    data: ptr<mut u8>
    poll: fn(ptr<mut u8>, ptr<mut u8>): bool
    release: fn(ptr<mut u8>): Unit
    drop { (self.release)(self.data) }
}

fn poll_erased<F: Future<Output = Unit>>(data: ptr<mut u8>, waker_slot: ptr<mut u8>): bool {
    var owner = unsafe { boxed::from_raw_in(data.cast::<F>(), Global()) }
    // Bitwise view of the caller's Waker; the caller keeps ownership.
    let waker = unsafe { core::ptr::`read`(waker_slot.cast::<Waker>()) }
    var cx = Context::from_waker(read waker)
    let polled = unsafe { core::pin::Pin::new_unchecked(owner.get_mut()).poll(mut cx) }
    // The allocation stays owned by the task's ErasedFuture.
    core::mem::forget(take owner)
    core::mem::forget(take waker)
    match take polled { Poll::Ready(unit) => true, Poll::Pending => false }
}
fn release_erased<F>(data: ptr<mut u8>): Unit {
    unsafe { let _owned = boxed::from_raw_in(data.cast::<F>(), Global()) }
}

// The queue holds raw Box<Arc<Task>> pointers: the Task -> Shared -> queue ->
// Task type cycle is otherwise beyond region inference.
fn leak_task(task: take Arc<Task>): ptr<mut u8> { boxed::new(task).into_raw().0.cast::<u8>() }
fn reclaim_task(raw: ptr<mut u8>): Arc<Task> {
    unsafe { boxed::from_raw_in(raw.cast::<Arc<Task>>(), Global()).into_inner() }
}

type Shared {
    queue: mutex::Mutex<VecDeque<ptr<mut u8>>>
    ready: condvar::Condvar
    live: core::sync::atomic::AtomicUsize
}
type Task {
    future: mutex::Mutex<ErasedFuture?>
    queued: core::sync::atomic::AtomicBool
    hub: Arc<Shared>
}
unsafe impl Shared implements Transferable {}
unsafe impl Shared implements Shareable {}
unsafe impl Task implements Transferable {}
unsafe impl Task implements Shareable {}

impl Task implements Wake {
    fn wake(me: read Arc<Task>): Unit {
        if !self.queued.swap(true, core::sync::atomic::Ordering::AcqRel) {
            let hub = self.hub.get()
            let locked = capture hub.queue.lock()
            var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
            guard.get_mut().push_back(leak_task(me.retain()))
            hub.ready.notify_one()
        }
    }
}

// Single-threaded cooperative executor: `run` polls on the calling thread;
// wakes may come from any thread. Spawned futures are heap-allocated.
pub type Executor {
    hub: Arc<Shared>
    drop {
        // Queued tasks hold the hub state; break that cycle.
        let locked = capture self.hub.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        var more = true
        while more {
            match take guard.get_mut().pop_front() {
                present(raw) => { let _task = reclaim_task(raw) },
                none => { more = false }
            }
        }
    }
}

pub fn executor(): Executor {
    Executor(arc::new(Shared(mutex::new(package::alloc::vec_deque::new::<ptr<mut u8>>()), condvar::new(),
                             core::sync::atomic::AtomicUsize::new(0usize))))
}

fn erase<F: Future<Output = Unit>>(future: take F): ErasedFuture {
    let storage = boxed::new(future).into_raw()
    ErasedFuture(storage.0.cast::<u8>(), poll_erased::<F>, release_erased::<F>)
}
fn new_task(erased: take ErasedFuture, hub: take Arc<Shared>): Arc<Task> {
    arc::new(Task(mutex::new(present(erased)), core::sync::atomic::AtomicBool::new(false), hub))
}

impl Executor {
    pub fn spawn<F: Future<Output = Unit>>(future: take F): Unit {
        let task = new_task(erase(future), self.hub.retain())
        let _old = self.hub.get().live.fetch_add(1usize, core::sync::atomic::Ordering::AcqRel)
        task.get().wake(read task)
    }

    // Number of spawned futures that have not completed.
    pub fn pending(): usize { self.hub.get().live.load(core::sync::atomic::Ordering::Acquire) }

    // Runs until every spawned future has completed, blocking while tasks wait
    // for a wake.
    pub fn run(): Unit {
        var finished = false
        while !finished {
            match take self.next_task(true) {
                present(task) => { self.poll_task(task) },
                none => { finished = true }
            }
        }
    }

    // Polls every task that is currently ready, including tasks woken while
    // running, without blocking. Returns the number of polls performed.
    pub fn run_until_stalled(): usize {
        var polls = 0usize
        var finished = false
        while !finished {
            match take self.next_task(false) {
                present(task) => { self.poll_task(task); polls += 1usize },
                none => { finished = true }
            }
        }
        polls
    }

    fn next_task(block: bool): Arc<Task>? {
        let hub = self.hub.get()
        let locked = capture hub.queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        var result: Arc<Task>? = none
        var waiting = true
        while waiting {
            let next = guard.get_mut().pop_front()
            match take next {
                present(raw) => { result = present(reclaim_task(raw)); waiting = false },
                none => {
                    if !block || hub.live.load(core::sync::atomic::Ordering::Acquire) == 0usize { waiting = false } else { guard = hub.ready.wait(guard) }
                }
            }
        }
        result
    }

    fn poll_task(task: take Arc<Task>): Unit {
        task.get().queued.store(false, core::sync::atomic::Ordering::Release)
        var waker = waker_from_arc(read task)
        let locked = capture task.get().future.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        var finished = false
        match mut guard.get_mut() {
            present(slot) => {
                finished = (slot.poll)(slot.data, core::ptr::from_mut(waker).cast::<u8>())
            },
            none => {}
        }
        if finished {
            *guard.get_mut() = none
            let _old = self.hub.get().live.fetch_sub(1usize, core::sync::atomic::Ordering::AcqRel)
        }
    }
}
