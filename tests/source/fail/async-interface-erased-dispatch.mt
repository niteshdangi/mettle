// expect-error: feature 16:5 erased async methods require an explicit future-storage
interface AsyncValue {
    async fn value<region r>(receiver self: read Self from r): i32
}

type Value { value: i32 }

extend Value implements AsyncValue {
    async fn value<region r>(receiver self: read Self from r): i32 {
        self.value
    }
}

fn main(): i32 {
    let value = Value(1)
    let erased: read any AsyncValue = read value
    0
}
