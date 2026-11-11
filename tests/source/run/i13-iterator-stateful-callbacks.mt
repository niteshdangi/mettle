import core.cmp.Ordering
import core.iter
import core.iter.{Iterator, BidirectionalIterator}

fn main(): i32 {
    var visits = 0
    {
        let lazy = iter.range(1, 5).map(fn(take value: i32): i32 {
            visits += 1
            value + visits
        })
    }
    assert(visits == 0, "mapping is lazy")
    {
        var mapped = iter.range(1, 5).map(fn(take value: i32): i32 {
            visits += 1
            value + visits
        })
        assert(mapped.next() == present(2), "forward mapping state")
        assert(mapped.next_back() == present(6), "backward mapping shares state")
        assert(mapped.next() == present(5) && mapped.next_back() == present(7), "mixed mapping")
        assert(mapped.next().is_none(), "mapping exhausted")
    }
    assert(visits == 4, "one callback per mapped item")
    visits = 0
    var observed = 0
    {
        var selected = iter.range(1, 7).filter(fn(read value: i32): bool {
            visits += 1
            value % 2 == 0
        }).inspect(fn(read value: i32): Unit { observed += value })
        assert(selected.next() == present(2) && selected.next() == present(4), "stateful filter and inspect")
        assert(selected.next() == present(6) && selected.next().is_none(), "filter exhaustion")
    }
    assert(visits == 6 && observed == 12, "filter visits rejected items; inspect only yielded items")
    visits = 0
    {
        var selected = iter.range(1, 5).filter_map(fn(take value: i32): i32? {
            visits += 1
            if visits % 2 == 0 { present(value * 10) } else { none }
        })
        assert(selected.next_back() == present(30) && selected.next() == present(20), "filter_map mixed state")
    }
    assert(visits == 4, "filter_map callback once per pulled item")
    visits = 0
    {
        var selected = iter.range(1, 6).take_while(fn(read value: i32): bool {
            visits += 1
            visits < 3
        })
        assert(selected.by_ref().count() == 2usize && selected.next().is_none(), "take_while stops permanently")
    }
    assert(visits == 3, "take_while does not call after rejection")
    visits = 0
    {
        var selected = iter.range(1, 6).skip_while(fn(read value: i32): bool {
            visits += 1
            visits < 3
        })
        assert(selected.next() == present(3) && selected.count() == 2usize, "skip_while keeps first rejected item")
    }
    assert(visits == 3, "skip_while stops testing after first rejection")
    visits = 0
    {
        var values = iter.range(1, 6)
        assert(values.any(fn(take value: i32): bool { visits += 1; value == 3 }), "stateful any")
        assert(values.next() == present(4), "any preserves unvisited suffix")
    }
    assert(visits == 3, "any short circuits")
    visits = 0
    {
        var values = iter.range(1, 6)
        assert(!values.all(fn(take value: i32): bool { visits += 1; value < 3 }), "stateful all")
        assert(values.next() == present(4), "all preserves unvisited suffix")
    }
    assert(visits == 3, "all short circuits")
    visits = 0
    {
        var values = iter.range(1, 6)
        assert(values.find(fn(read value: i32): bool { visits += 1; value == 3 }) == present(3), "stateful find")
        assert(values.next() == present(4), "find preserves unvisited suffix")
    }
    assert(visits == 3, "find short circuits")
    visits = 0
    {
        var values = iter.range(1, 6)
        assert(values.position(fn(take value: i32): bool { visits += 1; value == 2 }) == present(1usize), "stateful position")
        assert(values.next() == present(3), "position preserves unvisited suffix")
    }
    assert(visits == 2, "position short circuits")
    visits = 0
    {
        var values = iter.range(1, 6)
        assert(values.find_map(fn(take value: i32): i32? {
            visits += 1
            if value == 2 { present(value * 10) } else { none }
        }) == present(20), "stateful find_map")
        assert(values.next() == present(3), "find_map preserves suffix")
    }
    assert(visits == 2, "find_map short circuits")
    visits = 0
    let total = iter.range(1, 5).fold(0, fn(take total: i32, take value: i32): i32 {
        visits += 1
        total + value + visits
    })
    assert(total == 20 && visits == 4, "stateful fold")
    visits = 0
    let maximum = iter.range(1, 5).max_by(fn(read left: i32, read right: i32): Ordering {
        visits += 1
        Ordering.Equal
    })
    assert(maximum == present(4) && visits == 3, "max_by keeps last equal item")
    visits = 0
    let maximum_key = iter.range(1, 5).max_by_key(fn(read value: i32): i32 {
        visits += 1
        0
    })
    assert(maximum_key == present(4) && visits == 4, "max_by_key keeps last equal item")
    visits = 0
    let reverse = iter.range(1, 5).rfold(0, fn(take total: i32, take value: i32): i32 {
        visits += 1
        total * 10 + value
    })
    assert(reverse == 4321 && visits == 4, "stateful reverse fold")
    visits = 0
    {
        var values = iter.range(1, 5)
        assert(values.rfind(fn(read value: i32): bool { visits += 1; value == 3 }) == present(3), "stateful reverse find")
        assert(values.next_back() == present(2), "reverse find preserves prefix")
    }
    assert(visits == 2, "reverse find short circuits")
    visits = 0
    {
        var values = iter.from_fn(fn(): i32? {
            visits += 1
            if visits <= 3 { present(visits) } else { none }
        })
        assert(values.fold(0, fn(take total: i32, take value: i32): i32 { total + value }) == 6, "stateful factory")
    }
    assert(visits == 4, "factory observes first absence")
    visits = 0
    {
        var values = iter.repeat_with(fn(): i32 { visits += 1; visits }).take_n(3usize)
        assert(values.fold(0, fn(take total: i32, take value: i32): i32 { total + value }) == 6, "stateful repeat factory")
    }
    assert(visits == 3, "limited repetition does not over-pull")
    visits = 0
    {
        var values = iter.successors(present(0), fn(read value: i32): i32? {
            visits += 1
            if value < 3 { present(value + 1) } else { none }
        })
        assert(values.count() == 4usize, "stateful successor")
    }
    assert(visits == 4, "successor callback state")
    0
}
