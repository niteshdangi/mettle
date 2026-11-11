import std.thread
import std.sync.{ barrier, condvar, mutex, rwlock }
import std.panic.{ catch_panic, CatchResult }
import alloc.arc

type DropProbe {
    drops: arc.Arc<core.sync.atomic.AtomicUsize>
    value: i32
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

fn main(): i32 {
    if !thread.current_thread().id().same(thread.current()) { return 17 }

    let state = arc.new(mutex.new(false))
    let changed = arc.new(condvar.new())
    let entered = arc.new(core.sync.atomic.AtomicBool.new(false))
    let worker_state = state.retain()
    let worker_changed = changed.retain()
    let worker_entered = entered.retain()
    let waiter = thread.spawn(take fn(): i32 {
        let locked = capture worker_state.get().lock()
        var guard = match take locked {
            success(value) => value,
            failure(error) => error.into_inner()
        }
        worker_entered.get().store(true, core.sync.atomic.Ordering.Release)
        var checks = 0
        let waited = capture worker_changed.get().wait_while(
            guard,
            fn(mut ready: bool): bool {
                checks += 1
                !ready
            }
        )
        guard = match take waited { success(value) => value, failure(e) => e.into_inner() }
        if !*guard.get() || checks < 2 { return 1 }
        0
    })

    while !entered.get().load(core.sync.atomic.Ordering.Acquire) {
        thread.yield_now()
    }
    let locked = capture state.get().lock()
    var guard = match take locked {
        success(value) => value,
        failure(error) => error.into_inner()
    }
    *guard.get_mut() = true
    changed.get().notify_one()
    core.mem.drop(guard)
    let joined = capture waiter.join()
    match take joined {
        success(value) => { if value != 0 { return 1 } },
        failure(error) => { return 2 }
    }

    var timeout_checks = 0
    let timeout_lock = mutex.new(false)
    let timeout_locked = capture timeout_lock.lock()
    let timeout_guard = match take timeout_locked {
        success(value) => value,
        failure(error) => error.into_inner()
    }
    let timed_result = capture changed.get().wait_timeout(
        timeout_guard, std.time.from_nanos(0u64)
    )
    let timed = match take timed_result { success(value) => value, failure(e) => e.into_inner() }
    let timed_out = timed.1.timed_out()
    core.mem.drop(timed.0)
    if !timed_out { return 3 }

    let timeout_locked = capture timeout_lock.lock()
    let timeout_guard = match take timeout_locked {
        success(value) => value,
        failure(error) => error.into_inner()
    }
    let waited_result = capture changed.get().wait_timeout_while(
        timeout_guard,
        std.time.from_nanos(0u64),
        fn(mut ready: bool): bool {
            timeout_checks += 1
            if timeout_checks == 1 {
                true
            } else {
                ready = true
                false
            }
        }
    )
    let waited = match take waited_result { success(value) => value, failure(e) => e.into_inner() }
    if waited.1.timed_out() || timeout_checks != 2 || !*waited.0.get() {
        return 3
    }

    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let lock = arc.new(mutex.new(DropProbe(drops.retain(), 5)))
    let panicking_lock = lock.retain()
    let panicker = thread.spawn(take fn(): i32 {
        let locked = capture panicking_lock.get().lock()
        var held = match take locked {
            success(value) => value,
            failure(error) => error.into_inner()
        }
        held.get_mut().value = 9
        panic("poison mutex")
    })
    let panic_result = capture panicker.join()
    if panic_result.is_success() || !lock.get().is_poisoned() { return 9 }
    let poisoned = capture lock.get().lock()
    match take poisoned {
        success(guard) => { return 10 },
        failure(error) => {
            let guard = error.into_inner()
            if guard.get().value != 9 { return 11 }
            core.mem.drop(guard)
        }
    }
    lock.get().clear_poison()
    let usable = capture lock.get().lock()
    match take usable {
        success(guard) => { core.mem.drop(guard) },
        failure(error) => { return 12 }
    }
    core.mem.drop(lock)
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 13 }

    var unique_mutex = mutex.new(40)
    let mutex_panic = catch_panic(fn(): Unit {
        let locked = capture unique_mutex.lock()
        let _guard = match take locked {
            success(value) => value,
            failure(error) => error.into_inner()
        }
        panic("poison mutex get_mut")
    })
    match mutex_panic {
        CatchResult.Panicked(info) => {},
        CatchResult.Returned(value) => { return 17 }
    }
    let mutable_mutex = capture unique_mutex.get_mut()
    match take mutable_mutex {
        success(value) => { return 18 },
        failure(error) => { *error.into_inner() = 41 }
    }
    unique_mutex.clear_poison()
    let mutable_mutex = capture unique_mutex.get_mut()
    match take mutable_mutex {
        success(value) => { if *value != 41 { return 19 } },
        failure(error) => { return 20 }
    }

    var unique_rwlock = rwlock.new(50)
    let rwlock_panic = catch_panic(fn(): Unit {
        let locked = capture unique_rwlock.writer()
        let _guard = match take locked {
            success(value) => value,
            failure(error) => error.into_inner()
        }
        panic("poison rwlock get_mut")
    })
    match rwlock_panic {
        CatchResult.Panicked(info) => {},
        CatchResult.Returned(value) => { return 21 }
    }
    let mutable_rwlock = capture unique_rwlock.get_mut()
    match take mutable_rwlock {
        success(value) => { return 22 },
        failure(error) => { *error.into_inner() = 51 }
    }
    unique_rwlock.clear_poison()
    let mutable_rwlock = capture unique_rwlock.get_mut()
    match take mutable_rwlock {
        success(value) => { if *value != 51 { return 23 } },
        failure(error) => { return 24 }
    }

    let read_lock = arc.new(rwlock.new(1))
    let reader_copy = read_lock.retain()
    let read_panicker = thread.spawn(take fn(): i32 {
        let locked = capture reader_copy.get().reader()
        let _guard = match take locked {
            success(value) => value,
            failure(error) => error.into_inner()
        }
        panic("read guard does not poison")
    })
    let read_result = capture read_panicker.join()
    if read_result.is_success() || read_lock.get().is_poisoned() { return 14 }

    let gate = arc.new(barrier.new(2usize))
    let child_gate = gate.retain()
    let child = thread.spawn(take fn(): i32 {
        if child_gate.get().wait().is_leader() { 1 } else { 0 }
    })
    let parent_leader = gate.get().wait().is_leader()
    let child_result = capture child.join()
    let child_leader = match take child_result {
        success(value) => value == 1,
        failure(error) => { return 15 }
    }
    if parent_leader == child_leader { return 16 }
    0
}
