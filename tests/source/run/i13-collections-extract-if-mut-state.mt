// extract_if predicates keep mutable state while the iterator is consumed.
import alloc.vec
import alloc.hash_map
import alloc.btree

fn main(): i32 {
    var list = vec.new<i32>()
    list.push(1)
    list.push(2)
    list.push(3)
    list.push(4)
    var list_calls = 0
    var list_removed = 0
    {
        var extracted = list.extract_if(0usize, list.len(), fn(value: mut i32): bool {
            list_calls += 1
            list_calls % 2 == 0
        })
        while true {
            match extracted.next() {
                present(value) => { list_removed += value },
                none => { break }
            }
        }
    }
    if list_calls != 4 || list_removed != 6 || list.len() != 2usize ||
       list[0usize] != 1 || list[1usize] != 3 { return 1 }

    var map = hash_map.new<i32, i32>()
    let _ = map.insert(1, 10)
    let _ = map.insert(2, 20)
    let _ = map.insert(3, 30)
    var map_calls = 0
    var map_removed = 0
    {
        var extracted = map.extract_if(fn(key: read i32, value: mut i32): bool {
            map_calls += 1
            map_calls == 2
        })
        while true {
            match extracted.next() {
                present(entry) => { map_removed += entry.1 },
                none => { break }
            }
        }
    }
    if map_calls != 3 || map_removed <= 0 || map.len() != 2usize { return 2 }

    var set = hash_map.set_new<i32>()
    let _ = set.insert(1)
    let _ = set.insert(2)
    let _ = set.insert(3)
    var set_calls = 0
    var set_removed = 0
    {
        var extracted = set.extract_if(fn(key: read i32): bool {
            set_calls += 1
            set_calls == 2
        })
        while true {
            match extracted.next() {
                present(key) => { set_removed += key },
                none => { break }
            }
        }
    }
    if set_calls != 3 || set_removed <= 0 || set.len() != 2usize { return 3 }

    var tree = btree.new<i32, i32>()
    let _ = tree.insert(1, 10)
    let _ = tree.insert(2, 20)
    let _ = tree.insert(3, 30)
    var tree_calls = 0
    var tree_removed = 0
    {
        var extracted = tree.extract_if(fn(key: read i32, value: mut i32): bool {
            tree_calls += 1
            tree_calls == 2
        })
        while true {
            match extracted.next() {
                present(entry) => { tree_removed += entry.1 },
                none => { break }
            }
        }
    }
    if tree_calls != 3 || tree_removed != 20 || tree.len() != 2usize { return 4 }

    var tree_set = btree.set_new<i32>()
    let _ = tree_set.insert(1)
    let _ = tree_set.insert(2)
    let _ = tree_set.insert(3)
    var tree_set_calls = 0
    var tree_set_removed = 0
    {
        var extracted = tree_set.extract_if(fn(key: read i32): bool {
            tree_set_calls += 1
            tree_set_calls == 2
        })
        while true {
            match extracted.next() {
                present(key) => { tree_set_removed += key },
                none => { break }
            }
        }
    }
    if tree_set_calls != 3 || tree_set_removed != 2 || tree_set.len() != 2usize { return 5 }
    0
}
