// expect-error: type 5:19 an f-string can only be passed to a 'format' parameter
// expect-error-count: 1
fn main(): i32 {
    let a = 1
    let text = f"{a}"
    0
}
