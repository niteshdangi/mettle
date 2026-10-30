// expect-error: ownership 4:50 moved
type Point { value: i32; take fn consume() {} }
alias Same = Point
fn main() { let p = Point(42); Same::consume(p); p.value }
