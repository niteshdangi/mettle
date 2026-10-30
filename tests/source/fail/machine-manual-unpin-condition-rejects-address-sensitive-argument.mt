// expect-error: type 7:17 unsatisfied Unpin condition

type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T: Unpin> Wrapper<T> implements Unpin {}
fn main() {
    var handle = core.pin.pin(Wrapper(core.marker.PhantomPinned,core.marker.PhantomPinned))
    let value = handle.get_mut()
    0
}
