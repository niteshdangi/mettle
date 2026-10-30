// expect-error: name 3:1 duplicate type
type Point {}
alias Point = i32
fn main() { 0 }
