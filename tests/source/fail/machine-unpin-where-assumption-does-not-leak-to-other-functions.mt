// expect-error: type 10:18 unsatisfied Unpin condition

type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T: Copy> Wrapper<T> implements Unpin {}
fn allowed<T>(mut value: Wrapper<T>): mut Wrapper<T> from value where Wrapper<T>: Unpin {
    var handle = core.pin.Pin.new(mut value)
    handle.into_inner()
}
fn wrong<T>(mut value: Wrapper<T>) {
    let handle = core.pin.Pin.new(mut value)
}
fn main() { 0 }
