// expect-error: type 2:36 unreachable match arm
fn main() { match 1 { 0..=42 => 0, 1..=4 => 1, _ => 2 } }
