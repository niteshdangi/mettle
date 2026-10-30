fn main(): i32 {
    var m = alloc.btree.new<i32, i32>()
    var i = 0
    while i < 200 { let k = (i * 37) % 200; let r = m.insert(k + 0, k * 2); i += 1 }
    if m.len() != 200usize { return 1 }
    var j = 0usize
    while j < 200usize { if m.as_entries()[j].key != (j as i32) { return 2 }; j += 1usize }
    let rg = m.range(10 + 0, 20 + 0)
    if rg.1 - rg.0 != 10usize { return 3 }
    match m.remove(5 + 0) { present(v) => { if v != 10 { return 4 } }, none => { return 5 } }
    if m.contains_key(5 + 0) { return 6 }
    var h = alloc.binary_heap.new<i32>()
    i = 0
    while i < 100 { h.push((i * 73) % 101); i += 1 }
    var prev = 1000
    while true {
        match h.pop() { present(x) => { if x > prev { return 7 }; prev = x }, none => { break } }
    }
    0
}
