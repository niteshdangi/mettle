// Iterator ordering, sorted checks, partition, unzip, and peekable mapping.
import alloc.vec.List
import core.cmp.Ordering
import core.iter
import core.iter.Iterator

type Item {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    if take iter.range(1, 4).cmp(iter.range(1, 4)) != Ordering.Equal { return 1 }
    if take iter.range(1, 3).cmp(iter.range(1, 4)) != Ordering.Less { return 2 }
    if take iter.range(1, 4).cmp(iter.range(1, 3)) != Ordering.Greater { return 3 }
    if take iter.range(2, 4).cmp(iter.range(1, 4)) != Ordering.Greater { return 4 }
    match take iter.range(1, 3).partial_cmp(iter.range(1, 4)) {
        present(order) => { if !order.is_lt() { return 5 } },
        none => { return 5 }
    }
    if !take iter.range(1, 4).eq(iter.range(1, 4)) || take iter.range(1, 3).eq(iter.range(1, 4)) {
        return 6
    }
    if !take iter.range(1, 3).ne(iter.range(1, 4)) { return 7 }
    if !take iter.range(1, 3).lt(iter.range(1, 4)) { return 8 }
    if !take iter.range(1, 4).le(iter.range(1, 4)) { return 9 }
    if !take iter.range(2, 4).gt(iter.range(1, 4)) { return 10 }
    if !take iter.range(1, 4).ge(iter.range(1, 3)) { return 11 }

    if !take iter.range(1, 5).is_sorted() { return 12 }
    if take iter.once(3).chain(iter.once(1)).is_sorted() { return 13 }
    if !take iter.range(1, 5).is_sorted_by(fn(before: read i32, after: read i32): bool {
        before <= after
    }) {
        return 14
    }
    if !take iter.once(3).chain(iter.once(1)).is_sorted_by_key(fn(value: read i32): i32 { 0 - value }) {
        return 15
    }
    if take iter.once(1).chain(iter.once(3)).is_sorted_by_key(fn(value: read i32): i32 { 0 - value }) {
        return 28
    }

    let parts: (List<i32>, List<i32>) = take iter.range(1, 6).partition(
        fn(value: read i32): bool { value % 2 == 0 }
    )
    if parts.0.len() != 2usize || parts.0[0usize] != 2 || parts.0[1usize] != 4 { return 16 }
    if parts.1.len() != 3usize || parts.1[0usize] != 1 || parts.1[2usize] != 5 { return 17 }

    let pairs = iter.once((1, 10)).chain(iter.once((2, 20)))
    let unzipped: (List<i32>, List<i32>) = take pairs.unzip()
    if unzipped.0.len() != 2usize || unzipped.0[1usize] != 2 { return 18 }
    if unzipped.1.len() != 2usize || unzipped.1[0usize] != 10 || unzipped.1[1usize] != 20 { return 19 }

    var mapped = iter.range(1, 4).peekable()
    match take mapped.next_if_map(fn(value: read i32): i32? {
        if value == 1 { present(value * 10) } else { none }
    }) {
        present(value) => { if value != 10 { return 20 } },
        none => { return 20 }
    }
    match take mapped.next_if_map(fn(value: read i32): i32? { none }) {
        present(value) => { return 21 },
        none => {}
    }
    match take mapped.peek() {
        present(value) => { if *value != 2 { return 22 } },
        none => { return 22 }
    }
    match take mapped.next_if_map_mut(fn(value: mut i32): i32? {
        *value += 1
        none
    }) {
        present(value) => { return 23 },
        none => {}
    }
    match take mapped.next_if_map_mut(fn(value: mut i32): i32? { present(*value) }) {
        present(value) => { if value != 3 { return 24 } },
        none => { return 24 }
    }

    var drops = 0
    {
        let counter = core.ptr.from_mut(drops)
        let source = iter.once(Item(counter, 1))
            .chain(iter.once(Item(counter, 2)))
            .chain(iter.once(Item(counter, 3)))
        let split: (List<Item>, List<Item>) = take source.partition(
            fn(item: read Item): bool { item.value % 2 == 0 }
        )
        {
            let matched = split.0
            if matched.len() != 1usize { return 25 }
        }
        if drops != 1 || split.1.len() != 2usize { return 26 }
    }
    if drops != 3 { return 27 }
    0
}
