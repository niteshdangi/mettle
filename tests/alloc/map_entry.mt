import alloc.hash_map.Entry

fn main(): i32 {
    var calls = 0
    let counter = core.ptr.from_mut(calls)
    var map = alloc.hash_map.new<i32, i32>()
    {
        let value = map.entry(4).or_insert_with(take fn(): i32 {
            unsafe { *counter += 1 }
            12
        })
        if *value != 12 { return 1 }
    }
    {
        let value = map.entry(4).and_modify(take fn(mut value: i32): Unit {
            value += 3
        }).or_insert_with(take fn(): i32 {
            unsafe { *counter += 100 }
            99
        })
        if *value != 15 { return 2 }
    }
    if calls != 1 { return 3 }
    {
        let value = map.entry(7).or_default()
        if *value != 0 { return 4 }
        *value = 8
    }
    match take map.entry(4) {
        Entry.Occupied(entry) => {
            var occupied = entry
            if *occupied.get() != 15 { return 5 }
            if occupied.insert(20) != 15 { return 6 }
            if occupied.remove() != 20 { return 7 }
        },
        Entry.Vacant(_) => { return 8 }
    }
    if map.contains_key(4) { return 9 }
    match take map.entry(9) {
        Entry.Occupied(_) => { return 10 },
        Entry.Vacant(entry) => {
            let value = entry.insert(30)
            if *value != 30 { return 11 }
        }
    }
    0
}
