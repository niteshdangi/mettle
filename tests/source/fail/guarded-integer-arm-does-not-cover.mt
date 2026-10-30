// expect-error-count: 1
// expect-error: type 3:20 non-exhaustive match
fn f(x: u8): i32 { match x { 0..=255 if x > 3 => 1, 7 => 2 } }
fn main() { 0 }
