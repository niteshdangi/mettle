// expect-error: type 2:15 expected i32, found bool
fn f(b: bool) { if b { return 1 }; false }
fn main() { 0 }
