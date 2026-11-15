// profiles: debug release
import core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, FusedIterator}
import core.borrow.AsRef

fn require_fused<I: FusedIterator>(mut items: I): Unit {
    while items.next().is_present() {}
    assert(items.next().is_none(), "fused exhaustion")
}

fn require_bidirectional<I: Iterator + BidirectionalIterator>(mut items: I): Unit {
    let _ = items.next_back()
    let _ = items.next()
}

fn check<I: Iterator + BidirectionalIterator + ExactSizeIterator + FusedIterator>(
    take input: I, expected: usize
): Unit {
    var chunks = input
    var remaining = expected
    while remaining > 0usize {
        assert(chunks.len() == remaining, "remaining chunk count")
        let bounds = chunks.size_hint()
        assert(bounds.0 == remaining && bounds.1 == present(remaining), "exact bounds")
        if remaining % 2usize == 0usize {
            assert(chunks.next_back().is_present(), "back chunk")
        } else {
            assert(chunks.next().is_present(), "front chunk")
        }
        remaining -= 1usize
    }
    assert(chunks.len() == 0usize, "empty chunk count")
    let bounds = chunks.size_hint()
    assert(bounds.0 == 0usize && bounds.1 == present(0usize), "empty exact bounds")
    assert(chunks.next().is_none() && chunks.next_back().is_none(), "fused exhaustion")
    assert(chunks.next().is_none(), "repeated exhaustion")
}

fn main(): i32 {
    var values = [1, 2, 3, 4, 5, 6, 7]
    {
        var items = values.iter()
        let _first = items.next()
        let remaining = items.as_ref()
        assert(
            remaining.len() == 6usize && remaining[0usize] == 2 && remaining[5usize] == 7,
            "slice iterator AsRef exposes the remaining elements"
        )
    }
    {
        var items = values.iter_mut()
        let remaining = items.as_ref()
        assert(
            remaining.len() == 7usize && remaining[0usize] == 1 && remaining[6usize] == 7,
            "mutable slice iterator AsRef exposes unconsumed elements"
        )
    }
    {
        let view: read [i32] = read values
        require_fused(view.split(fn(value: i32): bool { value == 0 }))
        require_fused(view.chunk_by(fn(a: i32, b: i32): bool { a == b }))
        check(view.chunks(3usize), 3usize)
        check(view.chunks_exact(3usize), 2usize)
        check(view.rchunks(3usize), 3usize)
        check(view.rchunks_exact(3usize), 2usize)
        check(view.windows(3usize), 5usize)
        check(view.chunks(usize.MAX), 1usize)
        check(view.chunks_exact(usize.MAX), 0usize)
        check(view.rchunks(usize.MAX), 1usize)
        check(view.rchunks_exact(usize.MAX), 0usize)
        let empty = view.split_at(0usize).0
        check(empty.chunks(3usize), 0usize)
        check(empty.chunks_exact(3usize), 0usize)
        check(empty.rchunks(3usize), 0usize)
        check(empty.rchunks_exact(3usize), 0usize)
        check(empty.windows(3usize), 0usize)
    }
    {
        let view: mut [i32] = mut values
        require_fused(view.split_mut(fn(value: i32): bool { value == 0 }))
        require_fused(view.chunk_by_mut(fn(a: i32, b: i32): bool { a == b }))
        require_bidirectional(view.split_mut(fn(value: i32): bool { value == 0 }))
        require_bidirectional(view.split_inclusive_mut(fn(value: i32): bool { value == 0 }))
        require_bidirectional(view.rsplit_mut(fn(value: i32): bool { value == 0 }))
        check(view.chunks_mut(3usize), 3usize)
        check(view.chunks_exact_mut(3usize), 2usize)
        check(view.rchunks_mut(3usize), 3usize)
        check(view.rchunks_exact_mut(3usize), 2usize)
        check(view.chunks_mut(usize.MAX), 1usize)
        check(view.chunks_exact_mut(usize.MAX), 0usize)
        check(view.rchunks_mut(usize.MAX), 1usize)
        check(view.rchunks_exact_mut(usize.MAX), 0usize)
        let empty = view.split_at_mut(0usize).0
        check(empty.chunks_mut(3usize), 0usize)
        check(empty.chunks_exact_mut(3usize), 0usize)
        check(empty.rchunks_mut(3usize), 0usize)
        check(empty.rchunks_exact_mut(3usize), 0usize)
    }
    0
}
