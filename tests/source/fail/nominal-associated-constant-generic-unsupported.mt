// expect-error: feature 4:5 generic nominal associated constants are not implemented
copy type Value<T: Copy> { field: T }
extend<T: Copy> Value<T> {
    const EMPTY: Value<T> = Value<T>(0)
}
fn main(): i32 { 0 }
