// expect-error: ownership 3:39 cannot move out of a borrowed place
type Value { value: i32 }
fn bad(take a: Value, take b: Value = a) { a.value + b.value }
fn main() { bad(Value(20),Value(22)) }
