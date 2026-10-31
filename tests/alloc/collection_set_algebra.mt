type DrainDrop {
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1 } }
}

fn main(): i32 {
    var hash_left = alloc.hash_map.set_new<i32>()
    var hash_right = alloc.hash_map.set_new<i32>()
    let _a = hash_left.insert(1)
    let _b = hash_left.insert(2)
    let _c = hash_left.insert(3)
    let _d = hash_right.insert(3)
    let _e = hash_right.insert(4)
    if !hash_left.is_subset(hash_left) { return 1 }
    if !hash_left.is_superset(hash_left) { return 58 }
    if hash_left.is_superset(hash_right) { return 2 }
    if hash_left.is_subset(hash_right) { return 3 }
    if hash_left.is_disjoint(hash_right) { return 4 }

    var hash_union = hash_left.`union`(read hash_right)
    var union_sum = 0
    var union_count = 0
    while true {
        match hash_union.next() {
            present(value) => { union_sum += *value; union_count += 1 },
            none => { break }
        }
    }
    if union_count != 4 || union_sum != 10 { return 5 }
    var hash_intersection = hash_left.intersection(read hash_right)
    match hash_intersection.next() {
        present(value) => { if *value != 3 { return 6 } },
        none => { return 7 }
    }
    match hash_intersection.next() { none => {}, present(_) => { return 8 } }
    var hash_difference = hash_left.difference(read hash_right)
    var difference_sum = 0
    while true {
        match hash_difference.next() {
            present(value) => { difference_sum += *value },
            none => { break }
        }
    }
    if difference_sum != 3 { return 9 }
    var hash_symmetric = hash_left.symmetric_difference(read hash_right)
    var symmetric_sum = 0
    while true {
        match hash_symmetric.next() {
            present(value) => { symmetric_sum += *value },
            none => { break }
        }
    }
    if symmetric_sum != 7 { return 10 }

    var sorted_left = alloc.btree.set_new<i32>()
    var sorted_right = alloc.btree.set_new<i32>()
    let _f = sorted_left.insert(1)
    let _g = sorted_left.insert(2)
    let _h = sorted_left.insert(3)
    let _i = sorted_right.insert(3)
    let _j = sorted_right.insert(4)
    var sorted_union = sorted_left.`union`(read sorted_right)
    union_sum = 0
    union_count = 0
    while true {
        match sorted_union.next() {
            present(value) => { union_sum += *value; union_count += 1 },
            none => { break }
        }
    }
    if union_count != 4 || union_sum != 10 { return 11 }
    var sorted_intersection = sorted_left.intersection(read sorted_right)
    match sorted_intersection.next() {
        present(value) => { if *value != 3 { return 12 } },
        none => { return 13 }
    }
    match sorted_intersection.next() { none => {}, present(_) => { return 14 } }
    if sorted_left.is_subset(sorted_right) { return 15 }
    if !sorted_left.is_superset(sorted_left) { return 16 }
    if sorted_left.is_disjoint(sorted_right) { return 17 }
    var sorted_difference = sorted_left.difference(read sorted_right)
    difference_sum = 0
    while true {
        match sorted_difference.next() {
            present(value) => { difference_sum += *value },
            none => { break }
        }
    }
    if difference_sum != 3 { return 18 }
    var sorted_symmetric = sorted_left.symmetric_difference(read sorted_right)
    symmetric_sum = 0
    while true {
        match sorted_symmetric.next() {
            present(value) => { symmetric_sum += *value },
            none => { break }
        }
    }
    if symmetric_sum != 7 { return 19 }
    var sorted_disjoint = alloc.btree.set_new<i32>()
    let _o = sorted_disjoint.insert(9)
    if !sorted_left.is_disjoint(sorted_disjoint) { return 20 }
    var hash_disjoint = alloc.hash_map.set_new<i32>()
    let _p = hash_disjoint.insert(9)
    if !hash_left.is_disjoint(hash_disjoint) { return 21 }

    var map = alloc.hash_map.new<i32, i32>()
    let _k = map.insert(7, 70)
    let _k2 = map.insert(12, 120)
    match map.get_key_value(7) {
        present(pair) => { if *pair.0 != 7 || *pair.1 != 70 { return 22 } },
        none => { return 23 }
    }
    {
        let value = map.entry(10).or_insert_with_key(take fn(key: read i32): i32 { key * 2 })
        if *value != 20 { return 50 }
    }
    map.shrink_to(2usize)
    if map.capacity() < 2usize { return 24 }
    {
        var drain = map.drain()
        match drain.next() {
            present(pair) => { if pair.0 != 7 || pair.1 != 70 { return 25 } },
            none => { return 26 }
        }
        match drain.next_back() {
            present(pair) => { if pair.0 != 12 || pair.1 != 120 { return 54 } },
            none => { return 55 }
        }
    }
    if !map.is_empty() { return 27 }
    let _q = map.insert(8, 80)
    var keys = map.into_keys()
    match keys.next() {
        present(key) => { if key != 8 { return 28 } },
        none => { return 29 }
    }

    var values_map = alloc.hash_map.new<i32, i32>()
    let _r = values_map.insert(9, 90)
    var values = values_map.into_values()
    match values.next() {
        present(value) => { if value != 90 { return 30 } },
        none => { return 31 }
    }

    var drained_set = alloc.hash_map.set_new<i32>()
    let _s = drained_set.insert(6)
    let _s2 = drained_set.insert(7)
    {
        var drain = drained_set.drain()
        match drain.next() {
            present(value) => { if value != 6 { return 32 } },
            none => { return 33 }
        }
        match drain.next_back() {
            present(value) => { if value != 7 { return 56 } },
            none => { return 57 }
        }
    }
    if !drained_set.is_empty() { return 34 }

    var sorted_map = alloc.btree.new<i32, i32>()
    let _l = sorted_map.insert(2, 20)
    let _m = sorted_map.insert(1, 10)
    let _n = sorted_map.insert(3, 30)
    match sorted_map.get_key_value(2) {
        present(pair) => { if *pair.0 != 2 || *pair.1 != 20 { return 35 } },
        none => { return 36 }
    }
    match sorted_map.first_key_value() {
        present(pair) => { if *pair.0 != 1 || *pair.1 != 10 { return 37 } },
        none => { return 38 }
    }
    match sorted_map.last_key_value() {
        present(pair) => { if *pair.0 != 3 || *pair.1 != 30 { return 39 } },
        none => { return 40 }
    }
    {
        let value = sorted_map.entry(5).or_insert_with_key(take fn(key: read i32): i32 { key * 2 })
        if *value != 10 { return 51 }
    }
    match sorted_map.remove_entry(2) {
        present(pair) => { if pair.0 != 2 || pair.1 != 20 { return 41 } },
        none => { return 42 }
    }
    let _t = sorted_map.insert(4, 40)
    var sorted_values = sorted_map.into_values()
    match sorted_values.next() {
        present(value) => { if value != 10 { return 43 } },
        none => { return 44 }
    }
    var sorted_keys_map = alloc.btree.new<i32, i32>()
    let _z = sorted_keys_map.insert(6, 60)
    var sorted_keys = sorted_keys_map.into_keys()
    match sorted_keys.next() {
        present(key) => { if key != 6 { return 52 } },
        none => { return 53 }
    }
    var priority_queue = alloc.binary_heap.new<i32>()
    priority_queue.push(1)
    priority_queue.push(3)
    priority_queue.push(2)
    {
        var drain = priority_queue.drain()
        match drain.next() {
            present(value) => {
                if value < 1 || value > 3 { return 45 }
            },
            none => { return 46 }
        }
    }
    if !priority_queue.is_empty() { return 47 }

    var drops = 0
    let counter = core.ptr.from_mut(drops)
    {
        var dropping_map = alloc.hash_map.new<i32, DrainDrop>()
        let _u = dropping_map.insert(1, DrainDrop(counter))
        let _v = dropping_map.insert(2, DrainDrop(counter))
        let _w = dropping_map.insert(3, DrainDrop(counter))
        {
            var drain = dropping_map.drain()
            match drain.next() {
                present(pair) => { let removed = pair.1 },
                none => { return 48 }
            }
        }
        if drops != 3 { return 49 }
    }
    0
}
