// Optional hosted executor for the `core.future` protocol: `block_on` and a
// single-threaded `Executor`. Nothing in `core` or `alloc` depends on it; a
// program may use any other executor that supplies a `Waker`.
//
// Wake protocol (S030): every poll gets a fresh `Waker` for its task. A wake
// that arrives while the task is being polled (wake-before-pending) or any
// number of repeated wakes coalesce into one queued re-poll, because the
// task's `queued` flag is cleared before the poll and set by the first wake.
// A task whose future returned `Ready` is removed from its slot, so a later
// wake finds nothing to poll: the executor never polls a completed future.
import super.sync.mutex
import super.sys
import super.time.{Duration, Instant}
import super.thread.{Brand, Within}
import package.alloc.arc
import package.alloc.arc.Arc
import package.alloc.boxed
import package.alloc.alloc.Global
import package.alloc.vec.List
import package.alloc.vec_deque.Deque
import package.core.future.{Future, Poll, Context, Waker, RawWaker, RawWakerVTable}
import package.core.panic.panic

extern "C" {
    unsafe fn mettle_rt_catch(context: ptr<mut u8>, body: extern "C" fn(ptr<mut u8>): Unit): i32;
}

// A task handle that can be woken from any thread. `me` is the Arc the waker
// owns, so the implementation can re-queue itself.
pub interface Wake: Sized {
    fn wake(me: read Arc<Self>): Unit;
}

fn waker_table<W: Wake + Transferable + Shareable>(): RawWakerVTable {
    RawWakerVTable(waker_clone<W>, waker_wake<W>, waker_wake_by_ref<W>, waker_release<W>)
}

fn waker_clone<W: Wake + Transferable + Shareable>(data: ptr<mut u8>): RawWaker {
    unsafe {
        let handle = data.cast<Arc<W>>()
        let dup = boxed.new((*handle).retain())
        let parts = dup.into_raw()
        RawWaker(parts.0.cast<u8>(), waker_table<W>())
    }
}
fn waker_wake<W: Wake + Transferable + Shareable>(data: ptr<mut u8>): Unit {
    unsafe {
        let owned = boxed.from_raw_in(data.cast<Arc<W>>(), Global())
        owned.get().get().wake(owned.get())
    }
}
fn waker_wake_by_ref<W: Wake + Transferable + Shareable>(data: ptr<mut u8>): Unit {
    unsafe {
        let handle = data.cast<Arc<W>>()
        (*handle).get().wake(read *handle)
    }
}
fn waker_release<W: Wake + Transferable + Shareable>(data: ptr<mut u8>): Unit {
    unsafe { let _owned = boxed.from_raw_in(data.cast<Arc<W>>(), Global()) }
}

// A waker owning one reference to `handle`'s payload.
pub fn waker_from_arc<W: Wake + Transferable + Shareable>(handle: read Arc<W>): Waker {
    let dup = boxed.new(handle.retain())
    let parts = dup.into_raw()
    unsafe { package.core.future.waker_from_raw(RawWaker(parts.0.cast<u8>(), waker_table<W>())) }
}

// A latch that a waker sets and a blocked thread consumes.
type Signal {
    reactor: ptr<mut u8>
    set: mutex.Mutex<bool>
    drop { unsafe { sys.mettle_rt_reactor_close(self.reactor) } }
}
fn new_signal(): Signal {
    let reactor = unsafe { sys.mettle_rt_reactor_new() }
    if reactor == core.ptr.null_mut<u8>() {
        package.core.panic.panic("async reactor creation failed")
    }
    Signal(reactor, mutex.new(false))
}

extend Signal implements Wake {
    fn wake(me: read Arc<Signal>): Unit {
        let locked = capture self.set.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        *guard.get_mut() = true
        unsafe { sys.mettle_rt_reactor_wake(self.reactor) }
    }
}
extend Signal {
    fn wait(): Unit {
        var waiting = true
        while waiting {
            {
                let locked = capture self.set.lock()
                var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
                if *guard.get() {
                    *guard.get_mut() = false
                    waiting = false
                }
            }
            if waiting && unsafe { sys.mettle_rt_reactor_wait(self.reactor) } < 0 {
                package.core.panic.panic("async reactor wait failed")
            }
        }
    }
}
// Every executor waker retains the Signal Arc, which owns this reactor handle.
unsafe extend Signal implements Transferable {}
unsafe extend Signal implements Shareable {}

