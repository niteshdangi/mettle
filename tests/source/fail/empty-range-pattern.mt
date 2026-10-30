// expect-error: type 2:23 empty or reversed
fn main() { match 1 { 2..2 => 0, _ => 1 } }
