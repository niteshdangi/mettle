
copy enum Value { First(i32); Second(i32); Empty }
fn extract(value: Value) {
    match value {
        Value::First(number) | Value::Second(number) => number,
        Value::Empty => 0
    }
}
fn main() {
    if extract(Value::First(42)) == 42 && extract(Value::Second(42)) == 42 { 0 } else { 1 }
}
