// expect-exit: 101
fn main(): i32 {
    let values = [1, 2, 3]
    let _windows = values.windows(0usize)
    0
}
