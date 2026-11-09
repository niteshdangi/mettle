// expect-error: type 14:18 async method 'value' is not available through 'any AsyncValue'
interface AsyncValue {
    async fn value<region r>(receiver read self: Self from r): i32
}
type Value { value: i32 }
extend Value implements AsyncValue {
    async fn value<region r>(receiver read self: Self from r): i32 {
        self.value
    }
}
fn main(): i32 {
    let value = Value(1)
    let erased: read any AsyncValue = read value
    let future = erased.value()
    0
}
