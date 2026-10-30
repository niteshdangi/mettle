// expect-error: ownership 5:90 cannot move out of a borrowed place
type Owned { value: i32 }
enum Value { Held(Owned) }
fn consume(value: take Owned) {}
fn main() { let value = Value.Held(Owned(42)); match value { Value.Held(item) => consume(item) }; 0 }
