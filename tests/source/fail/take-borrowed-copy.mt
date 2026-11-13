// expect-error: ownership 2:40 cannot move out of a viewed place
fn bad(read value: i32) { let x = take value }
fn main() { 0 }
