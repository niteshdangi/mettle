// expect-error-count: 1
// expect-error: type 4:36 pattern payload count
copy enum Value { Held(i32) }
fn main() { match Value.Held(42) { Value.Held(first,second) => first } }
