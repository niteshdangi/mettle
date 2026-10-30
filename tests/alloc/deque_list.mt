fn main(): i32 {
    var d = alloc::vec_deque::new::<i32>()
    var i = 0
    while i < 50 { d.push_back(i + 0); d.push_front(0 - i - 1); i += 1 }
    if d.len() != 100usize { return 1 }
    match d.front() { present(x) => { if *x != -50 { return 2 } }, none => { return 3 } }
    match d.pop_back() { present(x) => { if x != 49 { return 4 } }, none => { return 5 } }
    if d[0usize] != -50 { return 6 }
    var l = alloc::linked_list::new::<i32>()
    i = 0
    while i < 20 { l.push_back(i + 0); l.push_front(i + 0); i += 1 }
    if l.len() != 40usize { return 7 }
    match l.pop_front() { present(x) => { if x != 19 { return 8 } }, none => { return 9 } }
    match l.pop_back() { present(x) => { if x != 19 { return 10 } }, none => { return 11 } }
    match l.get(2usize) { present(x) => { if *x != 16 { return 12 } }, none => { return 13 } }
    0
}
