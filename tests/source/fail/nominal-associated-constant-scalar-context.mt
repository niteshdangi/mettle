// expect-error: constant 5:18 required integer expression needs a scalar associated constant
copy type Value { field: u32 }
extend Value { const VALUE: Value = Value(1u32) }
fn main(): i32 {
    let row: [u8;Value.VALUE] = [1u8]
    0
}
