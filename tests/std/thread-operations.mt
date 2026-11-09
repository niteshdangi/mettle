// Thread spawn, join, builder names, scoped threads, identity, park/unpark and panics.
import std.io.{Error}
import std.thread
import std.time.from_millis

fn run(): i32 throws Error {
    if thread.panicking() { return 1 }
    let handle = thread.spawn(take fn(): i32 { 17 })
    var waits = 0
    while !handle.is_finished() {
        thread.yield_now()
        waits += 1
        if waits > 10000000 { return 2 }
    }
    let joined = capture handle.join()
    match take joined {
        success(value) => { if value != 17 { return 3 } },
        failure(_) => { return 3 }
    }

    let crashed = thread.spawn(take fn(): i32 { panic("worker failed") })
    let crash = capture crashed.join()
    match take crash {
        success(_) => { return 4 },
        failure(_) => {}
    }

    var config = thread.Builder.new()
    config.name("named worker")
    let named = capture config.spawn(take fn(): i32 { 5 })
    match take named {
        success(child) => {
            match child.thread().name() {
                present(name) => { if name.len() != 12usize { return 5 } },
                none => { return 5 }
            }
            let result = capture child.join()
            match take result {
                success(v) => { if v != 5 { return 6 } },
                failure(_) => { return 6 }
            }
        },
        failure(_) => { return 5 }
    }

    let me = thread.current()
    if !me.same(thread.current()) { return 7 }
    let worker_id = thread.spawn(take fn(): usize { thread.current().raw }).id()
    if worker_id.same(me) { return 8 }
    let here = thread.current_thread()
    if !here.id().same(me) { return 9 }

    // Scoped threads borrow locals and finish before `scope` returns.
    let base = 20
    let total = thread.scope(fn(read s: thread.Scope): i32 {
        let left = s.spawn(fn(): i32 { base + 1 })
        let right = s.spawn(fn(): i32 { base + 2 })
        let a = capture left.join()
        let b = capture right.join()
        var sum = 0
        match take a {
            success(v) => { sum += v },
            failure(_) => { return -1 }
        }
        match take b {
            success(v) => { sum += v },
            failure(_) => { return -1 }
        }
        sum
    })
    if total != 43 { return 10 }

    thread.sleep(from_millis(1u64))
    thread.sleep_ms(1u64)
    thread.sleep_nanos(1000u64)
    thread.park_timeout_ms(1u64)
    thread.current_thread().unpark()
    thread.park()
    if thread.available_parallelism() == 0usize { return 11 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
