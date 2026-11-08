// expect-exit: 0
// profiles: debug release
// Evidence for the sequence comparison operations (eq, ne, lt, le, gt, ge,
// cmp, partial_cmp), the sortedness checks, partition, and the Peekable
// conditional consumers next_if_map / next_if_map_mut.

import alloc.vec.List
import core.iter
import core.iter.{collect, Iterator, OwnedIterable, Peekable}

fn checks_equality(): i32 {
    if !iter.range(1, 4).eq(iter.range(1, 4)) { return 1 }
    if iter.range(1, 4).eq(iter.range(1, 3)) { return 2 }
    if iter.range(1, 3).ne(iter.range(1, 3)) { return 3 }
    if !iter.range(1, 3).ne(iter.range(1, 4)) { return 4 }
    let listed: List<i32> = collect(iter.range(0, 3))
    if !iter.range(0, 3).eq(listed) { return 5 }
    if !iter.range(0, 0).eq(iter.empty<i32>()) { return 6 }
    0
}

fn checks_ordering(): i32 {
    if !iter.range(1, 3).lt(iter.range(1, 4)) { return 10 }
    if iter.range(1, 4).lt(iter.range(1, 3)) { return 11 }
    if !iter.range(1, 3).le(iter.range(1, 3)) { return 12 }
    if !iter.range(1, 4).gt(iter.range(1, 3)) { return 13 }
    if iter.range(1, 3).gt(iter.range(1, 3)) { return 14 }
    if !iter.range(1, 3).ge(iter.range(1, 3)) { return 15 }
    if iter.range(1, 3).ge(iter.range(2, 3)) { return 16 }
    if !iter.range(1, 3).cmp(iter.range(1, 4)).is_lt() { return 20 }
    if !iter.range(1, 4).cmp(iter.range(1, 3)).is_gt() { return 21 }
    if !iter.range(1, 3).cmp(iter.range(1, 3)).is_eq() { return 22 }
    match iter.once(1.0f64).partial_cmp(iter.once(2.0f64)) {
        present(order) => { if !order.is_lt() { return 23 } },
        none => { return 23 }
    }
    match iter.range(3, 4).partial_cmp(iter.range(3, 4)) {
        present(order) => { if !order.is_eq() { return 24 } },
        none => { return 24 }
    }
    0
}

fn checks_sortedness(): i32 {
    if !iter.range(0, 5).is_sorted() { return 30 }
    if iter.range(0, 4).map(fn(x: take i32): i32 { 3 - x }).is_sorted() { return 31 }
    if !iter.range(0, 4).is_sorted_by(fn(a: read i32, b: read i32): bool { a <= b }) { return 32 }
    if iter.range(0, 4).is_sorted_by(fn(a: read i32, b: read i32): bool { a >= b }) { return 33 }
    if !iter.range(0, 4).map(fn(x: take i32): i32 { 3 - x }).is_sorted_by_key(fn(x: read i32): i32 { -x }) { return 34 }
    if iter.range(0, 4).is_sorted_by_key(fn(x: read i32): i32 { -x }) { return 35 }
    if !iter.empty<i32>().is_sorted() { return 36 }
    0
}

fn checks_partition(): i32 {
    let parts: (List<i32>, List<i32>) = iter.range(0, 7).partition(fn(x: read i32): bool { x % 2 == 0 })
    if parts.0.len() != 4usize || parts.0.as_slice()[3usize] != 6 { return 40 }
    if parts.1.len() != 3usize || parts.1.as_slice()[0usize] != 1 { return 41 }
    let none_matched: (List<i32>, List<i32>) = iter.range(0, 3).partition(fn(x: read i32): bool { x > 9 })
    if none_matched.0.len() != 0usize || none_matched.1.len() != 3usize { return 42 }
    0
}

fn checks_peekable_conditionals(): i32 {
    var peeked = iter.range(1, 6).peekable()
    match peeked.next_if_map(fn(x: take i32): i32 throws i32 {
        if x == 1 { throw x }
        x * 10
    }) {
        present(_) => { return 50 },
        none => {}
    }
    match peeked.next() {
        present(value) => { if value != 1 { return 51 } },
        none => { return 51 }
    }
    match peeked.next_if_map(fn(x: take i32): i32 throws i32 {
        if x == 9 { throw x }
        x * 10
    }) {
        present(value) => { if value != 20 { return 52 } },
        none => { return 52 }
    }
    match peeked.next_if_map(fn(x: take i32): i32 throws i32 {
        if x == 3 { throw x }
        x * 10
    }) {
        present(_) => { return 53 },
        none => {}
    }
    match peeked.next() {
        present(value) => { if value != 3 { return 54 } },
        none => { return 54 }
    }

    var inspected = iter.range(1, 5).peekable()
    match inspected.next_if(fn(x: read i32): bool { x == 1 }) {
        present(value) => { if value != 1 { return 58 } },
        none => { return 58 }
    }
    match take inspected.peek_mut() {
        present(view) => { *view = 7 },
        none => { return 59 }
    }
    if inspected.next_if_eq(read 9).is_present() { return 60 }
    match inspected.next_if_eq(read 7) {
        present(value) => { if value != 7 { return 61 } },
        none => { return 61 }
    }
    if inspected.next() != present(3) { return 62 }

    var mapped = iter.range(3, 6).peekable()
    match mapped.next_if_map_mut(fn(x: mut i32): i32? {
        if x == 3 { present(x * 2) } else { none }
    }) {
        present(value) => { if value != 6 { return 55 } },
        none => { return 55 }
    }
    match mapped.next_if_map_mut(fn(x: mut i32): i32? {
        if x == 99 { present(x) } else { none }
    }) {
        present(_) => { return 56 },
        none => {}
    }
    match mapped.next() {
        present(value) => { if value != 4 { return 57 } },
        none => { return 57 }
    }
    0
}

fn main(): i32 {
    var code = checks_equality()
    if code != 0 { return code }
    code = checks_ordering()
    if code != 0 { return code }
    code = checks_sortedness()
    if code != 0 { return code }
    code = checks_partition()
    if code != 0 { return code }
    checks_peekable_conditionals()
}
