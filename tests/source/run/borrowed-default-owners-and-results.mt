
type Value { value: i32 }
fn answer(a: read Value, b: read Value = a) { a.value + b.value }
fn temporary(a: read Value = Value(42)) { a.value }
fn main() {
    let value = Value(21)
    if answer(value) == 42 && temporary() == 42 { 0 } else { 1 }
}
