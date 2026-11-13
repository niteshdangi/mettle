// profiles: debug release
import core.iter.{Iterator, BidirectionalIterator}

fn main(): i32 {
    var forward = [1, 2, 3, 4, 5]
    {
        let view: mut [i32] = mut forward[..]
        var chunks = view.chunks_exact_mut(2usize)
        let first = chunks.next().or_panic()
        let last = chunks.next_back().or_panic()
        let remainder = take chunks.into_remainder()
        assert(remainder.len() == 1usize, "forward omitted suffix")
        first[0usize] = 10
        last[0usize] = 30
        remainder[0usize] = 50
    }
    assert(forward[0usize] == 10 && forward[2usize] == 30 && forward[4usize] == 50,
        "forward remainder remains disjoint from yielded chunks")
    var reverse = [1, 2, 3, 4, 5, 6, 7]
    {
        let view: mut [i32] = mut reverse[..]
        var chunks = view.rchunks_exact_mut(2usize)
        let last = chunks.next().or_panic()
        let first = chunks.next_back().or_panic()
        let remainder = take chunks.into_remainder()
        assert(remainder.len() == 1usize, "reverse remainder excludes unyielded full chunk")
        last[0usize] = 60
        first[0usize] = 20
        remainder[0usize] = 10
    }
    assert(reverse[0usize] == 10 && reverse[1usize] == 20 && reverse[5usize] == 60 &&
        reverse[3usize] == 4 && reverse[4usize] == 5,
        "reverse remainder remains disjoint from yielded chunks")
    {
        let view: mut [i32] = mut forward[..]
        var chunks = view.chunks_exact_mut(usize.MAX)
        assert(chunks.next().is_none(), "oversized chunk omitted")
        let remainder = take chunks.into_remainder()
        assert(remainder.len() == 5usize, "whole input is remainder")
        remainder[4usize] = 55
    }
    assert(forward[4usize] == 55, "whole-input remainder preserves owner")
    {
        let view: mut [i32] = mut reverse[..]
        var chunks = view.rchunks_exact_mut(7usize)
        let whole = chunks.next().or_panic()
        let remainder = take chunks.into_remainder()
        assert(remainder.len() == 0usize, "divisible input has empty remainder")
        whole[6usize] = 70
    }
    assert(reverse[6usize] == 70, "empty remainder leaves yielded view usable")
    0
}
