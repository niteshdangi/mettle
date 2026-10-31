import alloc.btree
import core.iter.Iterator

fn main(): i32 {
    var map = btree.new<i32, i32>()
    var key = 40i32
    while key > 0i32 {
        let doubled = key * 2i32
        let current = key
        let old = map.insert(current, doubled)
        key -= 1i32
    }

    var count = 0i32
    var sum = 0i32
    {
        var range = map.range(10i32, 20i32)
        while true {
            match range.next() {
                present(entry) => {
                    if entry.key < 10i32 || entry.key >= 20i32 { return 1 }
                    count += 1i32
                    sum += entry.value
                },
                none => { break }
            }
        }
    }
    if count != 10i32 || sum != 290i32 { return 2 }

    var previous = 0i32
    count = 0i32
    for entry in read map {
        if entry.key <= previous { return 3 }
        previous = entry.key
        count += 1i32
    }
    if count != 40i32 { return 4 }

    key = 2i32
    while key < 40i32 {
        let removed = map.remove(key)
        key += 3i32
    }
    previous = 0i32
    for entry in read map {
        if entry.key <= previous { return 5 }
        previous = entry.key
    }
    match map.get(40i32) {
        present(value) => { if *value != 80i32 { return 6 } },
        none => { return 7 }
    }
    0
}
