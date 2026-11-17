// expect-error: name 4:17 duplicate pattern binding
fn main(): i32 {
    let values = [1, 2, 3]
    let [value, value @ ..] = values
    0
}
