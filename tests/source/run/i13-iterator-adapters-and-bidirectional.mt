import core.iter
import core.iter.BidirectionalIterator
import core.iter.Iterator
import core.iter.ExactSizeIterator

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

    var flattened = iter.range(0, 4).flat_map(fn(x: take i32): iter.Range<i32> {
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
    let zip_left = [0i32, 1i32, 2i32]
    let zip_right = [10i32, 11i32, 12i32, 13i32, 14i32]
    var reverse_zip = zip_left.iter().zip(zip_right.iter())
    if reverse_zip.len() != 3usize { return 58 }
    let zip_hint = reverse_zip.size_hint()
    if zip_hint.0 != 3usize || zip_hint.1.unwrap() != 3usize { return 63 }
    match take reverse_zip.next_back() {
        present((left, right)) => {
            if *left != 2 || *right != 12 { return 59 }
        },
        none => { return 59 }
    }
    match take reverse_zip.next() {
        present((left, right)) => {
            if *left != 0 || *right != 10 { return 60 }
        },
        none => { return 60 }
    }
    match take reverse_zip.next_back() {
        present((left, right)) => {
            if *left != 1 || *right != 11 { return 61 }
        },
        none => { return 61 }
    }
    if reverse_zip.len() != 0usize || reverse_zip.size_hint().1.unwrap() != 0usize {
        return 62
    }

    var mapped_calls = 0
    if iter.range(0, 3).map(fn(value: take i32): i32 {
        mapped_calls += 1
        value + mapped_calls
    }).fold(0, fn(sum: take i32, value: take i32): i32 { sum + value }) != 9 ||
        mapped_calls != 3 {
        return 56
    }
    var predicate_calls = 0
    if iter.range(0, 5).filter(fn(value: read i32): bool {
        predicate_calls += 1
        value % 2 == 0
    }).count() != 3usize || predicate_calls != 5 {
        return 57
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

    let values = [8i32, 9i32, 10i32, 11i32]
    var enumerated = values.iter().enumerate()
    if enumerated.len() != 4usize { return 25 }
    match take enumerated.next() {
        present((index, value)) => { if index != 0usize || *value != 8 { return 26 } },
        none => { return 26 }
    }
    match take enumerated.next_back() {
        present((index, value)) => { if index != 3usize || *value != 11 { return 27 } },
        none => { return 27 }
    }
    match take enumerated.next_back() {
        present((index, value)) => { if index != 2usize || *value != 10 { return 28 } },
        none => { return 28 }
    }
    match take enumerated.next() {
        present((index, value)) => { if index != 1usize || *value != 9 { return 29 } },
        none => { return 29 }
    }
    if enumerated.len() != 0usize { return 30 }

    var limited_back = values.iter().take_n(3usize)
    if limited_back.len() != 3usize { return 35 }
    match take limited_back.next_back() {
        present(value) => { if *value != 10 { return 36 } },
        none => { return 36 }
    }
    match take limited_back.next() {
        present(value) => { if *value != 8 { return 37 } },
        none => { return 37 }
    }
    match take limited_back.next_back() {
        present(value) => { if *value != 9 { return 38 } },
        none => { return 38 }
    }
    if limited_back.len() != 0usize { return 39 }

    var skipped_back = values.iter().skip(1usize)
    if skipped_back.len() != 3usize { return 40 }
    match take skipped_back.next_back() {
        present(value) => { if *value != 11 { return 41 } },
        none => { return 41 }
    }
    match take skipped_back.next() {
        present(value) => { if *value != 9 { return 42 } },
        none => { return 42 }
    }
    match take skipped_back.next_back() {
        present(value) => { if *value != 10 { return 43 } },
        none => { return 43 }
    }
    if skipped_back.len() != 0usize { return 44 }

    var peekable_len = values.iter().peekable()
    if peekable_len.len() != 4usize { return 45 }
    match take peekable_len.peek() { present(_) => {}, none => { return 46 } }
    if peekable_len.len() != 4usize { return 47 }
    match take peekable_len.next_back() {
        present(value) => { if *value != 11 { return 48 } },
        none => { return 48 }
    }
    if peekable_len.len() != 3usize { return 49 }

    var cloned_back = values.iter().cloned()
    if cloned_back.len() != 4usize { return 50 }
    match take cloned_back.next_back() {
        present(value) => { if value != 11 { return 51 } },
        none => { return 51 }
    }
    if cloned_back.len() != 3usize { return 52 }

    var once_back = iter.once(12i32)
    if once_back.len() != 1usize { return 53 }
    match take once_back.next_back() {
        present(value) => { if value != 12 { return 54 } },
        none => { return 54 }
    }
    if once_back.len() != 0usize || iter.empty<i32>().len() != 0usize { return 55 }

    var calls = 0
    var from_fn = iter.from_fn(fn(): i32? {
        let attempt = calls
        calls += 1
        if attempt == 0 { none } else { present(7) }
    }).take_n(3usize)
    match take from_fn.next() { present(_) => { return 31 }, none => {} }
    if from_fn.limit() != 2usize { return 32 }
    match take from_fn.next() {
        present(value) => { if value != 7 { return 33 } },
        none => { return 33 }
    }
    if calls != 2 || from_fn.limit() != 1usize { return 34 }
    0
}
