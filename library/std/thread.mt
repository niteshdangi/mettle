// Owned and scoped threads over the hosted runtime's pthread shims.
//
// A spawned thread runs its closure and TLS cleanup under the runtime catch,
// so a panic ends only that thread and `join` reports it as `Panicked`. Owned
// threads need a Transferable, Static closure and result;
// scoped threads may borrow from the enclosing frame and are always joined
// before `scope` returns, also when the scope body panics.
import package.core.panic.panic
import package.alloc.string.String
import package.core.text.Text
import package.core.slice
import package.core.option
import package.std.time.Duration

extern "C" {
    unsafe fn mettle_rt_panicking(): i32;
    unsafe fn mettle_rt_thread_spawn_configured(
        entry: extern "C" fn(ptr<mut u8>): Unit,
        argument: ptr<mut u8>,
        handle: ptr<mut usize>,
        name: ptr<read u8>,
        name_length: usize,
        stack_size: usize
    ): i32;
    unsafe fn mettle_rt_thread_join(handle: usize): i32;
    unsafe fn mettle_rt_thread_detach(handle: usize): i32;
    unsafe fn mettle_rt_thread_current(): usize;
    unsafe fn mettle_rt_thread_park(): Unit;
    unsafe fn mettle_rt_thread_park_timeout(nanoseconds: u64): Unit;
    unsafe fn mettle_rt_thread_unpark(handle: usize): Unit;
    unsafe fn mettle_rt_thread_name(handle: usize, buffer: ptr<mut u8>, capacity: usize): isize;
    unsafe fn mettle_rt_thread_yield(): Unit;
    unsafe fn mettle_rt_thread_sleep(nanoseconds: u64): Unit;
    unsafe fn mettle_rt_thread_parallelism(): u64;
    unsafe fn mettle_rt_thread_catch(context: ptr<mut u8>, body: extern "C" fn(ptr<mut u8>): Unit): i32;
}

// The thread ended by panicking; `code` is the runtime's panic code.
pub copy type Panicked { pub code: i32 }
// The operating system refused to start a thread.
pub copy type SpawnError { pub code: i32 }

// Identity of a running thread.
pub copy type ThreadId { pub raw: usize }
pub copy type Thread { raw: usize }

pub fn current(): ThreadId { ThreadId(unsafe { mettle_rt_thread_current() }) }
pub fn current_thread(): Thread { Thread(unsafe { mettle_rt_thread_current() }) }
pub fn panicking(): bool { unsafe { mettle_rt_panicking() != 0 } }
pub fn yield_now(): Unit { unsafe { mettle_rt_thread_yield() } }
pub fn sleep_nanos(nanoseconds: u64): Unit { unsafe { mettle_rt_thread_sleep(nanoseconds) } }
pub fn sleep(duration: Duration): Unit { package.std.time.sleep(duration) }
pub fn sleep_ms(milliseconds: u64): Unit {
    sleep(package.std.time.from_millis(milliseconds))
}
pub fn park(): Unit { unsafe { mettle_rt_thread_park() } }
fn duration_nanos(duration: Duration): u64 {
    let value = duration.as_nanos()
    if value > 18446744073709551615u128 {
        18446744073709551615u64
    } else {
        value as u64
    }
}
pub fn park_timeout(duration: Duration): Unit {
    unsafe { mettle_rt_thread_park_timeout(duration_nanos(duration)) }
}
pub fn park_timeout_ms(milliseconds: u64): Unit {
    park_timeout(package.std.time.from_millis(milliseconds))
}
pub fn available_parallelism(): usize { unsafe { mettle_rt_thread_parallelism() as usize } }

extend ThreadId {
    pub fn same(other: ThreadId): bool { self.raw == other.raw }
}

extend Thread {
    pub fn id(): ThreadId { ThreadId(self.raw) }
    pub fn unpark(): Unit { unsafe { mettle_rt_thread_unpark(self.raw) } }
    pub fn name(): Text? {
        var buffer = [0u8; 64]
        let length = unsafe {
            mettle_rt_thread_name(self.raw, core.ptr.from_mut(buffer).cast<u8>(), 64usize)
        }
        if length < 0isize { return none }
        let bytes = unsafe {
            slice.subslice_unchecked(buffer, 0usize, length as usize)
        }
        package.core.text.from_utf8(bytes)
    }
}

