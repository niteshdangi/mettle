import core.ops.DerefMut

fn main(): i32 {
    var map = alloc.hash_map.new<i32, i32>()
    let _a = map.insert(1, 10)
    let _b = map.insert(2, 20)
    let _c = map.insert(3, 30)
    match take map.get_disjoint_mut(1, 2) {
        present(pair) => { *pair.0 += 1; *pair.1 += 2 },
        none => { return 1 }
    }
    match map.get_disjoint_mut(1, 4) {
        none => {},
        present(_) => { return 2 }
    }
    {
        var extracted = map.extract_if(fn(read key: i32, mut value: i32): bool {
            value += 5
            key == 2
        })
        match extracted.next() {
            present(pair) => { if pair.0 != 2 || pair.1 != 27 { return 3 } },
            none => { return 4 }
        }
        match extracted.next() { none => {}, present(_) => { return 5 } }
    }
    match map.get(1) { present(value) => { if *value != 16 { return 6 } }, none => { return 7 } }
    match map.get(3) { present(value) => { if *value != 35 { return 8 } }, none => { return 9 } }
    {
        let entry = map.entry(4).insert_entry(44)
        if *entry.key() != 4 || *entry.get() != 44 { return 28 }
    }
    var hash_set = alloc.hash_map.set_new<i32>()
    let _hs1 = hash_set.insert(1)
    let _hs2 = hash_set.insert(2)
    {
        var hash_extract = hash_set.extract_if(fn(read key: i32): bool { key == 2 })
        match hash_extract.next() {
            present(key) => { if key != 2 { return 29 } },
            none => { return 30 }
        }
        match hash_extract.next() { none => {}, present(_) => { return 31 } }
    }

    var tree = alloc.btree.new<i32, i32>()
    let _d = tree.insert(1, 10)
    let _e = tree.insert(2, 20)
    let _f = tree.insert(3, 30)
    let _g = tree.insert(4, 40)
    {
        match take tree.first_entry() {
            present(entry) => {
                if *entry.key() != 1 { return 10 }
                var mutable_entry = entry
                *mutable_entry.get_mut() += 1
            },
            none => { return 11 }
        }
    }
    {
        match take tree.last_entry() {
            present(entry) => {
                if *entry.key() != 4 { return 12 }
                var mutable_entry = entry
                *mutable_entry.get_mut() += 1
            },
            none => { return 13 }
        }
    }
    {
        var tree_extracted = tree.extract_if(fn(read key: i32, mut value: i32): bool {
            value += 2
            key == 2
        })
        match tree_extracted.next() {
            present(pair) => { if pair.0 != 2 || pair.1 != 22 { return 14 } },
            none => { return 15 }
        }
        match tree_extracted.next() { none => {}, present(_) => { return 16 } }
    }
    var upper = tree.split_off(3)
    if tree.len() != 1 || upper.len() != 2 { return 17 }
    match upper.first_key_value() {
        present(pair) => { if *pair.0 != 3 || *pair.1 != 32 { return 18 } },
        none => { return 19 }
    }
    {
        let entry = tree.entry(5).insert_entry(50)
        if *entry.key() != 5 || *entry.get() != 50 { return 32 }
    }
    {
        var values = tree.range_mut(1, 6)
        while true {
            match take values.next() {
                present(value) => { *value += 1 },
                none => { break }
            }
        }
    }
    var set = alloc.btree.set_new<i32>()
    let _h = set.insert(1)
    let _i = set.insert(2)
    let _j = set.insert(3)
    var set_upper = set.split_off(2)
    if set.len() != 1 || set_upper.len() != 2 { return 20 }
    {
        var set_extract = set_upper.extract_if(fn(read key: i32): bool { key == 2 })
        match set_extract.next() {
            present(key) => { if key != 2 { return 21 } },
            none => { return 22 }
        }
        match set_extract.next() { none => {}, present(_) => { return 23 } }
    }

    var priority_queue = alloc.binary_heap.new<i32>()
    priority_queue.push(1)
    priority_queue.push(4)
    priority_queue.push(3)
    {
        match take priority_queue.peek_mut() {
            present(top) => {
                var owner = top
                *owner.deref_mut() = 0
            },
            none => { return 24 }
        }
    }
    if priority_queue.pop() != present(3) || priority_queue.pop() != present(1) || priority_queue.pop() != present(0) { return 25 }
    priority_queue.push(1)
    priority_queue.push(2)
    priority_queue.reserve(8)
    let old_capacity = priority_queue.capacity()
    priority_queue.shrink_to(1)
    if priority_queue.capacity() < 2 || priority_queue.capacity() > old_capacity { return 26 }
    if priority_queue.into_sorted_vec().len() != 2 { return 27 }
    0
}
