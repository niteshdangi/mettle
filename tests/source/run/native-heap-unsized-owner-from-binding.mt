fn main(): i32 {
    let a: heap [i32; 3] = heap [10, 20, 30]
    let b: heap [i32] = a
    if b.get().len() != 3usize { return 1 }
    0
}
