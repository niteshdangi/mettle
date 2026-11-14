// profiles: debug release
// Evidence for Range and RangeInclusive: Clone, equality, Default, emptiness,
// construction and iteration in both directions.

import core.cmp.{Eq, PartialEq}
import core.clone.Clone
import core.convert.Into
import core.default.Default
import core.hash.hash_one
import core.iter
import core.iter.{BidirectionalIterator, ExactSizeIterator, Iterator, RangeBounds}
import core.slice.SliceIndex
import core.text.Text

fn slice_selection<I: SliceIndex<[i32]>>(read index: I, read values: [i32]): read I.Output from values {
    index.index(values)
}

fn text_selection<I: SliceIndex<Text>>(read index: I, read text: Text): (read I.Output from text)? {
    index.get(text)
}

fn checks_slice_indices(): i32 {
    var values = [10i32, 20i32, 30i32, 40i32]
    if *slice_selection(read 1usize, read values) != 20i32 { return 40 }
    let span = core.range.Range(1usize, 3usize)
    let selected = slice_selection(read span, read values)
    if selected.len() != 2usize || selected[1] != 30i32 { return 41 }
    if core.range.Range(3usize, 2usize).get(read values).is_present() { return 42 }
    if core.range.RangeToInclusive(0xffffffffffffffffusize).get(read values).is_present() { return 43 }
    if core.range.RangeFull().get(read values).or_panic().len() != 4usize { return 44 }
    if core.range.RangeFrom(4usize).get(read values).or_panic().len() != 0usize { return 45 }
    let through = core.range.RangeInclusive(1usize, 2usize)
    through.get_mut(mut values).or_panic()[0] = 99i32
    if values[1] != 99i32 { return 46 }
    let bounds = (iter.Bound.Excluded(0usize), iter.Bound.Included(2usize))
    if bounds.get(read values).or_panic().len() != 2usize { return 47 }
    let slice: read [i32] = read values
    let pointer = unsafe { span.get_unchecked(core.ptr.from_ref(slice)) }
    if unsafe { (read *pointer).len() } != 2usize { return 48 }
    let element_pointer = unsafe { 1usize.get_unchecked(core.ptr.from_ref(slice)) }
    if unsafe { *element_pointer } != 99i32 { return 67 }
    let mutable_slice: mut [i32] = mut values
    let mutable_pointer = unsafe { span.get_unchecked_mut(core.ptr.from_mut(mutable_slice)) }
    unsafe { (mut *mutable_pointer)[1] = 77i32 }
    if values[2] != 77i32 { return 49 }
    if 4usize.get(read values).is_present() { return 68 }
    if core.range.Range(4usize, 5usize).get_mut(mut values).is_present() { return 69 }
    if core.range.RangeTo(2usize).get(read values).or_panic().len() != 2usize { return 50 }
    let overflow_start = (iter.Bound.Excluded(0xffffffffffffffffusize), iter.Bound.Unbounded)
    if overflow_start.get(read values).is_present() { return 51 }

    let text = "a\u{e9}z"
    if text_selection(read core.range.Range(1usize, 3usize), text).or_panic() != "\u{e9}" { return 52 }
    if text_selection(read core.range.Range(1usize, 2usize), text).is_present() { return 53 }
    if text_selection(read core.range.RangeFrom(2usize), text).is_present() { return 54 }
    if text_selection(read core.range.RangeTo(3usize), text).or_panic() != "a\u{e9}" { return 55 }
    if text_selection(read core.range.RangeToInclusive(2usize), text).or_panic() != "a\u{e9}" { return 56 }
    if text_selection(read core.range.RangeInclusive(1usize, 2usize), text).or_panic() != "\u{e9}" { return 57 }
    if text_selection(read core.range.RangeFull(), text).or_panic() != text { return 58 }
    if text_selection(read bounds, text).or_panic() != "\u{e9}" { return 59 }
    if text_selection(read core.range.RangeToInclusive(0xffffffffffffffffusize), text).is_present() { return 60 }
    let text_pointer = unsafe {
        core.range.Range(1usize, 3usize).get_unchecked(core.ptr.from_ref(text))
    }
    if unsafe { read *text_pointer } != "\u{e9}" { return 61 }
    var text_bytes = [97u8, 195u8, 169u8, 122u8]
    let mutable_text = core.text.from_utf8_mut(mut text_bytes).or_panic()
    let first = core.range.Range(0usize, 1usize).get_mut(mut mutable_text).or_panic()
    first.make_ascii_uppercase()
    if mutable_text != "A\u{e9}z" { return 62 }
    let first_pointer = unsafe {
        core.range.Range(0usize, 1usize).get_unchecked_mut(core.ptr.from_mut(mut mutable_text))
    }
    unsafe { (mut *first_pointer).make_ascii_lowercase() }
    if mutable_text != text { return 63 }
    var exhausted = iter.RangeInclusive.new(0usize, 0usize)
    if exhausted.next() != present(0usize) { return 64 }
    if exhausted.get(read values).or_panic().len() != 0usize { return 65 }
    if text_selection(read exhausted, text).or_panic().len() != 0usize { return 66 }
    0
}

