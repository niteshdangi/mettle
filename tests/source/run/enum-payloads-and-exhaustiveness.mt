
copy enum Number { Empty; Scalar(i32); Pair { first: i32; second: i32 } }
fn value(number: Number) {
    match number {
        Number::Empty => 0,
        Number::Scalar(value) => value,
        Number::Pair { second: b, first: a } => a + b
    }
}
fn main() {
    if value(Number::Pair(second: 22, first: 20)) == 42 &&
       value(Number::Scalar(42)) == 42 && value(Number::Empty) == 0 { 0 } else { 1 }
}
