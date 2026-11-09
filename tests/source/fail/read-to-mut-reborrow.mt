// expect-error: ownership 4:23 mutable place
type C { value: i32 }
fn change(mut c: C) {}
fn bad(c: C) { change(c) }
fn main() { 0 }
