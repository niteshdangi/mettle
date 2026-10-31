// LinkedList cursors, bidirectional exact-size iteration, append, split_off,
// remove, retain and extract_if, with drop counts for removed elements.
import alloc.linked_list
import core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator}

type D { c: ptr<mut i32>; id: i32
    drop { unsafe { *self.c += self.id } } }

fn values(list: read linked_list.LinkedList<i32>): i32 {
    var total = 0
    var weight = 1
    var iter = list.iter()
    while true {
        match iter.next() {
            present(value) => { total += *value * weight; weight *= 10 },
            none => { break }
        }
    }
    total
}

fn front_is(list: read linked_list.LinkedList<i32>, expected: i32): bool {
    match list.front() { present(v) => *v == expected, none => false }
}
fn back_is(list: read linked_list.LinkedList<i32>, expected: i32): bool {
    match list.back() { present(v) => *v == expected, none => false }
}

fn main(): i32 {
    var list = linked_list.new<i32>()
    list.push_back(1)
    list.push_back(2)
    list.push_back(3)
    list.push_back(4)

    var iter = list.iter()
    if iter.len() != 4usize { return 1 }
    match iter.next_back() { present(v) => { if *v != 4 { return 2 } }, none => { return 2 } }
    match iter.next() { present(v) => { if *v != 1 { return 3 } }, none => { return 3 } }
    if iter.len() != 2usize { return 4 }
    match iter.next_back() { present(v) => { if *v != 3 { return 5 } }, none => { return 5 } }
    match iter.next() { present(v) => { if *v != 2 { return 6 } }, none => { return 6 } }
    if iter.next().is_present() || iter.next_back().is_present() || iter.len() != 0usize { return 7 }

    // Cursor navigation wraps through the ghost position.
    {
        var cursor = list.cursor_front()
        match cursor.index() { present(i) => { if i != 0usize { return 8 } }, none => { return 8 } }
        cursor.move_prev()
        if cursor.current().is_present() || cursor.index().is_present() { return 9 }
        match cursor.peek_next() { present(v) => { if *v != 1 { return 10 } }, none => { return 10 } }
        match cursor.peek_prev() { present(v) => { if *v != 4 { return 11 } }, none => { return 11 } }
        cursor.move_prev()
        match cursor.index() { present(i) => { if i != 3usize { return 12 } }, none => { return 12 } }
        match cursor.current() { present(v) => { if *v != 4 { return 13 } }, none => { return 13 } }
    }

    // Insertion and removal through a mutable cursor.
    {
        var cursor = list.cursor_front_mut()
        cursor.move_next()
        cursor.insert_before(10)
        match cursor.index() { present(i) => { if i != 2usize { return 14 } }, none => { return 14 } }
        cursor.insert_after(20)
        match cursor.remove_current() { present(v) => { if v != 2 { return 15 } }, none => { return 15 } }
        match cursor.current() { present(v) => { if *v != 20 { return 16 } }, none => { return 16 } }
        match cursor.current() { present(v) => { *v += 1 }, none => { return 17 } }
    }
    // 1, 10, 21, 3, 4
    if list.len() != 5usize || values(list) != 45201 { return 18 }

    // The ghost position inserts at either end.
    {
        var cursor = list.cursor_back_mut()
        cursor.move_next()
        cursor.insert_before(5)
        cursor.insert_after(0)
    }
    // 0, 1, 10, 21, 3, 4, 5
    if list.len() != 7usize || !front_is(list, 0) || !back_is(list, 5) { return 19 }

    // Empty-list cursors stay at the ghost.
    var empty = linked_list.new<i32>()
    {
        var cursor = empty.cursor_back_mut()
        cursor.move_prev()
        cursor.move_next()
        if cursor.current().is_present() || cursor.remove_current().is_present() { return 20 }
        cursor.insert_after(7)
    }
    if empty.len() != 1usize || !empty.contains(7) || empty.contains(8) { return 21 }

    // append moves nodes and empties the donor.
    var tail = linked_list.new<i32>()
    tail.push_back(100)
    tail.push_back(200)
    list.append(mut tail)
    if tail.len() != 0usize || tail.front().is_present() || list.len() != 9usize { return 22 }
    if !back_is(list, 200) { return 23 }
    var none_left = linked_list.new<i32>()
    list.append(mut none_left)
    if list.len() != 9usize { return 24 }

    // split_off at the boundaries and in the middle.
    var back = list.split_off(7usize)
    if back.len() != 2usize || list.len() != 7usize || !front_is(back, 100) { return 25 }
    if !back_is(list, 5) { return 26 }
    var everything = list.split_off(0usize)
    if list.len() != 0usize || everything.len() != 7usize { return 27 }
    var nothing = everything.split_off(7usize)
    if nothing.len() != 0usize || everything.len() != 7usize { return 28 }
    if everything.remove(3usize) != 21 || everything.len() != 6usize { return 29 }

    // Dropped elements are counted exactly once.
    var n = 0
    let c = core.ptr.from_mut(n)
    {
        var drops = linked_list.new<D>()
        var i = 1
        while i <= 6 { drops.push_back(D(c, i)); i += 1 }
        drops.retain(fn(d: read D): bool { d.id % 2 == 0 })
        if n != 9 || drops.len() != 3usize { return 30 }
        {
            var extracted = drops.extract_if(fn(d: mut D): bool { d.id == 4 })
            match extracted.next() {
                present(d) => { if d.id != 4 { return 31 } },
                none => { return 31 }
            }
            if n != 13 { return 32 }
        }
        if n != 13 || drops.len() != 2usize { return 33 }
        let gone = drops.remove(0usize)
        if n != 13 { return 34 }
    }
    if n != 21 { return 35 }
    0
}
