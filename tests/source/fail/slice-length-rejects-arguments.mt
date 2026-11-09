// expect-error: type 2:30 slice len requires no arguments
fn f(read s: [i32]): usize { s.len(1) }
fn main() { 0 }
