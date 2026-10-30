import core.iter.{Iterator, BidirectionalIterator}

fn total<I: Iterator<Item = i32>>(it: take I): i32 {
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
    let doubled = (0..5).map(fn(x: take i32): i32 { x * 2 })
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
    descending.sort_unstable_by(fn(a: read i32, b: read i32): Ordering { b.cmp(a) })
    k = 1usize
    while k < 300usize {
        if data[k - 1usize] < data[k] { return 9 }
        k += 1usize
    }
    let by_digit = mut data
    by_digit.sort_unstable_by_key(fn(v: read i32): i32 { v % 10 })
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
