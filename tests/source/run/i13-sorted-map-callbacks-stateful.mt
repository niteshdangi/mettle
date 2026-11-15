// expect-exit: 0
import alloc.btree
import core.iter.Iterator

type Counted {
    value: i32
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

type Token {
    value: i32
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var drops = 0
    let counter = core.ptr.from_mut(drops)
    {
        var map = btree.new<i32, Counted>()
        let _a = map.insert(1, Counted(10, counter))
        let _b = map.insert(2, Counted(20, counter))
        let _c = map.insert(3, Counted(30, counter))
        let _d = map.insert(4, Counted(40, counter))

        var calls = 0
        var expected = 1
        var ordered = true
        map.retain(fn(read key: i32, mut value: Counted): bool {
            calls += 1
            if key != expected { ordered = false }
            expected += 1
            value.value += key
            key % 2 == 0
        })
        if calls != 4 || expected != 5 || !ordered ||
            map.len() != 2usize || drops != 2 { return 1 }
        match map.get(2) {
            present(value) => { if value.value != 22 { return 2 } },
            none => { return 3 }
        }
        match map.get(4) {
            present(value) => { if value.value != 44 { return 4 } },
            none => { return 5 }
        }
    }
    if drops != 4 { return 6 }

    var map = btree.new<i32, i32>()
    let _a = map.insert(1, 10)
    let _b = map.insert(2, 20)
    let _c = map.insert(3, 30)
    let _d = map.insert(4, 40)
    var calls = 0
    var expected = 1
    var ordered = true
    var started = 0
    let started_ptr = core.ptr.from_mut(started)
    {
        var extracted = map.extract_if(core.iter.range_full(), fn(read key: i32, mut value: i32): bool {
            calls += 1
            unsafe { *started_ptr += 1 }
            if key != expected { ordered = false }
            expected += 1
            value += calls
            calls == 2
        })
        if unsafe { *started_ptr } != 0 { return 7 }
        match extracted.next() {
            present(entry) => {
                if entry.0 != 2 || entry.1 != 22 { return 8 }
            },
            none => { return 9 }
        }
        if calls != 2 || expected != 3 || !ordered { return 10 }
    }
    if map.len() != 3usize || map.contains_key(2) { return 11 }
    match map.get(1) {
        present(value) => { if *value != 11 { return 12 } },
        none => { return 13 }
    }
    match map.get(3) {
        present(value) => { if *value != 30 { return 14 } },
        none => { return 15 }
    }

    var set = btree.set_new<i32>()
    let _e = set.insert(1)
    let _f = set.insert(2)
    let _g = set.insert(3)
    let _h = set.insert(4)
    calls = 0
    expected = 1
    ordered = true
    set.retain(fn(read key: i32): bool {
        calls += 1
        if key != expected { ordered = false }
        expected += 1
        key % 2 == 0
    })
    if calls != 4 || expected != 5 || !ordered || set.len() != 2usize ||
        !set.contains(2) || !set.contains(4) { return 16 }

    var set_extract = btree.set_new<i32>()
    let _i = set_extract.insert(1)
    let _j = set_extract.insert(2)
    let _k = set_extract.insert(3)
    calls = 0
    expected = 1
    ordered = true
    unsafe { *started_ptr = 0 }
    {
        var extracted = set_extract.extract_if(core.iter.range_full(), fn(read key: i32): bool {
            calls += 1
            unsafe { *started_ptr += 1 }
            if key != expected { ordered = false }
            expected += 1
            calls == 2
        })
        if unsafe { *started_ptr } != 0 { return 17 }
        match extracted.next() {
            present(key) => { if key != 2 { return 18 } },
            none => { return 19 }
        }
        if calls != 2 || expected != 3 || !ordered { return 20 }
    }
    if set_extract.len() != 2usize || set_extract.contains(2) { return 21 }

    var tree = btree.new<i32, i32>()
    var key: i32 = 0
    while key < 96 {
        let insertion_key = key
        let _old = tree.insert(insertion_key, key * 10)
        key += 1
    }
    var visited = 0
    var in_order = true
    tree.retain(fn(read key: i32, mut value: i32): bool {
        if key != visited { in_order = false }
        visited += 1
        value += 1
        key % 3 == 0
    })
    if visited != 96 || !in_order || tree.len() != 32usize { return 30 }
    {
        var extracted = tree.extract_if(core.iter.range_full(), fn(read key: i32, mut value: i32): bool {
            key % 2 == 0
        })
        var next_key = 0
        while true {
            match take extracted.next() {
                present(entry) => {
                    if entry.0 != next_key || entry.1 != next_key * 10 + 1 {
                        return 31
                    }
                    next_key += 6
                },
                none => { break }
            }
        }
        if next_key != 96 { return 32 }
    }
    if tree.len() != 16usize { return 33 }

    var bounded_map = btree.new<i32, i32>()
    let _m1 = bounded_map.insert(1, 10)
    let _m2 = bounded_map.insert(2, 20)
    let _m3 = bounded_map.insert(3, 30)
    let _m4 = bounded_map.insert(4, 40)
    let _m5 = bounded_map.insert(5, 50)
    calls = 0
    {
        var extracted = bounded_map.extract_if(core.iter.range(2, 4), fn(read key: i32, mut value: i32): bool {
            calls += 1
            key % 2 == 0
        })
        match extracted.next() {
            present(entry) => { if entry.0 != 2 || entry.1 != 20 { return 40 } },
            none => { return 40 }
        }
        if extracted.next().is_present() || calls != 2 { return 41 }
    }
    if bounded_map.contains_key(2) || !bounded_map.contains_key(3) ||
        !bounded_map.contains_key(4) || !bounded_map.contains_key(5) { return 42 }

    var bounded_set = btree.set_new<i32>()
    let _s1 = bounded_set.insert(1)
    let _s2 = bounded_set.insert(2)
    let _s3 = bounded_set.insert(3)
    let _s4 = bounded_set.insert(4)
    let _s5 = bounded_set.insert(5)
    calls = 0
    {
        var extracted = bounded_set.extract_if(core.iter.range(2, 4), fn(read key: i32): bool {
            calls += 1
            key % 2 == 0
        })
        match extracted.next() {
            present(key) => { if key != 2 { return 43 } },
            none => { return 43 }
        }
        if extracted.next().is_present() || calls != 2 { return 44 }
    }
    if bounded_set.contains(2) || !bounded_set.contains(3) ||
        !bounded_set.contains(4) || !bounded_set.contains(5) { return 45 }

    var entries = btree.new<i32, i32>()
    let _l = entries.insert(1, 10)
    var calls = 0
    let call_counter = core.ptr.from_mut(calls)
    {
        let unused = Token(90, counter)
        let value = entries.entry(1).or_insert_with(take fn(): i32 {
            unsafe { *call_counter += 1 }
            let consumed = take unused
            consumed.value
        })
        if *value != 10 || calls != 0 { return 22 }
    }
    {
        let consumed = Token(20, counter)
        let value = entries.entry(2).or_insert_with_key(take fn(read key: i32): i32 {
            unsafe { *call_counter += 1 }
            let owned = take consumed
            key + owned.value
        })
        if *value != 22 || calls != 1 { return 23 }
    }
    {
        let consumed = Token(5, counter)
        let modified = entries.entry(1).and_modify(take fn(mut value: i32): Unit {
            unsafe { *call_counter += 1 }
            let owned = take consumed
            value += owned.value
        })
    }
    if calls != 2 { return 24 }
    match entries.get(1) {
        present(value) => { if *value != 15 { return 25 } },
        none => { return 26 }
    }
    if drops != 7 { return 27 }
    0
}
