// expect-error: type 2:1 ambiguous borrowed result
fn bad(read first: i32, read second: i32): read i32 { read first }
fn main() { 0 }
