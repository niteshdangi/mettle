// expect-error-count: 1
// expect-error: type 4:21 positional arguments must precede named arguments
fn f(x: i32, y: i32) { x }
fn main() { f(y: 1, 2) }
