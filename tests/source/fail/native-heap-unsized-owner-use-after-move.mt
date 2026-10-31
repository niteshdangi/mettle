// expect-error: ownership 5:5 moved
fn main(): i32 {
    let first: heap [i32] = heap [1, 2, 3]
    let second = first
    first.get().len()
    0
}
