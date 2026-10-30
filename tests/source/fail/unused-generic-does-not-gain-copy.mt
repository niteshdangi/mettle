// expect-error: ownership 2:20 cannot move out of a borrowed place
fn f<T>(x: T): T { x }
fn main() { 0 }