// Polls `future` on the calling thread, parking between wake-ups, until it is
// ready. The future is pinned in this frame and dropped before returning.
pub fn block_on<F: Future>(future: take F): F.Output {
    let signal = arc.new(new_signal())
    let waker = executor_waker(
        WakeTarget.Signal(signal.retain()), signal.get().reactor
    )
    var pin_ = core.pin.pin(future)
    var result: F.Output? = none
    while result.is_none() {
        // A fresh Context per poll: the interface call conservatively ties the
        // pinned receiver's loan to the Context it was given.
        var cx = Context.from_waker(read waker)
        match take pin_.as_mut().poll(mut cx) {
            Poll.Ready(value) => { result = present(value) },
            Poll.Pending => { signal.get().wait() }
        }
    }
    result.unwrap()
}

// Pending exactly once, waking itself first so a poll loop reschedules it.
pub type YieldNow { yielded: bool }
pub fn yield_now(): YieldNow { YieldNow(false) }
extend YieldNow implements Future {
    type Output = Unit
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<Unit> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.yielded { Poll.Ready(()) } else {
            me.yielded = true
            cx.waker().wake_by_ref()
            Poll.Pending
        }
    }
}

// Readiness is one-shot. After any wake this future completes and its caller
// retries the nonblocking operation; a spurious wake is therefore harmless.
pub type IoWait {
    fd: i32
    write: bool
    reactor: ptr<mut u8>
    token: u64
    registered: bool
    drop {
        if self.registered {
            unsafe { sys.mettle_rt_reactor_cancel(self.reactor, self.token) }
        }
    }
}

extend IoWait implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        // These fields are address-independent; the pinned value is only
        // mutated in place and is never moved by this projection.
        let me = unsafe { self.get_unchecked_mut() }
        if me.registered {
            unsafe { sys.mettle_rt_reactor_cancel(me.reactor, me.token) }
            me.registered = false
            me.reactor = core.ptr.null_mut<u8>()
            me.token = 0u64
            return Poll.Ready(0)
        }
        let reactor = match take reactor_from_waker(read cx.waker()) {
            present(value) => value,
            none => { return Poll.Ready(-1) }
        }
        let raw = cx.waker().clone().into_raw()
        // The sys shim stores and invokes this owned, pointer-only callback;
        // cancellation invokes release instead, never both.
        let wake = unsafe {
            core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(raw.vtable.wake)
        }
        let release = unsafe {
            core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(raw.vtable.release)
        }
        let token = unsafe {
            sys.mettle_rt_reactor_watch(
                reactor, me.fd, if me.write { 1 } else { 0 }, raw.data,
                wake, release
            )
        }
        if token == 0u64 {
            let error = sys.errno()
            (raw.vtable.release)(raw.data)
            return Poll.Ready(error)
        }
        me.reactor = reactor
        me.token = token
        me.registered = true
        Poll.Pending
    }
}

// While registered, the reactor holds a waker that retains the reactor's
// owner, and cancellation is serialized by the reactor, so a wait may move to
// and be dropped on another thread.
unsafe extend IoWait implements Transferable {}
unsafe extend Sleep implements Transferable {}

pub fn readable(fd: i32): IoWait {
    IoWait(fd, false, core.ptr.null_mut<u8>(), 0u64, false)
}
pub fn writable(fd: i32): IoWait {
    IoWait(fd, true, core.ptr.null_mut<u8>(), 0u64, false)
}

// Timers are registered in the same reactor as descriptor readiness. The
// absolute remainder is recomputed after every wake, so unrelated wakes never
// make sleep return early and very long durations can be chunked by the shim.
pub type Sleep {
    remaining: Duration
    last: Instant
    started: bool
    reactor: ptr<mut u8>
    token: u64
    registered: bool
    drop {
        if self.registered {
            unsafe { sys.mettle_rt_reactor_cancel(self.reactor, self.token) }
        }
    }
}

