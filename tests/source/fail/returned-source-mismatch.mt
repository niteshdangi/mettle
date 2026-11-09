// expect-error: ownership 2:66 declared input sources
fn bad(read first: i32, read second: i32): read i32 from first { read second }
fn main() { 0 }
