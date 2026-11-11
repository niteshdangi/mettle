// profiles: debug release
import core.iter
import core.iter.{Iterator, BidirectionalIterator}
import core.cmp.{Ord, Ordering}

type Gap { step: usize }
extend Gap implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        let step = self.step
        self.step += 1usize
        if step == 1usize { present(2) } else if step == 2usize { present(1) } else { none }
    }
}
fn gap(): Gap { Gap(0usize) }

type PeekGap { gap: bool; value: i32? }
extend PeekGap implements Iterator {
    type Item = i32
    fn size_hint(): (usize, usize?) {
        if self.gap { return (0usize, none) }
        let n = if self.value.is_present() { 1usize } else { 0usize }
        (n, present(n))
    }
    mut fn next(): i32? {
        if self.gap { self.gap = false; return none }
        self.value.take_value()
    }
}
extend PeekGap implements BidirectionalIterator {
    mut fn next_back(): i32? { self.value.take_value() }
}

fn main(): i32 {
    assert(gap().min().is_none(), "minimum stops on first none")
    assert(gap().max().is_none(), "maximum stops on first none")
    assert(iter.min(gap()).is_none() && iter.max(gap()).is_none(), "free extrema stop")
    assert(gap().min_by(fn(read a: i32, read b: i32): Ordering { a.cmp(b) }).is_none(), "minimum comparator")
    assert(gap().max_by(fn(read a: i32, read b: i32): Ordering { a.cmp(b) }).is_none(), "maximum comparator")
    assert(gap().min_by_key(fn(read a: i32): i32 { a }).is_none(), "minimum key")
    assert(gap().max_by_key(fn(read a: i32): i32 { a }).is_none(), "maximum key")
    assert(gap().reduce(fn(take a: i32, take b: i32): i32 { a + b }).is_none(), "reduce stops")
    assert(gap().is_sorted(), "initially empty input is sorted")
    assert(gap().is_sorted_by(fn(read a: i32, read b: i32): bool { a <= b }), "sorted predicate not polled")
    var peek = PeekGap(true, present(7)).peekable()
    assert(peek.peek().is_none(), "cache forward none")
    assert(peek.size_hint() == (0usize, present(0usize)), "cache empty bound")
    assert(peek.next_back().is_none(), "reverse consumes cached none without source poll")
    assert(peek.next() == present(7), "nonfused source resumes after cache consumed")
    assert(peek.next().is_none() && peek.next_back().is_none(), "exhaustion")
    var borrowed = iter.range(0, 3)
    assert(borrowed.by_ref().count() == 3usize, "explicit reborrow consumption")
    assert(borrowed.next().is_none(), "original iterator remains")
    0
}
