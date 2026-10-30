// expect-error-count: 1
// expect-error: type 3:22 non-exhaustive match
fn f(x: char): i32 { match x { '\u{0}'..='\u{d7ff}' => 1, '\u{e000}'..'\u{10ffff}' => 2 } }
fn main() { 0 }
