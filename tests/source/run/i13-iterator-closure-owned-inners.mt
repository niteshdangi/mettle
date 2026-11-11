// profiles: debug release
import core.clone.Clone
import core.default.Default
import core.iter
import core.iter.{BidirectionalIterator, Iterator, OwnedIterable}

type Row { start: i32; end: i32 }
extend Row implements OwnedIterable {
    type Item = i32
    type IntoIter = iter.Range<i32>
    fn into_iter(receiver take self: Self): iter.Range<i32> {
        iter.range(self.start, self.end)
    }
}
type Rows { remaining: iter.Range<i32> }
extend Rows implements Iterator {
    type Item = Row
    mut fn next(): Row? {
        match take self.remaining.next() {
            present(index) => present(Row(index * 10, index * 10 + 2)),
            none => none
        }
    }
}
extend Rows implements BidirectionalIterator {
    mut fn next_back(): Row? {
        match take self.remaining.next_back() {
            present(index) => present(Row(index * 10, index * 10 + 2)),
            none => none
        }
    }
}
extend Rows implements Clone {
    fn clone(): Rows { Rows(self.remaining.clone()) }
}
extend Rows implements Default {
    static fn default(): Rows { Rows(iter.range(0, 0)) }
}

fn main(): i32 {
    var calls = 0usize
    {
        var paired = iter.range(0, 3).flat_map(fn(take index: i32): [i32; 2] {
            calls += 1usize
            [index * 10, index * 10 + 1]
        })
        assert(paired.next() == present(0), "array inner front")
        assert(paired.next_back() == present(21), "array inner back")
        assert(paired.next() == present(1), "retained array front")
        assert(paired.next_back() == present(20), "retained array back")
        assert(paired.next() == present(10), "middle array front")
        assert(paired.next_back() == present(11), "middle array back")
        assert(paired.next().is_none() && paired.next_back().is_none(), "shared exhaustion")
    }
    assert(calls == 3usize, "convert each demanded array once")
    var optional = iter.range(0, 4).map(fn(take value: i32): i32? {
        if value % 2 == 0 { present(value) } else { none }
    }).flatten()
    assert(optional.next_back() == present(2) && optional.next() == present(0), "optional inners")
    assert(optional.next().is_none(), "absent optional inner skipped")
    var outcomes = iter.range(0, 4).flat_map(fn(take value: i32): (Outcome<i32, i32>) {
        if value % 2 == 0 { success(value) } else { failure(value) }
    })
    assert(outcomes.next_back() == present(2) && outcomes.next() == present(0), "outcome inners")
    assert(outcomes.next().is_none(), "failed outcome inner skipped")
    var rows = Rows(iter.range(0, 3)).flatten()
    assert(rows.next() == present(0) && rows.next_back() == present(21), "two active converted inners")
    var duplicate = rows.clone()
    assert(rows.next() == present(1) && duplicate.next() == present(1), "clone converted front")
    assert(rows.next_back() == present(20) && duplicate.next_back() == present(20), "clone converted back")
    assert(rows.sum<i32>() == 21 && duplicate.sum<i32>() == 21, "independent outer positions")
    var empty = iter.Flatten<Row, Rows>.(Default).default()
    assert(empty.next().is_none() && empty.next_back().is_none(), "default needs only outer default")
    var converted = iter.range(0, 2).flat_map(fn(take index: i32): Row { Row(index, index + 1) })
    assert(converted.next_back() == present(1) && converted.next() == present(0), "inner need not be an iterator")
    0
}
