
type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T: Copy> Wrapper<T> implements Unpin {}
fn access<T>(mut value: Wrapper<T>): mut Wrapper<T> from value where Wrapper<T>: Unpin {
    var handle = core.pin.Pin.new(mut value)
    handle.into_inner()
}
fn main() {
    var value = Wrapper(41,core.marker.PhantomPinned)
    access(value).value += 1
    if value.value == 42 { 0 } else { 1 }
}
