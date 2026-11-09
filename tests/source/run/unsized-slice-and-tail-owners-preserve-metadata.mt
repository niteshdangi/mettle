// flags: --sanitize address
type Tail<T: unsized> { tag: i32; data: T }
fn sum(read xs: [i32]): i32 {
    var t = 0
    for x in xs { t = t + x }
    t
}
fn main(): i32 {
    let a: heap [i32] = heap [1, 2, 3]
    if sum(read a.get()) != 6 { return 1 }
    let s: shared [i32] = shared [4, 5]
    if sum(read s.get()) != 9 { return 2 }
    let l: local shared [i32] = local shared [6]
    if sum(read l.get()) != 6 { return 3 }
    let fixed = Tail(7, [1, 2])
    let v: read Tail<[i32]> = read fixed
    if v.tag != 7 || sum(read v.data) != 3 { return 4 }
    let h: heap Tail<[i32]> = heap Tail(8, [3, 4, 5])
    if h.get().tag != 8 || sum(read h.get().data) != 12 { return 5 }
    let sh: shared Tail<[i32]> = shared Tail(9, [1])
    if sh.get().data.len() != 1 { return 6 }
    0
}
