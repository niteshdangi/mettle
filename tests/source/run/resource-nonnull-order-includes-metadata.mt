import core.ptr.NonNull
import core.cmp.{Ord, Ordering, PartialEq, PartialOrd}

fn main(): i32 {
    let data = NonNull<u8>.dangling()
    let short = NonNull<u8>.slice_from_raw_parts(data, 1usize)
    let long = NonNull<u8>.slice_from_raw_parts(data, 2usize)
    if short.eq(read long) || short.cmp(read long) != Ordering.Less ||
        long.cmp(read short) != Ordering.Greater {
        return 1
    }
    match short.partial_cmp(read long) {
        present(order) => { if order != Ordering.Less { return 2 } },
        none => { return 3 }
    }
    if short.cmp(read short) != Ordering.Equal { return 4 }
    0
}
