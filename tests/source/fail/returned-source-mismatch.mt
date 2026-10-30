// expect-error: ownership 2:66 declared input sources
fn bad(first: read i32, second: read i32): read i32 from first { read second }
fn main() { 0 }
