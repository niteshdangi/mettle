// expect-error: name 5:30 duplicate pattern binding
copy enum Value { First(i32); Second(i32) }
fn main(): i32 {
    match (42, Value.First(1)) {
        (number, Value.First(number) | Value.Second(_)) => number
    }
}
