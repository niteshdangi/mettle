import core.cmp.{Ordering, Ord, PartialEq}
import core.hash
import core.hash.Hash

fn identity(value: i32): i32 { value }

fn equal<T: PartialEq>(read left: T, read right: T): bool {
    left.eq(right)
}

fn order<T: Ord>(read left: T, read right: T): Ordering {
    left.cmp(right)
}

fn digest<T: Hash>(read value: T): u64 {
    hash.hash_one(value)
}

fn main(): i32 {
    var value = 7i32
    let shared = core.ptr.from_ref(read value)
    let shared_clone = shared.clone()
    if !equal(read shared, read shared_clone) { return 1 }
    if order(read shared, read shared_clone) != Ordering.Equal { return 2 }
    if digest(read shared) != digest(read shared_clone) { return 3 }

    let exclusive = core.ptr.from_mut(mut value)
    let exclusive_clone = exclusive.clone()
    if !equal(read exclusive, read exclusive_clone) { return 4 }
    if order(read exclusive, read exclusive_clone) != Ordering.Equal { return 5 }
    if digest(read exclusive) != digest(read exclusive_clone) { return 6 }

    let function: fn(i32): i32 = identity
    let same_function = function
    if !equal(read function, read same_function) { return 7 }
    if order(read function, read same_function) != Ordering.Equal { return 8 }
    if digest(read function) != digest(read same_function) { return 9 }
    0
}
