fn main(): i32 {
    var m = alloc.btree.new<i32, i32>()
    var i = 0
    while i < 200 { let k = (i * 37) % 200; let r = m.insert(k + 0, k * 2); i += 1 }
    if m.len() != 200usize { return 1 }
    var j = 0
    for e in read m { if e.key != j { return 2 }; j += 1 }
    if j != 200 { return 2 }
    var rg = m.range(core.iter.range(10 + 0, 20 + 0))
    var span = 0
    while true { match rg.next() { present(e) => { span += 1 }, none => { break } } }
    if span != 10 { return 3 }
    match m.remove(5 + 0) { present(v) => { if v != 10 { return 4 } }, none => { return 5 } }
    if m.contains_key(5 + 0) { return 6 }
    var h = alloc.binary_heap.new<i32>()
    h.reserve(100usize)
    if h.capacity() < 100usize { return 8 }
    i = 0
    while i < 100 { h.push((i * 73) % 101); i += 1 }
    var prev = 1000
    while true {
        match h.pop() { present(x) => { if x > prev { return 7 }; prev = x }, none => { break } }
    }
    var sorted = alloc.binary_heap.new<i32>()
    sorted.push(4)
    sorted.push(1)
    sorted.push(3)
    sorted.push(2)
    let ordered = sorted.into_sorted_vec()
    var index = 0usize
    while index < ordered.len() {
        if ordered[index] != (index as i32) + 1 { return 9 }
        index += 1usize
    }
    0
}