pub type Builder {
    name: String?
    stack_size: usize
}

extend Builder {
    pub static fn new(): Builder { Builder(none, 0usize) }

    pub mut fn name(value: read Text): Unit {
        self.name = present(package.alloc.string.from_text(value))
    }

    pub mut fn stack_size(bytes: usize): Unit { self.stack_size = bytes }

    pub take fn spawn<T: Transferable + Static, F: fn(): T + Transferable + Static>(
        f: take F
    ): JoinHandle<T> throws SpawnError {
        let started = match self.name.as_view() {
            present(name) => unsafe {
                try start<T, F>(
                    f,
                    package.core.slice.data(name.as_bytes()),
                    name.as_bytes().len(),
                    self.stack_size
                )
            },
            none => unsafe {
                try start<T, F>(f, core.ptr.null<u8>(), 0usize, self.stack_size)
            }
        }
        JoinHandle(started.0, started.1)
    }

    pub take fn spawn_scoped<
        region s,
        T: Transferable,
        F: fn(): T + Transferable + Within<region s>
    >(
        scope: read Scope<region s> from s,
        f: take F
    ): ScopedJoinHandle<T> throws SpawnError {
        try scope.try_spawn_configured(read self, f)
    }
}

// Non-generic part shared by the spawner and the thread. Two owners (the
// thread and its handle or scope) release it; the last one frees the generic
// state through `release`.
type Header {
    run: fn(ptr<mut u8>): Unit
    release: fn(ptr<mut u8>): Unit
    data: ptr<mut u8>
    refs: core.sync.atomic.AtomicU32
    code: i32
    thread: usize
    joined: core.sync.atomic.AtomicBool
    finished: core.sync.atomic.AtomicBool
}

// The closure waiting to run; dropped by `release` if it never started.
type Packet<F, T> {
    f: core.mem.MaybeUninit<F>
    started: bool
    slot: ptr<mut Slot<T>>
}

// Where the thread leaves its result.
type Slot<T> {
    filled: bool
    value: core.mem.MaybeUninit<T>
}

fn run_packet<T, F: fn(): T>(data: ptr<mut u8>): Unit {
    unsafe {
        let packet = data.cast<Packet<F, T>>()
        let f = core.ptr.`read`((*packet).f.as_ptr())
        (*packet).started = true
        let result = f()
        let slot = (*packet).slot
        core.ptr.write((*slot).value.as_mut_ptr(), result)
        (*slot).filled = true
    }
}

fn release_packet<T, F: fn(): T>(data: ptr<mut u8>): Unit {
    unsafe {
        let packet = data.cast<Packet<F, T>>()
        if !(*packet).started { core.ptr.drop_in_place((*packet).f.as_mut_ptr()) }
        let slot = (*packet).slot
        if (*slot).filled { core.ptr.drop_in_place((*slot).value.as_mut_ptr()) }
        let _slot = package.alloc.boxed.from_raw_in(slot, package.alloc.alloc.Global())
        let _packet = package.alloc.boxed.from_raw_in(packet, package.alloc.alloc.Global())
    }
}

// Drops one reference; the last one frees the shared state.
unsafe fn release(header: ptr<mut Header>): Unit {
    if (*header).refs.fetch_sub(1u32, core.sync.atomic.Ordering.AcqRel) == 1u32 {
        let release_data = (*header).release
        release_data((*header).data)
        let _header = package.alloc.boxed.from_raw_in(header, package.alloc.alloc.Global())
    }
}

// Runs the closure and then its TLS destructors under runtime catch
// boundaries, so a panic stays on this thread; records its code and drops
// its reference.
extern "C" fn thread_entry(raw: ptr<mut u8>): Unit {
    unsafe {
        let header = raw.cast<Header>()
        let run = (*header).run
        let body = core.mem.transmute<extern "C" fn(ptr<mut u8>): Unit>(run)
        (*header).code = mettle_rt_thread_catch((*header).data, body)
        (*header).finished.store(true, core.sync.atomic.Ordering.Release)
        release(header)
    }
}

