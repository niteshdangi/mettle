// expect-exit: trap
fn main() {
    let values = [1, 2, 3]
    let _windows = values.windows(0usize)
}
