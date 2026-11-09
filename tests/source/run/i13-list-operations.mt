import alloc.vec
import alloc.vec.List
import alloc.alloc.{ Allocator, Global, Layout, AllocError }
import alloc.binary_heap
import alloc.string
import alloc.vec_deque
import core.borrow.AsRef
import core.convert.From
import core.cmp.PartialEq
import core.default.Default
import core.iter.ExtendItems
import core.ptr.NonNull
import std.panic.CatchResult

type Counted {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

copy type Forwarding { unused: u8 }

extend Forwarding implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.allocate(layout)
    }
    mut fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        var global = Global()
        global.deallocate(pointer, layout)
    }
    mut fn grow(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.grow(pointer, old, new_size)
    }
    mut fn shrink(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.shrink(pointer, old, new_size)
    }
}

fn filled(n: i32): List<i32> {
    var v = vec.with_capacity<i32>(0usize)
    var i = 0
    while i < n { v.push(i + 0); i += 1 }
    v
}

fn extend_borrowed<region r>(
    mut target: List<i32>,
    read source: List<i32> from r
) {
    target.extend(source.iter())
}

fn panics(f: fn(): Unit): bool {
    match take std.panic.catch_panic(f) {
        CatchResult.Panicked(_) => true,
        CatchResult.Returned(_) => false
    }
}

