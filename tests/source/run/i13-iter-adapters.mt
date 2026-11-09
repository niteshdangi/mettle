// expect-exit: 0
// profiles: debug release
// Evidence for the lazy Iterator adapters: each adapter's items, its
// double-ended behaviour where it has one, and its size hint. Expected values
// are derived by hand from the input ranges.

import alloc.vec.List
import core.iter
import core.iter.{collect, BidirectionalIterator, ExtendItems, Iterator, OwnedIterable}

fn checks_mapping(): i32 {
    if iter.range(1, 4).map(fn(take x: i32): i32 { x * 2 }).sum<i32>() != 12 { return 1 }
    var mapped = iter.range(1, 4).map(fn(take x: i32): i32 { x * 2 })
    if mapped.next_back() != present(6) || mapped.next() != present(2) { return 2 }
    if iter.range(0, 5).filter_map(fn(take x: i32): i32? {
        if x % 2 == 1 { present(x * 10) } else { none }
    }).sum<i32>() != 40 { return 3 }
    if iter.range(0, 10).map_while(fn(take x: i32): i32? {
        if x < 3 { present(x) } else { none }
    }).count() != 3usize { return 4 }
    if iter.range(0, 6).filter(fn(read x: i32): bool { x % 2 == 0 }).count() != 3usize { return 5 }
    var filtered = iter.range(0, 6).filter(fn(read x: i32): bool { x % 2 == 0 })
    if filtered.next_back() != present(4) || filtered.next() != present(0) { return 6 }
    0
}

fn checks_nesting(): i32 {
    if iter.range(1, 4).flat_map(fn(take x: i32): iter.Range<i32> { iter.range(0, x) }).count() != 6usize { return 10 }
    if iter.range(1, 3).map(fn(take x: i32): iter.Range<i32> { iter.range(0, x) }).flatten().sum<i32>() != 1 { return 11 }
    var flat = iter.range(1, 4).flat_map(fn(take x: i32): iter.Range<i32> { iter.range(0, x) })
    if flat.next_back() != present(2) || flat.next() != present(0) { return 12 }
    0
}

fn checks_pairing(): i32 {
    var enumerated = iter.range(5, 8).enumerate()
    match take enumerated.next() {
        present((index, value)) => { if index != 0usize || value != 5 { return 20 } },
        none => { return 20 }
    }
    match take enumerated.next_back() {
        present((index, value)) => { if index != 2usize || value != 7 { return 21 } },
        none => { return 21 }
    }
    if iter.range(0, 3).zip(iter.range(10, 20)).count() != 3usize { return 22 }
    if iter.zip(iter.range(0, 2), iter.range(5, 9)).count() != 2usize { return 23 }
    var zipped = iter.range(0, 3).zip(iter.range(10, 13))
    match take zipped.next_back() {
        present((left, right)) => { if left != 2 || right != 12 { return 24 } },
        none => { return 24 }
    }
    if iter.range(0, 2).chain(iter.range(5, 7)).sum<i32>() != 12 { return 25 }
    if iter.chain(iter.range(0, 2), iter.range(5, 7)).count() != 4usize { return 26 }
    var chained = iter.range(0, 2).chain(iter.range(5, 7))
    if chained.next_back() != present(6) || chained.next_back() != present(5) { return 27 }
    if chained.next() != present(0) || chained.next_back() != present(1) { return 28 }
    if chained.next().is_present() { return 29 }
    0
}

fn checks_reversal_and_slicing(): i32 {
    var reversed = iter.range(0, 4).rev()
    if reversed.next() != present(3) || reversed.next_back() != present(0) { return 30 }
    if iter.range(0, 10).take_n(3usize).sum<i32>() != 3 { return 31 }
    if iter.range(0, 10).skip(7usize).sum<i32>() != 24 { return 32 }
    if iter.range(0, 10).take_while(fn(read x: i32): bool { x < 4 }).count() != 4usize { return 33 }
    if iter.range(0, 10).skip_while(fn(read x: i32): bool { x < 7 }).count() != 3usize { return 34 }
    if iter.range(0, 10).step_by(3usize).count() != 4usize { return 35 }
    var stepped = iter.range(0, 10).step_by(3usize)
    if stepped.next() != present(0) || stepped.next() != present(3) { return 36 }
    var limited = iter.range(0, 10).take_n(4usize)
    if limited.next() != present(0) || limited.count() != 3usize { return 37 }
    0
}

