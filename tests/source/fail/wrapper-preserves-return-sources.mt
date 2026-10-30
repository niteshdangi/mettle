// expect-error: ownership 4:57 declared input sources

fn first(a: read i32, b: read i32): read i32 from (a, b) { read a }
fn wrapper(a: read i32, b: read i32): read i32 from a { first(a, b) }
fn main() { 0 }
