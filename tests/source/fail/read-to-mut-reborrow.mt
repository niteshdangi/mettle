// expect-error: ownership 4:23 mutable place
type C { value: i32 }
fn change(c: mut C) {}
fn bad(c: C) { change(c) }
fn main() { 0 }
