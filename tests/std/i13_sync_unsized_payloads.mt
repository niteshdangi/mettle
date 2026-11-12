import std.sync.{mutex, rwlock, condvar}
import core.fmt.{Debug, Display}
import core.ops.{Deref, DerefMut}

fn debug<T: Debug + unsized>(read value: T): alloc.string.String {
    var output = alloc.string.new()
    {
        var formatter = core.fmt.formatter(mut output, core.fmt.spec())
        match capture T.(Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { panic("unsized Debug failed") }
        }
    }
    output
}

fn display<T: Display + unsized>(read value: T): alloc.string.String {
    var output = alloc.string.new()
    {
        var formatter = core.fmt.formatter(mut output, core.fmt.spec())
        match capture T.(Display).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { panic("unsized Display failed") }
        }
    }
    output
}

type Tracked {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var sized_mutex = mutex.new([1, 2, 3])
    let condition = condvar.new()
    {
        let lock: read mutex.Mutex<[i32]> = read sized_mutex
        let locked = capture lock.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if guard.deref().len() != 3usize { return 1 }
        guard.deref_mut()[1usize] = 7
        if debug(guard).as_text() != "[1, 7, 3]" { return 2 }
        let waited = capture condition.wait_timeout(guard, std.time.from_nanos(0u64))
        let result = match take waited { success(v) => v, failure(e) => e.into_inner() }
        if !result.1.timed_out() || result.0.get().len() != 3usize { return 3 }
        core.mem.drop(result.0)
        if !debug(lock).as_text().contains("[1, 7, 3]") { return 4 }
    }
    {
        let lock: mut mutex.Mutex<[i32]> = mut sized_mutex
        match take capture lock.get_mut() {
            success(value) => { value[2usize] = 8 },
            failure(_) => { return 5 }
        }
    }
    match take capture sized_mutex.into_inner() {
        success(value) => { if value[2usize] != 8 { return 6 } },
        failure(_) => { return 7 }
    }

    var sized_rwlock = rwlock.new([10, 11])
    {
        let lock: read rwlock.RwLock<[i32]> = read sized_rwlock
        let locked = capture lock.writer()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        guard.deref_mut()[0usize] = 12
        if debug(guard).as_text() != "[12, 11]" { return 8 }
        core.mem.drop(guard)
        let locked = capture lock.reader()
        let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if guard.deref().len() != 2usize || debug(guard).as_text() != "[12, 11]" {
            return 9
        }
        core.mem.drop(guard)
        if !debug(lock).as_text().contains("[12, 11]") { return 10 }
    }
    {
        let lock: mut rwlock.RwLock<[i32]> = mut sized_rwlock
        match take capture lock.get_mut() {
            success(value) => { value[1usize] = 13 },
            failure(_) => { return 11 }
        }
    }
    match take capture sized_rwlock.into_inner() {
        success(value) => { if value[1usize] != 13 { return 12 } },
        failure(_) => { return 13 }
    }

    let mutex_value = mutex.new(42)
    let erased_mutex: read mutex.Mutex<any Display> = read mutex_value
    let locked = capture erased_mutex.lock()
    let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    if display(guard).as_text() != "42" { return 14 }
    core.mem.drop(guard)
    let rwlock_value = rwlock.new(43)
    let erased_rwlock: read rwlock.RwLock<any Display> = read rwlock_value
    let locked = capture erased_rwlock.writer()
    let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    if display(guard).as_text() != "43" { return 15 }
    core.mem.drop(guard)
    let locked = capture erased_rwlock.reader()
    let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    if display(guard).as_text() != "43" { return 16 }
    core.mem.drop(guard)

    var drops = 0
    let counter = core.ptr.from_mut(drops)
    {
        let sized: heap mutex.Mutex<[Tracked; 2]> =
            heap mutex.new([Tracked(counter), Tracked(counter)])
        let dynamic: heap mutex.Mutex<[Tracked]> = sized
        let locked = capture dynamic.get().lock()
        let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if guard.get().len() != 2usize { return 17 }
    }
    if drops != 2 { return 18 }
    {
        let sized: heap rwlock.RwLock<[Tracked; 2]> =
            heap rwlock.new([Tracked(counter), Tracked(counter)])
        let dynamic: heap rwlock.RwLock<[Tracked]> = sized
        let locked = capture dynamic.get().reader()
        let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if guard.get().len() != 2usize { return 19 }
    }
    if drops != 4 { return 20 }
    0
}
