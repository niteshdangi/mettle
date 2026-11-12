// expect-exit: 0
// Evidence for Mutex/RwLock formatting, guard Deref/DerefMut/Drop, and the
// Debug forms of Once, Barrier and Condvar.
import std.sync.{ mutex, rwlock, once, once_lock, barrier, condvar }
import core.cmp.Eq
import core.fmt
import core.fmt.{Debug, Display}
import core.ops.{Deref, DerefMut}
import core.text.Text

fn debug_text<T: Debug>(read value: T): alloc.string.String {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { panic("Debug formatting failed") }
        }
    }
    output
}

fn display_text<T: Display>(read value: T): alloc.string.String {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(Display).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { panic("Display formatting failed") }
        }
    }
    output
}

fn require_eq<T: Eq>(read value: T): Unit {}

fn read_through<G: Deref>(read guard: G): read G.(Deref).Target from guard {
    G.(Deref).deref(guard)
}

fn write_through<G: DerefMut>(mut guard: G): mut G.(Deref).Target from guard {
    G.(DerefMut).deref_mut(mut guard)
}

fn checks_mutex_guard(): i32 {
    let lock = mutex.new(5)
    {
        var guard = match take capture lock.lock() { success(g) => g, failure(e) => e.into_inner() }
        if *read_through(read guard) != 5 { return 10 }
        *write_through(mut guard) = 6
        if *read_through(read guard) != 6 { return 11 }
        if debug_text(read guard).as_text() != "6" { return 12 }
        if display_text(read guard).as_text() != "6" { return 13 }
        let text = debug_text(read lock)
        if !text.as_text().starts_with("Mutex") || !text.as_text().contains("<locked>") { return 14 }
    }
    match take capture lock.try_lock() {
        success(g) => { if *g.get() != 6 { return 15 } },
        failure(_) => { return 16 }
    }
    let idle = debug_text(read lock)
    if !idle.as_text().contains("data: 6") { return 17 }
    0
}

fn checks_rwlock_guards(): i32 {
    let lock = rwlock.new(7)
    {
        let first = match take capture lock.`read`() { success(g) => g, failure(e) => e.into_inner() }
        let second = match take capture lock.`read`() { success(g) => g, failure(e) => e.into_inner() }
        if *read_through(read first) != 7 || *read_through(read second) != 7 { return 20 }
        if debug_text(read first).as_text() != "7" { return 21 }
        if display_text(read second).as_text() != "7" { return 22 }
        match take capture lock.try_write() {
            success(_) => { return 23 },
            failure(_) => {}
        }
    }
    {
        var writer = match take capture lock.write() { success(g) => g, failure(e) => e.into_inner() }
        *write_through(mut writer) = 8
        if *read_through(read writer) != 8 { return 24 }
        if debug_text(read writer).as_text() != "8" { return 25 }
        if display_text(read writer).as_text() != "8" { return 26 }
        if !debug_text(read lock).as_text().starts_with("RwLock") { return 27 }
        match take capture lock.try_read() {
            success(_) => { return 28 },
            failure(_) => {}
        }
    }
    match take capture lock.try_write() {
        success(g) => { if *g.get() != 8 { return 29 } },
        failure(_) => { return 30 }
    }
    0
}

fn checks_sync_object_debug(): i32 {
    if debug_text(read once.new()).as_text() != "Once { .. }" { return 40 }
    if debug_text(read barrier.new(2usize)).as_text() != "Barrier { .. }" { return 41 }
    if debug_text(read condvar.new()).as_text() != "Condvar { .. }" { return 42 }
    let cell = once_lock.new<i32>()
    require_eq(read cell)
    if !debug_text(read cell).as_text().starts_with("OnceLock") { return 43 }
    0
}

fn main(): i32 {
    let first = checks_mutex_guard()
    if first != 0 { return first }
    let second = checks_rwlock_guards()
    if second != 0 { return second }
    checks_sync_object_debug()
}
