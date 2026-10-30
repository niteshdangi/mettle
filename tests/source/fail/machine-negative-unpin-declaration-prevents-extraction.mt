// expect-error: type 4:64 invalid primitive operation or operand types
type Stable { value: i32 }
extend Stable not Unpin
fn main() { var handle = core.pin.pin(Stable(42)); let value = handle.get_mut(); 0 }
