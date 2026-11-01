// profiles: debug release
import core.iter
import core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, FusedIterator, Iterable}

fn exhausted_fused<I: FusedIterator>(items: mut I): bool {
    items.next().is_none() && items.next().is_none()
}

fn main(): i32 {
    assert(iter.range(i8.MIN, i8.MAX).len() == 255usize, "signed distance")
    assert(iter.range(i8.MAX, i8.MIN).len() == 0usize, "reversed distance")
    assert(iter.range_inclusive(u8.MIN, u8.MAX).len() == 256usize, "inclusive full width")
    match iter.range(i128.MIN, i128.MAX).size_hint() {
        (lower, none) => assert(lower == usize.MAX, "wide distance saturates"),
        _ => { return 1 }
    }
    match iter.range_inclusive(0usize, usize.MAX).size_hint() {
        (lower, none) => assert(lower == usize.MAX, "inclusive upper overflow"),
        _ => { return 2 }
    }
    match iter.range('\u{d7ff}', '\u{e001}').size_hint() {
        (2usize, present(2usize)) => {},
        _ => { return 3 }
    }
    var stepped = iter.range(0, 10).step_by(3usize)
    assert(stepped.len() == 4usize, "initial stepped count")
    assert(stepped.next_back() == present(9), "last step")
    assert(stepped.len() == 3usize, "back count")
    assert(stepped.next() == present(0), "first step")
    assert(stepped.next_back() == present(6), "mixed last step")
    assert(stepped.len() == 1usize, "mixed count")
    assert(stepped.next() == present(3), "remaining step")
    assert(stepped.next_back().is_none() && stepped.len() == 0usize, "step exhaustion")
    assert(exhausted_fused(mut stepped), "fused repeated exhaustion")
    var zipped = iter.range(0, 5).zip(iter.range(10, 13))
    assert(zipped.next_back() == present((2, 12)), "unequal zip aligns tails")
    assert(zipped.len() == 2usize, "zip count after alignment")
    assert(zipped.next() == present((0, 10)), "zip front")
    assert(zipped.next_back() == present((1, 11)), "zip remaining back")
    assert(zipped.next().is_none(), "zip exhaustion")
    var numbered = iter.range(4, 8).enumerate()
    assert(numbered.next() == present((0usize, 4)), "enumerated front")
    assert(numbered.next_back() == present((3usize, 7)), "global back index")
    assert(numbered.next_back() == present((2usize, 6)), "next global back index")
    assert(numbered.next() == present((1usize, 5)), "global middle index")
    var calls = 0usize
    {
        var flattened = iter.range(1, 4).flat_map(fn(value: i32): iter.Range<i32> {
            calls += 1usize
            iter.range(value * 10, value * 10 + 2)
        })
        assert(flattened.size_hint().0 == 0usize, "flat map initial hint")
        assert(flattened.next() == present(10), "flat map front")
        assert(flattened.next_back() == present(31), "independent back inner")
        assert(flattened.next() == present(11), "retained front inner")
        assert(flattened.next_back() == present(30), "retained back inner")
        assert(flattened.next() == present(20), "middle inner")
        assert(flattened.next_back() == present(21), "middle inner from back")
        assert(flattened.next().is_none() && flattened.next_back().is_none(), "flat map exhaustion")
    }
    assert(calls == 3usize, "mapper called once per outer item")
    var reverse_search = iter.range(0, 6)
    assert(reverse_search.rposition(fn(value: i32): bool { value == 3 }) == present(3usize), "reverse index")
    assert(reverse_search.len() == 3usize, "rposition preserves prefix")
    assert(reverse_search.next() == present(0), "prefix remains usable")
    let values = [4, 5, 6]
    let slice: read [i32] = read values
    var copied = slice.iter().copied()
    assert(copied.next_back() == present(6) && copied.next() == present(4), "copied reverse")
    var cloned = slice.iter().cloned()
    assert(cloned.next_back() == present(6) && cloned.len() == 2usize, "cloned reverse count")
    var peeked = iter.range(0, 2).peekable()
    match take peeked.peek() {
        present(value) => assert(*value == 0, "peek returns actual first item"),
        none => { return 4 }
    }
    assert(peeked.len() == 2usize, "buffered item counted")
    assert(peeked.next_back() == present(1) && peeked.next() == present(0), "peek mixed traversal")
    assert(peeked.len() == 0usize, "peek exhaustion count")
    0
}
