import alloc.linked_list
import alloc.hash_map
import alloc.btree
import alloc.vec
import alloc.vec_deque
import core.iter.{BidirectionalIterator, ExactSizeIterator, FusedIterator, Iterator}
import core.default.Default
import core.fmt.Debug

type Counted {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

fn exact_len<I: ExactSizeIterator>(read items: I): usize {
    I.(ExactSizeIterator).len(items)
}

fn require_debug<T: Debug>(read value: T): bool { true }

fn default_value<T: Default>(): T { T.(Default).default() }

fn require_fused<I: FusedIterator>(take items: I): Unit {
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
    if *list.get(0usize).or_panic() != 10 ||
        *list.get(1usize).or_panic() != 20 ||
        *list.get(2usize).or_panic() != 30 {
        return 43
    }
    {
        var items = list.extract_if(fn(mut value: i32): bool {
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
    if list.len() != 2usize || *list.get(0usize).or_panic() != 10 ||
        *list.get(1usize).or_panic() != 30 {
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
        var items = filtered.extract_if(core.iter.range_full(), fn(mut value: i32): bool {
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

    var map = hash_map.new<i32, i32>()
    map.insert(1, 10)
    map.insert(2, 20)
    if exact_len(read map.iter()) != 2usize ||
        exact_len(read map.keys()) != 2usize ||
        exact_len(read map.values()) != 2usize {
        return 68
    }
    {
        var iter = map.iter_mut()
        if exact_len(read iter) != 2usize { return 69 }
        let _ = iter.next()
        if exact_len(read iter) != 1usize { return 70 }
    }
    {
        var drain = map.drain()
        if exact_len(read drain) != 2usize { return 71 }
        let _ = drain.next_back()
        if exact_len(read drain) != 1usize { return 72 }
    }
    var owned_map = hash_map.new<i32, i32>()
    owned_map.insert(1, 10)
    owned_map.insert(2, 20)
    if exact_len(read owned_map.into_iter()) != 2usize { return 73 }
    var keys_map = hash_map.new<i32, i32>()
    keys_map.insert(1, 10)
    keys_map.insert(2, 20)
    if exact_len(read keys_map.into_keys()) != 2usize { return 74 }
    var values_map = hash_map.new<i32, i32>()
    values_map.insert(1, 10)
    values_map.insert(2, 20)
    if exact_len(read values_map.into_values()) != 2usize { return 75 }

    var sorted = btree.new<i32, i32>()
    sorted.insert(1, 10)
    sorted.insert(2, 20)
    if exact_len(read sorted.iter()) != 2usize ||
        exact_len(read sorted.keys()) != 2usize ||
        exact_len(read sorted.values()) != 2usize {
        return 76
    }
    {
        var iter = sorted.iter_mut()
        if exact_len(read iter) != 2usize { return 77 }
        let _ = iter.next_back()
        if exact_len(read iter) != 1usize { return 78 }
    }
    {
        var iter = sorted.values_mut()
        if exact_len(read iter) != 2usize { return 79 }
        let _ = iter.next()
        if exact_len(read iter) != 1usize { return 80 }
    }
    var sorted_owned = btree.new<i32, i32>()
    sorted_owned.insert(1, 10)
    sorted_owned.insert(2, 20)
    if exact_len(read sorted_owned.into_iter()) != 2usize { return 81 }
    var sorted_keys = btree.new<i32, i32>()
    sorted_keys.insert(1, 10)
    sorted_keys.insert(2, 20)
    if exact_len(read sorted_keys.into_keys()) != 2usize { return 82 }
    var sorted_values = btree.new<i32, i32>()
    sorted_values.insert(1, 10)
    sorted_values.insert(2, 20)
    if exact_len(read sorted_values.into_values()) != 2usize { return 83 }
    var double_ended_map = btree.new<i32, i32>()
    double_ended_map.insert(1, 10)
    double_ended_map.insert(2, 20)
    double_ended_map.insert(3, 30)
    {
        var iter = double_ended_map.into_iter()
        match take iter.next_back() {
            present(entry) => { if entry.key != 3 || entry.value != 30 { return 85 } },
            none => { return 86 }
        }
        match take iter.next() {
            present(entry) => { if entry.key != 1 || entry.value != 10 { return 87 } },
            none => { return 88 }
        }
        match take iter.next_back() {
            present(entry) => { if entry.key != 2 || entry.value != 20 { return 89 } },
            none => { return 90 }
        }
        if iter.next().is_present() || iter.next_back().is_present() ||
            exact_len(read iter) != 0usize {
            return 91
        }
    }

    let default_hash_iter: hash_map.MapIntoIter<i32, i32> =
        default_value<hash_map.MapIntoIter<i32, i32>>()
    let default_full_range: core.iter.RangeFull = default_value<core.iter.RangeFull>()
    let default_repeat_n: core.iter.RepeatN<i32> = default_value<core.iter.RepeatN<i32>>()
    let default_hash_keys: hash_map.IntoKeys<i32, i32, alloc.alloc.Global> =
        default_value<hash_map.IntoKeys<i32, i32, alloc.alloc.Global>>()
    let default_hash_values: hash_map.IntoValues<i32, i32, alloc.alloc.Global> =
        default_value<hash_map.IntoValues<i32, i32, alloc.alloc.Global>>()
    let default_hash_set: hash_map.SetIntoIter<i32> =
        default_value<hash_map.SetIntoIter<i32>>()
    let default_sorted_iter: btree.MapIntoIter<i32, i32, alloc.alloc.Global> =
        default_value<btree.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    let default_sorted_keys: btree.IntoKeys<i32, i32, alloc.alloc.Global> =
        default_value<btree.IntoKeys<i32, i32, alloc.alloc.Global>>()
    let default_sorted_values: btree.IntoValues<i32, i32, alloc.alloc.Global> =
        default_value<btree.IntoValues<i32, i32, alloc.alloc.Global>>()
    let default_sorted_set: btree.SetIntoIter<i32, alloc.alloc.Global> =
        default_value<btree.SetIntoIter<i32, alloc.alloc.Global>>()
    let default_deque_iter: vec_deque.DequeIntoIter<i32> =
        default_value<vec_deque.DequeIntoIter<i32>>()
    if default_hash_iter.size_hint() != (0usize, present(0usize)) ||
        default_repeat_n.size_hint() != (0usize, present(0usize)) ||
        default_hash_keys.size_hint() != (0usize, present(0usize)) ||
        default_hash_values.size_hint() != (0usize, present(0usize)) ||
        default_hash_set.size_hint() != (0usize, present(0usize)) ||
        default_sorted_iter.size_hint() != (0usize, present(0usize)) ||
        default_sorted_keys.size_hint() != (0usize, present(0usize)) ||
        default_sorted_values.size_hint() != (0usize, present(0usize)) ||
        default_sorted_set.size_hint() != (0usize, present(0usize)) ||
        default_deque_iter.size_hint() != (0usize, present(0usize)) {
        return 84
    }
    let _ = default_full_range
    require_fused(take default_hash_iter)
    require_fused(take default_hash_keys)
    require_fused(take default_hash_values)
    require_fused(take default_hash_set)
    require_fused(take default_sorted_iter)
    require_fused(take default_sorted_keys)
    require_fused(take default_sorted_values)
    require_fused(take default_sorted_set)
    require_fused(take default_deque_iter)
    var debug_sorted = btree.new<i32, i32>()
    debug_sorted.insert(1, 10)
    let _ = require_debug(read debug_sorted.into_iter())
    var debug_hash_map = hash_map.new<i32, i32>()
    debug_hash_map.insert(1, 10)
    let _ = require_debug(read debug_hash_map.into_iter())
    var debug_keys = hash_map.new<i32, i32>()
    debug_keys.insert(1, 10)
    let _ = require_debug(read debug_keys.into_keys())
    var debug_values = hash_map.new<i32, i32>()
    debug_values.insert(1, 10)
    let _ = require_debug(read debug_values.into_values())
    var debug_set = hash_map.set_new<i32>()
    debug_set.insert(1)
    let _ = require_debug(read debug_set.into_iter())
    var debug_sorted_set = btree.set_new<i32>()
    debug_sorted_set.insert(1)
    let _ = require_debug(read debug_sorted_set.into_iter())
    var debug_deque = vec_deque.new<i32>()
    debug_deque.push_back(1)
    let _ = require_debug(read debug_deque.into_iter())
    0
}
