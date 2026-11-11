// expect-error: type 6:20 expected u32, found bool
copy type Value { field: u32 }
extend Value {
    const VALUE: Value = if true {
        Value(1u32)
    } else { Value(true) }
}
fn main(): i32 { 0 }
