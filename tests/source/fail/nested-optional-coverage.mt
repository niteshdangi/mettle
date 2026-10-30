// expect-error: type 2:47 non-exhaustive match
fn main() { let value: i32?? = present(none); match value { none => 0, present(present(_)) => 1 } }
