// expect-error: type 3:13 non-exhaustive match
copy enum Value { First; Second }
fn main() { match Value::First { Value::First => 0 } }
