// expect-error: type 7:17 unsatisfied Unpin condition

type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T> Wrapper<T> implements Unpin where Wrapper<T>: Unpin {}
fn main() {
    var handle = core.pin.pin(Wrapper(42,core.marker.PhantomPinned))
    let wrong = handle.get_mut()
    0
}
