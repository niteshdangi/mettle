// expect-error: ownership 3:71 moved
type Value { value: i32 }
fn main() { let first = Value(42); let second = loop { break first }; first.value }
