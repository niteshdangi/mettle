import core.clone.Clone
import core.cmp.PartialEq
import core.iter.Bound
type Counted {
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1 } }
}

fn main(): i32 {
    var drops = 0
    let counter = core.ptr.from_mut(drops)
    {
        var map = alloc.btree.new<i32, Counted>()
        var i = 0
        while i < 1000 {
            let key = (i * 37) % 1000
            let old = map.insert(key, Counted(counter))
            i += 1
        }
        if map.len() != 1000usize { return 1 }
        i = 1
        while i < 1000 {
            match map.remove(i + 0) {
                present(value) => {},
                none => { return 2 }
            }
            i += 2
        }
        if map.len() != 500usize || drops != 500 { return 3 }
        if map.contains_key(11) || !map.contains_key(10) { return 4 }
        match map.first_key() { present(k) => { if *k != 0 { return 5 } }, none => { return 5 } }
        match map.last_key() { present(k) => { if *k != 998 { return 5 } }, none => { return 5 } }
        i = 0
        for entry in read map {
            if entry.key != i { return 6 }
            i += 2
        }
        if i != 1000 { return 7 }
        var seen = 0
        var inside = map.range((Bound.Excluded(99), Bound.Included(198)))
        while true {
            match inside.next() {
                present(entry) => {
                    if entry.key != 100 + seen * 2 { return 8 }
                    seen += 1
                },
                none => { break }
            }
        }
        if seen != 50 { return 9 }
        var expected = 0
        for entry in take map {
            if entry.key != expected { return 10 }
            expected += 2
            if expected == 4 { break }
        }
        if expected != 4 { return 11 }
    }
    if drops != 1000 { return 12 }

    drops = 0
    {
        var map = alloc.btree.new<i32, Counted>()
        var i = 0
        while i < 300 {
            let old = map.insert((i * 7) % 300, Counted(counter))
            i += 1
        }
        i = 299
        while i >= 0 {
            match map.remove(i + 0) {
                present(value) => {},
                none => { return 13 }
            }
            i -= 1
        }
        if !map.is_empty() || drops != 300 { return 14 }
        let old = map.insert(1, Counted(counter))
        if map.len() != 1usize { return 15 }
    }
    if drops != 301 { return 16 }

    var small = alloc.btree.new<i32, i32>()
    var k = 0
    while k < 40 {
        let old = small.insert((k * 13) % 40, k + 0)
        k += 1
    }
    let dup = small.clone()
    if dup != small || dup.len() != 40usize { return 17 }
    match take small.get_mut(7) { present(v) => { *v = -1 }, none => { return 18 } }
    if dup == small { return 19 }
    {
        var mutable_range = small.range_mut((Bound.Excluded(9), Bound.Included(19)))
        var changed = 0
        while true {
            match take mutable_range.next() {
                present(value) => { *value += 1; changed += 1 },
                none => { break }
            }
        }
        if changed != 10 { return 22 }
    }
    match small.get(10) {
        present(value) => { if *value != 11 { return 23 } },
        none => { return 24 }
    }
    match small.get(20) {
        present(value) => { if *value != 20 { return 25 } },
        none => { return 26 }
    }

    var set = alloc.btree.set_new<i32>()
    set.insert(8)
    set.insert(2)
    set.insert(5)
    var want = 2
    for key in take set {
        if key != want { return 20 }
        want += 3
    }
    if want != 11 { return 21 }
    var extremes = alloc.btree.new<i32, i32>()
    let first = extremes.insert(2, 20)
    let second = extremes.insert(1, 10)
    let third = extremes.insert(3, 30)
    match extremes.pop_first() {
        present(entry) => { if entry.0 != 1 || entry.1 != 10 { return 27 } },
        none => { return 28 }
    }
    match extremes.pop_last() {
        present(entry) => { if entry.0 != 3 || entry.1 != 30 { return 29 } },
        none => { return 30 }
    }
    if extremes.len() != 1usize || !extremes.contains_key(2) { return 31 }
    var extremes_set = alloc.btree.set_new<i32>()
    extremes_set.insert(2)
    extremes_set.insert(1)
    extremes_set.insert(3)
    match extremes_set.pop_first() {
        present(value) => { if value != 1 { return 32 } },
        none => { return 33 }
    }
    match extremes_set.pop_last() {
        present(value) => { if value != 3 { return 34 } },
        none => { return 35 }
    }
    if extremes_set.len() != 1usize || !extremes_set.contains(2) { return 36 }
    0
}
