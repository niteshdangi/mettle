
fn value() {
    if false { return false }
    while false { return () }
    42
}
fn truth() {
    let _ = false && { return 123 }
    true
}
fn main() { if value() == 42 && truth() { 0 } else { 1 } }
