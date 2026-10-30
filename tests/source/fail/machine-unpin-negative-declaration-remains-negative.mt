// expect-error: type 8:17 invalid primitive operation or operand types

type Blocked { value: i32 }
extend Blocked not Unpin
type Outer { value: Blocked }
fn main() {
    var handle = core.pin.pin(Outer(Blocked(42)))
    let wrong = handle.get_mut()
    0
}
