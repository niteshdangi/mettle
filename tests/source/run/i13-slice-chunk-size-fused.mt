// profiles: debug release
import core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, FusedIterator}

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
        let view: read [i32] = read values
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
