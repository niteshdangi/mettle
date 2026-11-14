// expect-error: feature 6:29 generic nominal associated constant requires a concrete owner type
copy type Value<T> { field: i32 }
extend<T> Value<T> {
    const EMPTY: Value<T> = Value<T>(0i32)
}
fn generic<T>(): Value<T> { Value<T>.EMPTY }
fn main(): i32 { 0 }
