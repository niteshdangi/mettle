// expect-error-count: 1
// expect-error: ownership 4:16 write through a read parameter
type C { value: i32 }
fn bad(c: C) { c.value = 2 }
fn main() { 0 }
