// expect-error: parse 2:56 an inclusive range requires an upper bound
fn main(): i32 { let a = [1, 2, 3]; let y = read a[1..=]; 0 }
