// expect-error: type 4:70 invalid primitive operation or operand types

type Owned { value: i32 }
fn main() { let cell = core::cell::Cell::new(Owned(42)); let value = cell.get(); 0 }
