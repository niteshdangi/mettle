// expect-error: parse 2:22 comparisons do not chain
fn main() { if 1 < 2 < 3 { 0 } else { 1 } }
