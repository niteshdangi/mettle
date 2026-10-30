// expect-error: ownership 5:73 pattern binding 'item' moves a non-copyable payload out of a borrowed scrutinee
type Owned { value: i32 }
enum Value { Held(Owned) }
fn consume(value: take Owned) {}
fn main() { let value = Value.Held(Owned(42)); match value { Value.Held(item) => consume(item) }; 0 }