fn checks_observation(): i32 {
    var observed = 0
    let total = iter.range(1, 5).inspect(fn(read x: i32): Unit { observed = observed + x }).count()
    if total != 4usize || observed != 10 { return 40 }
    var peeked = iter.range(4, 6).peekable()
    match peeked.peek() {
        present(value) => { if *value != 4 { return 41 } },
        none => { return 41 }
    }
    if peeked.next() != present(4) || peeked.next() != present(5) || peeked.next().is_present() { return 42 }
    var fused = iter.range(0, 2).fuse()
    if fused.next() != present(0) || fused.next() != present(1) { return 43 }
    if fused.next().is_present() || fused.next().is_present() { return 44 }
    var scanned = iter.range(1, 5).scan(0, fn(mut state: i32, take x: i32): i32? {
        state = state + x
        present(state)
    })
    if scanned.count() != 4usize { return 45 }
    var running = iter.range(1, 5).scan(0, fn(mut state: i32, take x: i32): i32? {
        state = state + x
        present(state)
    })
    if running.last() != present(10) { return 46 }
    var stopped = iter.range(1, 9).scan(0, fn(mut state: i32, take x: i32): i32? {
        state = state + x
        if state > 5 { none } else { present(state) }
    })
    if stopped.count() != 2usize { return 47 }
    if iter.range(1, 3).cycle().take_n(5usize).sum<i32>() != 7 { return 48 }
    0
}

fn checks_borrowed_items(): i32 {
    var source: List<i32> = collect(iter.range(1, 4))
    if source.iter().copied().sum<i32>() != 6 { return 50 }
    if source.iter().cloned().count() != 3usize { return 51 }
    var backward = source.iter().copied()
    if backward.next_back() != present(3) { return 52 }
    source.extend(iter.range(9, 10))
    if source.len() != 4usize { return 53 }
    0
}

fn checks_size_hints(): i32 {
    if iter.range(0, 5).map(fn(take x: i32): i32 { x }).size_hint() != (5usize, present(5usize)) { return 60 }
    if iter.range(0, 5).filter(fn(read x: i32): bool { x > 0 }).size_hint() != (0usize, present(5usize)) { return 61 }
    if iter.range(0, 10).take_n(3usize).size_hint() != (3usize, present(3usize)) { return 62 }
    if iter.range(0, 10).skip(7usize).size_hint() != (3usize, present(3usize)) { return 63 }
    if iter.range(0, 10).step_by(3usize).size_hint() != (4usize, present(4usize)) { return 64 }
    if iter.range(0, 2).chain(iter.range(5, 8)).size_hint() != (5usize, present(5usize)) { return 65 }
    if iter.range(0, 3).zip(iter.range(0, 5)).size_hint() != (3usize, present(3usize)) { return 66 }
    if iter.range(5, 8).enumerate().size_hint() != (3usize, present(3usize)) { return 67 }
    if iter.range(0, 4).rev().size_hint() != (4usize, present(4usize)) { return 68 }
    if iter.range(0, 4).fuse().size_hint() != (4usize, present(4usize)) { return 69 }
    if iter.range(0, 4).inspect(fn(read x: i32): Unit {}).size_hint() != (4usize, present(4usize)) { return 70 }
    if iter.range(0, 4).peekable().size_hint() != (4usize, present(4usize)) { return 71 }
    if iter.range(0, 4).take_while(fn(read x: i32): bool { x < 9 }).size_hint().1 != present(4usize) { return 72 }
    0
}

fn main(): i32 {
    var code = checks_mapping()
    if code != 0 { return code }
    code = checks_nesting()
    if code != 0 { return code }
    code = checks_pairing()
    if code != 0 { return code }
    code = checks_reversal_and_slicing()
    if code != 0 { return code }
    code = checks_observation()
    if code != 0 { return code }
    code = checks_borrowed_items()
    if code != 0 { return code }
    checks_size_hints()
}
