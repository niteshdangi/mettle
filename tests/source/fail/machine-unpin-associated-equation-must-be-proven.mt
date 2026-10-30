// expect-error: type 10:17 unsatisfied Unpin condition

interface Family { type Item; }
type Source {}
extend Source implements Family { type Item = bool; }
type Wrapper<T> { value: T; marker: core.marker.PhantomPinned }
unsafe extend<T: Family> Wrapper<T> implements Unpin where T.(Family).Item = i32 {}
fn main() {
    var handle = core.pin.pin(Wrapper(Source(),core.marker.PhantomPinned))
    let wrong = handle.get_mut()
    0
}
