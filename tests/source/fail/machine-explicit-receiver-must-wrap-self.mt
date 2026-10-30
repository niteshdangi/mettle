// expect-error: signature 2:28 explicit receiver must wrap Self
type Payload { value: i32; fn wrong(receiver self: i32): i32 { self } }
fn main() { 0 }
