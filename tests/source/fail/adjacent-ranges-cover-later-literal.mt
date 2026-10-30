// expect-error-count: 1
// expect-error: type 3:66 unreachable match arm
fn f(x: i8): i32 { match x { -128..0 => 1, 0 => 2, 1..=127 => 3, -7 => 4 } }
fn main() { 0 }
