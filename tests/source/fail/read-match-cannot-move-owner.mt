// expect-error: ownership 5:73 pattern binding 'item' moves a non-copyable payload out of a viewed scrutinee
type Owned { value: i32 }
enum Value { Held(Owned) }
fn consume(take value: Owned) {}
fn main() { let value = Value.Held(Owned(42)); match value { Value.Held(item) => consume(item) }; 0 }
