import alloc.borrow.BorrowedOrOwned
import alloc.vec.List
import core.clone.Clone
import core.convert.From

type Value {
    number: i32
    clones: ptr<mut i32>
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

extend Value implements Clone {
    fn clone(): Value {
        unsafe { *self.clones += 1 }
        Value(self.number, self.clones, self.drops)
    }
}

fn borrowed<region r>(read values: [Value] from r): i32 {
    let cow: BorrowedOrOwned<region r, [Value]> = BorrowedOrOwned.Borrowed(read values)
    var owned = List<Value>.(From<BorrowedOrOwned<region r, [Value]>>).from(cow)
    if owned.len() != 2usize || owned[1usize].number != 9 { return 1 }
    if owned.as_ptr() == core.ptr.from_ref(values[0usize]) { return 2 }
    owned[0usize].number = 99
    if values[0usize].number != 7 { return 3 }
    0
}

fn owned<region r>(
    read anchor: i32 from r,
    clones: ptr<mut i32>,
    drops: ptr<mut i32>
): i32 {
    let _ = anchor
    var values = alloc.vec.with_capacity<Value>(4usize)
    values.push(Value(11, clones, drops))
    let address = values.as_ptr()
    let capacity = values.capacity()
    let before = unsafe { *clones }
    let cow: BorrowedOrOwned<region r, [Value]> = BorrowedOrOwned.Owned(values)
    let moved = cow.into_owned()
    if moved.as_ptr() != address || moved.capacity() != capacity { return 4 }
    if moved.len() != 1usize || moved[0usize].number != 11 { return 5 }
    if unsafe { *clones } != before { return 6 }
    0
}

fn empty<region r>(read values: [Value] from r): i32 {
    let cow: BorrowedOrOwned<region r, [Value]> = BorrowedOrOwned.Borrowed(read values)
    let owned = cow.into_owned()
    if owned.len() != 0usize || owned.capacity() != 0usize { return 7 }
    0
}

fn clone_and_mutate<region r>(read values: [Value] from r): i32 {
    var cow: BorrowedOrOwned<region r, [Value]> = BorrowedOrOwned.Borrowed(read values)
    let borrowed_clone = cow.clone()
    if !borrowed_clone.is_borrowed() || unsafe { *values[0usize].clones } != 2 {
        return 12
    }
    cow.to_mut()[0usize].number = 99
    let address = cow.to_mut().as_ptr()
    if cow.to_mut().as_ptr() != address || !cow.is_owned() { return 13 }
    if unsafe { *values[0usize].clones } != 4 { return 14 }
    let owned_clone = cow.clone()
    if !owned_clone.is_owned() || owned_clone.as_ref()[0usize].number != 99 {
        return 15
    }
    if owned_clone.as_ref()[0usize].number == borrowed_clone.as_ref()[0usize].number {
        return 16
    }
    cow.to_mut()[0usize].number = 101
    if owned_clone.as_ref()[0usize].number != 99 ||
        borrowed_clone.as_ref()[0usize].number != 7 ||
        values[0usize].number != 7 {
        return 17
    }
    if unsafe { *values[0usize].clones } != 6 { return 18 }
    0
}

fn main(): i32 {
    var clones = 0
    var drops = 0
    {
        let values = [
            Value(7, core.ptr.from_mut(clones), core.ptr.from_mut(drops)),
            Value(9, core.ptr.from_mut(clones), core.ptr.from_mut(drops))
        ]
        let result = borrowed(read values)
        if result != 0 { return result }
        if clones != 2 || drops != 2 { return 8 }
        let result = clone_and_mutate(read values)
        if result != 0 { return result }
        if clones != 6 || drops != 6 { return 19 }
    }
    if drops != 8 { return 9 }
    let anchor = 0
    let result = owned(
        read anchor, core.ptr.from_mut(clones), core.ptr.from_mut(drops)
    )
    if result != 0 { return result }
    if clones != 6 || drops != 9 { return 10 }
    let values: [Value; 0] = []
    let result = empty(read values)
    if result != 0 { return result }
    if clones != 6 || drops != 9 { return 11 }
    0
}
