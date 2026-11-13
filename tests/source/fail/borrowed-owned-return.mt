// expect-error: ownership 3:19 cannot move out of a viewed place
type C { value: i32 }
fn bad(c: C): C { c }
fn main() { 0 }