fn main(): i32 {
    var v = vec.with_capacity<i32>(10usize)
    if v.capacity() < 10usize || !v.is_empty() { return 1 }
    v.reserve(20usize)
    if v.capacity() < 20usize { return 2 }
    v.shrink_to(5usize)
    if v.capacity() < 5usize || v.capacity() >= 20usize { return 3 }
    v.shrink_to_fit()
    if v.capacity() != 0usize { return 4 }
    v.reserve_exact(3usize)
    if v.capacity() < 3usize { return 5 }
    match capture v.try_reserve(4usize) { success(_) => {}, failure(_) => { return 6 } }
    match capture v.try_reserve_exact(4usize) { success(_) => {}, failure(_) => { return 7 } }
    match capture v.try_reserve(0xffffffffffffffffusize) { success(_) => { return 8 }, failure(_) => {} }

    var w = filled(5)
    w.insert(2usize, 99)
    if w.len() != 6usize || w[2usize] != 99 || w[3usize] != 2 { return 10 }
    if w.remove(2usize) != 99 || w.len() != 5usize { return 11 }
    if w.swap_remove(0usize) != 0 || w[0usize] != 4 { return 12 }
    w.swap(0usize, 1usize)
    if w[0usize] != 1 || w[1usize] != 4 { return 13 }
    w.reverse()
    if w[0usize] != 3 || w[3usize] != 1 { return 14 }
    w.truncate(10usize)
    if w.len() != 4usize { return 15 }
    w.truncate(2usize)
    if w.len() != 2usize { return 16 }
    w.clear()
    if !w.is_empty() || w.pop().is_present() { return 17 }
    w.push(5)
    if w.pop().unwrap() != 5 { return 18 }

    var a = filled(5)
    {
        var d = a.drain(1usize..3usize)
        if d.size_hint().0 != 2usize { return 20 }
        if d.next().unwrap() != 1 || d.next_back().unwrap() != 2 { return 21 }
    }
    if a.len() != 3usize || a[1usize] != 3 { return 22 }
    let a_len = a.len()
    {
        var d = a.drain(0usize..a_len)
        let _first = d.next()
    }
    if !a.is_empty() { return 23 }

    var b = filled(6)
    var tail = b.split_off(4usize)
    if b.len() != 4usize || tail.len() != 2usize || tail[0usize] != 4 { return 24 }
    b.append(tail)
    if tail.len() != 0usize || b.len() != 6usize || b[5usize] != 5 { return 25 }
    let empty = b.split_off(6usize)
    if !empty.is_empty() { return 26 }

    var r = vec.new<i32>()
    r.resize(3usize, 7)
    r.resize_with(5usize, fn(): i32 { 8 })
    if r.len() != 5usize || r[2usize] != 7 || r[4usize] != 8 { return 27 }
    r.resize(1usize, 0)
    if r.len() != 1usize { return 28 }
    let src = [1, 2, 3]
    r.extend_from_slice(read src)
    r.extend_from_within(1usize..3usize)
    if r.len() != 6usize || r[4usize] != 1 || r[5usize] != 2 { return 29 }

    var dd = vec.new<i32>()
    for x in [1, 1, 2, 2, 2, 3, 1] { dd.push(x) }
    dd.dedup()
    if dd.len() != 4usize || dd[3usize] != 1 { return 30 }
    var dk = filled(6)
    dk.dedup_by_key(fn(mut x: i32): i32 { x / 2 })
    if dk.len() != 3usize || dk[1usize] != 2 { return 31 }
    var db = filled(6)
    db.dedup_by(fn(mut x: i32, mut y: i32): bool { x - y == 1 })
    if db.len() != 3usize { return 32 }

    var s = vec.new<i32>()
    for x in [3, 1, 2] { s.push(x) }
    s.sort()
    if s[0usize] != 1 || s[2usize] != 3 { return 33 }
    s.sort_by(fn(read p: i32, read q: i32): core.cmp.Ordering { q.cmp(p) })
    if s[0usize] != 3 { return 34 }
    s.sort_by_key(fn(read p: i32): i32 { p })
    if s[0usize] != 1 { return 35 }
    s.sort_by_cached_key(fn(read p: i32): i32 { -p })
    if s[0usize] != 3 { return 36 }

    var p = vec.new<i32>()
    p.push(1)
    p.push(2)
    if p.pop_if(fn(mut x: i32): bool { x == 1 }).is_present() { return 37 }
    if p.pop_if(fn(mut x: i32): bool { x == 2 }).unwrap() != 2 { return 38 }
    *p.get_mut(0usize).unwrap() = 9
    if *p.get(0usize).unwrap() != 9 || p.get(1usize).is_present() { return 39 }

    var e = filled(6)
    var gone = vec.new<i32>()
    {
        var it = e.extract_if(0usize..6usize, fn(mut x: i32): bool { x % 2 == 0 })
        while true { match take it.next() { present(x) => { gone.push(x) }, none => { break } } }
    }
    if e.len() != 3usize || gone.len() != 3usize || e[0usize] != 1 { return 40 }

    var sp = filled(5)
    var repl = vec.new<i32>()
    repl.push(10)
    repl.push(20)
    repl.push(30)
    {
        var it = sp.splice(1usize..3usize, repl)
        if it.next().unwrap() != 1 { return 41 }
    }
    if sp.len() != 6usize || sp[1usize] != 10 || sp[3usize] != 30 || sp[4usize] != 3 { return 42 }

    var sc = vec.with_capacity<i32>(4usize)
    sc.push(1)
    if sc.spare_capacity_mut().len() < 3usize { return 43 }
    let boxed = filled(3).into_boxed_slice()
    if boxed.get().len() != 3usize { return 44 }
    let leaked = filled(2).leak()
    if leaked.len() != 2usize { return 45 }

    var drops = 0usize
    {
        var c = vec.new<Counted>()
        var i = 0
        while i < 6 { c.push(Counted(i + 0, core.ptr.from_mut(drops))); i += 1 }
        c.truncate(5usize)
        if drops != 1usize { return 50 }
        let _removed = c.remove(0usize)
    }
    if drops != 6usize { return 51 }

    let from_array = List<i32>.(From<[i32; 3]>).from([1, 2, 3])
    let view: read [i32] = List<i32>.(AsRef<[i32]>).as_ref(read from_array)
    if from_array.capacity() != 3usize || view.len() != 3usize || view[2usize] != 3 { return 52 }
    let same = [1, 2, 3]
    let other = [1, 2, 4]
    if !(from_array == same) || from_array == other { return 53 }
    let boxed_back = List<i32>.(From<alloc.boxed.Box<[i32]>>).from(from_array.into_boxed_slice())
    if boxed_back.len() != 3usize || boxed_back[1usize] != 2 { return 54 }
    // Accessors, iteration and slice-owned conversions.
    var acc = filled(4)
    if !acc.contains(3) || acc.contains(4) { return 70 }
    if acc.as_slice().len() != 4usize || acc.as_mut_slice().len() != 4usize { return 71 }
    var total = 0
    for x in read acc { total += *x }
    for x in mut acc { *x += 10 }
    if total != 6 || acc[0usize] != 10 || acc[3usize] != 13 { return 72 }
    if unsafe { *acc.as_ptr().add(1usize) } != 11 { return 73 }
    unsafe { *acc.as_mut_ptr().add(1usize) = 5 }
    if acc[1usize] != 5 { return 74 }
    let slice_prefix = [10, 5]
    if !acc.starts_with(read slice_prefix) { return 88 }
    unsafe { acc.set_len(2usize) }
    if acc.len() != 2usize || acc[1usize] != 5 { return 75 }
    let pair = [1, 2]
    let rep = pair.repeat(2usize)
    let duplicate = pair.to_vec()
    if rep.len() != 4usize || rep[3usize] != 2 || duplicate.len() != 2usize { return 76 }

    var deque = vec_deque.with_capacity<i32>(4usize)
    deque.push_back(2)
    deque.push_back(3)
    deque.push_front(1)
    deque.push_front(0)
    let _front = deque.pop_front()
    deque.push_back(9)
    let from_deque = List<i32>.(From<vec_deque.Deque<i32>>).from(deque)
    if from_deque.len() != 4usize || from_deque[0usize] != 1 || from_deque[3usize] != 9 { return 77 }
    var heap_source = binary_heap.new<i32>()
    heap_source.push(5)
    heap_source.push(8)
    if List<i32>.(From<binary_heap.BinaryHeap<i32>>).from(heap_source).len() != 2usize { return 78 }
    let from_string = List<u8>.(From<string.String>).from(string.from_text("hi"))
    if from_string.len() != 2usize || from_string[0usize] != 104u8 { return 79 }
    let from_text = List<u8>.(From<read core.text.Text>).from("abc")
    if from_text.len() != 3usize || from_text[2usize] != 99u8 { return 80 }
    let numbers = [4, 5, 6]
    let numbers_view: read [i32] = read numbers
    let from_view = List<i32>.(From<read [i32]>).from(numbers_view)
    if from_view.len() != 3usize || from_view[1usize] != 5 { return 81 }
    var extended_from_view = vec.new<i32>()
    extend_borrowed(mut extended_from_view, read from_view)
    if extended_from_view.len() != 3usize || extended_from_view[2usize] != 6 {
        return 89
    }
    var numbers_copy = [7, 8]
    let from_mut_array = List<i32>.(From<mut [i32; 2]>).from(mut numbers_copy)
    if from_mut_array.len() != 2usize || from_mut_array[0usize] != 7 { return 82 }

    let default_list = List<i32>.(Default).default()
    if !default_list.is_empty() || default_list.capacity() != 0usize { return 87 }

    var forwarded = vec.new_in<i32, Forwarding>(Forwarding(0u8))
    forwarded.push(1)
    forwarded.push(2)
    let plain = filled(3)
    var plain_two = vec.new<i32>()
    plain_two.push(1)
    plain_two.push(2)
    if !(forwarded == plain_two) || forwarded == plain { return 83 }
    if !(forwarded <= plain_two) || forwarded < plain_two { return 84 }

    let (raw, raw_len, raw_cap) = filled(3).into_parts()
    let pointer = raw.as_ptr()
    match NonNull<i32>.new(pointer) {
        present(rewrapped) => {
            if rewrapped.as_ptr() != pointer { return 90 }
        },
        none => { return 91 }
    }
    let adopted = unsafe { List<i32>.from_parts(raw, raw_len, raw_cap) }
    if adopted.len() != 3usize || adopted[2usize] != 2 { return 85 }
    if NonNull<i32>.new(core.ptr.null_mut<i32>()).is_present() { return 86 }
    var allocator_parts = vec.new_in<i32, Forwarding>(Forwarding(0u8))
    allocator_parts.push(42)
    let (allocator_pointer, allocator_len, allocator_cap, allocator) =
        allocator_parts.into_parts_with_alloc()
    let restored = unsafe {
        List<i32, Forwarding>.from_parts_in(
            allocator_pointer,
            allocator_len,
            allocator_cap,
            allocator
        )
    }
    if restored.len() != 1usize || restored[0usize] != 42 { return 92 }

    if !panics(fn(): Unit { var x = filled(2); x.insert(3usize, 0) }) { return 60 }
    if !panics(fn(): Unit { var x = filled(2); let _y = x.remove(2usize) }) { return 61 }
    if !panics(fn(): Unit { var x = filled(2); let _y = x.swap_remove(2usize) }) { return 62 }
    if !panics(fn(): Unit { var x = filled(2); x.swap(0usize, 2usize) }) { return 63 }
    if !panics(fn(): Unit { var x = filled(2); let _y = x.split_off(3usize) }) { return 64 }
    if !panics(fn(): Unit { var x = filled(2); let _y = x.drain(1usize..3usize) }) { return 65 }
    0
}
