import alloc.borrow.BorrowedOrOwned
import alloc.vec.List
import core.convert.From

fn equals_mut_slice<region r>(
    read items: [i32] from r,
    mut other: [i32] from r
): bool {
    let cow: BorrowedOrOwned<region r, [i32]> = BorrowedOrOwned.Borrowed(read items)
    cow == other
}

fn equals_slice<region r>(read other: [i32] from r): bool {
    let cow: BorrowedOrOwned<region r, [i32]> = BorrowedOrOwned.Owned(
        List<i32>.(From<[i32; 2]>).from([4, 7])
    )
    cow == other
}

fn equals_list<region r>(read items: [i32] from r): bool {
    let cow: BorrowedOrOwned<region r, [i32]> = BorrowedOrOwned.Borrowed(read items)
    let other = List<i32>.(From<[i32; 2]>).from([4, 7])
    cow == other
}

fn main(): i32 {
    let items = [4i32, 7i32]
    var other = [4i32, 7i32]
    if !equals_mut_slice(read items, mut other) { return 1 }
    if !equals_slice(read other) { return 2 }
    if !equals_list(read items) { return 3 }
    0
}
