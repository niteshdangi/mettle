// expect-exit: 0
import alloc.hash_map
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
        var map = hash_map.new<i32, Counted>()
        let _a = map.insert(1, Counted(10, counter))
        let _b = map.insert(2, Counted(20, counter))
        let _c = map.insert(3, Counted(30, counter))
        let _d = map.insert(4, Counted(40, counter))

        var calls = 0
        var key_sum = 0
        map.retain(fn(read key: i32, mut value: Counted): bool {
            calls += 1
            key_sum += key
            value.value += key
            key % 2 == 0
        })
        if calls != 4 || key_sum != 10 || map.len() != 2usize { return 1 }
        match map.get(2) {
            present(value) => { if value.value != 22 { return 2 } },
            none => { return 3 }
        }
        match map.get(4) {
            present(value) => { if value.value != 44 { return 4 } },
            none => { return 5 }
        }
        if map.contains_key(1) || map.contains_key(3) || drops != 2 { return 6 }
    }
    if drops != 4 { return 7 }

    var map = hash_map.new<i32, i32>()
    let _a = map.insert(1, 10)
    let _b = map.insert(2, 20)
    let _c = map.insert(3, 30)
    var calls = 0
    var key_sum = 0
    var removed_key = 0
    var started = 0
    let started_ptr = core.ptr.from_mut(started)
    {
        var extracted = map.extract_if(fn(read key: i32, mut value: i32): bool {
            calls += 1
            unsafe { *started_ptr += 1 }
            key_sum += key
            value += 1
            calls == 2
        })
        if unsafe { *started_ptr } != 0 { return 8 }
        match extracted.next() {
            present(entry) => {
                removed_key = entry.0
                if entry.1 != entry.0 * 10 + 1 { return 9 }
            },
            none => { return 10 }
        }
    }
    if calls != 2 || key_sum < 3 || key_sum > 5 ||
        map.len() != 2usize || map.contains_key(removed_key) { return 11 }

    var set = hash_map.set_new<i32>()
    let _d = set.insert(1)
    let _e = set.insert(2)
    let _f = set.insert(3)
    let _g = set.insert(4)
    calls = 0
    key_sum = 0
    set.retain(fn(read key: i32): bool {
        calls += 1
        key_sum += key
        key % 2 == 0
    })
    if calls != 4 || key_sum != 10 || set.len() != 2usize ||
        !set.contains(2) || !set.contains(4) { return 13 }

    var set_extract = hash_map.set_new<i32>()
    let _h = set_extract.insert(1)
    let _i = set_extract.insert(2)
    let _j = set_extract.insert(3)
    calls = 0
    var extracted_key = 0
    unsafe { *started_ptr = 0 }
    {
        var extracted = set_extract.extract_if(fn(read key: i32): bool {
            calls += 1
            unsafe { *started_ptr += 1 }
            calls == 2
        })
        if unsafe { *started_ptr } != 0 { return 12 }
        match extracted.next() {
            present(key) => { extracted_key = key },
            none => { return 13 }
        }
    }
    if calls != 2 || set_extract.len() != 2usize ||
        set_extract.contains(extracted_key) { return 14 }

    var entries = hash_map.new<i32, i32>()
    let _k = entries.insert(1, 10)
    var calls = 0
    let call_counter = core.ptr.from_mut(calls)
    {
        let unused = Token(90, counter)
        let value = entries.entry(1).or_insert_with(take fn(): i32 {
            unsafe { *call_counter += 1 }
            let consumed = take unused
            consumed.value
        })
        if *value != 10 || calls != 0 { return 13 }
    }
    {
        let consumed = Token(20, counter)
        let value = entries.entry(2).or_insert_with_key(take fn(read key: i32): i32 {
            unsafe { *call_counter += 1 }
            let owned = take consumed
            key + owned.value
        })
        if *value != 22 || calls != 1 { return 14 }
    }
    {
        let consumed = Token(5, counter)
        let modified = entries.entry(1).and_modify(take fn(mut value: i32): Unit {
            unsafe { *call_counter += 1 }
            let owned = take consumed
            value += owned.value
        })
    }
    if calls != 2 { return 15 }
    match entries.get(1) {
        present(value) => { if *value != 15 { return 16 } },
        none => { return 17 }
    }
    if drops != 7 { return 18 }
    0
}
