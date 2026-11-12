// expect-exit: 0
// profiles: debug release
// Evidence for the consuming Iterator operations: folds, counts, searches,
// extremes, sums/products, collection, and the double-ended consumers. Each
// result is checked against a value derived by hand.

import alloc.vec.List
import core.cmp.Ordering
import core.iter
import core.iter.{collect, BidirectionalIterator, ExtendItems, Iterator}

fn stop_past_ten(take value: i32): Unit throws bool {
    if value > 10 { throw true }
}

fn checks_folds(): i32 {
    if iter.range(1, 5).fold(0, fn(take total: i32, take value: i32): i32 { total + value }) != 10 { return 1 }
    if iter.empty<i32>().fold(7, fn(take total: i32, take value: i32): i32 { total + value }) != 7 { return 2 }
    var reversed = iter.range(0, 4)
    if reversed.rfold(0, fn(take acc: i32, take value: i32): i32 { acc * 10 + value }) != 3210 { return 3 }
    var attempted = iter.range(1, 5)
    let total = attempted.try_fold(0, fn(take acc: i32, take value: i32): i32 throws bool {
        acc + value
    })
    match total {
        success(value) => { if value != 10 { return 4 } },
        failure(_) => { return 5 }
    }
    var stopping = iter.range(1, 9)
    let stopped = stopping.try_fold(0, fn(take acc: i32, take value: i32): i32 throws i32 {
        if value == 3 { throw value }
        acc + value
    })
    match stopped {
        success(_) => { return 6 },
        failure(value) => { if value != 3 { return 7 } }
    }
    var backward = iter.range(1, 5)
    let back_total = backward.try_rfold(0, fn(take acc: i32, take value: i32): i32 throws bool {
        acc * 10 + value
    })
    match back_total {
        success(value) => { if value != 4321 { return 8 } },
        failure(_) => { return 9 }
    }
    var each = iter.range(0, 3)
    let ok = each.try_for_each(stop_past_ten)
    match ok {
        success(_) => {},
        failure(_) => { return 10 }
    }
    var seen = 0
    var visitor = iter.range(0, 4)
    visitor.for_each(fn(take value: i32): Unit { seen = seen + value })
    if seen != 6 { return 11 }
    0
}

fn checks_counts_and_ends(): i32 {
    var counted = iter.range(0, 7)
    if counted.count() != 7usize { return 20 }
    if iter.range(0, 0).count() != 0usize { return 21 }
    if iter.range(3, 6).last() != present(5) { return 22 }
    if iter.empty<i32>().last().is_present() { return 23 }
    var nth = iter.range(0, 10)
    if nth.nth(3usize) != present(3) { return 24 }
    if nth.next() != present(4) { return 25 }
    var short = iter.range(0, 2)
    if short.nth(5usize).is_present() { return 26 }
    var back = iter.range(0, 6)
    if back.nth_back(2usize) != present(3) { return 27 }
    if back.next_back() != present(2) { return 28 }
    var first = iter.range(4, 9)
    match take first.next() {
        present(value) => { if value != 4 { return 29 } },
        none => { return 29 }
    }
    0
}

fn checks_searches(): i32 {
    var finder = iter.range(1, 10)
    if finder.find(fn(read value: i32): bool { value * value > 20 }) != present(5) { return 30 }
    if iter.range(1, 4).find(fn(read value: i32): bool { value > 9 }).is_present() { return 31 }
    if iter.range(0, 8).position(fn(take value: i32): bool { value == 6 }) != present(6usize) { return 32 }
    if iter.range(0, 8).position(fn(take value: i32): bool { value > 90 }).is_present() { return 33 }
    if iter.range(0, 5).rposition(fn(take value: i32): bool { value == 3 }) != present(3usize) { return 34 }
    var backward = iter.range(0, 6)
    if backward.rfind(fn(read value: i32): bool { value % 2 == 1 }) != present(5) { return 35 }
    if iter.range(0, 6).find_map(fn(take value: i32): i32? {
        if value > 3 { present(value * 100) } else { none }
    }) != present(400) { return 36 }
    if iter.range(0, 6).find_map(fn(take value: i32): i32? { none }).is_present() { return 37 }
    if !iter.range(1, 5).any(fn(take value: i32): bool { value == 4 }) { return 38 }
    if iter.range(1, 5).any(fn(take value: i32): bool { value == 9 }) { return 39 }
    if !iter.range(1, 5).all(fn(take value: i32): bool { value > 0 }) { return 40 }
    if iter.range(1, 5).all(fn(take value: i32): bool { value < 3 }) { return 41 }
    if !iter.empty<i32>().all(fn(take value: i32): bool { false }) { return 42 }
    0
}