extend Sleep implements Future {
    type Output = Unit
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<Unit> {
        // Sleep has no self-references; its pinned state is only mutated.
        let me = unsafe { self.get_unchecked_mut() }
        let now = super.time.now()
        if me.started {
            me.remaining = me.remaining.saturating_sub(now.duration_since(me.last))
        } else {
            me.started = true
        }
        if me.registered {
            unsafe { sys.mettle_rt_reactor_cancel(me.reactor, me.token) }
            me.registered = false
            me.reactor = core.ptr.null_mut<u8>()
            me.token = 0u64
        }
        if me.remaining.is_zero() { return Poll.Ready(()) }
        let reactor = match take reactor_from_waker(read cx.waker()) {
            present(value) => value,
            none => package.core.panic.panic("sleep requires the std.task executor")
        }
        let raw = cx.waker().clone().into_raw()
        let wake = unsafe {
            core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(raw.vtable.wake)
        }
        let release = unsafe {
            core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(raw.vtable.release)
        }
        let token = unsafe {
            sys.mettle_rt_reactor_timer(
                reactor, me.remaining.as_secs(), me.remaining.subsec_nanos(), raw.data,
                wake, release
            )
        }
        if token == 0u64 {
            (raw.vtable.release)(raw.data)
            package.core.panic.panic("async reactor timer registration failed")
        }
        me.last = now
        me.reactor = reactor
        me.token = token
        me.registered = true
        Poll.Pending
    }
}

pub fn sleep(duration: Duration): Sleep {
    Sleep(duration, super.time.now(), false, core.ptr.null_mut<u8>(),
          0u64, false)
}

// The result is independent of task/waker lifetime. Status is protected by
// the mutex: 0 running, 1 ready, 2 cancelled, 3 panicked.
type ResultState<T> { value: T?; status: u8; code: i32 }
type ResultSlot<T> { state: mutex.Mutex<ResultState<T>> }
unsafe extend<T: Transferable> ResultSlot<T> implements Transferable {}
unsafe extend<T: Transferable> ResultSlot<T> implements Shareable {}

pub enum JoinError { Cancelled; Panicked(i32) }

type Packet<F, T> { future: F; result: Arc<ResultSlot<T>> }

type ErasedReport {
    data: ptr<mut u8>
    fail: fn(ptr<mut u8>, i32): Unit
    release: fn(ptr<mut u8>): Unit
    drop { (self.release)(self.data) }
}

// The packet stays at one address until release, including through unwind.
type ErasedFuture {
    data: ptr<mut u8>
    poll: fn(ptr<mut u8>, ptr<mut u8>): bool
    release: fn(ptr<mut u8>): Unit
    report: ErasedReport?
    drop { (self.release)(self.data) }
}

fn poll_erased<T, F: Future<Output = T>>(data: ptr<mut u8>, waker_slot: ptr<mut u8>): bool {
    // The caller owns the Waker for the whole call.
    unsafe { poll_packet<T, F>(data, read *waker_slot.cast<Waker>()) }
}
fn poll_packet<T, F: Future<Output = T>>(data: ptr<mut u8>, waker: read Waker): bool {
    var cx = Context.from_waker(waker)
    let packet = data.cast<Packet<F, T>>()
    let polled = unsafe { core.pin.Pin.new_unchecked(mut (*packet).future).poll(mut cx) }
    match take polled {
        Poll.Ready(value) => {
            let locked = capture unsafe { (*packet).result.get().state.lock() }
            var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
            guard.get_mut().value = present(value)
            guard.get_mut().status = 1u8
            true
        },
        Poll.Pending => false
    }
}
fn fail_erased<T>(data: ptr<mut u8>, code: i32): Unit {
    let result = data.cast<Arc<ResultSlot<T>>>()
    let locked = capture unsafe { (*result).get().state.lock() }
    var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    guard.get_mut().status = if code == 0 { 2u8 } else { 3u8 }
    guard.get_mut().code = code
}
fn release_report<T>(data: ptr<mut u8>): Unit {
    unsafe { let _owner = boxed.from_raw_in(data.cast<Arc<ResultSlot<T>>>(), Global()) }
}
fn release_erased<T, F>(data: ptr<mut u8>): Unit {
    unsafe { let _owned = boxed.from_raw_in(data.cast<Packet<F, T>>(), Global()) }
}

