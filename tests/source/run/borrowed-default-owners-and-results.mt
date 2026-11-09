
type Value { value: i32 }
fn answer(read a: Value, read b: Value = a) { a.value + b.value }
fn temporary(read a: Value = Value(42)) { a.value }
fn main() {
    let value = Value(21)
    if answer(value) == 42 && temporary() == 42 { 0 } else { 1 }
}
