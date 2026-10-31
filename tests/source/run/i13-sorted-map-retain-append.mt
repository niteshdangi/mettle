// Sorted map and set retain, append, replace, and take.
import alloc.btree
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}

type DropCount {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

copy type Tag { id: i32; mark: i32 }
extend Tag implements PartialEq {
    fn eq(other: read Tag): bool { self.id == other.id }
}
extend Tag implements Eq {}
extend Tag implements PartialOrd {
    fn partial_cmp(other: read Tag): Ordering? { present(self.id.cmp(read other.id)) }
}
extend Tag implements Ord {
    fn cmp(other: read Tag): Ordering { self.id.cmp(read other.id) }
}

fn main(): i32 {
    var map = alloc.btree.new<i32, i32>()
    let _ = map.insert(1, 10)
    let _ = map.insert(2, 20)
    let _ = map.insert(3, 30)
    map.retain(fn(key: read i32, value: mut i32): bool {
        if key == 2 { *value = 21 }
        key != 1
    })
    if map.len() != 2usize || map.contains_key(1) { return 1 }
    match map.get(2) {
        present(value) => { if *value != 21 { return 2 } },
        none => { return 2 }
    }

    var extra = alloc.btree.new<i32, i32>()
    let _ = extra.insert(0, 5)
    let _ = extra.insert(2, 200)
    let _ = extra.insert(4, 40)
    map.append(mut extra)
    if extra.len() != 0usize || map.len() != 4usize { return 3 }
    match map.first_key_value() {
        present(entry) => { if *entry.0 != 0 || *entry.1 != 5 { return 4 } },
        none => { return 4 }
    }
    match map.get(2) {
        present(value) => { if *value != 200 { return 5 } },
        none => { return 5 }
    }
    match map.last_key_value() {
        present(entry) => { if *entry.0 != 4 || *entry.1 != 40 { return 6 } },
        none => { return 6 }
    }

    var drops = 0
    {
        var owned = alloc.btree.new<i32, DropCount>()
        let counter = core.ptr.from_mut(drops)
        let _ = owned.insert(1, DropCount(counter))
        let _ = owned.insert(2, DropCount(counter))
        let _ = owned.insert(3, DropCount(counter))
        owned.retain(fn(key: read i32, value: mut DropCount): bool { key == 2 })
        if owned.len() != 1usize || drops != 2 { return 7 }
        var incoming = alloc.btree.new<i32, DropCount>()
        let _ = incoming.insert(2, DropCount(counter))
        owned.append(mut incoming)
        if drops != 3 || owned.len() != 1usize { return 8 }
    }
    if drops != 4 { return 9 }

    var set = alloc.btree.set_new<i32>()
    if !set.insert(5) || !set.insert(6) { return 10 }
    var more = alloc.btree.set_new<i32>()
    if !more.insert(1) || !more.insert(6) || !more.insert(9) { return 11 }
    set.append(mut more)
    if more.len() != 0usize || set.len() != 4usize { return 12 }
    match set.first() { present(key) => { if *key != 1 { return 13 } }, none => { return 13 } }
    match set.last() { present(key) => { if *key != 9 { return 14 } }, none => { return 14 } }
    set.retain(fn(key: read i32): bool { key != 6 })
    if set.len() != 3usize || set.contains(6) || !set.contains(9) { return 15 }
    match set.get(1) { present(key) => { if *key != 1 { return 16 } }, none => { return 16 } }
    match set.`take`(9) { present(key) => { if key != 9 { return 17 } }, none => { return 17 } }
    if set.contains(9) || set.len() != 2usize { return 18 }
    set.clear()
    if !set.is_empty() { return 19 }

    var tags = alloc.btree.set_new<Tag>()
    if !tags.insert(Tag(1, 4)) { return 20 }
    match tags.replace(Tag(1, 9)) {
        present(old) => { if old.mark != 4 { return 21 } },
        none => { return 21 }
    }
    match tags.get(Tag(1, 0)) {
        present(found) => { if found.mark != 9 || found.id != 1 { return 22 } },
        none => { return 22 }
    }
    match tags.replace(Tag(2, 3)) { present(old) => { return 23 }, none => {} }
    if tags.len() != 2usize { return 24 }
    0
}
