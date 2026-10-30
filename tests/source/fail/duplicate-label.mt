// expect-error-count: 1
// expect-error: type 4:24 duplicate argument
fn f(x: i32, y: i32) { x }
fn main() { f(x: 1, x: 2) }
