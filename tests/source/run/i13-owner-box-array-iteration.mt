import alloc.boxed
import core.iter.{BidirectionalIterator, ExactSizeIterator, Iterator, OwnedIterable}

type DropItem {
    value: i32
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var drops = 0
    var owner = boxed.new([
        DropItem(1, core.ptr.from_mut(drops)),
        DropItem(2, core.ptr.from_mut(drops)),
        DropItem(3, core.ptr.from_mut(drops))
    ])
    var borrowed_sum = 0i32
    for item in read owner { borrowed_sum += (*item).value }
    if borrowed_sum != 6i32 { return 1 }

    for item in mut owner { (*item).value += 10i32 }
    var mutated_sum = 0i32
    for item in read owner { mutated_sum += (*item).value }
    if mutated_sum != 36i32 { return 2 }

    var first_owned = 0i32
    for item in take owner {
        first_owned = item.value
        break
    }
    if first_owned != 11i32 || drops != 3 { return 3 }

    var mixed_drops = 0
    {
        var mixed = boxed.new([
            DropItem(21, core.ptr.from_mut(mixed_drops)),
            DropItem(22, core.ptr.from_mut(mixed_drops)),
            DropItem(23, core.ptr.from_mut(mixed_drops))
        ]).into_iter()
        if mixed.len() != 3usize { return 4 }
        match take mixed.next_back() {
            present(item) => { if item.value != 23i32 { return 5 } },
            none => { return 5 }
        }
        if mixed.len() != 2usize || mixed_drops != 1 { return 6 }
        match take mixed.next() {
            present(item) => { if item.value != 21i32 { return 7 } },
            none => { return 7 }
        }
        if mixed.len() != 1usize || mixed_drops != 2 { return 8 }
        match take mixed.next_back() {
            present(item) => { if item.value != 22i32 { return 9 } },
            none => { return 9 }
        }
        if mixed.len() != 0usize || mixed_drops != 3 { return 10 }
        match take mixed.next() {
            none => {},
            present(_) => { return 11 }
        }
        match take mixed.next() {
            none => {},
            present(_) => { return 12 }
        }
    }

    if mixed_drops != 3 { return 13 }

    var empty = boxed.new([0i32; 0usize])
    for item in read empty {
        let _ = item
        return 14
    }
    for item in mut empty {
        let _ = item
        return 14
    }
    for item in take empty {
        let _ = item
        return 14
    }
    0
}
