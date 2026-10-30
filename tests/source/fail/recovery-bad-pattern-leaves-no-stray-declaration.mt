// expect-error-count: 1
// expect-error: parse 3:43 expected an integer literal after '-' in a pattern
fn f(x: i32): i32 { let y = 1; match x { -y => 1, _ => 0 } }
fn main(): i32 { f(1) }
