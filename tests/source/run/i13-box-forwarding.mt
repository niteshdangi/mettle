import alloc.alloc.Global
import alloc.boxed
import core.convert.{From, TryFrom}
import core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, FromItems}

type Counted {
    counter: ptr<mut i32>
    value: i32
    drop { unsafe { *self.counter += 1 } }
}

type Count { front: i32; back: i32 }
extend Count implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.front >= self.back { return none }
        let value = self.front
        self.front += 1
        present(value)
    }
}
extend Count implements BidirectionalIterator {
    mut fn next_back(): i32? {
        if self.front >= self.back { return none }
        self.back -= 1
        present(self.back)
    }
}
extend Count implements ExactSizeIterator {
    fn len(): usize { (self.back - self.front) as usize }
}

// A boxed iterator is an iterator: next, next_back and len reach the payload.
fn iteration(): i32 {
    var items = boxed.new(Count(0, 5))
    if items.len() != 5usize { return 1 }
    match take items.next() { present(v) => { if v != 0 { return 2 } }, none => { return 3 } }
    match take items.next_back() { present(v) => { if v != 4 { return 4 } }, none => { return 5 } }
    if items.len() != 3usize { return 6 }
    var sum = 0
    while true {
        match take items.next() { present(v) => { sum += v }, none => { break } }
    }
    if sum != 6 { return 7 }
    if items.len() != 0usize { return 8 }
    0
}

// A boxed slice builds from items or an array; a fixed-size box needs the right length.
fn conversions(): i32 {
    let collected = boxed.Box<[i32]>.(FromItems<i32>).from_iter([4, 5, 6])
    if collected.get().len() != 3usize || collected.get()[2usize] != 6 { return 10 }
    let from_array = boxed.Box<[i32]>.(From<[i32; 2]>).`from`([7, 8])
    if from_array.get().len() != 2usize || from_array.get()[0usize] != 7 { return 11 }
    let exact = capture boxed.Box<[i32; 3], Global>.(TryFrom<boxed.Box<[i32], Global>>).try_from(collected)
    match take exact {
        success(fixed) => { if fixed.get()[1usize] != 5 { return 12 } },
        failure(_) => { return 13 }
    }
    let wrong = capture boxed.Box<[i32; 3], Global>.(TryFrom<boxed.Box<[i32], Global>>).try_from(from_array)
    match take wrong {
        success(_) => { return 14 },
        failure(back) => { if back.get().len() != 2usize { return 15 } }
    }
    0
}

// The non-null form round-trips the allocation and drops the payload once.
fn non_null(): i32 {
    var drops = 0
    {
        let owner = boxed.new(Counted(core.ptr.from_mut(drops), 21))
        let pair = owner.into_non_null()
        if drops != 0 { return 20 }
        let rebuilt = unsafe { boxed.from_non_null_in(pair.0, pair.1) }
        if rebuilt.get().value != 21 { return 21 }
    }
    if drops != 1 { return 22 }
    0
}

fn main(): i32 {
    let first = iteration()
    if first != 0 { return first }
    let second = conversions()
    if second != 0 { return second }
    non_null()
}
