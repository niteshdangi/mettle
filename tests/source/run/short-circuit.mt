
fn bad(): bool {
    let _ = 1 / 0
    true
}
fn main() {
    if false && bad() { return 1 }
    if true || bad() { 0 } else { 2 }
}
