// expect-error: type 9:22 invalid primitive operation or operand types

type Parent<T> {
    fn bounded<U: Unpin>(mut value: T): Unit where T = U {
        var handle = core.pin.Pin.new(mut value)
        let reference = handle.into_inner()
    }
    fn wrong(mut value: T): Unit {
        let handle = core.pin.Pin.new(mut value)
    }
}
fn main() { 0 }
