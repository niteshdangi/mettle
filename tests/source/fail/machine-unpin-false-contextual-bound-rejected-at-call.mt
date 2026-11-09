// expect-error: type 12:17 Unpin

type Owned { marker: core.marker.PhantomPinned }
type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T: Copy> Wrapper<T> implements Unpin {}
fn access<T>(mut value: Wrapper<T>): mut Wrapper<T> from value where Wrapper<T>: Unpin {
    var handle = core.pin.Pin.new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(Owned(core.marker.PhantomPinned),core.marker.PhantomPinned)
    let wrong = access(value)
    0
}
