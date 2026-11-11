fn bound(mut calls: i32): usize {
    calls += 1
    0usize
}

fn main(): i32 {
    let values = [42]
    var calls = 0
    let selected: read [i32] = read values[bound(calls)..=bound(calls)]
    if calls == 2 && selected.len() == 1usize && selected[0] == 42 {
        0
    } else { 1 }
}
