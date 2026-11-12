// profiles: debug release

import core.cell

type Pair { left: i32; right: i32 }
type Nested { prefix: i32; pair: Pair }
interface Readable { fn value(): i32; }
@align(64)
type Number { number: i32 }
extend Number implements Readable { fn value(): i32 { self.number } }

fn erase<region r>(read value: Number from r): read any Readable from r {
    read value
}
fn inner<region r>(read value: Nested from r): read Pair from r {
    read value.pair
}
fn inner_mut<region r>(mut value: Nested from r): mut Pair from r {
    mut value.pair
}

fn left<region r>(read value: Pair from r): read i32 from r {
    read value.left
}
fn left_mut<region r>(mut value: Pair from r): mut i32 from r {
    mut value.left
}
fn selected<region r>(read value: Pair from r): (read i32 from r)? {
    present(read value.right)
}
fn selected_mut<region r>(mut value: Pair from r): (mut i32 from r)? {
    present(mut value.right)
}
fn absent<region r>(read value: Pair from r): (read i32 from r)? { none }
fn absent_mut<region r>(mut value: Pair from r): (mut i32 from r)? {
    value.left += 1
    none
}
fn split<region r>(read value: Pair from r): (read i32 from r, read i32 from r) {
    (read value.left, read value.right)
}
fn split_mut<region r>(mut value: Pair from r): (mut i32 from r, mut i32 from r) {
    (mut value.left, mut value.right)
}
fn slice<region r>(read value: [i32; 4] from r): read [i32] from r {
    read value
}
fn split_slice<region r>(
    mut value: [i32] from r
): (mut [i32] from r, mut [i32] from r) {
    value.split_at_mut(2usize)
}
fn shared_available<T: unsized>(read value: core.cell.RefCell<T>): bool {
    match value.try_borrow() { success(_) => true, failure(_) => false }
}
fn exclusive_available<T: unsized>(read value: core.cell.RefCell<T>): bool {
    match value.try_borrow_mut() { success(_) => true, failure(_) => false }
}
fn main(): i32 {
    var value = core.cell.RefCell.new(Pair(3, 5))
    {
        let mapped = core.cell.Ref<Pair>.map(value.borrow(), left)
        if *mapped.get_ref() != 3 || exclusive_available(value) { return 1 }
        let cloned = mapped.clone()
        core.mem.drop(mapped)
        if *cloned.get_ref() != 3 || exclusive_available(value) { return 2 }
    }
    if !exclusive_available(value) { return 3 }
    {
        var mapped = core.cell.RefMut<Pair>.map(value.borrow_mut(), left_mut)
        *mapped.get_mut() += 4
        if shared_available(value) { return 4 }
    }
    {
        let guard = match take capture core.cell.Ref<Pair>.filter_map(value.borrow(), selected) {
            success(projected) => projected,
            failure(_) => { return 19 }
        }
        if *guard.get_ref() != 5 { return 5 }
    }
    match take capture core.cell.Ref<Pair>.filter_map(value.borrow(), absent) {
        success(_) => { return 6 },
        failure(original) => {
            if original.get_ref().left != 7 || exclusive_available(value) {
                return 7
            }
        }
    }
    {
        var guard = match take capture core.cell.RefMut<Pair>.filter_map(value.borrow_mut(), selected_mut) {
            success(projected) => projected,
            failure(_) => { return 20 }
        }
        *guard.get_mut() = 11
    }
    match take capture core.cell.RefMut<Pair>.filter_map(value.borrow_mut(), absent_mut) {
        success(_) => { return 8 },
        failure(original) => {
            var guard = original
            if guard.get_ref().left != 8 || shared_available(value) { return 9 }
            guard.get_mut().right += 1
        }
    }
    {
        let (first, last) = core.cell.Ref<Pair>.map_split(value.borrow(), split)
        core.mem.drop(first)
        if *last.get_ref() != 12 || exclusive_available(value) { return 10 }
        let clone = last.clone()
        core.mem.drop(last)
        if *clone.get_ref() != 12 || exclusive_available(value) { return 11 }
    }
    {
        let (first, last) = core.cell.RefMut<Pair>.map_split(value.borrow_mut(), split_mut)
        var a = first
        var b = last
        *a.get_mut() = 17
        *b.get_mut() = 19
        core.mem.drop(b)
        if shared_available(value) { return 12 }
        *a.get_mut() += 1
    }
    if !exclusive_available(value) || value.borrow().get_ref().left != 18 {
        return 13
    }
    let array = core.cell.RefCell.new([1i32, 2, 3, 4])
    {
        let view = core.cell.Ref<[i32; 4]>.map(array.borrow(), slice)
        if view.get_ref().len() != 4usize || view.get_ref()[3] != 4 { return 14 }
    }
    let unsized: read core.cell.RefCell<[i32]> = read array
    {
        let (a, b) = core.cell.RefMut<[i32]>.map_split(unsized.borrow_mut(), split_slice)
        var first = a
        var last = b
        if first.get_ref().len() != 2usize || last.get_ref().len() != 2usize {
            return 15
        }
        first.get_mut()[0] = 23
        last.get_mut()[1] = 29
        core.mem.drop(first)
        if shared_available(unsized) { return 16 }
    }
    if array.borrow().get_ref()[0] != 23 || array.borrow().get_ref()[3] != 29 {
        return 17
    }
    let empty = core.cell.RefCell.new([0i32; 0])
    let empty_slice: read core.cell.RefCell<[i32]> = read empty
    {
        let (a, b) = core.cell.RefMut<[i32]>.map_split(empty_slice.borrow_mut(),
            fn(mut items: [i32]): (mut [i32] from items, mut [i32] from items) {
                items.split_at_mut(0usize)
            })
        if a.get_ref().len() != 0usize || b.get_ref().len() != 0usize {
            return 24
        }
    }
    let number = core.cell.RefCell.new(Number(31))
    {
        let projected = core.cell.Ref<Number>.map(number.borrow(), erase)
        let cloned = projected.clone()
        core.mem.drop(projected)
        if cloned.get_ref().value() != 31 { return 21 }
    }
    let nested = core.cell.RefCell.new(Nested(0, Pair(37, 41)))
    {
        let projected = core.cell.Ref<Nested>.map(nested.borrow(), inner)
        if projected.get_ref().right != 41 { return 22 }
    }
    {
        var projected = core.cell.RefMut<Nested>.map(nested.borrow_mut(), inner_mut)
        projected.get_mut().left = 43
    }
    if nested.borrow().get_ref().pair.left != 43 { return 23 }
    {
        let (first, last) = core.cell.RefMut<Pair>.map_split(value.borrow_mut(), split_mut)
        core.mem.forget(first)
        core.mem.drop(last)
    }
    if shared_available(value) || exclusive_available(value) { return 18 }
    0
}
