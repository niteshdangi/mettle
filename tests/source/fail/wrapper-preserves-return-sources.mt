// expect-error: ownership 4:57 declared input sources

fn first(read a: i32, read b: i32): read i32 from (a, b) { read a }
fn wrapper(read a: i32, read b: i32): read i32 from a { first(a, b) }
fn main() { 0 }
