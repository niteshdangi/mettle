
type Owned { value: i32 }
enum Result { Value(Owned); Empty }
fn extract(take value: Result) {
    match take value {
        Result.Value(item) if item.value < 0 => 1,
        Result.Value(item) => item.value,
        Result.Empty => 0
    }
}
fn main() { if extract(Result.Value(Owned(42))) == 42 { 0 } else { 1 } }
