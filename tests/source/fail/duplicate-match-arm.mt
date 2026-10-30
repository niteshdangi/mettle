// expect-error: type 2:37 unreachable match arm
fn main() { match true { true => 0, true => 1, false => 2 } }
