// expect-error: type 8:17 unsatisfied Unpin condition

type Owned { marker: core.marker.PhantomPinned }
type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T: Copy> Wrapper<T> implements Unpin {}
fn wrong<T>(read value: Wrapper<T>): Unit where Wrapper<T>: Unpin {
    var handle = core.pin.pin(Wrapper(Owned(core.marker.PhantomPinned),core.marker.PhantomPinned))
    let wrong = handle.get_mut()
}
fn main() { 0 }
