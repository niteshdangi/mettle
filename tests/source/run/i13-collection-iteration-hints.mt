import alloc.linked_list
import alloc.vec
import alloc.vec_deque
import core.iter.{BidirectionalIterator, ExactSizeIterator, FusedIterator, Iterator}

type Counted {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

fn exact_len<I: ExactSizeIterator>(items: read I): usize {
    I.(ExactSizeIterator).len(items)
}

fn require_fused<I: FusedIterator>(items: take I): Unit {
    let _ = items
}

fn main(): i32 {
    var drops = 0usize
    {
        var source = vec.new<Counted>()
        source.push(Counted(1, core.ptr.from_mut(drops)))
        source.push(Counted(2, core.ptr.from_mut(drops)))
        source.push(Counted(3, core.ptr.from_mut(drops)))
        var items = source.into_iter()
        if items.size_hint() != (3usize, present(3usize)) ||
            exact_len(read items) != 3usize {
            return 1
        }
        match take items.next() {
            present(item) => { if item.value != 1 { return 2 } },
            none => { return 3 }
        }
        if drops != 1usize || items.size_hint() != (2usize, present(2usize)) {
            return 4
        }
        match take items.next_back() {
            present(item) => { if item.value != 3 { return 5 } },
            none => { return 6 }
        }
        if items.size_hint() != (1usize, present(1usize)) { return 7 }
        match take items.next() {
            present(item) => { if item.value != 2 { return 8 } },
            none => { return 9 }
        }
        if items.size_hint() != (0usize, present(0usize)) ||
            exact_len(read items) != 0usize ||
            items.next().is_present() || items.next_back().is_present() {
            return 10
        }
        require_fused(take items)
    }
    if drops != 3usize { return 11 }

    var deque = vec_deque.new<i32>()
    deque.push_back(1)
    deque.push_back(2)
    deque.push_back(3)
    deque.push_back(4)
    {
        var range = deque.range(1usize, 4usize)
        if range.size_hint() != (3usize, present(3usize)) ||
            exact_len(read range) != 3usize {
            return 12
        }
        match take range.next_back() {
            present(value) => { if *value != 4 { return 13 } },
            none => { return 14 }
        }
        match take range.next() {
            present(value) => { if *value != 2 { return 15 } },
            none => { return 16 }
        }
        if range.size_hint() != (1usize, present(1usize)) { return 17 }
        match take range.next() {
            present(value) => { if *value != 3 { return 18 } },
            none => { return 19 }
        }
        if range.size_hint() != (0usize, present(0usize)) ||
            range.next().is_present() || range.next_back().is_present() {
            return 20
        }
        require_fused(take range)
    }
    {
        var range = deque.range_mut(1usize, 3usize)
        if range.size_hint() != (2usize, present(2usize)) { return 21 }
        match take range.next() {
            present(value) => { *value = 20 },
            none => { return 22 }
        }
        match take range.next_back() {
            present(value) => { *value = 30 },
            none => { return 23 }
        }
        if range.size_hint() != (0usize, present(0usize)) ||
            range.next().is_present() {
            return 24
        }
        require_fused(take range)
    }
    if deque[1usize] != 20 || deque[2usize] != 30 { return 25 }
    {
        var items = deque.into_iter()
        if items.size_hint() != (4usize, present(4usize)) { return 26 }
        let _first = items.next()
        let _last = items.next_back()
        if items.size_hint() != (2usize, present(2usize)) { return 27 }
        let _ = items.next()
        let _ = items.next_back()
        if items.size_hint() != (0usize, present(0usize)) ||
            items.next().is_present() {
            return 28
        }
        require_fused(take items)
    }

    var list = linked_list.new<i32>()
    list.push_back(1)
    list.push_back(2)
    list.push_back(3)
    {
        var items = list.iter()
        if items.size_hint() != (3usize, present(3usize)) ||
            exact_len(read items) != 3usize {
            return 29
        }
        match take items.next_back() {
            present(value) => { if *value != 3 { return 30 } },
            none => { return 31 }
        }
        match take items.next() {
            present(value) => { if *value != 1 { return 32 } },
            none => { return 33 }
        }
        if items.size_hint() != (1usize, present(1usize)) { return 34 }
        match take items.next() {
            present(value) => { if *value != 2 { return 35 } },
            none => { return 36 }
        }
        if items.size_hint() != (0usize, present(0usize)) ||
            items.next_back().is_present() {
            return 37
        }
        require_fused(take items)
    }
    {
        var items = list.iter_mut()
        match take items.next() {
            present(value) => { *value = 10 },
            none => { return 38 }
        }
        match take items.next_back() {
            present(value) => { *value = 30 },
            none => { return 39 }
        }
        if items.size_hint() != (1usize, present(1usize)) { return 40 }
        match take items.next_back() {
            present(value) => { *value = 20 },
            none => { return 41 }
        }
        if items.size_hint() != (0usize, present(0usize)) ||
            items.next().is_present() {
            return 42
        }
        require_fused(take items)
    }
    if *list.get(0usize).unwrap() != 10 ||
        *list.get(1usize).unwrap() != 20 ||
        *list.get(2usize).unwrap() != 30 {
        return 43
    }
    {
        var items = list.extract_if(fn(value: mut i32): bool {
            value == 20
        })
        if items.size_hint() != (0usize, present(3usize)) { return 44 }
        match take items.next() {
            present(value) => { if value != 20 { return 45 } },
            none => { return 46 }
        }
        if items.size_hint() != (0usize, present(1usize)) { return 47 }
        if items.next().is_present() || items.size_hint() != (0usize, present(0usize)) ||
            items.next().is_present() {
            return 48
        }
        require_fused(take items)
    }
    if list.len() != 2usize || *list.get(0usize).unwrap() != 10 ||
        *list.get(1usize).unwrap() != 30 {
        return 49
    }
    list.push_back(40)
    {
        var items = list.into_iter()
        if items.size_hint() != (3usize, present(3usize)) { return 50 }
        let _last = items.next_back()
        let _first = items.next()
        if items.size_hint() != (1usize, present(1usize)) ||
            exact_len(read items) != 1usize {
            return 51
        }
        let _middle = items.next()
        if items.size_hint() != (0usize, present(0usize)) ||
            items.next_back().is_present() {
            return 52
        }
        require_fused(take items)
    }

    var drained = vec.new<i32>()
    drained.push(1)
    drained.push(2)
    drained.push(3)
    drained.push(4)
    {
        var items = drained.drain(1usize..3usize)
        if items.size_hint() != (2usize, present(2usize)) { return 53 }
        let _first = items.next()
        if items.size_hint() != (1usize, present(1usize)) { return 54 }
        let _last = items.next_back()
        if items.size_hint() != (0usize, present(0usize)) ||
            items.next().is_present() {
            return 55
        }
        require_fused(take items)
    }
    if drained.len() != 2usize || drained[0usize] != 1 ||
        drained[1usize] != 4 {
        return 56
    }

    var spliced = vec.new<i32>()
    spliced.push(1)
    spliced.push(2)
    spliced.push(3)
    spliced.push(4)
    var replacement = vec.new<i32>()
    replacement.push(9)
    {
        var items = spliced.splice(1usize..3usize, replacement)
        if items.size_hint() != (2usize, present(2usize)) { return 57 }
        let _first = items.next()
        let _last = items.next_back()
        if items.size_hint() != (0usize, present(0usize)) ||
            items.next().is_present() {
            return 58
        }
        require_fused(take items)
    }
    if spliced.len() != 3usize || spliced[0usize] != 1 ||
        spliced[1usize] != 9 || spliced[2usize] != 4 {
        return 59
    }

    var filtered = vec.new<i32>()
    filtered.push(1)
    filtered.push(2)
    filtered.push(3)
    {
        var items = filtered.extract_if(core.iter.range_full(), fn(value: mut i32): bool {
            value % 2 == 0
        })
        if items.size_hint() != (0usize, present(3usize)) { return 60 }
        match take items.next() {
            present(value) => { if value != 2 { return 61 } },
            none => { return 62 }
        }
        if items.size_hint() != (0usize, present(1usize)) { return 63 }
        match take items.next() {
            none => {},
            present(value) => { if value != 1 && value != 3 { return 64 } }
        }
        match take items.next() {
            none => {},
            present(value) => { if value != 1 && value != 3 { return 65 } }
        }
        if items.size_hint() != (0usize, present(0usize)) ||
            items.next().is_present() {
            return 66
        }
        require_fused(take items)
    }
    if filtered.len() != 2usize || filtered[0usize] != 1 ||
        filtered[1usize] != 3 {
        return 67
    }
    0
}
