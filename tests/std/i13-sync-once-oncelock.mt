// expect-exit: 0
// Evidence for the V1 Once and OnceLock operations. Initialization runs once
// across racing threads, a panicking initializer poisons Once until a forced
// call succeeds, and OnceLock values are read, replaced, taken and dropped
// exactly once.
import std.thread
import std.sync.{ once, once_lock }
import std.panic.{ catch_panic, CatchResult }
import alloc.arc
import core.clone.Clone
import core.cmp.{ Eq, PartialEq }
import core.convert.From
import core.default.Default

type Counted {
    drops: arc.Arc<core.sync.atomic.AtomicUsize>
    value: i32
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

fn default_value<T: Default>(): T { T.(Default).default() }
fn from_value<T: From<i32>>(value: i32): T { T.(From<i32>).from(value) }

// Many threads race call_once; the initializer body runs once and every
// caller returns after it finished. is_completed reports the result.
fn checks_once_across_threads(): i32 {
    let gate = arc.new(once.new())
    let runs = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    if gate.get().is_completed() { return 10 }
    var handles = alloc.vec.new<thread.JoinHandle<i32>>()
    var spawned = 0
    while spawned < 4 {
        let worker_gate = gate.retain()
        let worker_runs = runs.retain()
        handles.push(thread.spawn(take fn(): i32 {
            worker_gate.get().call_once(fn(): Unit {
                let _previous = worker_runs.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
            })
            if !worker_gate.get().is_completed() { 1 } else { 0 }
        }))
        spawned += 1
    }
    var failures = 0
    while true {
        let next = handles.pop()
        match take next {
            present(handle) => {
                let joined = capture handle.join()
                match take joined {
                    success(code) => { failures += code },
                    failure(_) => { failures += 1 }
                }
            },
            none => { break }
        }
    }
    if failures != 0 { return 11 }
    if runs.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 12 }
    gate.get().wait()
    gate.get().wait_force()
    0
}

// A panicking initializer poisons Once: later call_once panics, and only a
// forced call sees the poisoned state and completes the cell.
fn checks_once_poison_and_force(): i32 {
    let gate = once.new()
    let first = catch_panic(fn(): Unit {
        gate.call_once(fn(): Unit { panic("once initializer failed") })
    })
    match first {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 20 }
    }
    if gate.is_completed() { return 21 }
    let refused = catch_panic(fn(): Unit {
        gate.call_once(fn(): Unit {})
    })
    match refused {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 22 }
    }
    let saw_poison = arc.new(core.sync.atomic.AtomicBool.new(false))
    gate.call_once_force(fn(state: once.OnceState): Unit {
        saw_poison.get().store(state.is_poisoned(), core.sync.atomic.Ordering.SeqCst)
    })
    if !saw_poison.get().load(core.sync.atomic.Ordering.SeqCst) || !gate.is_completed() { return 23 }
    gate.wait_force()
    // the completed cell now ignores further initializers
    let reran = arc.new(core.sync.atomic.AtomicBool.new(false))
    gate.call_once(fn(): Unit { reran.get().store(true, core.sync.atomic.Ordering.SeqCst) })
    if reran.get().load(core.sync.atomic.Ordering.SeqCst) { return 24 }
    let defaulted: once.Once = default_value<once.Once>()
    if defaulted.is_completed() { return 25 }
    0
}

// OnceLock: set once, read, mutate, take and replace under exclusive access.
fn checks_oncelock_single_thread(): i32 {
    var cell = once_lock.new<i32>()
    if cell.get().is_present() { return 30 }
    let first = capture cell.set(40)
    match take first { success(_) => {}, failure(_) => { return 31 } }
    let second = capture cell.set(41)
    match take second {
        success(_) => { return 32 },
        failure(refused) => { if refused.into_inner() != 41 { return 33 } }
    }
    match cell.get() {
        present(value) => { if *value != 40 { return 34 } },
        none => { return 35 }
    }
    match take cell.get_mut() {
        present(value) => { *value = 42 },
        none => { return 36 }
    }
    if *cell.get().unwrap() != 42 { return 37 }
    match cell.get() {
        present(value) => { if *value != 42 { return 38 } },
        none => { return 39 }
    }
    let taken = cell.`take`()
    match taken {
        present(value) => { if value != 42 { return 43 } },
        none => { return 44 }
    }
    if cell.get().is_present() { return 45 }
    if cell.`take`().is_present() { return 46 }

    let lazy = once_lock.new<i32>()
    let initialized = *lazy.get_or_init(fn(): i32 { 50 })
    if initialized != 50 { return 47 }
    if *lazy.get_or_init(fn(): i32 { 99 }) != 50 { return 48 }
    if *lazy.wait() != 50 { return 49 }
    match lazy.into_inner() {
        present(value) => { if value != 50 { return 60 } },
        none => { return 61 }
    }

    let built: once_lock.OnceLock<i32> = from_value<once_lock.OnceLock<i32>>(70)
    if *built.get().unwrap() != 70 { return 62 }
    let defaulted: once_lock.OnceLock<i32> = default_value<once_lock.OnceLock<i32>>()
    if defaulted.get().is_present() { return 63 }
    let copied = built.clone()
    if *copied.get().unwrap() != 70 { return 64 }
    if !(copied == built) { return 65 }
    0
}

// get_or_init races across threads: the initializer runs exactly once and
// readers wait for the stored value.
fn checks_oncelock_threads_and_drop(): i32 {
    let cell = arc.new(once_lock.new<i32>())
    let calls = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var handles = alloc.vec.new<thread.JoinHandle<i32>>()
    var spawned = 0
    while spawned < 4 {
        let worker_cell = cell.retain()
        let worker_calls = calls.retain()
        handles.push(thread.spawn(take fn(): i32 {
            let value = *worker_cell.get().get_or_init(fn(): i32 {
                let _previous = worker_calls.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
                9
            })
            if value == 9 { 0 } else { 1 }
        }))
        spawned += 1
    }
    var failures = 0
    while true {
        let next = handles.pop()
        match take next {
            present(handle) => {
                let joined = capture handle.join()
                match take joined {
                    success(code) => { failures += code },
                    failure(_) => { failures += 1 }
                }
            },
            none => { break }
        }
    }
    if failures != 0 { return 70 }
    if calls.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 71 }
    if *cell.get().wait() != 9 { return 72 }

    // a reader thread blocks in wait until another thread stores the value
    let late = arc.new(once_lock.new<i32>())
    let reader = late.retain()
    let waiter = thread.spawn(take fn(): i32 {
        if *reader.get().wait() == 33 { 0 } else { 1 }
    })
    let setter = capture late.get().set(33)
    match take setter { success(_) => {}, failure(_) => { return 73 } }
    let waited = capture waiter.join()
    match take waited {
        success(code) => { if code != 0 { return 74 } },
        failure(_) => { return 75 }
    }

    // dropping an initialized OnceLock drops its value once
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    {
        let owned = once_lock.new<Counted>()
        let stored = capture owned.set(Counted(drops.retain(), 1))
        match take stored { success(_) => {}, failure(_) => { return 76 } }
    }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 77 }
    {
        let _empty = once_lock.new<Counted>()
    }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 78 }
    0
}

fn main(): i32 {
    let first = checks_once_across_threads()
    if first != 0 { return first }
    let second = checks_once_poison_and_force()
    if second != 0 { return second }
    let third = checks_oncelock_single_thread()
    if third != 0 { return third }
    checks_oncelock_threads_and_drop()
}