// Allocates the shared state and starts the thread; on failure everything is
// released again and the closure is dropped.
unsafe fn start<T, F: fn(): T>(
    f: take F,
    name: ptr<read u8>,
    name_length: usize,
    stack_size: usize
): (ptr<mut Header>, ptr<mut Slot<T>>) throws SpawnError {
    let slot = package.alloc.boxed.new(Slot<T>(false, core.mem.MaybeUninit<T>.uninit())).into_raw().0
    let packet = package.alloc.boxed.new(Packet<F, T>(core.mem.MaybeUninit.new(f), false, slot)).into_raw().0
    let header = package.alloc.boxed.new(Header(run_packet<T, F>, release_packet<T, F>, packet.cast<u8>(),
                                          core.sync.atomic.AtomicU32.new(2u32), 0,
                                          0usize, core.sync.atomic.AtomicBool.new(false),
                                          core.sync.atomic.AtomicBool.new(false))).into_raw().0
    var thread = 0usize
    let status = mettle_rt_thread_spawn_configured(
        thread_entry,
        header.cast<u8>(),
        core.ptr.from_mut(thread),
        name,
        name_length,
        stack_size
    )
    if status != 0 {
        release(header)
        release(header)
        throw SpawnError(status)
    }
    (*header).thread = thread
    (header, slot)
}

// Owner of a running thread; dropping it detaches the thread.
pub type JoinHandle<T> {
    header: ptr<mut Header>
    slot: ptr<mut Slot<T>>
    drop {
        unsafe {
            let _detached = mettle_rt_thread_detach((*self.header).thread)
            release(self.header)
        }
    }
}
unsafe extend<T: Transferable> JoinHandle<T> implements Transferable {}
unsafe extend<T: Transferable> JoinHandle<T> implements Shareable {}

pub fn try_spawn<T: Transferable + Static, F: fn(): T + Transferable + Static>(f: take F): JoinHandle<T> throws SpawnError {
    try Builder.new().spawn(f)
}

pub fn spawn<T: Transferable + Static, F: fn(): T + Transferable + Static>(f: take F): JoinHandle<T> {
    let outcome = capture try_spawn<T, F>(f)
    match take outcome {
        success(handle) => handle,
        failure(error) => panic("failed to spawn a thread")
    }
}

unsafe fn finish<T>(header: ptr<mut Header>, slot: ptr<mut Slot<T>>): T throws Panicked {
    let _joined = mettle_rt_thread_join((*header).thread)
    (*header).joined.store(true, core.sync.atomic.Ordering.Release)
    if (*header).code != 0 || !(*slot).filled { throw Panicked((*header).code) }
    (*slot).filled = false
    core.ptr.`read`((*slot).value.as_ptr())
}

extend<T> JoinHandle<T> {
    pub fn thread(): Thread { Thread(unsafe { (*self.header).thread }) }
    pub fn is_finished(): bool {
        unsafe { (*self.header).finished.load(core.sync.atomic.Ordering.Acquire) }
    }

    // Waits for the thread; a panic on it is reported, not propagated.
    pub take fn join(): T throws Panicked {
        let header = self.header
        let slot = self.slot
        core.mem.forget(take self)
        unsafe {
            let outcome = capture finish(header, slot)
            release(header)
            match take outcome { success(value) => value, failure(error) => throw error }
        }
    }
    pub fn id(): ThreadId { ThreadId(unsafe { (*self.header).thread }) }
    pub fn is_finished(): bool {
        unsafe { (*self.header).finished.load(core.sync.atomic.Ordering.Acquire) }
    }
}

// Everything a type borrows outlives the region `r`. The compiler enforces it
// where the bound is declared; any type satisfies the interface itself.
pub interface Within<region r> {}
extend<region r, F> F implements Within<region r> {}

