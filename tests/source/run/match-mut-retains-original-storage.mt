
copy enum Value { Number(i32); Empty }
fn main() {
    var value = Value::Number(40)
    match mut value { Value::Number(number) => { number += 2 }, Value::Empty => {} }
    match value { Value::Number(number) => if number == 42 { 0 } else { 1 }, Value::Empty => 1 }
}