type PollCall { future: ptr<mut ErasedFuture>; waker: ptr<mut Waker>; ready: bool }
fn poll_call(raw: ptr<mut u8>): Unit {
    unsafe {
        let call = raw.cast<PollCall>()
        let future = (*call).future
        (*call).ready = ((*future).poll)((*future).data, (*call).waker.cast<u8>())
    }
}

type DisposeCall { future: ErasedFuture? }
fn dispose_call(raw: ptr<mut u8>): Unit {
    unsafe {
        let call = raw.cast<DisposeCall>()
        let _future = (*call).future.take_value()
    }
}

// Task poll and destruction panics are isolated at the same runtime boundary
// as thread bodies. A second panic while handling the first is fatal.
fn dispose(future: take ErasedFuture, code: i32, cancelled: bool): Unit {
    var owner = future
    let report = owner.report.take_value().unwrap()
    var call = DisposeCall(present(owner))
    let action: fn(ptr<mut u8>): Unit = dispose_call
    let body = unsafe { core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(action) }
    let drop_code = unsafe { mettle_rt_catch(core.ptr.from_mut(call).cast<u8>(), body) }
    if code != 0 && drop_code != 0 { core.intrinsics.abort() }
    if drop_code != 0 { (report.fail)(report.data, drop_code) }
    else if code != 0 { (report.fail)(report.data, code) }
    else if cancelled { (report.fail)(report.data, 0) }
}

// The queue holds raw Box<Arc<Task>> pointers: the Task -> Shared -> queue ->
// Task type cycle is otherwise beyond region inference.
fn leak_task(task: take Arc<Task>): ptr<mut u8> { boxed.new(task).into_raw().0.cast<u8>() }
fn reclaim_task(raw: ptr<mut u8>): Arc<Task> {
    unsafe { boxed.from_raw_in(raw.cast<Arc<Task>>(), Global()).into_inner() }
}

type Shared {
    queue: mutex.Mutex<Queue>
    reactor: ptr<mut u8>
    live: core.sync.atomic.AtomicUsize
    polling: core.sync.atomic.AtomicBool
    drop { unsafe { sys.mettle_rt_reactor_close(self.reactor) } }
}
type Queue { items: Deque<ptr<mut u8>>; closed: bool }
type Task {
    future: mutex.Mutex<ErasedFuture?>
    queued: core.sync.atomic.AtomicBool
    active: core.sync.atomic.AtomicBool
    finished: core.sync.atomic.AtomicBool
    finalizing: core.sync.atomic.AtomicBool
    polling: core.sync.atomic.AtomicBool
    cancel_requested: core.sync.atomic.AtomicBool
    hub: Arc<Shared>
}

enum WakeTarget { Task(Arc<Task>); Signal(Arc<Signal>) }
type ExecutorWake {
    target: WakeTarget
    reactor: ptr<mut u8>
}

// The retained target owns the reactor handle for the entire waker lifetime.
unsafe extend WakeTarget implements Transferable {}
unsafe extend WakeTarget implements Shareable {}
unsafe extend ExecutorWake implements Transferable {}
unsafe extend ExecutorWake implements Shareable {}

extend ExecutorWake implements Wake {
    fn wake(me: read Arc<ExecutorWake>): Unit {
        match self.target {
            WakeTarget.Task(task) => task.get().wake(read task),
            WakeTarget.Signal(signal) => signal.get().wake(read signal)
        }
    }
}

fn executor_waker(target: take WakeTarget, reactor: ptr<mut u8>): Waker {
    let handle = arc.new(ExecutorWake(target, reactor))
    waker_from_arc(read handle)
}

