import std.sync.{mutex, rwlock}
import std.panic.{catch_panic, CatchResult}

fn main(): i32 {
    var lock = mutex.new(1)
    let panicked = catch_panic(fn(): Unit {
        let acquired = capture lock.lock()
        let guard = match take acquired { success(g) => g, failure(e) => e.into_inner() }
        panic("poison mutex for exclusive access")
    })
    match take panicked { CatchResult.Panicked(_) => {}, CatchResult.Returned(_) => { return 1 } }
    let exclusive = capture lock.get_mut()
    match take exclusive {
        success(_) => { return 2 },
        failure(error) => { *error.into_inner() = 7 }
    }
    lock.clear_poison()
    let value = capture lock.into_inner()
    match take value { success(v) => { if v != 7 { return 3 } }, failure(_) => { return 4 } }

    var shared = rwlock.new(2)
    let panicked = catch_panic(fn(): Unit {
        let acquired = capture shared.writer()
        let guard = match take acquired { success(g) => g, failure(e) => e.into_inner() }
        panic("poison rwlock for exclusive access")
    })
    match take panicked { CatchResult.Panicked(_) => {}, CatchResult.Returned(_) => { return 5 } }
    let exclusive = capture shared.get_mut()
    match take exclusive {
        success(_) => { return 6 },
        failure(error) => { *error.into_inner() = 8 }
    }
    shared.clear_poison()
    let value = capture shared.into_inner()
    match take value { success(v) => { if v != 8 { return 7 } }, failure(_) => { return 8 } }
    0
}
