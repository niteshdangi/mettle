import core.iter
import core.iter.BidirectionalIterator
import core.iter.Iterator

fn main(): i32 {
    var mapped = iter.range(0, 6).map_while(fn(x: take i32): i32? {
        if x == 3 { none } else { present(x) }
    })
    if mapped.fold(0, fn(sum: take i32, x: take i32): i32 { sum + x }) != 3 {
        return 1
    }
    match take mapped.next() { present(x) => { if x != 4 { return 2 } }, none => { return 2 } }
    match take iter.empty<i32>().reduce(fn(a: take i32, b: take i32): i32 { a + b }) {
        present(_) => { return 22 },
        none => {}
    }
    match take iter.range(1, 5).reduce(fn(a: take i32, b: take i32): i32 { a + b }) {
        present(sum) => { if sum != 10 { return 23 } },
        none => { return 23 }
    }

    let flattened = iter.range(0, 4).flat_map(fn(x: take i32): iter.Range<i32> {
        iter.range(0, x)
    })
    if flattened.count() != 6usize { return 3 }
    var reverse_flattened = iter.range(0, 3).flat_map(fn(x: take i32): iter.Range<i32> {
        iter.range(0, x)
    })
    match take reverse_flattened.next_back() {
        present(x) => { if x != 1 { return 20 } },
        none => { return 20 }
    }
    match take reverse_flattened.next() {
        present(x) => { if x != 0 { return 21 } },
        none => { return 21 }
    }

    if iter.range(1, 3).cycle().take_n(5usize).fold(
        0,
        fn(sum: take i32, x: take i32): i32 { sum + x }
    ) != 7 {
        return 4
    }

    var back = iter.range(0, 5)
    match back.nth_back(1usize) { present(x) => { if x != 3 { return 5 } }, none => { return 5 } }
    match back.rfind(fn(x: read i32): bool { x % 2 == 0 }) {
        present(x) => { if x != 2 { return 6 } },
        none => { return 6 }
    }

    match iter.range(0, 5).rposition(fn(x: take i32): bool { x == 3 }) {
        present(index) => { if index != 3usize { return 7 } },
        none => { return 7 }
    }
    if iter.range(0, 4).rfold(0, fn(value: take i32, x: take i32): i32 {
        value * 10 + x
    }) != 3210 {
        return 8
    }

    var chained = iter.range(0, 3).chain(iter.range(10, 12))
    match take chained.next_back() { present(x) => { if x != 11 { return 9 } }, none => { return 9 } }
    match take chained.next() { present(x) => { if x != 0 { return 10 } }, none => { return 10 } }
    match take chained.next_back() { present(x) => { if x != 10 { return 11 } }, none => { return 11 } }
    match take chained.next() { present(x) => { if x != 1 { return 12 } }, none => { return 12 } }
    if iter.chain(iter.range(0, 2), iter.range(4, 6)).count() != 4usize ||
        iter.zip(iter.range(0, 3), iter.range(0, 2)).count() != 2usize {
        return 24
    }

    var filtered = iter.range(0, 6).filter_map(fn(x: take i32): i32? {
        if x % 2 == 0 { present(x) } else { none }
    })
    match take filtered.next_back() { present(x) => { if x != 4 { return 13 } }, none => { return 13 } }
    match take filtered.next() { present(x) => { if x != 0 { return 14 } }, none => { return 14 } }

    var peekable = iter.range(0, 3).peekable()
    match take peekable.peek() { present(x) => { if *x != 0 { return 15 } }, none => { return 15 } }
    match take peekable.next_back() { present(x) => { if x != 2 { return 16 } }, none => { return 16 } }
    match take peekable.next_back() { present(x) => { if x != 1 { return 17 } }, none => { return 17 } }
    match take peekable.next_back() { present(x) => { if x != 0 { return 18 } }, none => { return 18 } }
    match take peekable.next() { present(_) => { return 19 }, none => {} }
    0
}