fn checks_extremes(): i32 {
    if iter.range(1, 5).max() != present(4) { return 50 }
    if iter.range(1, 5).min() != present(1) { return 51 }
    if iter.empty<i32>().max().is_present() || iter.empty<i32>().min().is_present() { return 52 }
    if iter.range(1, 5).max_by(fn(read a: i32, read b: i32): Ordering {
        if a < b { Ordering.Less } else if a == b { Ordering.Equal } else { Ordering.Greater }
    }) != present(4) { return 53 }
    if iter.range(1, 5).min_by(fn(read a: i32, read b: i32): Ordering {
        if a < b { Ordering.Less } else if a == b { Ordering.Equal } else { Ordering.Greater }
    }) != present(1) { return 54 }
    if iter.range(1, 5).max_by_key(fn(read value: i32): i32 { -value }) != present(1) { return 55 }
    if iter.range(1, 5).min_by_key(fn(read value: i32): i32 { -value }) != present(4) { return 56 }
    if iter.range(1, 4).reduce(fn(take a: i32, take b: i32): i32 { a * b }) != present(6) { return 57 }
    if iter.empty<i32>().reduce(fn(take a: i32, take b: i32): i32 { a + b }).is_present() { return 58 }
    0
}

fn checks_sums_and_collection(): i32 {
    if iter.range(1, 5).sum<i32>() != 10 { return 60 }
    if iter.range(1, 5).product<i32>() != 24 { return 61 }
    if iter.range(0, 0).sum<i32>() != 0 { return 62 }
    let squares: List<i32> = iter.range(0, 4).map(fn(take x: i32): i32 { x * x }).collect()
    if squares.len() != 4usize || squares.as_slice()[3usize] != 9 { return 63 }
    let copied: List<i32> = collect(iter.range(2, 5))
    if copied.len() != 3usize || copied.as_slice()[0usize] != 2 { return 64 }
    var rebuilt: List<i32> = collect(iter.range(0, 0))
    if rebuilt.len() != 0usize { return 65 }
    rebuilt.extend(iter.range(7, 9))
    if rebuilt.len() != 2usize || rebuilt.as_slice()[1usize] != 8 { return 66 }
    0
}

fn checks_by_ref(): i32 {
    var source = iter.range(0, 10)
    {
        var front = source.by_ref().take_n(3usize)
        if front.count() != 3usize { return 70 }
    }
    match take source.next() {
        present(value) => { if value != 3 { return 71 } },
        none => { return 71 }
    }
    0
}

type Counted {
    value: i32
    drops: ptr<mut usize>
    // The enclosing checks_unzip scope keeps this counter alive through every drop.
    drop { unsafe { *self.drops += 1usize } }
}

fn checks_unzip(): i32 {
    let (empty_left, empty_right) = iter.empty<(i32, bool)>().unzip<i32, bool, List<i32>, List<bool>>()
    if empty_left.len() != 0usize || empty_right.len() != 0usize { return 80 }
    let (left, right) = iter.range(0, 4).map(
        fn(take value: i32): (i32, bool) { (value * 10, value % 2 == 0) }
    ).unzip<i32, bool, List<i32>, List<bool>>()
    if left.len() != 4usize || right.len() != 4usize { return 81 }
    if left.as_slice()[0usize] != 0 || left.as_slice()[3usize] != 30 { return 82 }
    if !right.as_slice()[0usize] || right.as_slice()[1usize] ||
        !right.as_slice()[2usize] || right.as_slice()[3usize] { return 83 }
    var drops = 0usize
    {
        var pairs = alloc.vec.new<(Counted, Counted)>()
        pairs.push((Counted(1, core.ptr.from_mut(drops)), Counted(2, core.ptr.from_mut(drops))))
        pairs.push((Counted(3, core.ptr.from_mut(drops)), Counted(4, core.ptr.from_mut(drops))))
        let (owners_left, owners_right) = pairs.into_iter().unzip<Counted, Counted, List<Counted>, List<Counted>>()
        if drops != 0usize { return 84 }
        if owners_left.len() != 2usize || owners_right.len() != 2usize { return 85 }
        if owners_left.as_slice()[1usize].value != 3 || owners_right.as_slice()[0usize].value != 2 { return 86 }
    }
    if drops != 4usize { return 87 }
    0
}

fn main(): i32 {
    var code = checks_folds()
    if code != 0 { return code }
    code = checks_counts_and_ends()
    if code != 0 { return code }
    code = checks_searches()
    if code != 0 { return code }
    code = checks_extremes()
    if code != 0 { return code }
    code = checks_sums_and_collection()
    if code != 0 { return code }
    code = checks_by_ref()
    if code != 0 { return code }
    checks_unzip()
}
