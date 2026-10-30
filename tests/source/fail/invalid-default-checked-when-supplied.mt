// expect-error: type 2:8 expected i32, found bool
fn bad(value: i32 = true) { value }
fn main() { bad(42) }
