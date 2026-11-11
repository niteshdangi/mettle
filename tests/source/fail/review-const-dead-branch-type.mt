// expect-error: type 2:42 expected i32, found bool
const VALUE: i32 = if true { 42 } else { false + 1 }
fn main(): i32 { 0 }
