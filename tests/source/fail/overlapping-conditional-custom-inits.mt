// expect-error: type 7:5 overlapping constructor argument shapes
type Number<T> { value: i32 }
extend<T> Number<T> {
    init(value: i32) { self.value = value }
}
extend Number<i32> {
    init(other: i32) { self.value = other }
}
fn main() { 0 }