// Names the scope's region; the cell around it makes that region invariant.
pub copy type Brand<region s> { pub unused: u8 }

// Threads started inside `scope`. It is neither Transferable nor Shareable
// (its cell opts out), so every spawn and join happens on the scoping thread.
// `s` ends when the scope closure returns, so a spawned closure may borrow
// only what outlives it, never a local of the scope body.
pub type Scope<region s> {
    threads: core.cell.UnsafeCell<package.alloc.vec.List<ptr<mut Header>>>
    brand: core.cell.Cell<Brand<region s>>
}

// Joins every thread of the scope when dropped, so the borrows they hold end
// before `scope` returns even if the scope body panics.
type ScopeGuard<region r, region s> {
    scope: read Scope<region s> from r
    panicked: bool
    drop {
        unsafe {
            var failed = false
            let list = self.scope.threads.get()
            var more = true
            while more {
                let next = (*list).pop()
                match take next {
                    present(header) => {
                        if !(*header).joined.load(core.sync.atomic.Ordering.Acquire) {
                            let _joined = mettle_rt_thread_join((*header).thread)
                            (*header).joined.store(true, core.sync.atomic.Ordering.Release)
                            if (*header).code != 0 { failed = true }
                        }
                        release(header)
                    },
                    none => { more = false }
                }
            }
            if failed && mettle_rt_panicking() == 0 { panic("a scoped thread panicked") }
        }
    }
}

// Owner of a scoped thread's result; confined to the scoping thread.
pub type ScopedJoinHandle<T> {
    header: ptr<mut Header>
    slot: ptr<mut Slot<T>>
    drop { unsafe { release(self.header) } }
}
extend<T> ScopedJoinHandle<T> not Transferable
extend<T> ScopedJoinHandle<T> not Shareable

extend<T> ScopedJoinHandle<T> {
    pub take fn join(): T throws Panicked {
        let header = self.header
        let slot = self.slot
        core.mem.forget(take self)
        unsafe {
            let outcome = capture finish(header, slot)
            release(header)
            match take outcome { success(value) => value, failure(error) => throw error }
        }
    }
    pub fn is_finished(): bool {
        unsafe { (*self.header).finished.load(core.sync.atomic.Ordering.Acquire) }
    }
}

extend<region s> Scope<region s> {
    fn try_spawn_configured<
        T: Transferable,
        F: fn(): T + Transferable + Within<region s>
    >(
        receiver self: read Scope<region s> from s,
        config: read Builder,
        f: take F
    ): ScopedJoinHandle<T> throws SpawnError {
        unsafe { (*self.threads.get()).reserve(1usize) }
        let started = match config.name.as_view() {
            present(name) => unsafe {
                try start<T, F>(
                    f,
                    package.core.slice.data(name.as_bytes()),
                    name.as_bytes().len(),
                    config.stack_size
                )
            },
            none => unsafe {
                try start<T, F>(f, core.ptr.null<u8>(), 0usize, config.stack_size)
            }
        }
        let header = started.0
        let slot = started.1
        unsafe {
            // refs: thread, handle and scope list
            (*header).refs.fetch_add(1u32, core.sync.atomic.Ordering.Relaxed)
            (*self.threads.get()).push(header.cast<Header>())
        }
        ScopedJoinHandle(header, slot)
    }

    // Starts a thread that may borrow from the enclosing frame.
    pub fn spawn<
        T: Transferable,
        F: fn(): T + Transferable + Within<region s>
    >(
        receiver self: read Scope<region s> from s,
        f: take F
    ): ScopedJoinHandle<T> {
        let outcome = capture self.try_spawn_configured(Builder.new(), f)
        match take outcome {
            success(handle) => handle,
            failure(error) => panic("failed to spawn a thread")
        }
    }
}

pub fn scope<R, F: for<region s> fn(read Scope<region s>): R>(f: take F): R {
    let state = Scope(core.cell.UnsafeCell.new(package.alloc.vec.new<ptr<mut Header>>()), core.cell.Cell.new(Brand(0u8)))
    let guard = ScopeGuard(read state, false)
    f(read state)
}
