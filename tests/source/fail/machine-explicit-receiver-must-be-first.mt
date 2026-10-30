// expect-error: signature 2:50 explicit receiver must be first and bind self
type Payload { fn wrong(value: i32, receiver self: read Self): i32 { value } }
fn main() { 0 }
