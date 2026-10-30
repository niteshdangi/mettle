
module values {
    pub copy enum Choice { Empty; Value(i32) }
    pub copy type Counter {
        pub value: i32
        pub static fn make(value: i32 = 42): Self { Self(value) }
    }
}
import values::{Choice as Value, Counter}
fn main() {
    let item = Value::Value(Counter::make().value)
    match item { Value::Empty => 1, Value::Value(answer) => if answer == 42 { 0 } else { 1 } }
}
