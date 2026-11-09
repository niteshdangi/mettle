import alloc.vec
import core.iter.Iterator

type Item {
    value: i32
    drop {}
}

fn is_even<region r>(read item: Item from r): bool { item.value % 2 == 0 }
fn increment(take item: Item): i32 { item.value + 1 }

fn main(): i32 {
    var items = vec.new<Item>()
    items.push(Item(2))
    items.push(Item(3))
    items.push(Item(4))
    var adapted = items.into_iter().filter(is_even).map(increment)
    match take adapted.next() {
        present(value) => { if value != 3 { return 1 } },
        none => { return 2 }
    }
    match take adapted.next() {
        present(value) => { if value != 5 { return 3 } },
        none => { return 4 }
    }
    match take adapted.next() {
        present(_) => { return 5 },
        none => {}
    }
    0
}
