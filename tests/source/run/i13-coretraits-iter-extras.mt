import core.cmp.Ordering
import core.iter
import core.iter.BidirectionalIterator
import core.iter.Iterator

fn less_than_three(read value: i32): bool { value < 3 }

fn main(): i32 {
    if iter.repeat(3i32).take_n(4usize).fold(
        0,
        fn(take total: i32, take value: i32): i32 { total + value }
    ) != 12 {
        return 1
    }

    var successors = iter.successors(
        present(1i32),
        fn(read value: i32): i32? {
            if value < 4 { present(value + 1) } else { none }
        }
    )
    if successors.fold(0, fn(take total: i32, take value: i32): i32 {
        total + value
    }) != 10 {
        return 2
    }

    var peekable = iter.range(1, 5).take_n(4usize).peekable()
    match take peekable.next_if(less_than_three) {
        present(value) => { if value != 1 { return 3 } },
        none => { return 3 }
    }
    match take peekable.peek_mut() {
        present(value) => { *value = 3 },
        none => { return 4 }
    }
    let expected = 3i32
    match take peekable.next_if_eq(read expected) {
        present(value) => { if value != 3 { return 5 } },
        none => { return 5 }
    }
    var limited = iter.range(1, 5).take_n(4usize)
    if limited.limit() != 4usize { return 6 }
    limited.set_limit(2usize)
    if limited.count() != 2usize { return 7 }

    let inclusive = iter.range_inclusive(2, 4)
    if inclusive.end != 4 { return 8 }
    var flattened = iter.range(1, 4).map(
        fn(take value: i32): iter.Range<i32> { iter.range(0, value) }
    ).flatten()
    if flattened.count() != 6usize { return 9 }
    var mixed = iter.range(1, 4).map(
        fn(take value: i32): iter.Range<i32> { iter.range(0, value) }
    ).flatten()
    match take mixed.next() {
        present(value) => { if value != 0 { return 10 } },
        none => { return 10 }
    }
    match take mixed.next_back() {
        present(value) => { if value != 2 { return 11 } },
        none => { return 11 }
    }
    match take mixed.next() {
        present(value) => { if value != 0 { return 12 } },
        none => { return 12 }
    }
    match take mixed.next_back() {
        present(value) => { if value != 1 { return 13 } },
        none => { return 13 }
    }
    match iter.range(1, 5).min_by(fn(read a: i32, read b: i32): Ordering {
        if a < b { Ordering.Less } else if a == b { Ordering.Equal } else { Ordering.Greater }
    }) {
        present(value) => { if value != 1 { return 14 } },
        none => { return 14 }
    }
    match iter.range(1, 5).max_by(fn(read a: i32, read b: i32): Ordering {
        if a < b { Ordering.Less } else if a == b { Ordering.Equal } else { Ordering.Greater }
    }) {
        present(value) => { if value != 4 { return 15 } },
        none => { return 15 }
    }
    match iter.range(1, 5).min_by_key(fn(read value: i32): i32 { -value }) {
        present(value) => { if value != 4 { return 16 } },
        none => { return 16 }
    }
    match iter.range(1, 5).max_by_key(fn(read value: i32): i32 { -value }) {
        present(value) => { if value != 1 { return 17 } },
        none => { return 17 }
    }
    0
}
