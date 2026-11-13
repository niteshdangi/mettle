// profiles: debug release
import alloc.vec_deque
import core.iter.{BidirectionalIterator, Bound, ExactSizeIterator, FusedIterator, Iterator}

static mut ZST_DROPS: usize = 0usize

type UnitDrop {
    drop { unsafe { ZST_DROPS += 1usize } }
}

fn exact_len<I: ExactSizeIterator>(read items: I): usize {
    I.(ExactSizeIterator).len(items)
}

fn require_fused<I: FusedIterator>(take items: I): Unit {
    let _ = items
}

fn main(): i32 {
    var contiguous = vec_deque.with_capacity<i32>(8usize)
    var value = 0
    while value < 7 {
        let item: i32 = value
        contiguous.push_back(item)
        value += 1
    }
    {
        var drain = contiguous.drain(2usize..5usize)
        if drain.size_hint() != (3usize, present(3usize)) ||
            exact_len(read drain) != 3usize {
            return 1
        }
        match take drain.next() {
            present(item) => { if item != 2 { return 2 } },
            none => { return 3 }
        }
        match take drain.next_back() {
            present(item) => { if item != 4 { return 4 } },
            none => { return 5 }
        }
        if drain.size_hint() != (1usize, present(1usize)) { return 6 }
        match take drain.next() {
            present(item) => { if item != 3 { return 7 } },
            none => { return 8 }
        }
        if drain.size_hint() != (0usize, present(0usize)) ||
            drain.next().is_present() || drain.next_back().is_present() {
            return 9
        }
        require_fused(take drain)
    }
    if contiguous.len() != 4usize || contiguous[0usize] != 0 ||
        contiguous[1usize] != 1 || contiguous[2usize] != 5 ||
        contiguous[3usize] != 6 {
        return 10
    }
    {
        var empty = contiguous.drain(2usize..2usize)
        if empty.size_hint() != (0usize, present(0usize)) ||
            empty.next().is_present() || empty.next_back().is_present() {
            return 11
        }
        require_fused(take empty)
    }
    if contiguous.len() != 4usize || contiguous[2usize] != 5 { return 12 }

    var wrapped = vec_deque.with_capacity<i32>(8usize)
    var next_value = 1
    while next_value <= 8 {
        let item: i32 = next_value
        wrapped.push_back(item)
        next_value += 1
    }
    let _first = wrapped.pop_front()
    let _second = wrapped.pop_front()
    let _third = wrapped.pop_front()
    wrapped.push_back(9)
    wrapped.push_back(10)
    wrapped.push_back(11)
    {
        let segments = wrapped.as_slices()
        if segments.0.len() != 5usize || segments.1.len() != 3usize { return 13 }
    }
    {
        var drain = wrapped.drain(3usize..7usize)
        if drain.size_hint() != (4usize, present(4usize)) { return 14 }
        match take drain.next_back() {
            present(item) => { if item != 10 { return 15 } },
            none => { return 16 }
        }
        match take drain.next() {
            present(item) => { if item != 7 { return 17 } },
            none => { return 18 }
        }
        if drain.size_hint() != (2usize, present(2usize)) { return 19 }
        match take drain.next() {
            present(item) => { if item != 8 { return 20 } },
            none => { return 21 }
        }
        match take drain.next() {
            present(item) => { if item != 9 { return 40 } },
            none => { return 41 }
        }
    }
    if wrapped.len() != 4usize || wrapped[0usize] != 4 ||
        wrapped[1usize] != 5 || wrapped[2usize] != 6 ||
        wrapped[3usize] != 11 {
        return 22
    }
    wrapped.push_front(3)
    wrapped.push_back(12)
    if wrapped.len() != 6usize || wrapped[0usize] != 3 ||
        wrapped[1usize] != 4 || wrapped[5usize] != 12 {
        return 23
    }

    var suffix = vec_deque.new<i32>()
    var i = 0
    while i < 8 {
        let item: i32 = i
        suffix.push_back(item)
        i += 1
    }
    {
        let _drain = suffix.drain(1usize..3usize)
    }
    if suffix.len() != 6usize || suffix[0usize] != 0 ||
        suffix[1usize] != 3 || suffix[5usize] != 7 {
        return 24
    }

    var bounded = vec_deque.new<i32>()
    bounded.push_back(10)
    bounded.push_back(11)
    bounded.push_back(12)
    bounded.push_back(13)
    bounded.push_back(14)
    {
        var drain = bounded.drain((Bound.Excluded(0usize), Bound.Included(3usize)))
        if drain.size_hint() != (3usize, present(3usize)) { return 25 }
        match take drain.next() {
            present(item) => { if item != 11 { return 26 } },
            none => { return 27 }
        }
        match take drain.next_back() {
            present(item) => { if item != 13 { return 28 } },
            none => { return 29 }
        }
        match take drain.next() {
            present(item) => { if item != 12 { return 30 } },
            none => { return 31 }
        }
    }
    if bounded.len() != 2usize || bounded[0usize] != 10 ||
        bounded[1usize] != 14 {
        return 32
    }

    var all = vec_deque.new<i32>()
    all.push_back(10)
    all.push_back(11)
    all.push_back(12)
    {
        var drain = all.drain(core.iter.range_full())
        if drain.size_hint() != (3usize, present(3usize)) { return 33 }
    }
    if !all.is_empty() { return 34 }
    all.push_back(99)
    if all.len() != 1usize || all[0usize] != 99 { return 35 }

    unsafe { ZST_DROPS = 0usize }
    {
        var zero = vec_deque.new<UnitDrop>()
        zero.push_back(UnitDrop())
        zero.push_back(UnitDrop())
        zero.push_back(UnitDrop())
        zero.push_back(UnitDrop())
        {
            var drain = zero.drain(1usize..3usize)
            let _yielded = drain.next()
        }
        unsafe {
            if ZST_DROPS != 2usize { return 36 }
        }
    }
    unsafe {
        if ZST_DROPS != 4usize { return 37 }
    }

    var forgotten = vec_deque.new<i32>()
    forgotten.push_back(20)
    forgotten.push_back(21)
    forgotten.push_back(22)
    forgotten.push_back(23)
    {
        let drain = forgotten.drain(1usize..3usize)
        core.mem.forget(take drain)
    }
    if forgotten.len() != 1usize || forgotten[0usize] != 20 { return 38 }
    forgotten.push_back(24)
    if forgotten.len() != 2usize || forgotten[1usize] != 24 { return 39 }
    0
}
