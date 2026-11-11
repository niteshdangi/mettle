// expect-error: feature 4:20 required projection of a non-Copy associated value is not implemented
type Value { pub field: u32; drop {} }
extend Value { const VALUE: Value = Value(1u32) }
const VALUE: u32 = Value.VALUE.field
fn main(): i32 { 0 }
