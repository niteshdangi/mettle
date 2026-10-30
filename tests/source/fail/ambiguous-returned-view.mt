// expect-error: type 2:1 ambiguous borrowed result
fn bad(first: read i32, second: read i32): read i32 { read first }
fn main() { 0 }
