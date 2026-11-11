// profiles: debug release
import core.borrow.ToOwned
import core.clone.Clone
import core.iter
import core.iter.{BidirectionalIterator, Iterator, OwnedIterable}

type Pulse { at: i32 }
extend Pulse implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        self.at += 1
        if self.at % 2 == 0 { present(self.at) } else { none }
    }
}
extend Pulse implements Clone {
    fn clone(): Pulse { Pulse(self.at) }
}
type Guard<region r> { log: mut i32 from r; drop { *self.log += 1 } }
copy type Counts { a: i32; b: i32; c: i32; d: i32 }

fn exhaust(take back_first: bool): Unit {
    var counts = Counts(0, 0, 0, 0)
    {
        var nested = [
            [Guard(mut counts.a), Guard(mut counts.b)],
            [Guard(mut counts.c), Guard(mut counts.d)]
        ].into_iter().flatten()
        var index = 0
        while index < 4 {
            let item = if (index % 2 == 0) == back_first {
                nested.next_back()
            } else { nested.next() }
            match take item {
                present(value) => {},
                none => { panic("flatten exhausted before all items") }
            }
            index += 1
        }
        if back_first {
            assert(nested.next_back().is_none() && nested.next().is_none(),
                "retire back and front after exhaustion")
        } else {
            assert(nested.next().is_none() && nested.next_back().is_none(),
                "retire front and back after exhaustion")
        }
    }
    assert(counts.a == 1 && counts.b == 1 && counts.c == 1 && counts.d == 1,
        "exhausted inners drop each item exactly once")
}

fn main(): i32 {
    var pulse = Pulse(0).peekable()
    assert(pulse.peek().is_none() && pulse.peek().is_none(), "cache absence without another pull")
    var duplicate = pulse.clone()
    var owned = pulse.to_owned()
    assert(pulse.next().is_none() && duplicate.next().is_none() && owned.next().is_none(), "clone cached absence")
    assert(pulse.next() == present(2) && duplicate.next() == present(2) && owned.next() == present(2), "resume nonfused inputs independently")
    var counts = Counts(0, 0, 0, 0)
    {
        var cached = [Guard(mut counts.a), Guard(mut counts.b)].into_iter().peekable()
        assert(cached.peek().is_present() && cached.peek().is_present(), "retain owned cached item")
    }
    assert(counts.a == 1 && counts.b == 1, "drop cached item and untouched suffix once")
    counts = Counts(0, 0, 0, 0)
    {
        var nested = [
            [Guard(mut counts.a), Guard(mut counts.b)],
            [Guard(mut counts.c), Guard(mut counts.d)]
        ].into_iter().flatten()
        match take nested.next() { present(item) => {}, none => { return 1 } }
        match take nested.next_back() { present(item) => {}, none => { return 2 } }
    }
    assert(counts.a == 1 && counts.b == 1 && counts.c == 1 && counts.d == 1, "drop both converted active inners once")
    exhaust(false)
    exhaust(true)
    0
}
