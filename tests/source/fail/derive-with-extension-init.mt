// expect-error: feature 2:9 derive(Clone) is not implemented for types with an init constructor
@derive(Clone)
type Value { value: i32 }
extend Value {
    init(value: i32) { self.value = value + 1 }
}
fn main() { 0 }
