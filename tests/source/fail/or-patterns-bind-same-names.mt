// expect-error: type 3:37 identical names
copy enum Value { First(i32); Second(i32) }
fn main() { match Value.First(42) { Value.First(a) | Value.Second(b) => a } }