fn reactor_from_waker(waker: read Waker): ptr<mut u8>? {
    if !waker.uses_vtable(waker_table<ExecutorWake>()) { return none }
    let raw = waker.clone().into_raw()
    // The exact executor vtable identifies data as its boxed Arc payload.
    let reactor = unsafe {
        (*raw.data.cast<Arc<ExecutorWake>>()).get().reactor
    }
    (raw.vtable.release)(raw.data)
    present(reactor)
}

// The executor and handles cannot cross threads. Its registry owns every
// active task until the unique poll has returned and the future and erased
// result report have been removed. The scoped entry additionally proves that
// every input and output region outlives the scope. A foreign waker owns an
// Arc<Task> but only takes the queue lock: it never dereferences the erased
// payload. The queue lock orders close/finish against enqueue, and the atomic
// flags publish completion to handles. Thus a wake retained after scope exit
// can retain metadata but cannot touch borrowed storage.
// The retained Shared reference also keeps its C reactor handle alive until
// the last executor, task, and executor waker has been dropped.
unsafe extend Shared implements Transferable {}
unsafe extend Shared implements Shareable {}
unsafe extend Task implements Transferable {}
unsafe extend Task implements Shareable {}

extend Task implements Wake {
    fn wake(me: read Arc<Task>): Unit {
        let hub = self.hub.get()
        let locked = capture hub.queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if !guard.get().closed && self.active.load(core.sync.atomic.Ordering.Acquire) &&
           !self.queued.swap(true, core.sync.atomic.Ordering.AcqRel) {
            guard.get_mut().items.push_back(leak_task(me.retain()))
            unsafe { sys.mettle_rt_reactor_wake(hub.reactor) }
        }
    }
}

// Registry ownership is independent of both a handle and queued wakes.
// Completed task metadata is retained until executor destruction.
pub type Executor {
    hub: Arc<Shared>
    tasks: core.cell.UnsafeCell<List<ptr<mut u8>>>
    drop {
        let _cancel = CancelRest(self.tasks.get())
        let hub = self.hub.get()
        {
            let locked = capture hub.queue.lock()
            var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
            guard.get_mut().closed = true
        }
        unsafe { sys.mettle_rt_reactor_wake(hub.reactor) }
        var more = true
        while more {
            match take next_task(hub, false) {
                present(task) => {},
                none => { more = false }
            }
        }
    }
}
extend Executor not Transferable
extend Executor not Shareable

// The nested guard continues cancelling the remaining registrations if a
// future destructor unwinds. A second panic during unwinding aborts.
type CancelRest {
    tasks: ptr<mut List<ptr<mut u8>>>
    drop {
        let remaining = CancelRest(self.tasks)
        var more = true
        while more {
            let next = unsafe { (*self.tasks).pop() }
            match take next {
                present(raw) => {
                    let task = reclaim_task(raw)
                    cancel(read task)
                },
                none => { more = false }
            }
        }
        core.mem.forget(take remaining)
    }
}

pub fn executor(): Executor {
    let queue = Queue(package.alloc.vec_deque.new<ptr<mut u8>>(), false)
    let reactor = unsafe { sys.mettle_rt_reactor_new() }
    if reactor == core.ptr.null_mut<u8>() {
        package.core.panic.panic("async reactor creation failed")
    }
    Executor(arc.new(Shared(mutex.new(queue), reactor,
                             core.sync.atomic.AtomicUsize.new(0usize),
                             core.sync.atomic.AtomicBool.new(false))),
             core.cell.UnsafeCell.new(package.alloc.vec.new<ptr<mut u8>>()))
}

fn erase<T, F: Future<Output = T>>(future: take F, result: take Arc<ResultSlot<T>>): ErasedFuture {
    let report = boxed.new(result.retain()).into_raw()
    let storage = boxed.new(Packet(future, result)).into_raw()
    ErasedFuture(storage.0.cast<u8>(), poll_erased<T, F>, release_erased<T, F>,
                 present(ErasedReport(report.0.cast<u8>(), fail_erased<T>, release_report<T>)))
}
fn new_task(erased: take ErasedFuture, hub: take Arc<Shared>): Arc<Task> {
    arc.new(Task(mutex.new(present(erased)), core.sync.atomic.AtomicBool.new(false),
                  core.sync.atomic.AtomicBool.new(true),
                  core.sync.atomic.AtomicBool.new(false),
                  core.sync.atomic.AtomicBool.new(false),
                  core.sync.atomic.AtomicBool.new(false),
                  core.sync.atomic.AtomicBool.new(false), hub))
}

