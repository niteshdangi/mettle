import alloc.vec
import core.iter.Iterator

type Item {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var drops = 0
    {
        var values = vec.new<Item>()
        values.push(Item(core.ptr.from_mut(drops), 1))
        values.push(Item(core.ptr.from_mut(drops), 2))
        values.push(Item(core.ptr.from_mut(drops), 3))
        values.push(Item(core.ptr.from_mut(drops), 4))

        var filtered = values.into_iter().filter(
            fn(item: read Item): bool { item.value % 2 == 0 }
        )
        var adapted = filtered.map(take fn(item: Item): Item { item })
        var total = 0
        for item in take adapted { total += item.value }
        if total != 6 || drops != 4 { return 1 }
    }
    if drops != 4 { return 2 }
    0
}
