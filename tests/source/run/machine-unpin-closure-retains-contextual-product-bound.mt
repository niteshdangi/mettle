
type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T: Copy> Wrapper<T> implements Unpin {}
fn access<T>(mut value: Wrapper<T>): Unit where Wrapper<T>: Unpin {
    var operation = fn(): Unit {
        var handle = core.pin.Pin.new(mut value)
        let reference = handle.into_inner()
    }
    operation()
}
fn main() {
    var value = Wrapper(42,core.marker.PhantomPinned)
    access(value)
    if value.value == 42 { 0 } else { 1 }
}
