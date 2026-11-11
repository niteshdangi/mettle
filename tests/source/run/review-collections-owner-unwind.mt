// profiles: debug release
import core.cmp.PartialEq
import core.iter.{Iterator, OwnedIterable}
import std.panic.CatchResult

type Bomb {
    id: i32
    drops: ptr<mut usize>
    mode: u8
    drop {
        unsafe { *self.drops += 1usize }
        if self.mode == 1u8 { panic("drop stop") }
    }
}

extend Bomb implements PartialEq {
    fn eq(read other: Bomb): bool {
        if self.mode == 2u8 { panic("eq stop") }
        self.id == other.id
    }
}

fn main(): i32 {
    var drops = 0usize
    let counter = core.ptr.from_mut(drops)
    var values = alloc.vec.new<Bomb>()
    values.push(Bomb(1, counter, 0u8))
    values.push(Bomb(1, counter, 0u8))
    values.push(Bomb(2, counter, 2u8))
    values.push(Bomb(3, counter, 0u8))
    let dedup = std.panic.catch_panic(fn(): Unit { values.dedup() })
    match take dedup {
        CatchResult.Panicked(info) => { if info.message() != "eq stop" { return 1 } },
        CatchResult.Returned(_) => { return 2 }
    }
    if drops != 1usize || values.len() != 3usize ||
        values[0usize].id != 1 || values[1usize].id != 2 || values[2usize].id != 3 { return 3 }
    values.clear()
    if drops != 4usize { return 4 }
    drops = 0usize
    values.push(Bomb(1, counter, 1u8))
    values.push(Bomb(2, counter, 0u8))
    values.push(Bomb(3, counter, 0u8))
    let clear = std.panic.catch_panic(fn(): Unit { values.clear() })
    match take clear {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 5 }
    }
    if drops != 3usize || !values.is_empty() { return 6 }
    drops = 0usize
    let owned = std.panic.catch_panic(fn(): Unit {
        var source = alloc.vec.new<Bomb>()
        source.push(Bomb(1, counter, 1u8))
        source.push(Bomb(2, counter, 0u8))
        source.push(Bomb(3, counter, 0u8))
    })
    match take owned {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 20 }
    }
    if drops != 3usize { return 21 }
    drops = 0usize
    values.push(Bomb(1, counter, 0u8))
    values.push(Bomb(2, counter, 1u8))
    values.push(Bomb(3, counter, 0u8))
    values.push(Bomb(4, counter, 0u8))
    let drain = std.panic.catch_panic(fn(): Unit {
        let removed = values.drain(1usize..3usize)
    })
    match take drain {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 7 }
    }
    if drops != 2usize || values.len() != 2usize ||
        values[0usize].id != 1 || values[1usize].id != 4 { return 8 }
    values.clear()
    if drops != 4usize { return 9 }
    drops = 0usize
    let consuming = std.panic.catch_panic(fn(): Unit {
        var source = alloc.vec.new<Bomb>()
        source.push(Bomb(1, counter, 0u8))
        source.push(Bomb(2, counter, 1u8))
        source.push(Bomb(3, counter, 0u8))
        var items = source.into_iter()
        let first = items.next().unwrap()
    })
    match take consuming {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 10 }
    }
    if drops != 3usize { return 11 }
    drops = 0usize
    let linked = std.panic.catch_panic(fn(): Unit {
        var items = alloc.linked_list.new<Bomb>()
        items.push_back(Bomb(1, counter, 1u8))
        items.push_back(Bomb(2, counter, 0u8))
        items.push_back(Bomb(3, counter, 0u8))
    })
    match take linked {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 12 }
    }
    if drops != 3usize { return 13 }
    drops = 0usize
    let ring = std.panic.catch_panic(fn(): Unit {
        var items = alloc.vec_deque.new<Bomb>()
        items.push_back(Bomb(1, counter, 1u8))
        items.push_back(Bomb(2, counter, 0u8))
        items.push_back(Bomb(3, counter, 0u8))
    })
    match take ring {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 14 }
    }
    if drops != 3usize { return 15 }
    drops = 0usize
    let tree = std.panic.catch_panic(fn(): Unit {
        var items = alloc.btree.new<i32, Bomb>()
        var id = 0
        while id < 24 {
            let old = items.insert(id + 0, Bomb(id + 0, counter, if id == 0 { 1u8 } else { 0u8 }))
            id += 1
        }
    })
    match take tree {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 16 }
    }
    if drops != 24usize { return 17 }
    drops = 0usize
    let tree_iter = std.panic.catch_panic(fn(): Unit {
        var items = alloc.btree.new<i32, Bomb>()
        let first = items.insert(1, Bomb(1, counter, 1u8))
        let second = items.insert(2, Bomb(2, counter, 0u8))
        let third = items.insert(3, Bomb(3, counter, 0u8))
        let source = items.into_iter()
    })
    match take tree_iter {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 18 }
    }
    if drops != 3usize { return 19 }
    0
}
