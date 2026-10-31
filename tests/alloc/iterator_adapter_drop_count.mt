import alloc.vec
import core.iter.Iterator

type Item {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}

fn is_even(item: read Item): bool { item.value % 2 == 0 }

fn value_of(item: take Item): i32 { item.value }

fn even_value(item: take Item): i32? {
    if item.value % 2 == 0 { present(item.value) } else { none }
}

fn main(): i32 {
    var drops = 0
    {
        var values = vec.new<Item>()
        values.push(Item(core.ptr.from_mut(drops), 1))
        values.push(Item(core.ptr.from_mut(drops), 2))
        values.push(Item(core.ptr.from_mut(drops), 3))
        values.push(Item(core.ptr.from_mut(drops), 4))

        var adapted = values.into_iter().filter(is_even).map(value_of)
        var total = 0
        for item in take adapted { total += item }
        if total != 6 || drops != 4 { return 1 }
    }
    if drops != 4 { return 2 }

    var mapped_drops = 0
    {
        var values = vec.new<Item>()
        values.push(Item(core.ptr.from_mut(mapped_drops), 1))
        values.push(Item(core.ptr.from_mut(mapped_drops), 2))
        values.push(Item(core.ptr.from_mut(mapped_drops), 3))
        values.push(Item(core.ptr.from_mut(mapped_drops), 4))
        var adapted = values.into_iter().filter_map(even_value)
        var total = 0
        for item in take adapted { total += item }
        if total != 6 || mapped_drops != 4 { return 3 }
    }
    if mapped_drops != 4 { return 4 }
    0
}
