// expect-error: type 7:13 expected Record<i32>, found Record<bool>
// expect-error-count: 1
type Record<T> { value: T }
fn accepts(value: Record<i32>) {}
fn main() {
    let value: Record<bool> = Record(true)
    accepts(value)
}
