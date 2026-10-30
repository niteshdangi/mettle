// expect-error: name 2:17 unresolved value 'b'
fn bad(a: i32 = b, b: i32 = 42) { a + b }
fn main() { bad(0,0) }