fn default_of<T: Default>(): T { T.(Default).default() }

fn checks_range(): i32 {
    let span = iter.Range(2i32, 6i32)
    let duplicate = span.clone()
    if duplicate != span || duplicate.start != 2 || duplicate.end != 6 { return 1 }
    if hash_one(read span) != hash_one(read duplicate) { return 9 }
    let converted: iter.Range<i32> = span.clone().into()
    if converted != span { return 20 }
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
    if hash_one(read closed) != hash_one(read duplicate) { return 19 }
    let converted: iter.RangeInclusive<i32> = closed.clone().into()
    if converted != closed { return 21 }
    if closed.start != 1 || closed.end != 3 { return 22 }
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

fn checks_borrowed_range_iterators(): i32 {
    let span = core.range.Range(1i32, 4i32)
    if span.is_empty() || !core.range.Range(4i32, 4i32).is_empty() { return 29 }
    let default_span: core.range.Range<i32> = default_of()
    if default_span.start != 0 || default_span.end != 0 { return 31 }
    if !span.contains(read 1) || span.contains(read 4) { return 35 }
    var span_iter = span.iter()
    if span_iter.next() != present(1) || span_iter.next_back() != present(3) { return 23 }
    var repeated_span_iter = span.iter()
    if repeated_span_iter.next() != present(1) { return 24 }
    var owned_span_iter = core.iter.into_iterator(core.range.Range(2i32, 4i32))
    if owned_span_iter.next() != present(2) || owned_span_iter.next() != present(3) { return 32 }

    let open = core.range.RangeFrom(5i32)
    if !open.contains(read 5) || open.contains(read 4) { return 36 }
    var open_iter = open.iter()
    if open_iter.next() != present(5) || open_iter.next() != present(6) { return 25 }
    var repeated_open_iter = open.iter()
    if repeated_open_iter.next() != present(5) { return 26 }
    var owned_open_iter = core.iter.into_iterator(core.range.RangeFrom(5i32))
    if owned_open_iter.next() != present(5) || owned_open_iter.next() != present(6) { return 33 }

    let closed = core.range.RangeInclusive(2i32, 4i32)
    if closed.is_empty() || !core.range.RangeInclusive(5i32, 4i32).is_empty() { return 30 }
    if !closed.contains(read 4) || closed.contains(read 5) { return 37 }
    var closed_iter = closed.iter()
    if closed_iter.next_back() != present(4) || closed_iter.next() != present(2) { return 27 }
    var repeated_closed_iter = closed.iter()
    if repeated_closed_iter.next() != present(2) { return 28 }
    var owned_closed_iter = core.iter.into_iterator(core.range.RangeInclusive(2i32, 3i32))
    if owned_closed_iter.next() != present(2) || owned_closed_iter.next_back() != present(3) { return 34 }
    let before = core.range.RangeTo(4i32)
    if !before.contains(read 3) || before.contains(read 4) { return 38 }
    let through = core.range.RangeToInclusive(4i32)
    if !through.contains(read 4) || through.contains(read 5) { return 39 }
    0
}

fn main(): i32 {
    let slice_status = checks_slice_indices()
    if slice_status != 0 { return slice_status }
    let range_status = checks_range()
    if range_status != 0 { return range_status }
    let inclusive_status = checks_inclusive()
    if inclusive_status != 0 { return inclusive_status }
    checks_borrowed_range_iterators()
}
