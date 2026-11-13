import alloc.borrow.BorrowedOrOwned
import alloc.vec.List

type Value {
    number: i32
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn borrowed<region r>(read values: [Value] from r): i32 {
    let cow: BorrowedOrOwned<region r, [Value]> = BorrowedOrOwned.Borrowed(read values)
    if !cow.is_borrowed() || cow.as_ref().len() != 2usize { return 1 }
    if cow.as_ref()[0usize].number != 7 || cow.as_ref()[1usize].number != 9 {
        return 2
    }
    0
}

fn owned<region r>(read anchor: i32 from r, drops: ptr<mut i32>): i32 {
    let _ = anchor
    let initial_drops = unsafe { *drops }
    var values = alloc.vec.with_capacity<Value>(4usize)
    values.push(Value(11, drops))
    values.push(Value(13, drops))
    let address = values.as_ptr()
    let capacity = values.capacity()
    let cow: BorrowedOrOwned<region r, [Value]> = BorrowedOrOwned.Owned(values)
    if cow.is_borrowed() || cow.as_ref()[1usize].number != 13 { return 3 }
    let moved: List<Value> = match take cow {
        BorrowedOrOwned.Borrowed(_) => { return 4 },
        BorrowedOrOwned.Owned(items) => items
    }
    if moved.as_ptr() != address || moved.capacity() != capacity { return 5 }
    if moved.len() != 2usize || moved[0usize].number != 11 { return 6 }
    if unsafe { *drops } != initial_drops { return 7 }
    0
}

fn main(): i32 {
    var drops = 0
    {
        let values = [
            Value(7, core.ptr.from_mut(drops)),
            Value(9, core.ptr.from_mut(drops))
        ]
        let result = borrowed(read values)
        if result != 0 { return result }
        if drops != 0 || values[0usize].number != 7 { return 8 }
    }
    if drops != 2 { return 9 }
    let anchor = 0
    let result = owned(read anchor, core.ptr.from_mut(drops))
    if result != 0 { return result }
    if drops != 4 { return 10 }
    0
}
