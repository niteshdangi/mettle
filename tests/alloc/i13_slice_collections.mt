type DropCount {
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1 } }
}

fn main(): i32 {
    var list = alloc.vec.new<i32>()
    list.push(1)
    list.push(2)
    list.push(3)
    list.push(4)
    list.rotate_left(1usize)
    if list[0usize] != 2 || list[3usize] != 1 { return 1 }
    list.copy_within(0usize, 2usize, 1usize)
    if list[1usize] != 2 || list[2usize] != 3 { return 2 }
    list.extend_from_within(0usize, 2usize)
    if list.len() != 6usize || list[4usize] != 2 || list[5usize] != 2 { return 3 }
    list.resize_with(8usize, fn(): i32 { 9 })
    if list[6usize] != 9 || list[7usize] != 9 { return 4 }
    let tail = list.split_off(6usize)
    if list.len() != 6usize || tail.len() != 2usize || tail[1usize] != 9 { return 5 }
    let copied = list.as_slice().to_vec()
    let repeated = list.as_slice().repeat(2usize)
    if copied.len() != 6usize || copied[0usize] != list[0usize] ||
        repeated.len() != 12usize || repeated[6usize] != list[0usize] {
        return 14
    }
    var filtered = alloc.vec.new<i32>()
    filtered.push(1)
    filtered.push(1)
    filtered.push(2)
    filtered.push(2)
    filtered.push(3)
    filtered.dedup_by(fn(current: mut i32, previous: mut i32): bool {
        current == previous
    })
    if filtered.len() != 3usize || filtered[1usize] != 2 { return 15 }
    filtered.dedup_by_key(fn(value: mut i32): i32 { value })
    filtered.retain_mut(fn(value: mut i32): bool {
        value += 1
        value % 2 == 0
    })
    if filtered.len() != 2usize || filtered[0usize] != 2 || filtered[1usize] != 4 {
        return 16
    }
    {
        var extracted = filtered.extract_if(0usize, filtered.len(),
            fn(value: mut i32): bool { value == 2 })
        match extracted.next() {
            present(value) => { if value != 2 { return 17 } },
            none => { return 17 }
        }
        match extracted.next() { none => {}, present(_) => { return 18 } }
    }
    if filtered.len() != 1usize || filtered[0usize] != 4 { return 19 }
    match filtered.pop_if(fn(value: mut i32): bool { value == 4 }) {
        present(value) => { if value != 4 { return 20 } },
        none => { return 20 }
    }
    if filtered.pop_if(fn(value: mut i32): bool { value == 0 }).is_present() { return 21 }
    var spliced = alloc.vec.new<i32>()
    spliced.push(1)
    spliced.push(2)
    spliced.push(3)
    var replacement = alloc.vec.new<i32>()
    replacement.push(8)
    replacement.push(9)
    {
        var removed = spliced.splice(1usize, 2usize, replacement)
        match removed.next() {
            present(value) => { if value != 2 { return 22 } },
            none => { return 22 }
        }
        match removed.next() { none => {}, present(_) => { return 34 } }
    }
    if spliced.len() != 4usize || spliced[1usize] != 8 || spliced[2usize] != 9 {
        return 35
    }
    spliced.reserve(1usize)
    {
        var spare = spliced.spare_capacity_mut()
        match take spare.get_mut(0usize) {
            present(slot) => { let initialized = slot.write(10); let _ = initialized },
            none => { return 36 }
        }
    }
    unsafe { spliced.set_len(5usize) }
    if spliced[4usize] != 10 { return 23 }
    spliced.shrink_to(5usize)
    let boxed = spliced.into_boxed_slice()
    if boxed.get().len() != 5usize || boxed.get()[4usize] != 10 { return 24 }
    var to_leak = alloc.vec.new<i32>()
    to_leak.push(42)
    let leaked = to_leak.leak()
    leaked[0usize] = 43
    if leaked[0usize] != 43 { return 25 }

    var deque = alloc.vec_deque.new<i32>()
    deque.push_back(1)
    deque.push_back(2)
    deque.push_back(3)
    deque.push_back(4)
    let first = deque.pop_front()
    let second = deque.pop_front()
    deque.push_back(5)
    deque.push_back(6)
    let parts = deque.as_slices()
    if parts.0.len() != 2usize || parts.1.len() != 2usize ||
        parts.0[0usize] != 3 || parts.1[1usize] != 6 {
        return 6
    }
    {
        let pieces = take deque.as_mut_slices()
        pieces.0[0usize] = 30
        pieces.1[1usize] = 60
    }
    deque.rotate_left(1usize)
    if deque[0usize] != 4 || deque[3usize] != 30 { return 7 }
    let removed_front = deque.swap_remove_front(1usize)
    if removed_front != 5 { return 8 }
    let removed_back = deque.swap_remove_back(1usize)
    if removed_back != 60 { return 9 }
    let right = deque.split_off(1usize)
    if deque.len() != 1usize || deque[0usize] != 4 ||
        right.len() != 1usize || right[0usize] != 30 {
        return 10
    }
    deque.resize_with(3usize, fn(): i32 { 11 })
    if deque.len() != 3usize || deque[1usize] != 11 || deque[2usize] != 11 { return 11 }
    {
        var range = deque.range_mut(1usize, 3usize)
        match take range.next_back() {
            present(value) => { *value = 12 },
            none => { return 26 }
        }
        match take range.next() {
            present(value) => { *value = 13 },
            none => { return 27 }
        }
    }
    if deque[1usize] != 13 || deque[2usize] != 12 { return 28 }
    deque.retain_mut(fn(value: mut i32): bool { value != 12 })
    if deque.len() != 2usize || deque[0usize] != 4 || deque[1usize] != 13 { return 29 }
    {
        let contiguous = deque.make_contiguous()
        if contiguous.len() != 2usize || contiguous[0usize] != 4 { return 30 }
    }
    deque.shrink_to(1usize)
    if deque.capacity() < deque.len() { return 31 }
    match deque.pop_front_if(fn(value: mut i32): bool { value == 4 }) {
        present(value) => { if value != 4 { return 32 } },
        none => { return 32 }
    }
    match deque.pop_back_if(fn(value: mut i32): bool { value == 13 }) {
        present(value) => { if value != 13 { return 33 } },
        none => { return 33 }
    }

    var dedup_drops = 0
    {
        var owned = alloc.vec.new<DropCount>()
        owned.push(DropCount(core.ptr.from_mut(dedup_drops)))
        owned.push(DropCount(core.ptr.from_mut(dedup_drops)))
        owned.push(DropCount(core.ptr.from_mut(dedup_drops)))
        owned.dedup_by(fn(current: mut DropCount, previous: mut DropCount): bool {
            true
        })
        if owned.len() != 1usize || dedup_drops != 2 { return 86 }
    }
    if dedup_drops != 3 { return 87 }
    var retain_drops = 0
    {
        var owned = alloc.vec.new<DropCount>()
        owned.push(DropCount(core.ptr.from_mut(retain_drops)))
        owned.push(DropCount(core.ptr.from_mut(retain_drops)))
        owned.push(DropCount(core.ptr.from_mut(retain_drops)))
        var seen = 0
        owned.retain(fn(value: read DropCount): bool {
            let _ = value
            seen += 1
            seen == 1
        })
        if owned.len() != 1usize || retain_drops != 2 { return 88 }
    }
    if retain_drops != 3 { return 89 }
    var splice_drops = 0
    {
        var owned = alloc.vec.new<DropCount>()
        owned.push(DropCount(core.ptr.from_mut(splice_drops)))
        owned.push(DropCount(core.ptr.from_mut(splice_drops)))
        owned.push(DropCount(core.ptr.from_mut(splice_drops)))
        var replacement = alloc.vec.new<DropCount>()
        replacement.push(DropCount(core.ptr.from_mut(splice_drops)))
        {
            let _removed = owned.splice(1usize, 2usize, replacement)
        }
        if owned.len() != 3usize || splice_drops != 1 { return 92 }
    }
    if splice_drops != 4 { return 93 }

    var drops = 0
    let count = core.ptr.from_mut(drops)
    {
        var owned = alloc.vec_deque.new<DropCount>()
        owned.push_back(DropCount(count))
        owned.push_back(DropCount(count))
        owned.push_back(DropCount(count))
        let removed = owned.swap_remove_back(0usize)
        if drops != 0 || owned.len() != 2usize { return 12 }
    }
    if drops != 3 { return 13 }
    0
}
