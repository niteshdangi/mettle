// expect-error-count: 1
// expect-error: type 4:18 unknown or excess argument
fn f(x: i32) { x }
fn main() { f(y: 1) }
