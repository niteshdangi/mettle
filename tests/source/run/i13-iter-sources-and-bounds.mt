// expect-exit: 0
// profiles: debug release
// Evidence for the iterator sources (once, empty, from_fn, repeat, successors),
// owned iteration (OwnedIterable / into_iterator on collections and iterators),
// the ExactSizeIterator and FusedIterator contracts, and the double-ended
// contract of the sources.

import alloc.vec.List
import core.iter
import core.iter.{collect, BidirectionalIterator, ExactSizeIterator, FusedIterator, Iterator, OwnedIterable}

fn require_exact<I: ExactSizeIterator>(take items: I): usize {
    var source = items
    source.len()
}

fn require_fused<I: FusedIterator>(take items: I): usize {
    var source = items
    var seen = 0usize
    while true {
        match take source.next() {
            present(_) => { seen += 1usize },
            none => { break }
        }
    }
    seen
}

fn require_double_ended<I: BidirectionalIterator + Iterator<Item = i32>>(take items: I): i32? {
    var source = items
    source.next_back()
}

fn checks_sources(): i32 {
    var single = iter.once(5)
    if single.size_hint() != (1usize, present(1usize)) { return 1 }
    if single.next_back() != present(5) || single.next().is_present() { return 2 }
    if iter.once(7).next() != present(7) { return 3 }
    var none_left = iter.empty<i32>()
    if none_left.next().is_present() || none_left.next_back().is_present() { return 4 }
    if iter.empty<i32>().size_hint() != (0usize, present(0usize)) { return 5 }
    var counter = 0
    var generated = iter.from_fn(fn(): i32? {
        counter = counter + 1
        if counter <= 3 { present(counter) } else { none }
    })
    if generated.next() != present(1) || generated.next() != present(2) { return 6 }
    if generated.next() != present(3) || generated.next().is_present() { return 7 }
    var repeated = iter.repeat(7)
    if repeated.take_n(3usize).sum<i32>() != 21 { return 8 }
    var chained_successors = iter.successors(
        present(1),
        fn(read value: i32): i32? { if value < 4 { present(value + 1) } else { none } }
    )
    if chained_successors.sum<i32>() != 10 { return 9 }
    var single_successor = iter.successors(present(9), fn(read value: i32): i32? { none })
    if single_successor.next() != present(9) || single_successor.next().is_present() { return 10 }
    if iter.successors(none, fn(read value: i32): i32? { none }).next().is_present() { return 11 }
    0
}

fn checks_owned_iteration(): i32 {
    var source: List<i32> = collect(iter.range(4, 7))
    var owned = iter.into_iterator(source)
    if owned.next() != present(4) || owned.next_back() != present(6) { return 20 }
    var from_range = iter.into_iterator(iter.range(0, 3))
    if from_range.sum<i32>() != 3 { return 21 }
    let pairs: List<(i32, i32)> = collect(iter.range(0, 2).map(fn(take x: i32): (i32, i32) { (x, x * 2) }))
    if pairs.len() != 2usize || pairs.as_slice()[1usize].1 != 2 { return 22 }
    0
}

fn checks_exact_and_fused(): i32 {
    if require_exact(iter.range(0, 6)) != 6usize { return 30 }
    if require_exact(iter.range(0, 6).map(fn(take x: i32): i32 { x + 1 })) != 6usize { return 31 }
    if require_exact(iter.once(1)) != 1usize { return 32 }
    if require_exact(iter.empty<i32>()) != 0usize { return 33 }
    var ranged = iter.range(3, 5)
    if ranged.len() != 2usize { return 34 }
    if require_fused(iter.range(0, 3)) != 3usize { return 35 }
    if require_fused(iter.once(9)) != 1usize { return 36 }
    if require_fused(iter.empty<i32>()) != 0usize { return 37 }
    if require_fused(iter.range(0, 4).fuse()) != 4usize { return 38 }
    if require_fused(iter.repeat(1).take_n(2usize)) != 2usize { return 39 }
    0
}

fn checks_double_ended_sources(): i32 {
    if require_double_ended(iter.once(4)) != present(4) { return 40 }
    if require_double_ended(iter.range(0, 5)) != present(4) { return 41 }
    if require_double_ended(iter.range(0, 5).rev()) != present(0) { return 42 }
    if require_double_ended(iter.empty<i32>()).is_present() { return 43 }
    0
}

fn main(): i32 {
    var code = checks_sources()
    if code != 0 { return code }
    code = checks_owned_iteration()
    if code != 0 { return code }
    code = checks_exact_and_fused()
    if code != 0 { return code }
    checks_double_ended_sources()
}
