import alloc.vec
import core.iter.Iterator

type Item {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}

fn is_even<region r>(item: read Item from r): bool {
    item.value % 2 == 0
}

fn item_value(item: take Item): i32 {
    item.value
}

fn main(): i32 {
    var drops = 0
    {
        var values = vec.new<Item>()
        values.push(Item(core.ptr.from_mut(drops), 1))
        values.push(Item(core.ptr.from_mut(drops), 2))
        values.push(Item(core.ptr.from_mut(drops), 3))
        values.push(Item(core.ptr.from_mut(drops), 4))

        {
            var adapted = values.into_iter().filter(is_even).map(item_value)
            match take adapted.next() {
                present(item) => { if item != 2 { return 1 } },
                none => { return 1 }
            }
            if drops != 2 { return 2 }
        }
        if drops != 4 { return 3 }
    }
    if drops != 4 { return 4 }
    0
}
