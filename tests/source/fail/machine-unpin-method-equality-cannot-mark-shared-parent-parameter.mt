// expect-error: type 9:22 invalid primitive operation or operand types

type Parent<T> {
    fn bounded<U: Unpin>(value: mut T): Unit where T = U {
        var handle = core.pin.Pin.new(mut value)
        let reference = handle.into_inner()
    }
    fn wrong(value: mut T): Unit {
        let handle = core.pin.Pin.new(mut value)
    }
}
fn main() { 0 }
