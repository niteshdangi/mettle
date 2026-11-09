fn main(): i32 {
    var d = alloc.vec_deque.new<i32>()
    d.reserve(128usize)
    if d.capacity() < 128usize { return 14 }
    var i = 0
    while i < 50 { d.push_back(i + 0); d.push_front(0 - i - 1); i += 1 }
    if d.len() != 100usize { return 1 }
    match d.front() { present(x) => { if *x != -50 { return 2 } }, none => { return 3 } }
    match d.pop_back() { present(x) => { if x != 49 { return 4 } }, none => { return 5 } }
    if d[0usize] != -50 { return 6 }
    match take d.front_mut() { present(x) => { *x = -500 }, none => { return 21 } }
    match take d.back_mut() { present(x) => { *x = 500 }, none => { return 22 } }
    d.insert(50usize, 777)
    if d[49usize] != -1 || d[50usize] != 777 || d[51usize] != 0 { return 24 }
    if d.remove(50usize) != 777 || d[50usize] != 0 { return 25 }
    d.shrink_to_fit()
    if d.capacity() < d.len() || d[0usize] != -500 || d[d.len() - 1usize] != 500 {
        return 23
    }
    var l = alloc.linked_list.new<i32>()
    i = 0
    while i < 20 { l.push_back(i + 0); l.push_front(i + 0); i += 1 }
    if l.len() != 40usize { return 7 }
    match l.pop_front() { present(x) => { if x != 19 { return 8 } }, none => { return 9 } }
    match l.pop_back() { present(x) => { if x != 19 { return 10 } }, none => { return 11 } }
    match l.get(2usize) { present(x) => { if *x != 16 { return 12 } }, none => { return 13 } }
    match take l.get_mut(2usize) { present(x) => { *x = 160 }, none => { return 15 } }
    match take l.back_mut() { present(x) => { *x = 190 }, none => { return 16 } }
    match l.get(2usize) { present(x) => { if *x != 160 { return 17 } }, none => { return 18 } }
    match l.back() { present(x) => { if *x != 190 { return 19 } }, none => { return 20 } }
    var retained_calls = 0
    d.retain(fn(read value: i32): bool {
        retained_calls += 1
        value == 500
    })
    if retained_calls != 99 || d.len() != 1usize || d[0usize] != 500 {
        return 26
    }
    0
}
