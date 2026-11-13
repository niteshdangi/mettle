import std.sync.{ barrier, condition, mutex, once, once_lock, rwlock }
import core.borrow.Borrow
import core.clone.Clone
import core.convert.From
import core.error.{ Error as CoreError }
import core.fmt
import core.fmt.{ Debug, Display }
import core.ops.{ Deref, DerefMut }

fn require_debug<T: Debug>(read value: T, read prefix: core.text.Text): Unit {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { panic("sync debug formatting failed") }
        }
    }
    assert(output.as_text().starts_with(read prefix), "sync Debug output prefix")
}

fn require_display<T: Display>(read value: T, read expected: core.text.Text): Unit {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(Display).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { panic("sync display formatting failed") }
        }
    }
    assert(output.as_text() == expected, "sync Display output")
}

fn require_error<T: CoreError>(read value: T): Unit {}

fn from_value<T: From<i32>>(take value: i32): T {
    T.(From<i32>).from(value)
}

fn borrowed_value<T: Borrow<i32>>(read value: T): i32 {
    *value.borrow()
}

fn main(): i32 {
    let lock = mutex.new(41)
    require_debug(read lock, "Mutex {")
    let locked = capture lock.lock()
    var guard = match take locked {
        success(value) => value,
        failure(error) => error.into_inner()
    }
    // Debugging a held mutex must use the nonblocking path.
    require_debug(read lock, "Mutex {")
    if *guard.deref() != 41 || borrowed_value(guard) != 41 { return 5 }
    *guard.deref_mut() = 42
    require_debug(read guard, "42")
    require_display(read guard, "42")
    let blocked = capture lock.try_lock()
    match take blocked {
        success(unexpected) => { core.mem.drop(unexpected); return 4 },
        failure(error) => {
            require_debug(read error, "WouldBlock")
            require_display(read error, "try_lock failed because the operation would block")
        }
    }
    core.mem.drop(guard)
    let from_mutex: mutex.Mutex<i32> = from_value(70)
    require_debug(read from_mutex, "Mutex {")

    let rw = rwlock.new(52)
    require_debug(read rw, "RwLock {")
    let write = capture rw.writer()
    var write_guard = match take write {
        success(value) => value,
        failure(error) => error.into_inner()
    }
    require_debug(read rw, "RwLock {")
    *write_guard.deref_mut() = 53
    require_debug(read write_guard, "53")
    require_display(read write_guard, "53")
    core.mem.drop(write_guard)
    let reader_result = capture rw.reader()
    let read_guard = match take reader_result {
        success(value) => value,
        failure(error) => error.into_inner()
    }
    require_debug(read read_guard, "53")
    require_display(read read_guard, "53")
    if *read_guard.deref() != 53 || borrowed_value(read_guard) != 53 { return 6 }
    core.mem.drop(read_guard)
    let from_rwlock: rwlock.RwLock<i32> = from_value(71)
    require_debug(read from_rwlock, "RwLock {")

    let signal = condition.new()
    require_debug(read signal, "Condition")
    let gate = barrier.new(1usize)
    require_debug(read gate, "Barrier {")
    let barrier_result = gate.wait()
    let cloned_barrier_result = barrier_result.clone()
    require_debug(read cloned_barrier_result, "BarrierWaitResult { is_leader:")
    if !cloned_barrier_result.is_leader() { return 1 }

    let once_cell = once.new()
    once_cell.call_once(fn(): Unit {})
    require_debug(read once_cell, "Once { .. }")
    let state = once.OnceState(true)
    let cloned_state = state.clone()
    require_debug(read cloned_state, "OnceState {")
    if !cloned_state.is_poisoned() { return 2 }

    let cell = once_lock.new<i32>()
    require_debug(read cell, "OnceLock(<uninit>)")
    let initialized = capture cell.set(63)
    match take initialized {
        success(_) => {},
        failure(error) => { return 3 }
    }
    require_debug(read cell, "OnceLock(63")
    let from_cell: once_lock.OnceLock<i32> = from_value(72)
    require_debug(read from_cell, "OnceLock(72")

    let poison = mutex.PoisonError.new(7)
    require_debug(read poison, "PoisonError {")
    require_display(read poison, "poisoned lock: another task failed inside")
    require_error(read poison)
    let poisoned_try = mutex.TryLockError.Poisoned(7)
    require_debug(read poisoned_try, "Poisoned(..)")
    require_display(read poisoned_try, "poisoned lock: another task failed inside")
    0
}
