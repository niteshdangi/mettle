// expect-error: type 2:59 invalid primitive operation or operand types
fn access<T>(mut value: pinned mut T): mut T from value { value.get_mut() }
fn main() { 0 }
