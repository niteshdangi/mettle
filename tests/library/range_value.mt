import core.iter.{Iterator, BidirectionalIterator}

fn check_to(range: core.iter.RangeTo<i32>): i32 {
    let _ = range
    0
}

fn check_to_inclusive(range: core.iter.RangeToInclusive<i32>): i32 {
    let _ = range
    0
}

fn check_full(range: core.iter.RangeFull): i32 {
    let _ = range
    0
}

fn total<I: Iterator<Item = i32>>(take it: I): i32 {
    var items = it
    var sum = 0
    while true {
        match take items.next() {
            present(v) => { sum += v },
            none => { break }
        }
    }
    sum
}

fn main(): i32 {
    if total((3..).take_n(4usize)) != 18 { return 12 }
    var upper_edge = 255u8..=255u8
    match take upper_edge.next() {
        present(value) => { if value != 255u8 { return 16 } },
        none => { return 17 }
    }
    match take upper_edge.next() {
        present(value) => { return 18 },
        none => {}
    }
    var scalar_edge = '\u{d7fe}'..
    match take scalar_edge.next() {
        present(value) => { if value != '\u{d7fe}' { return 19 } },
        none => { return 20 }
    }
    match take scalar_edge.next() {
        present(value) => { if value != '\u{d7ff}' { return 21 } },
        none => { return 22 }
    }
    match take scalar_edge.next() {
        present(value) => { if value != '\u{e000}' { return 23 } },
        none => { return 24 }
    }
    match take scalar_edge.next() {
        present(value) => { if value != '\u{e001}' { return 25 } },
        none => { return 26 }
    }
    var scalar_maximum = '\u{10ffff}'..='\u{10ffff}'
    match take scalar_maximum.next() {
        present(value) => { if value != '\u{10ffff}' { return 28 } },
        none => { return 29 }
    }
    match take scalar_maximum.next() {
        present(value) => { return 30 },
        none => {}
    }
    var scalar_closed = '\u{d7ff}'..='\u{e000}'
    match take scalar_closed.next() {
        present(value) => { if value != '\u{d7ff}' { return 31 } },
        none => { return 32 }
    }
    match take scalar_closed.next() {
        present(value) => { if value != '\u{e000}' { return 33 } },
        none => { return 34 }
    }
    var bounded_loop = 0
    for value in 2.. {
        bounded_loop += value
        if value == 4 { break }
    }
    if bounded_loop != 9 { return 27 }
    let upper: core.iter.RangeTo<i32> = ..5
    if check_to(upper) != 0 { return 13 }
    let inclusive_upper: core.iter.RangeToInclusive<i32> = ..=5
    if check_to_inclusive(inclusive_upper) != 0 { return 14 }
    let full: core.iter.RangeFull = ..
    if check_full(full) != 0 { return 15 }

    let doubled = (0..5).map(fn(take x: i32): i32 { x * 2 })
    if total(doubled) != 20 { return 1 }
    var count = 0
    let r = 2..6
    for i in r { count += i }
    if count != 14 { return 2 }
    if total(1..=4) != 10 { return 3 }
    var empty = 0..0
    if empty.count() != 0usize { return 4 }
    var back = (0..3).rev()
    match take back.next() {
        present(v) => { if v != 2 { return 5 } },
        none => { return 6 }
    }
    var tight = 0
    for i in 0..=3 { tight += i }
    if tight != 6 { return 7 }

    var data = [0; 300]
    var k = 0usize
    while k < 300usize {
        data[k] = ((k * 7919usize + 13usize) % 101usize) as i32
        k += 1usize
    }
    let ascending = mut data
    ascending.sort_unstable()
    if !data.is_sorted() { return 8 }
    let descending = mut data
    descending.sort_unstable_by(fn(read a: i32, read b: i32): Ordering { b.cmp(a) })
    k = 1usize
    while k < 300usize {
        if data[k - 1usize] < data[k] { return 9 }
        k += 1usize
    }
    let by_digit = mut data
    by_digit.sort_unstable_by_key(fn(read v: i32): i32 { v % 10 })
    k = 1usize
    while k < 300usize {
        if data[k - 1usize] % 10 > data[k] % 10 { return 10 }
        k += 1usize
    }
    var same = [7; 100]
    let flat = mut same
    flat.sort_unstable()
    if same[0usize] != 7 || same[99usize] != 7 { return 11 }
    0
}
