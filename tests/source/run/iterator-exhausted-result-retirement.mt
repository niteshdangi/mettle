// profiles: debug release
import core.iter.{Iterator, OwnedIterable}

type Guard<region r> { log: mut i32 from r; drop { *self.log += 1 } }

fn retire<I: Iterator>(mut values: I?): Unit {
    match mut values {
        present(inner) => match take inner.next() {
            present(value) => {},
            none => { values = none }
        },
        none => {}
    }
}

fn first<I: Iterator>(mut values: I?): I.Item? {
    match mut values {
        present(inner) => match take inner.next() {
            present(value) => { return present(value) },
            none => { values = none; return none }
        },
        none => { return none }
    }
    none
}

fn main(): i32 {
    var drops = 0
    {
        var values = present([Guard(mut drops)].into_iter())
        retire(mut values)
        retire(mut values)
        assert(values.is_none(), "retire the exhausted iterator")
    }
    assert(drops == 1, "retired iterator releases its item")
    drops = 0
    {
        var values = present([Guard(mut drops)].into_iter())
        match take first(mut values) { present(value) => {}, none => { return 1 } }
        assert(first(mut values).is_none(), "forward exhausted result")
        assert(first(mut values).is_none(), "retired iterator stays absent")
    }
    assert(drops == 1, "forwarded item releases its source")
    0
}
