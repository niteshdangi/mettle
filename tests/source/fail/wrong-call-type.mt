// expect-error: type 3:15 expected i32, found bool
fn f(x: i32) { x }
fn main() { f(true) }
