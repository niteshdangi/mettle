// profiles: debug release
// Evidence for Range and RangeInclusive: Clone, equality, Default, emptiness,
// construction and iteration in both directions.

import core.cmp.{Eq, PartialEq}
import core.clone.Clone
import core.default.Default
import core.iter
import core.iter.{BidirectionalIterator, ExactSizeIterator, Iterator, RangeBounds}

fn default_of<T: Default>(): T { T.(Default).default() }

fn checks_range(): i32 {
    let span = iter.Range(2i32, 6i32)
    let duplicate = span.clone()
    if duplicate != span || duplicate.start != 2 || duplicate.end != 6 { return 1 }
    if span == iter.Range(2i32, 7i32) { return 2 }
    let fallback: iter.Range<i32> = default_of<iter.Range<i32>>()
    if fallback.start != 0 || fallback.end != 0 || !fallback.is_empty() { return 3 }
    if span.is_empty() || !iter.Range(5i32, 5i32).is_empty() || !iter.Range(7i32, 3i32).is_empty() { return 4 }
    if span.len() != 4usize { return 5 }
    if !span.contains(read 2) || span.contains(read 6) { return 6 }
    var walked = iter.Range(2i32, 6i32)
    if walked.next() != present(2) || walked.next_back() != present(5) { return 7 }
    if walked.next() != present(3) || walked.next() != present(4) || walked.next().is_present() { return 8 }
    0
}

fn checks_inclusive(): i32 {
    let closed = iter.RangeInclusive.new(1i32, 3i32)
    let duplicate = closed.clone()
    if duplicate != closed { return 10 }
    if closed == iter.RangeInclusive.new(1i32, 4i32) { return 11 }
    let (low, high) = closed.clone().into_inner()
    if low != 1 || high != 3 { return 12 }
    if closed.is_empty() || !iter.RangeInclusive.new(4i32, 3i32).is_empty() { return 13 }
    if iter.RangeInclusive.new(1u8, 3u8).len() != 3usize { return 14 }
    if !closed.contains(read 3) || closed.contains(read 4) { return 15 }
    var walked = iter.RangeInclusive.new(1i32, 3i32)
    if walked.next_back() != present(3) || walked.next() != present(1) { return 16 }
    if walked.next() != present(2) || walked.next().is_present() { return 17 }
    var single = iter.RangeInclusive.new(7i32, 7i32)
    if single.next() != present(7) || single.next().is_present() { return 18 }
    0
}

fn main(): i32 {
    let range_status = checks_range()
    if range_status != 0 { return range_status }
    checks_inclusive()
}
