// expect-error: constant 4:5 cycle in associated constant definition
type Value { field: u32 }
extend Value {
    const FIRST: Value = Self.SECOND
    const SECOND: Value = Self.FIRST
}
fn main(): i32 { 0 }
