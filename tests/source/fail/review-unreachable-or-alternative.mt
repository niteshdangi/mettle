// expect-error: type 2:27 unreachable or-pattern alternative
fn main() { match 1 { 1 | 1 => 0, _ => 1 } }
