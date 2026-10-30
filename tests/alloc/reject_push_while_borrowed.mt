// expect-error: ownership
fn main(): i32 {
    var v = alloc.vec.new<i32>()
    v.push(1)
    let first = v.get(0usize)
    v.push(2)
    match first { present(x) => { *x }, none => { 0 } }
}
