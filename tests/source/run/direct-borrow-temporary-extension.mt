
type Counter { value: i32 }
fn main() {
    let view = read Counter(42)
    if view.value == 42 { 0 } else { 1 }
}