extend Executor {
    // Private callers must require either Transferable + Static or Within
    // bounds, and must retain the registration until destruction completes.
    fn spawn_inner<T, F: Future<Output = T>>(future: take F): JoinHandle<T> {
        {
            let locked = capture self.hub.get().queue.lock()
            let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
            if guard.get().closed { panic("cannot spawn on a closed executor") }
        }
        let result = arc.new(ResultSlot(mutex.new(ResultState<T>(none, 0u8, 0))))
        let task = new_task(erase(future, result.retain()), self.hub.retain())
        unsafe { (*self.tasks.get()).push(leak_task(task.retain())) }
        let old = self.hub.get().live.fetch_add(1usize, core.sync.atomic.Ordering.AcqRel)
        if old == 0xffffffffffffffffusize { core.intrinsics.abort() }
        task.get().wake(read task)
        JoinHandle(task, result)
    }

    // Owned tasks and their results must be safe to retain independently.
    pub fn spawn<T: Transferable + Static, F: Future<Output = T> + Transferable + Static>(future: take F): JoinHandle<T> {
        self.spawn_inner(future)
    }

    // Number of spawned futures that have not completed.
    pub fn pending(): usize { self.hub.get().live.load(core.sync.atomic.Ordering.Acquire) }

    // Runs until every spawned future has completed, blocking while tasks wait
    // for a wake.
    pub fn run(): Unit {
        var finished = false
        while !finished {
            match take next_task(self.hub.get(), true) {
                present(task) => { let _polled = poll_task(task) },
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
            match take next_task(self.hub.get(), false) {
                present(task) => { if poll_task(task) { polls += 1usize } },
                none => { finished = true }
            }
        }
        polls
    }
}

fn next_task(hub: read Shared, block: bool): Arc<Task>? {
    loop {
        var next: ptr<mut u8>? = none
        var closed = false
        {
            let locked = capture hub.queue.lock()
            var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
            next = guard.get_mut().items.pop_front()
            closed = guard.get().closed
        }
        match take next {
            present(raw) => { return present(reclaim_task(raw)) },
            none => {}
        }
        if !block || closed ||
           hub.live.load(core.sync.atomic.Ordering.Acquire) == 0usize {
            return none
        }
        if unsafe { sys.mettle_rt_reactor_wait(hub.reactor) } < 0 {
            package.core.panic.panic("async reactor wait failed")
        }
    }
}

// Lock order is future then queue. Wake takes only queue; the queue lock
// serializes close/completion against enqueue. Drop payloads after unlocking.
fn finish_task(task: read Arc<Task>): Unit {
    let hub = task.get().hub.get()
    let locked = capture hub.queue.lock()
    var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    task.get().finalizing.store(true, core.sync.atomic.Ordering.Release)
    task.get().active.store(false, core.sync.atomic.Ordering.Release)
    let _old = hub.live.fetch_sub(1usize, core.sync.atomic.Ordering.AcqRel)
    unsafe { sys.mettle_rt_reactor_wake(hub.reactor) }
}

fn cancel(task: read Arc<Task>): Unit {
    // A task can drop its own local handle during poll. Its payload cannot be
    // destroyed until that exclusive poll has returned.
    if task.get().polling.load(core.sync.atomic.Ordering.Acquire) {
        task.get().cancel_requested.store(true, core.sync.atomic.Ordering.Release)
        return ()
    }
    var removed: ErasedFuture? = none
    {
        let locked = capture task.get().future.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        var active = false
        match mut guard.get_mut() {
            present(slot) => { active = true },
            none => {}
        }
        if active {
            removed = guard.get_mut().take_value()
            finish_task(task)
        }
    }
    match take removed {
        present(future) => {
            dispose(future, 0, true)
            task.get().finished.store(true, core.sync.atomic.Ordering.Release)
            task.get().finalizing.store(false, core.sync.atomic.Ordering.Release)
        },
        none => {}
    }
}

fn poll_task(task: take Arc<Task>): bool {
    task.get().queued.store(false, core.sync.atomic.Ordering.Release)
    var waker = executor_waker(
        WakeTarget.Task(task.retain()), task.get().hub.get().reactor
    )
    var removed: ErasedFuture? = none
    var panic_code = 0
    var cancelled = false
    var polled = false
    {
        let locked = capture task.get().future.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        var finished = false
        match mut guard.get_mut() {
            present(slot) => {
                polled = true
                var call = PollCall(core.ptr.from_mut(slot), core.ptr.from_mut(waker), false)
                task.get().polling.store(true, core.sync.atomic.Ordering.Release)
                task.get().hub.get().polling.store(true, core.sync.atomic.Ordering.Release)
                let action: fn(ptr<mut u8>): Unit = poll_call
                let body = unsafe { core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(action) }
                let code = unsafe { mettle_rt_catch(core.ptr.from_mut(call).cast<u8>(), body) }
                task.get().hub.get().polling.store(false, core.sync.atomic.Ordering.Release)
                task.get().polling.store(false, core.sync.atomic.Ordering.Release)
                cancelled = task.get().cancel_requested.load(core.sync.atomic.Ordering.Acquire)
                if code != 0 { panic_code = code; finished = true } else { finished = call.ready || cancelled }
            },
            none => {}
        }
        if finished {
            removed = guard.get_mut().take_value()
            finish_task(read task)
        }
    }
    match take removed {
        present(future) => {
            dispose(future, panic_code, cancelled)
            task.get().finished.store(true, core.sync.atomic.Ordering.Release)
            task.get().finalizing.store(false, core.sync.atomic.Ordering.Release)
        },
        none => {}
    }
    polled
}

// Handles are local to the executor thread. Forgetting one leaks its reference,
// but does not remove the executor's registration or permit a scoped escape.
pub type JoinHandle<T> {
    task: Arc<Task>
    result: Arc<ResultSlot<T>>
    drop { cancel(read self.task) }
}
extend<T> JoinHandle<T> not Transferable
extend<T> JoinHandle<T> not Shareable

extend<T> JoinHandle<T> {
    pub fn abort(): Unit { cancel(read self.task) }
    pub fn is_finished(): bool { self.task.get().finished.load(core.sync.atomic.Ordering.Acquire) }

    // Drives this executor until the task completes or has been cancelled.
    pub take fn join(): T throws JoinError {
        if !self.is_finished() &&
           (self.task.get().finalizing.load(core.sync.atomic.Ordering.Acquire) ||
            self.task.get().hub.get().polling.load(core.sync.atomic.Ordering.Acquire)) {
            panic("cannot join an active executor from one of its tasks")
        }
        while !self.is_finished() {
            match take next_task(self.task.get().hub.get(), true) {
                present(task) => { let _polled = poll_task(task) },
                none => { break }
            }
        }
        let locked = capture self.result.get().state.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        let status = guard.get().status
        if status == 1u8 { return guard.get_mut().value.take_value().unwrap() }
        if status == 3u8 { throw JoinError.Panicked(guard.get().code) }
        throw JoinError.Cancelled
    }
}

// A synchronous, local scope executes ready child polls before returning and
// cancels suspended children. No poll can remain active after scope returns.
pub type Scope<region s> {
    executor: Executor
    brand: core.cell.Cell<Brand<region s>>
}
extend<region s> Scope<region s> not Transferable
extend<region s> Scope<region s> not Shareable

extend<region s> Scope<region s> {
    pub fn spawn<T: Within<region s>, F: Future<Output = T> + Within<region s>>(receiver self: read Scope<region s> from s, future: take F): JoinHandle<T> {
        self.executor.spawn_inner(future)
    }
}

pub fn scope<R, F: for<region s> fn(read Scope<region s>): R>(f: take F): R {
    let state = Scope(executor(), core.cell.Cell.new(Brand(0u8)))
    let result = f(read state)
    let _polls = state.executor.run_until_stalled()
    result
}
