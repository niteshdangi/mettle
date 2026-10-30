// expect-error: type 2:13 non-exhaustive match
fn main() { match true { true if true => 0, false => 1 } }
