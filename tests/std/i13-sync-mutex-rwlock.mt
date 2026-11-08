// expect-exit: 0
// Evidence for the V1 Mutex and RwLock operations and their guards. Lock
// results are checked on the success, WouldBlock and poisoned paths; poisoning
// is produced by a thread that panics while holding the guard.
import std.thread
import std.sync.{ mutex, rwlock }
import std.panic.{ catch_panic, CatchResult }
import alloc.arc
import core.convert.From
import core.default.Default

fn default_value<T: Default>(): T { T.(Default).default() }
fn from_value<T: From<i32>>(value: i32): T { T.(From<i32>).from(value) }

// Exclusive, same-thread locking: lock and try_lock report contention.
fn checks_mutex_guards(): i32 {
    let lock = mutex.new(10)
    let locked = capture lock.lock()
    var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    if *guard.get() != 10 { return 10 }
    *guard.get_mut() = 11
    if *guard.get() != 11 { return 11 }
    *guard.get_mut() = 12
    if *guard.get() != 12 { return 12 }
    let busy = capture lock.try_lock()
    match take busy {
        success(_) => { return 13 },
        failure(e) => match e {
            mutex.TryLockError.WouldBlock => {},
            mutex.TryLockError.Poisoned(_) => { return 14 }
        }
    }
    core.mem.drop(guard)
    let free = capture lock.try_lock()
    match take free {
        success(g) => { if *g.get() != 12 { return 15 } },
        failure(_) => { return 16 }
    }
    if lock.is_poisoned() { return 17 }
    0
}

// Constructors, Default and From build a mutex holding the given value.
fn checks_mutex_construction(): i32 {
    let defaulted: mutex.Mutex<i32> = default_value<mutex.Mutex<i32>>()
    let defaulted_value = capture defaulted.lock()
    match take defaulted_value {
        success(g) => { if *g.get() != 0 { return 20 } },
        failure(_) => { return 21 }
    }
    let converted: mutex.Mutex<i32> = from_value<mutex.Mutex<i32>>(7)
    let owned = capture converted.lock()
    match take owned {
        success(g) => { if *g.get() != 7 { return 22 } },
        failure(_) => { return 23 }
    }
    var unique = mutex.new(30)
    let value = capture unique.get_mut()
    match take value {
        success(v) => { *v = 31 },
        failure(_) => { return 24 }
    }
    let inner = capture unique.into_inner()
    match take inner {
        success(v) => { if v != 31 { return 25 } },
        failure(_) => { return 26 }
    }
    0
}

// A thread that panics inside the critical section poisons the mutex; the
// poisoned guard still carries the data, and clear_poison restores the lock.
fn checks_mutex_poison(): i32 {
    let shared_lock = arc.new(mutex.new(1))
    let holder = shared_lock.retain()
    let panicker = thread.spawn(take fn(): i32 {
        let locked = capture holder.get().lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        *guard.get_mut() = 2
        panic("mutex holder panicked")
    })
    let joined = capture panicker.join()
    if joined.is_success() { return 30 }
    if !shared_lock.get().is_poisoned() { return 31 }

    let poisoned = capture shared_lock.get().lock()
    match take poisoned {
        success(_) => { return 32 },
        failure(e) => {
            let guard = e.into_inner()
            if *guard.get() != 2 { return 33 }
        }
    }
    let try_poisoned = capture shared_lock.get().try_lock()
    match take try_poisoned {
        success(_) => { return 34 },
        failure(e) => match e {
            mutex.TryLockError.Poisoned(g) => { if *g.get() != 2 { return 35 } },
            mutex.TryLockError.WouldBlock => { return 36 }
        }
    }
    shared_lock.get().clear_poison()
    if shared_lock.get().is_poisoned() { return 37 }
    let recovered = capture shared_lock.get().lock()
    match take recovered {
        success(g) => { if *g.get() != 2 { return 38 } },
        failure(_) => { return 39 }
    }
    0
}

// get_mut and into_inner on a poisoned, uniquely owned mutex return the
// value inside a PoisonError rather than a plain reference or value.
fn checks_mutex_unique_poison(): i32 {
    var unique = mutex.new(40)
    let outcome = catch_panic(fn(): Unit {
        let locked = capture unique.lock()
        let _guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        panic("poison unique mutex")
    })
    match outcome {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 40 }
    }
    if !unique.is_poisoned() { return 41 }
    let mutable = capture unique.get_mut()
    match take mutable {
        success(_) => { return 42 },
        failure(e) => { *e.into_inner() = 43 }
    }
    unique.clear_poison()
    let cleared = capture unique.get_mut()
    match take cleared {
        success(v) => { if *v != 43 { return 44 } },
        failure(_) => { return 45 }
    }
    let poisoned_inner = mutex.new(50)
    let inner_outcome = catch_panic(fn(): Unit {
        let locked = capture poisoned_inner.lock()
        let _guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        panic("poison mutex into_inner")
    })
    match inner_outcome {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 46 }
    }
    let taken = capture poisoned_inner.into_inner()
    match take taken {
        success(_) => { return 47 },
        failure(e) => { if e.into_inner() != 50 { return 48 } }
    }
    0
}

