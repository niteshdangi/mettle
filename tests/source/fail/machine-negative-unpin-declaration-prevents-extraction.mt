// expect-error: type 4:66 invalid primitive operation or operand types
type Stable { value: i32 }
impl Stable not Unpin;
fn main() { var handle = core::pin::pin(Stable(42)); let value = handle.get_mut(); 0 }
