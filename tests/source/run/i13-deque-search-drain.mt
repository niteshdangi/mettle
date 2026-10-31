// Deque search, drain, retain, and in-place mutation, including a wrapped ring.
import alloc.vec
import alloc.vec_deque
import alloc.vec_deque.Deque
import core.cmp.Ordering
import core.iter.{Iterator, BidirectionalIterator}

type DropCount {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var spaced = Deque<i32>.with_capacity(4usize)
    if spaced.capacity() < 4usize { return 1 }
    spaced.push_back(1)
    spaced.push_back(2)
    spaced.push_back(3)
    spaced.push_back(4)
    match spaced.pop_front() {
        present(value) => { if value != 1 { return 2 } },
        none => { return 2 }
    }
    spaced.push_back(5)
    var extra = vec_deque.new<i32>()
    extra.push_back(6)
    extra.push_back(7)
    spaced.append(mut extra)
    if extra.len() != 0usize || spaced.len() != 6usize { return 3 }
    if spaced[0usize] != 2 || spaced[5usize] != 7 { return 4 }
    if !spaced.contains(4) || spaced.contains(1) { return 5 }

    match capture spaced.binary_search(4) {
        success(index) => { if index != 2usize { return 6 } },
        failure(index) => { return 6 }
    }
    match capture spaced.binary_search(1) {
        success(index) => { return 7 },
        failure(index) => { if index != 0usize { return 7 } }
    }
    match capture spaced.binary_search_by(fn(value: read i32): Ordering {
        if value < 5 { Ordering.Less } else if value > 5 { Ordering.Greater } else { Ordering.Equal }
    }) {
        success(index) => { if index != 3usize { return 8 } },
        failure(index) => { return 8 }
    }
    match capture spaced.binary_search_by_key(6, fn(value: read i32): i32 { *value }) {
        success(index) => { if index != 4usize { return 9 } },
        failure(index) => { return 9 }
    }
    let point = spaced.partition_point(fn(value: read i32): bool { value < 5 })
    if point != 3usize { return 10 }

    spaced.swap(0usize, 5usize)
    if spaced[0usize] != 7 || spaced[5usize] != 2 { return 11 }
    spaced.swap(0usize, 5usize)
    spaced.truncate(4usize)
    if spaced.len() != 4usize || spaced[3usize] != 5 { return 12 }
    spaced.resize(6usize, 9)
    if spaced.len() != 6usize || spaced[4usize] != 9 || spaced[5usize] != 9 { return 13 }

    var edited = vec_deque.new<i32>()
    edited.push_back(1)
    edited.push_back(3)
    let inserted = edited.insert_mut(1usize, 2)
    *inserted = 20
    if edited[1usize] != 20 { return 14 }
    let front = edited.push_front_mut(0)
    *front = 8
    let back = edited.push_back_mut(4)
    *back = 40
    if edited[0usize] != 8 || edited[edited.len() - 1usize] != 40 { return 15 }

    var walked = 0
    {
        var cursor = edited.iter()
        while true {
            match cursor.next() {
                present(value) => { walked += *value },
                none => { break }
            }
        }
    }
    if walked != 8 + 1 + 20 + 3 + 40 { return 16 }
    {
        var editable = edited.iter_mut()
        while true {
            match editable.next() {
                present(value) => { *value += 1 },
                none => { break }
            }
        }
    }
    if edited[0usize] != 9 { return 17 }
    var window = 0
    {
        var window_iter = edited.range(1usize, 3usize)
        while true {
            match window_iter.next() {
                present(value) => { window += *value },
                none => { break }
            }
        }
    }
    if window != 2 + 21 { return 18 }
    {
        var window_back = edited.range(1usize, 3usize)
        match window_back.next_back() {
            present(value) => { if *value != 21 { return 19 } },
            none => { return 19 }
        }
    }

    var retain_drops = 0
    {
        var owned = vec_deque.new<DropCount>()
        owned.push_back(DropCount(core.ptr.from_mut(retain_drops), 1))
        owned.push_back(DropCount(core.ptr.from_mut(retain_drops), 2))
        owned.push_back(DropCount(core.ptr.from_mut(retain_drops), 3))
        let _ = owned.pop_front()
        owned.push_back(DropCount(core.ptr.from_mut(retain_drops), 4))
        owned.retain(fn(value: read DropCount): bool { value.value % 2 == 0 })
        if owned.len() != 2usize || owned[0usize].value != 2 || owned[1usize].value != 4 {
            return 20
        }
        if retain_drops != 2 { return 21 }
    }
    if retain_drops != 4 { return 22 }

    var back_drops = 0
    var seen = vec.new<i32>()
    {
        var owned = vec_deque.new<DropCount>()
        owned.push_back(DropCount(core.ptr.from_mut(back_drops), 10))
        owned.push_back(DropCount(core.ptr.from_mut(back_drops), 20))
        owned.push_back(DropCount(core.ptr.from_mut(back_drops), 30))
        owned.retain_back(fn(value: read DropCount): bool {
            seen.push(value.value)
            value.value != 20
        })
        if owned.len() != 2usize || owned[0usize].value != 10 || owned[1usize].value != 30 {
            return 23
        }
        if back_drops != 1 { return 24 }
    }
    if back_drops != 3 { return 25 }
    if seen.len() != 3usize || seen[0usize] != 30 || seen[1usize] != 20 || seen[2usize] != 10 {
        return 26
    }

    var drain_drops = 0
    {
        var owned = vec_deque.new<DropCount>()
        owned.push_back(DropCount(core.ptr.from_mut(drain_drops), 1))
        owned.push_back(DropCount(core.ptr.from_mut(drain_drops), 2))
        owned.push_back(DropCount(core.ptr.from_mut(drain_drops), 3))
        owned.push_back(DropCount(core.ptr.from_mut(drain_drops), 4))
        let _ = owned.pop_front()
        owned.push_back(DropCount(core.ptr.from_mut(drain_drops), 5))
        {
            var removed = owned.drain(1usize, 4usize)
            match removed.next() {
                present(value) => { if value.value != 3 { return 27 } },
                none => { return 27 }
            }
            match removed.next_back() {
                present(value) => { if value.value != 5 { return 28 } },
                none => { return 28 }
            }
        }
        if owned.len() != 1usize || owned[0usize].value != 2 { return 29 }
        if drain_drops != 4 { return 30 }
    }
    if drain_drops != 5 { return 31 }
    0
}
