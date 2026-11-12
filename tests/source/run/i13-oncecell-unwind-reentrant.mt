// profiles: debug release

import core.cell.OnceCell
import std.panic.{catch_panic, CatchResult}

type Counted {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += self.value } }
}

fn main(): i32 {
    let updated = core.cell.Cell.new(5i32)
    let update_failed = catch_panic(fn(): Unit {
        updated.update(fn(value: i32): i32 { panic("update failed") })
    })
    match update_failed {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 7 }
    }
    if updated.get() != 5 { return 8 }
    let borrowed = core.cell.RefCell.new(9i32)
    let replacement_failed = catch_panic(fn(): Unit {
        let _ = borrowed.replace_with(fn(mut value: i32): i32 {
            value = 10
            panic("replacement failed")
        })
    })
    match replacement_failed {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 9 }
    }
    {
        var guard = borrowed.try_borrow_mut().unwrap()
        if *guard.get_ref() != 10 { return 10 }
        *guard.get_mut() = 11
    }
    let retry = OnceCell<i32>.new()
    let failed = catch_panic(fn(): Unit {
        let _ = retry.get_or_init(fn(): i32 { panic("initializer failed") })
    })
    match failed {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    if retry.get().is_present() { return 2 }
    if *retry.get_or_init(fn(): i32 { 42 }) != 42 { return 3 }

    var drops = 0
    let counter = core.ptr.from_mut(drops)
    let cell = OnceCell<Counted>.new()
    let reentered = catch_panic(fn(): Unit {
        let _ = cell.get_or_init(fn(): Counted {
            let _ = cell.get_or_init(fn(): Counted { Counted(counter, 1) })
            Counted(counter, 10)
        })
    })
    match reentered {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 4 }
    }
    if drops != 10 || cell.get().unwrap().value != 1 { return 5 }
    let extracted = cell.into_inner().unwrap()
    if extracted.value != 1 || drops != 10 { return 6 }
    0
}
