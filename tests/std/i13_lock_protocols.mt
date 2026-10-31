import std.sync.{mutex, rwlock, condvar, once, barrier, mpsc}
import core.convert.From
import core.ops.{Deref, DerefMut}
import core.fmt
import core.fmt.{Debug, Display}
import alloc.string

fn debug<T: Debug>(value: read T): string.String throws fmt.Error {
    var output = string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        try T.(Debug).fmt(value, mut formatter)
    }
    output
}

fn display<T: Display>(value: read T): string.String throws fmt.Error {
    var output = string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        try T.(Display).fmt(value, mut formatter)
    }
    output
}

fn check(): i32 throws fmt.Error {
    let lock = mutex.Mutex<i32>.(From<i32>).`from`(41)
    if (try debug(lock)).as_text() != "Mutex { data: 41, poisoned: false }" { return 1 }
    {
        let acquired = capture lock.lock()
        var guard = match take acquired { success(g) => g, failure(e) => e.into_inner() }
        *guard.deref_mut() += 1
        if *guard.deref() != 42 { return 2 }
        if (try display(guard)).as_text() != "42" { return 3 }
        if (try debug(guard)).as_text() != "42" { return 4 }
        // Formatting a lock held by this thread must return without relocking.
        if !(try debug(lock)).as_text().contains("<locked>") { return 5 }
    }
    if (try debug(lock)).as_text() != "Mutex { data: 42, poisoned: false }" { return 6 }

    let shared = rwlock.RwLock<i32>.(From<i32>).`from`(7)
    {
        let acquired = capture shared.writer()
        var guard = match take acquired { success(g) => g, failure(e) => e.into_inner() }
        *guard.deref_mut() += 2
        if *guard.deref() != 9 { return 7 }
        if (try display(guard)).as_text() != "9" { return 8 }
        if (try debug(guard)).as_text() != "9" { return 9 }
        if !(try debug(shared)).as_text().contains("<locked>") { return 10 }
    }
    {
        let acquired = capture shared.reader()
        let guard = match take acquired { success(g) => g, failure(e) => e.into_inner() }
        if *guard.deref() != 9 { return 11 }
        if (try display(guard)).as_text() != "9" { return 12 }
        if (try debug(guard)).as_text() != "9" { return 13 }
    }
    if (try debug(shared)).as_text() != "RwLock { data: 9, poisoned: false }" { return 14 }
    let condition = condvar.new()
    let state = mutex.new(3)
    let acquired = capture state.lock()
    let guard = match take acquired { success(g) => g, failure(e) => e.into_inner() }
    var predicate_calls = 0
    let guard = condition.wait_while(guard, fn(value: mut i32): bool {
        predicate_calls += 1
        *value += 1
        false
    })
    if predicate_calls != 1 || *guard.get() != 4 { return 16 }
    let timed = condition.wait_timeout_while(guard, 0u64, fn(value: mut i32): bool {
        predicate_calls += 1
        *value += 1
        true
    })
    if predicate_calls != 2 || *timed.0.get() != 5 || !timed.1.timed_out() { return 17 }
    if (try debug(condition)).as_text() != "Condvar { .. }" { return 18 }
    let single = barrier.new(1usize)
    if (try debug(single)).as_text() != "Barrier { .. }" { return 19 }
    let initialize = once.new()
    if (try debug(initialize)).as_text() != "Once { completed: false }" { return 20 }
    initialize.call_once(fn(): Unit {})
    if (try debug(initialize)).as_text() != "Once { completed: true }" { return 21 }
    let channel = mpsc.channel<i32>()
    if (try debug(channel.0)).as_text() != "Sender { .. }" ||
       (try debug(channel.1)).as_text() != "Receiver { .. }" { return 22 }
    let bounded = mpsc.sync_channel<i32>(1usize)
    if (try debug(bounded.0)).as_text() != "SyncSender { .. }" { return 23 }
    0
}

fn main(): i32 {
    match capture check() { success(result) => result, failure(_) => 15 }
}
