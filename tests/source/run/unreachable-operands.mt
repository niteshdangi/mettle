
fn combine(x: i32, y: i32): i32 { x + y }
fn condition() {
    while { return 42 } { return false }
}
fn arguments() {
    combine({ return 42 }, { return false })
}
fn main() { if condition() == 42 && arguments() == 42 { 0 } else { 1 } }
