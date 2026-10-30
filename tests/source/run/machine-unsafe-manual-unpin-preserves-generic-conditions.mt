
type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T: Unpin> Wrapper<T> implements Unpin {}
fn main() {
    var handle = core.pin.pin(Wrapper(41,core.marker.PhantomPinned))
    handle.get_mut().value += 1
    if handle.get_ref().value == 42 { 0 } else { 1 }
}
