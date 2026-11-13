// expect-exit: 0
// Evidence for the V1 Condition and Barrier operations. Waits are checked for
// predicate handoff across threads, expiry and immediate return; barrier
// rounds are checked for exactly one leader per round.
import std.thread
import std.time
import std.sync.{ barrier, condition, mutex }
import alloc.arc
import core.clone.Clone
import core.default.Default

fn default_value<T: Default>(): T { T.(Default).default() }

// wait_while blocks until another thread publishes the flag, then notify_all
// wakes every waiter; notify_one and default construction are exercised too.
fn checks_condvar_handoff(): i32 {
    let state = arc.new(mutex.new(false))
    let signal = arc.new(condition.new())
    var waiters = alloc.vec.new<thread.JoinHandle<i32>>()
    var spawned = 0
    while spawned < 2 {
        let worker_state = state.retain()
        let worker_signal = signal.retain()
        // the first waiter loops on wait directly; the second uses wait_while
        let by_loop = spawned == 0
        waiters.push(thread.spawn(take fn(): i32 {
            let locked = capture worker_state.get().lock()
            var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
            if by_loop {
                while !*guard.get() {
                    let waited = capture worker_signal.get().wait(guard)
                    guard = match take waited { success(g) => g, failure(e) => e.into_inner() }
                }
            } else {
                let waited = capture worker_signal.get().wait_while(guard, fn(mut ready: bool): bool { !ready })
                guard = match take waited { success(g) => g, failure(e) => e.into_inner() }
            }
            if *guard.get() { 0 } else { 1 }
        }))
        spawned += 1
    }

    // waiters only depend on the flag, so the publish order is irrelevant
    let publisher = capture state.get().lock()
    var published = match take publisher { success(g) => g, failure(e) => e.into_inner() }
    *published.get_mut() = true
    signal.get().notify_one()
    signal.get().notify_all()
    core.mem.drop(published)

    var failures = 0
    while true {
        let next = waiters.pop()
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
    if failures != 0 { return 10 }

    // a wait that expires without a notification reports the timeout
    let idle_lock = mutex.new(0)
    let idle = capture idle_lock.lock()
    let idle_guard = match take idle { success(g) => g, failure(e) => e.into_inner() }
    let expired_result = capture signal.get().wait_timeout(idle_guard, time.from_nanos(0u64))
    let expired = match take expired_result { success(value) => value, failure(e) => e.into_inner() }
    if !expired.1.timed_out() { return 11 }
    core.mem.drop(expired.0)

    // wait_timeout_ms with a predicate that is already false returns at once
    let ready_lock = mutex.new(true)
    let ready_result = capture ready_lock.lock()
    let ready_guard = match take ready_result { success(g) => g, failure(e) => e.into_inner() }
    let immediate_result = capture signal.get().wait_timeout_while(ready_guard, time.from_nanos(60000000000u64),
        fn(mut ready: bool): bool { !ready })
    let immediate = match take immediate_result { success(value) => value, failure(e) => e.into_inner() }
    if immediate.1.timed_out() { return 12 }
    core.mem.drop(immediate.0)

    // a predicate that never clears times out
    let stuck_lock = mutex.new(false)
    let stuck = capture stuck_lock.lock()
    let stuck_guard = match take stuck { success(g) => g, failure(e) => e.into_inner() }
    let stuck_result = capture signal.get().wait_timeout_while(stuck_guard, time.from_nanos(0u64),
        fn(mut ready: bool): bool { !ready })
    let stuck_wait = match take stuck_result { success(value) => value, failure(e) => e.into_inner() }
    if !stuck_wait.1.timed_out() { return 13 }
    core.mem.drop(stuck_wait.0)

    let fallback = condition.new()
    let fallback_lock = mutex.new(0)
    let fallback_locked = capture fallback_lock.lock()
    let fallback_guard = match take fallback_locked { success(g) => g, failure(e) => e.into_inner() }
    let short_result = capture fallback.wait_timeout_ms(fallback_guard, 1u64)
    let short = match take short_result { success(value) => value, failure(e) => e.into_inner() }
    if !short.1.timed_out() { return 14 }
    core.mem.drop(short.0)
    let defaulted: condition.Condition = default_value<condition.Condition>()
    defaulted.notify_all()
    0
}

// Each round releases all parties together and exactly one of them is the
// leader; reusing the barrier across rounds keeps that property.
fn checks_barrier_rounds(): i32 {
    let gate = arc.new(barrier.new(3usize))
    var round = 0
    while round < 2 {
        var handles = alloc.vec.new<thread.JoinHandle<i32>>()
        var spawned = 0
        while spawned < 2 {
            let worker_gate = gate.retain()
            handles.push(thread.spawn(take fn(): i32 {
                if worker_gate.get().wait().is_leader() { 1 } else { 0 }
            }))
            spawned += 1
        }
        var leaders = if gate.get().wait().is_leader() { 1 } else { 0 }
        var collected = 0
        while true {
            let next = handles.pop()
            match take next {
                present(handle) => {
                    let joined = capture handle.join()
                    match take joined {
                        success(value) => { leaders += value },
                        failure(_) => { return 20 }
                    }
                    collected += 1
                },
                none => { break }
            }
        }
        if collected != 2 || leaders != 1 { return 21 }
        round += 1
    }

    // a single party is always the leader, and the result clones intact
    let solo = barrier.new(1usize)
    let result = solo.wait()
    let copied = result.clone()
    if !result.is_leader() || !copied.is_leader() { return 22 }

    let zero = barrier.new(0usize)
    var trivial_round = 0
    while trivial_round < 2 {
        if !zero.wait().is_leader() || !solo.wait().is_leader() { return 23 }
        trivial_round += 1
    }
    0
}

fn main(): i32 {
    let first = checks_condvar_handoff()
    if first != 0 { return first }
    checks_barrier_rounds()
}
