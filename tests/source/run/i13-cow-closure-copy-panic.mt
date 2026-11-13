import alloc.borrow.BorrowedOrOwned
import core.clone.Clone
import core.panic.panic
import std.panic.CatchResult

type Value {
    number: i32
    attempts: ptr<mut i32>
    drops: ptr<mut i32>
    fail_at: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

extend Value implements Clone {
    fn clone(): Value {
        unsafe {
            *self.attempts += 1
            if *self.attempts == *self.fail_at { panic("cow clone stop") }
        }
        Value(self.number, self.attempts, self.drops, self.fail_at)
    }
}

fn copy_with_panic<region r>(read values: [Value] from r): i32 {
    var cow: BorrowedOrOwned<region r, [Value]> = BorrowedOrOwned.Borrowed(read values)
    let result = std.panic.catch_panic(fn(): Unit { let _ = cow.to_mut() })
    match take result {
        CatchResult.Panicked(info) => {
            if info.message() != "cow clone stop" { return 1 }
        },
        CatchResult.Returned(_) => { return 2 }
    }
    if !cow.is_borrowed() || cow.as_ref().len() != 3usize ||
        unsafe { *values[0usize].attempts } != 2 ||
        unsafe { *values[0usize].drops } != 1 {
        return 3
    }
    let fail_at = values[0usize].fail_at
    unsafe { *fail_at = 0 }
    cow.to_mut()[0usize].number = 99
    if !cow.is_owned() || cow.as_ref()[0usize].number != 99 ||
        values[0usize].number != 7 ||
        unsafe { *values[0usize].attempts } != 5 ||
        unsafe { *values[0usize].drops } != 1 {
        return 4
    }
    0
}

fn main(): i32 {
    var attempts = 0
    var drops = 0
    var fail_at = 2
    {
        let values = [
            Value(7, core.ptr.from_mut(attempts), core.ptr.from_mut(drops), core.ptr.from_mut(fail_at)),
            Value(9, core.ptr.from_mut(attempts), core.ptr.from_mut(drops), core.ptr.from_mut(fail_at)),
            Value(11, core.ptr.from_mut(attempts), core.ptr.from_mut(drops), core.ptr.from_mut(fail_at))
        ]
        let result = copy_with_panic(read values)
        if result != 0 { return result }
        if attempts != 5 || drops != 4 { return 5 }
    }
    if drops != 7 { return 6 }
    0
}