// RwLock: several readers share the value, a writer excludes everyone.
fn checks_rwlock_guards(): i32 {
    let lock = rwlock.new(60)
    let first = capture lock.`read`()
    let first_guard = match take first { success(g) => g, failure(e) => e.into_inner() }
    let second = capture lock.try_read()
    match take second {
        success(g) => { if *g.get() != 60 { return 61 } },
        failure(_) => { return 62 }
    }
    if *first_guard.get() != 60 { return 63 }
    let writer_blocked = capture lock.try_write()
    match take writer_blocked {
        success(_) => { return 64 },
        failure(e) => match e {
            mutex.TryLockError.WouldBlock => {},
            mutex.TryLockError.Poisoned(_) => { return 65 }
        }
    }
    core.mem.drop(first_guard)

    let writer = capture lock.write()
    var write_guard = match take writer { success(g) => g, failure(e) => e.into_inner() }
    *write_guard.get_mut() = 61
    *write_guard.get_mut() = 62
    if *write_guard.get() != 62 { return 66 }
    let reader_blocked = capture lock.try_read()
    match take reader_blocked {
        success(_) => { return 67 },
        failure(e) => match e {
            mutex.TryLockError.WouldBlock => {},
            mutex.TryLockError.Poisoned(_) => { return 68 }
        }
    }
    core.mem.drop(write_guard)
    let writable = capture lock.try_write()
    match take writable {
        success(g) => { if *g.get() != 62 { return 69 } },
        failure(_) => { return 70 }
    }
    0
}

// Only writer panics poison an RwLock; a reader panicking leaves it usable.
fn checks_rwlock_poison(): i32 {
    let shared_lock = arc.new(rwlock.new(70))
    let writer = shared_lock.retain()
    let poisoner = thread.spawn(take fn(): i32 {
        let locked = capture writer.get().write()
        let mut_guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        let _keep = mut_guard
        panic("rwlock writer panicked")
    })
    let joined = capture poisoner.join()
    if joined.is_success() || !shared_lock.get().is_poisoned() { return 71 }
    let read_after = capture shared_lock.get().`read`()
    match take read_after {
        success(_) => { return 72 },
        failure(e) => { if *e.into_inner().get() != 70 { return 73 } }
    }
    shared_lock.get().clear_poison()
    if shared_lock.get().is_poisoned() { return 74 }

    let reader = shared_lock.retain()
    let reading_panic = thread.spawn(take fn(): i32 {
        let locked = capture reader.get().`read`()
        let _guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        panic("rwlock reader panicked")
    })
    let reader_joined = capture reading_panic.join()
    if reader_joined.is_success() || shared_lock.get().is_poisoned() { return 75 }
    let usable = capture shared_lock.get().write()
    match take usable {
        success(_) => {},
        failure(_) => { return 76 }
    }
    0
}

// Unique access and into_inner on a non-shared_lock RwLock, and its defaults.
fn checks_rwlock_unique_and_construction(): i32 {
    var unique = rwlock.new(80)
    let mutable = capture unique.get_mut()
    match take mutable {
        success(v) => { *v = 81 },
        failure(_) => { return 82 }
    }
    let defaulted: rwlock.RwLock<i32> = default_value<rwlock.RwLock<i32>>()
    let converted: rwlock.RwLock<i32> = from_value<rwlock.RwLock<i32>>(83)
    let read_default = capture defaulted.`read`()
    match take read_default {
        success(g) => { if *g.get() != 0 { return 83 } },
        failure(_) => { return 84 }
    }
    let read_converted = capture converted.`read`()
    match take read_converted {
        success(g) => { if *g.get() != 83 { return 85 } },
        failure(_) => { return 86 }
    }
    let inner = capture unique.into_inner()
    match take inner {
        success(v) => { if v != 81 { return 87 } },
        failure(_) => { return 88 }
    }
    0
}

fn main(): i32 {
    let first = checks_mutex_guards()
    if first != 0 { return first }
    let second = checks_mutex_construction()
    if second != 0 { return second }
    let third = checks_mutex_poison()
    if third != 0 { return third }
    let fourth = checks_mutex_unique_poison()
    if fourth != 0 { return fourth }
    let fifth = checks_rwlock_guards()
    if fifth != 0 { return fifth }
    let sixth = checks_rwlock_poison()
    if sixth != 0 { return sixth }
    checks_rwlock_unique_and_construction()
}
